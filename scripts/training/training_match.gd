class_name TrainingMatch
extends Node3D
## Modo TREINAMENTO DE MIRA. Campo 3D exclusivo com alvos físicos (estáticos, móveis e pop-up), bots de
## treino controlados por IA, percurso para testar movimento/controles, rack de equipamentos virtuais,
## contador de acertos, precisão, cronômetro e reinício. Tipos: livre, precisão (60 s) e contra bots.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const BOT_SCENE := preload("res://scenes/bots/bot.tscn")
const PRECISION_TIME := 60.0

var player: Player
var cam: ThirdPersonCamera
var hud: Hud
var env: EnvironmentBuilder
var loot: LootManager
var zone: ZoneController = null
var map: MapData = null
var state := "loading"
var mode := "free"
var elapsed := 0.0
var score := 0
var target_hits := 0
var missed := 0
var bot_kills := 0
var time_left := PRECISION_TIME
var bots: Array = []
var popups: Array = []
var _active: Array = []
var _spawn_cd := 0.0
var _stats_label: Label
var _rack := {}
var _rng := RandomNumberGenerator.new()
var _finished := false


func _ready() -> void:
	_rng.randomize()
	mode = str(SaveSystem.prefs().get("training", "free"))
	await _boot()


func _boot() -> void:
	SceneRouter.report(0.15, "Construindo o campo de treino")
	await get_tree().process_frame
	env = EnvironmentBuilder.new()
	add_child(env)
	env.build(200.0)
	_arena()
	SceneRouter.report(0.45, "Posicionando alvos")
	await get_tree().process_frame
	_targets()
	loot = LootManager.new()
	add_child(loot)
	_rack_items()
	SceneRouter.report(0.7, "Preparando o jogador")
	await get_tree().process_frame
	player = PLAYER_SCENE.instantiate()
	player.init_player(SaveSystem.customization(), str(SaveSystem.profile().get("name", "Jogador")))
	player.position = Vector3(0, 0.1, 46)
	player.loot_mgr = loot
	loot.viewer = player
	add_child(player)
	cam = ThirdPersonCamera.new()
	add_child(cam)
	cam.target = player
	player.cam = cam
	cam.yaw = 0.0
	cam.pitch = -0.08
	cam.enemies_provider = _enemy_list
	_give_loadout()
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	_build_stats_panel()
	QualityManager.register_world(env.sun, cam.camera)
	QualityManager.in_match = true
	Events.combatant_eliminated.connect(_on_eliminated)
	Events.item_picked.connect(_on_item_picked)
	SceneRouter.report(1.0, "Pronto")
	await get_tree().create_timer(0.3).timeout
	SceneRouter.hide_loading()
	AudioManager.stop_music()
	AudioManager.play_ambient("amb_field")
	state = "running"
	player.ctl_enabled = true
	if not GameSettings.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_big("TREINAMENTO", 1.2)
	_apply_mode()


