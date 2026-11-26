class_name ClassicMatch
extends Node3D
## Modo CLÁSSICO (Mapa 1): 1 jogador + até 15 bots, loot, zona segura que fecha, eliminações e resultados.
## Fluxo: gerar mapa -> loot -> participantes -> HUD -> contagem 3-2-1 -> partida -> fim -> resultados.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOT_SCENE := preload("res://scenes/bots/bot.tscn")

## Usado por testes automatizados: simulação só com bots (sem jogador humano).
static var autoplay_next := false
static var bots_override := -1

var map: MapData
var player: Player
var cam: ThirdPersonCamera
var loot: LootManager
var zone: ZoneController
var hud: Hud
var env: EnvironmentBuilder
var participants: Array = []
var state := "loading"
var elapsed := 0.0
var total := 16
var alive_count := 16
var autoplay := false
var winner: Combatant
var ended_data := {}
var _countdown := 0.0
var _last_count := 99
var _end_wait := -1.0
var _was_captured := false
var _round_over := false
var pause_on_loss := true     # online: nunca pausa (o host é o servidor da partida)
var _amb_t := 0.0
var _orbit_victory := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	autoplay = autoplay_next
	autoplay_next = false
	_rng.randomize()
	await _boot()


func _report(v: float, msg: String) -> void:
	SceneRouter.report(v, msg)


func _boot() -> void:
	var gen := MapGenerator.new()
	map = await gen.generate(self, func(v: float, m: String): _report(v * 0.8, m))
	env = EnvironmentBuilder.new()
	env.name = "Environment"
	add_child(env)
	env.build(map.half)
	_report(0.84, "Distribuindo recursos pelo mapa")
	await get_tree().process_frame
	loot = LootManager.new()
	loot.name = "Loot"
	add_child(loot)
	var bots_n := clampi(int(SaveSystem.prefs().get("bots", 15)), 1, 15)
	if bots_override > 0:
		bots_n = bots_override
	total = bots_n if autoplay else bots_n + 1
	alive_count = total
	var count := loot.populate(map, total)
	zone = ZoneController.new()
	zone.name = "Zone"
	add_child(zone)
	_report(0.90, "Posicionando %d participantes (%d itens no mapa)" % [total, count])
	await get_tree().process_frame
	_spawn_participants(bots_n)
	_report(0.96, "Montando interface")
	await get_tree().process_frame
	if autoplay:
		var c := Camera3D.new()
		c.position = Vector3(0, 380, 160)
		c.rotation_degrees = Vector3(-68, 0, 0)
		c.far = 1500.0
		add_child(c)
		c.make_current()
		QualityManager.register_world(env.sun, c)
	else:
		hud = Hud.new()
		hud.name = "Hud"
		add_child(hud)
		hud.setup(self)
		QualityManager.register_world(env.sun, cam.camera)
		_setup_player_view()
	QualityManager.in_match = true
	Events.combatant_eliminated.connect(_on_eliminated)
	_report(1.0, "Tudo pronto")
	await get_tree().create_timer(0.4).timeout
	SceneRouter.hide_loading()
	AudioManager.stop_music()
	AudioManager.play_ambient("amb_field")
	state = "countdown"
	_countdown = 4.0
	if not autoplay and not GameSettings.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _setup_player_view() -> void:
	cam.yaw = player.rotation.y
	cam.pitch = -0.1


func _spawn_participants(bots_n: int) -> void:
	var pts: Array = map.spawn_points.duplicate()
	pts.shuffle()
	var names: Array = Bot.NAMES.duplicate()
	names.shuffle()
	var diff := str(SaveSystem.prefs().get("difficulty", "mixed"))
	var idx := 0
	if not autoplay:
		player = PLAYER_SCENE.instantiate()
		player.init_player(SaveSystem.customization(), str(SaveSystem.profile().get("name", "Jogador")))
		player.position = _spawn_at(pts, idx)
		player.rotation.y = _rng.randf() * TAU
		player.loot_mgr = loot
		player.ctl_enabled = false   # só libera após a contagem regressiva
		loot.viewer = player
		add_child(player)
		cam = ThirdPersonCamera.new()
		cam.name = "Camera"
		add_child(cam)
		cam.target = player
		player.cam = cam
		cam.enemies_provider = _enemies_of_player
		participants.append(player)
		idx += 1
	for i in bots_n:
		var level := diff
		if diff == "mixed":
			var r := _rng.randf()
			level = "beginner" if r < 0.35 else ("intermediate" if r < 0.75 else "advanced")
		var b: Bot = BOT_SCENE.instantiate()
		b.init_bot(str(names[i % names.size()]), level, CosmeticsDB.random_appearance(_rng))
		b.position = _spawn_at(pts, idx)
		b.rotation.y = _rng.randf() * TAU
		b.map = map
		b.nav = map.nav
		b.loot_mgr = loot
		b.zone = zone
		add_child(b)
		b.set_physics_process(false)
		participants.append(b)
		idx += 1