# ------------------------------------------------------------------ cenário
func _arena() -> void:
	var b := WorldBatch.new()
	b.box("concrete", Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.62, 0.64, 0.62), true, false, 4.0)
	for w in [[0, -90, 180, 1], [0, 90, 180, 1]]:
		b.box("concrete", Vector3(w[0], 1.5, w[1]), Vector3(w[2], 3, w[3]), Color(0.45, 0.47, 0.5), true, false, 3.0)
	for w in [[-90, 0], [90, 0]]:
		b.box("concrete", Vector3(w[0], 1.5, w[1]), Vector3(1, 3, 180), Color(0.45, 0.47, 0.5), true, false, 3.0)
	# faixas e marcadores da pista de tiro (distâncias a partir do ponto de partida em z = 46)
	for d in [20, 35, 55, 75]:
		var z := 46.0 - d
		b.box("plain", Vector3(0, 0.02, z + 3.0), Vector3(30, 0.03, 0.4), Color(1.0, 0.8, 0.2), false, false, 1.0)
		b.box("metal", Vector3(-16, 0.6, z + 3.0), Vector3(0.5, 1.2, 0.5), Color(0.9, 0.5, 0.1), true, false, 1.0)
		var lb := Label3D.new()
		lb.text = "%d m" % d
		lb.font_size = 96
		lb.pixel_size = 0.01
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.modulate = Color(1.0, 0.85, 0.3)
		lb.position = Vector3(-16, 1.9, z + 3.0)
		add_child(lb)
	# percurso de movimento (direita): muro baixo, caixas, barra para agachar, plataforma com escada, muro alto
	b.box("concrete", Vector3(36, 0.5, 30), Vector3(8, 1.0, 0.6), Color(0.6, 0.6, 0.62), true, false, 2.0)
	for p in [Vector3(48, 0.45, 28), Vector3(52, 0.45, 25), Vector3(50, 1.35, 26.5)]:
		b.box("wood", p, Vector3(1.8, 0.9, 1.8), Color(0.7, 0.55, 0.35), true, false, 2.0)
	b.box("metal", Vector3(40, 0.7, 14), Vector3(0.3, 1.4, 0.3), Color(0.8, 0.3, 0.1), true, false, 1.0)
	b.box("metal", Vector3(46, 0.7, 14), Vector3(0.3, 1.4, 0.3), Color(0.8, 0.3, 0.1), true, false, 1.0)
	b.box("metal", Vector3(43, 1.55, 14), Vector3(6.3, 0.3, 0.3), Color(0.9, 0.7, 0.1), true, false, 1.0)
	b.box("concrete", Vector3(60, 1.2, 0), Vector3(8, 2.4, 8), Color(0.55, 0.57, 0.6), true, false, 2.0)
	BuildingBuilder._stairs(b, "S", Rect2(56, -4, 8, 8), 0.0, 2.4)
	b.box("concrete", Vector3(44, 1.6, -14), Vector3(10, 3.2, 0.6), Color(0.6, 0.6, 0.62), true, false, 2.0)
	# área de bots (esquerda): barreiras para cobertura
	for p in [Vector3(-50, 0.9, 10), Vector3(-62, 0.9, -6), Vector3(-44, 0.9, -14), Vector3(-70, 0.9, 20)]:
		b.box("concrete", p, Vector3(5, 1.8, 0.8), Color(0.58, 0.58, 0.6), true, false, 2.0)
	b.box("plain", Vector3(-56, 0.02, 4), Vector3(40, 0.03, 40), Color(0.85, 0.3, 0.2, 1.0), false, false, 1.0)
	b.build(self, "Arena")
	for pos in [Vector3(36, 1.7, 30), Vector3(43, 2.2, 14)]:
		var tag := Label3D.new()
		tag.text = "MURO BAIXO\n(pule)" if pos.z > 20 else "BARRA\n(agache)"
		tag.font_size = 64
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = pos
		add_child(tag)


func _targets() -> void:
	# estáticos em 4 distâncias
	var static_defs := [[-6.0, 26.0], [0.0, 11.0], [6.0, -9.0], [-3.0, -29.0]]
	for d in static_defs:
		var t := TrainingTarget.new()
		add_child(t)
		t.position = Vector3(d[0], 0, d[1])
		t.build(1.4, 0.5)
		t.configure("static")
		t.scored.connect(_on_target_scored)
	# móveis (vai e vem lateral)
	for i in 3:
		var t2 := TrainingTarget.new()
		add_child(t2)
		t2.position = Vector3(0, 0, 18.0 - i * 14.0)
		t2.build(1.3, 0.45)
		t2.configure("moving", 14.0, 4.0 + i)
		t2.scored.connect(_on_target_scored)
	# pop-ups do treino de precisão (posições predefinidas)
	var slots := [Vector3(-16, 0, 20), Vector3(-9, 0, 5), Vector3(9, 0, 8), Vector3(16, 0, 22), Vector3(-12, 0, -10),
		Vector3(12, 0, -12), Vector3(0, 0, -20), Vector3(-20, 0, -28), Vector3(20, 0, -26), Vector3(0, 0, 0)]
	for i in slots.size():
		var t3 := TrainingTarget.new()
		add_child(t3)
		t3.position = slots[i]
		t3.build(0.9 + float(i % 4) * 0.45, 0.42)
		t3.configure("popup")
		t3.set_up(false, true)
		t3.scored.connect(_on_target_scored)
		popups.append(t3)