func _spawn_at(pts: Array, i: int) -> Vector3:
	if i < pts.size():
		return pts[i]
	var p := Vector3(_rng.randf_range(-250, 250), 0, _rng.randf_range(-250, 250))
	return Vector3(p.x, map.height_at(p.x, p.z) + 0.2, p.z)


func _enemies_of_player() -> Array:
	var out: Array = []
	for p in participants:
		if is_instance_valid(p) and p != player and p.alive:
			out.append(p)
	return out


func count_alive() -> int:
	var n := 0
	for p in participants:
		if is_instance_valid(p) and p.alive:
			n += 1
	return n


func _process(delta: float) -> void:
	match state:
		"countdown":
			_countdown -= delta
			var c := ceili(_countdown - 1.0)
			if c != _last_count and hud != null:
				_last_count = c
				if c > 0:
					hud.show_big(str(c), 0.9)
					AudioManager.play_sfx("countdown", -4.0)
			if _countdown <= 1.0:
				_start_match()
		"running":
			elapsed += delta
			alive_count = count_alive()
			_amb_t -= delta
			if _amb_t <= 0.0 and player != null and is_instance_valid(player):
				_amb_t = 1.5
				var here := map.city_at(player.global_position.x, player.global_position.z)
				AudioManager.play_ambient("amb_city" if (not here.is_empty() and str(here["id"]) != "valeverde") else "amb_field")
			if not autoplay and not GameSettings.touch_mode:
				var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				if _was_captured and not cap and hud != null and not get_tree().paused:
					hud.open_pause()
				_was_captured = cap
			if _end_wait >= 0.0:
				_end_wait -= delta
				if _end_wait < 0.0:
					_show_results()


func _start_match() -> void:
	state = "running"
	zone.start()
	for p in participants:
		if is_instance_valid(p):
			p.set_physics_process(true)
	if player != null:
		player.ctl_enabled = true
	if hud != null:
		hud.show_big("INICIAR!", 1.2)
	AudioManager.play_sfx("go", -2.0)
	Events.notify.emit("Sobreviva! Colete equipamentos e acompanhe a zona.", "info")


func _on_eliminated(victim: Node, killer: Node) -> void:
	if state != "running":
		return
	var v := victim as Combatant
	var k := killer as Combatant
	alive_count = count_alive()
	v.place = alive_count + 1
	if k != null and k != v:
		Events.notify.emit("%s eliminou %s" % [k.display_name, v.display_name], "kill")
	else:
		Events.notify.emit("%s foi eliminado pela zona" % v.display_name, "kill")
	if v == player:
		ended_data = {"won": false, "place": v.place}
		_end_wait = 2.6
	if alive_count <= 1 and not _round_over:
		_round_over = true
		winner = _find_winner()
		Events.match_ended.emit(winner)
		if winner == player and player != null:
			_player_wins()


func _find_winner() -> Combatant:
	for p in participants:
		if is_instance_valid(p) and p.alive:
			return p
	var best: Combatant = null
	for p in participants:
		if is_instance_valid(p) and (best == null or p.survive_time > best.survive_time):
			best = p
	return best


func _player_wins() -> void:
	winner.place = 1
	ended_data = {"won": true, "place": 1}
	player.ctl_enabled = false
	GameSettings.clear_touch_state()
	player.model.animator.trigger("victory")
	cam.look_locked = true
	AudioManager.play_sfx("win")
	_confetti()
	_orbit_victory = true
	_end_wait = 3.5


func _confetti() -> void:
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.5, 0.2, 2.5)
	p.direction = Vector3.DOWN
	p.spread = 25.0
	p.gravity = Vector3(0, -2.5, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.2)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	p.color_ramp = null
	p.color = Color(1.0, 0.7, 0.2)
	p.position = player.global_position + Vector3(0, 4.0, 0)
	add_child(p)


func _physics_process(delta: float) -> void:
	if _orbit_victory and cam != null and is_instance_valid(player):
		cam.yaw += delta * 0.6


func _show_results() -> void:
	if hud == null or player == null:
		return
	var data := ended_data.duplicate()
	data["kills"] = player.kills
	data["damage"] = player.damage_dealt
	data["survive"] = player.survive_time
	data["total"] = total
	data["name"] = player.display_name
	data["xp"] = SaveSystem.record_match(int(data.get("place", total)), player.kills, player.survive_time, bool(data.get("won", false)), player.damage_dealt)
	hud.show_results(data)
	state = "ended"
	if not bool(data.get("won", false)) and pause_on_loss:
		get_tree().paused = true


func leave() -> void:
	get_tree().paused = false
	SceneRouter.go_lobby()


func play_again() -> void:
	get_tree().paused = false
	SceneRouter.start_mode("classic")


func _exit_tree() -> void:
	QualityManager.unregister_world()
	QualityManager.in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.clear_touch_state()
	if Events.combatant_eliminated.is_connected(_on_eliminated):
		Events.combatant_eliminated.disconnect(_on_eliminated)
	get_tree().paused = false