func _rack_items() -> void:
	var ids := ["pistol", "smg", "rifle", "shotgun", "dmr", "bandage", "medkit", "vest_2", "helmet_2", "suppressor"]
	for i in ids.size():
		var pos := Vector3(-9.0 + i * 2.0, 0.8, 52.0)
		_rack[ids[i]] = pos
		loot.spawn(ids[i], ItemDB.default_qty(ids[i]), pos)


func _on_item_picked(id: String, who: Node) -> void:
	if who != player or not _rack.has(id):
		return
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and loot != null:
		loot.spawn(id, ItemDB.default_qty(id), _rack[id])


func _give_loadout() -> void:
	player.pickup_item("rifle", 1)
	player.pickup_item("pistol", 1)
	player.pickup_item("shotgun", 1)
	player.pickup_item("bandage", 3)
	player.equip(0)
	_refill()


func _refill() -> void:
	for k in player.inv.ammo:
		player.inv.ammo[k] = 999


func _enemy_list() -> Array:
	var out: Array = []
	for b in bots:
		if is_instance_valid(b) and b.alive:
			out.append(b)
	return out


# ------------------------------------------------------------------ modos
func extra_pause_items() -> Array:
	return [["REINICIAR TREINO", _restart_current], ["MODO: LIVRE", _set_mode.bind("free")],
		["MODO: PRECISÃO (60 s)", _set_mode.bind("precision")], ["MODO: CONTRA BOTS", _set_mode.bind("bots")]]


func _set_mode(m: String) -> void:
	SaveSystem.prefs()["training"] = m
	SaveSystem.mark_dirty()
	mode = m
	hud.close_pause()
	_restart_current()


func _restart_current() -> void:
	if hud != null and hud.menu_open:
		hud.close_pause()
	_reset_stats()
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()
	for t in popups:
		t.set_up(false, true)
	_active.clear()
	player.hp = 100.0
	player.position = Vector3(0, 0.1, 46)
	player.velocity = Vector3.ZERO
	player.ctl_enabled = true
	player.shots = 0
	player.hits = 0
	player.kills = 0
	_refill()
	_finished = false
	state = "running"
	_apply_mode()


func _reset_stats() -> void:
	elapsed = 0.0
	score = 0
	target_hits = 0
	missed = 0
	bot_kills = 0
	time_left = PRECISION_TIME


func _apply_mode() -> void:
	match mode:
		"bots":
			for i in 4:
				_spawn_bot()
			Events.notify.emit("Treino contra bots: elimine os adversários.", "info")
		"precision":
			Events.notify.emit("Precisão: acerte os alvos que surgem. 60 segundos!", "info")
			_spawn_cd = 0.5
		_:
			Events.notify.emit("Treino livre: teste a mira, os controles e o percurso.", "info")


func _spawn_bot() -> void:
	var b: Bot = BOT_SCENE.instantiate()
	b.training = true
	b.init_bot("Alvo %d" % (bots.size() + 1), ["beginner", "intermediate"][_rng.randi() % 2], CosmeticsDB.random_appearance(_rng))
	b.position = Vector3(_rng.randf_range(-68.0, -36.0), 0.1, _rng.randf_range(-18.0, 22.0))
	b.zone = null
	add_child(b)
	b.pickup_item("rifle", 1)
	for k in b.inv.ammo:
		b.inv.ammo[k] = 999
	b.equip(0)
	b.hp = 70.0
	bots.append(b)


func _on_eliminated(victim: Node, killer: Node) -> void:
	if victim is Bot and (victim as Bot).training:
		if killer == player:
			bot_kills += 1
			score += 25
		await get_tree().create_timer(3.0).timeout
		if mode == "bots" and is_inside_tree() and state == "running":
			_spawn_bot()


func _on_target_scored(points: int, _ring: int, t: TrainingTarget) -> void:
	if _finished:
		return
	if mode == "precision":
		if t.kind != "popup" or not _active.has(t):
			return
		_active.erase(t)
		t.set_up(false)
	elif t.kind == "popup":
		return
	if points > 0:
		score += points
		target_hits += 1
	Events.notify.emit("+%d pontos" % points if points > 0 else "Na borda do alvo", "good" if points > 0 else "info")


# ------------------------------------------------------------------ painel de estatísticas
func _build_stats_panel() -> void:
	var p := UIKit.panel(Color(0.04, 0.05, 0.08, 0.78), 12, 10.0)
	_stats_label = UIKit.label("", 17, UIKit.TEXT)
	p.add_child(_stats_label)
	hud.ui.add_child(p)
	p.position = Vector2(14, 14)


func _process(delta: float) -> void:
	if state != "running" or player == null:
		return
	elapsed += delta
	_refill()
	if mode == "precision" and not _finished:
		_precision_tick(delta)
	var shots := player.shots
	var acc := 100.0 * float(player.hits) / float(maxi(shots, 1))
	var txt: String = "MODO: %s\n" % {"free": "LIVRE", "precision": "PRECISÃO", "bots": "CONTRA BOTS"}.get(mode, "LIVRE")
	if mode == "precision":
		txt += "TEMPO: %d s\n" % ceili(maxf(time_left, 0.0))
	else:
		txt += "TEMPO: %d:%02d\n" % [int(elapsed) / 60, int(elapsed) % 60]
	txt += "DISPAROS: %d   ACERTOS: %d\nPRECISÃO: %d%%\nPONTOS: %d" % [shots, player.hits, int(acc), score]
	if mode == "precision":
		txt += "   PERDIDOS: %d" % missed
	if mode == "bots":
		txt += "\nBOTS ELIMINADOS: %d" % bot_kills
	_stats_label.text = txt
	if player.global_position.y < -20.0:
		player.position = Vector3(0, 0.5, 46)
		player.velocity = Vector3.ZERO


func _precision_tick(delta: float) -> void:
	time_left -= delta
	for t in _active.duplicate():
		t.set_meta("life", float(t.get_meta("life", 3.0)) - delta)
		if float(t.get_meta("life")) <= 0.0:
			_active.erase(t)
			t.set_up(false)
			missed += 1
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and _active.size() < 3:
		_spawn_cd = 0.9
		var free: Array = []
		for t in popups:
			if not _active.has(t):
				free.append(t)
		if not free.is_empty():
			var t2: TrainingTarget = free[_rng.randi() % free.size()]
			t2.set_meta("life", 3.0)
			t2.set_up(true)
			_active.append(t2)
	if time_left <= 0.0:
		_finish_precision()


func _finish_precision() -> void:
	_finished = true
	for t in popups:
		t.set_up(false)
	_active.clear()
	var shots := maxi(player.shots, 1)
	var acc := int(100.0 * float(player.hits) / float(shots))
	var st := SaveSystem.stats()
	if score > int(st.get("train_best", 0)):
		st["train_best"] = score
	hud.show_big("FIM! %d pts  |  %d%% precisão" % [score, acc], 4.0)
	Events.notify.emit("Treino de precisão concluído: %d pontos, %d%% de precisão." % [score, acc], "good")
	SaveSystem.mark_dirty()


func leave() -> void:
	_save_stats()
	get_tree().paused = false
	SceneRouter.go_lobby()


func play_again() -> void:
	_restart_current()


func _save_stats() -> void:
	if player == null:
		return
	var st := SaveSystem.stats()
	st["train_shots"] = int(st.get("train_shots", 0)) + player.shots
	st["train_hits"] = int(st.get("train_hits", 0)) + player.hits
	SaveSystem.save_data()


func _exit_tree() -> void:
	QualityManager.unregister_world()
	QualityManager.in_match = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.clear_touch_state()
	if Events.combatant_eliminated.is_connected(_on_eliminated):
		Events.combatant_eliminated.disconnect(_on_eliminated)
	if Events.item_picked.is_connected(_on_item_picked):
		Events.item_picked.disconnect(_on_item_picked)
	get_tree().paused = false
