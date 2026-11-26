class_name OnlineMatch
extends ClassicMatch
## Partida ONLINE. Modelo "listen-server": o jogador host (escolhido pelo servidor) roda toda a simulação
## (mapa, loot, bots, zona, dano). Os outros clientes enviam entrada (posição, tiros, coleta) ao host e
## recebem snapshots (~12/s). O servidor só repassa mensagens. Bots completam as vagas no host.
## shortcut: movimento dos clientes é confiado (sem anti-cheat) e não há migração de host; ok entre amigos.

const SNAP_DT := 0.083
const STATE_DT := 0.066

var is_host := false
var my_id := 0
var session: Dictionary = {}
var by_id := {}
var _pending: Array = []
var _ready_ids := {}
var _roster: Array = []
var _sent_go := false
var _end_sent := false
var _leaving := false
var _loading := true
var _go_wait := 0.0
var _t_net := 0.0
var _t_inv := 0.0
var _fire_seen := {}


func _boot() -> void:
	pause_on_loss = false
	session = NetClient.session
	my_id = int(session["you"])
	is_host = my_id == int(session["host"])
	NetClient.relayed.connect(_on_relay)
	NetClient.server_message.connect(_on_server_msg)
	NetClient.disconnected.connect(_net_lost)
	var gen := MapGenerator.new()
	map = await gen.generate(self, func(v: float, m: String): _report(v * 0.8, m), int(session["seed"]))
	env = EnvironmentBuilder.new()
	add_child(env)
	env.build(map.half)
	loot = LootManager.new()
	add_child(loot)
	total = int(session["capacity"])
	alive_count = total
	zone = ZoneController.new()
	add_child(zone)
	zone.remote = not is_host
	if is_host:
		loot.populate(map, total)
		loot.spawned.connect(_on_loot_spawned)
		loot.removed.connect(_on_loot_removed)
		Events.combatant_damaged.connect(_on_damaged_net)
	_report(0.9, "Posicionando %d participantes" % total)
	await get_tree().process_frame
	_spawn_online()
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.pause_tree = false
	QualityManager.register_world(env.sun, cam.camera)
	QualityManager.in_match = true
	Events.combatant_eliminated.connect(_on_eliminated)
	_report(1.0, "Aguardando os outros jogadores")
	await get_tree().create_timer(0.4).timeout
	SceneRouter.hide_loading()
	AudioManager.stop_music()
	AudioManager.play_ambient("amb_field")
	state = "waiting"
	_loading = false
	if not GameSettings.touch_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_big("Aguardando jogadores…", 2.5)
	if is_host:
		_ready_ids[my_id] = true
	else:
		NetClient.to_host({"k": "ready"})
	for m in _pending:
		_handle(int(m[0]), m[1])
	_pending.clear()


func _seeded_spawns() -> Array:
	var pts: Array = map.spawn_points.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = int(session["seed"])
	for i in range(pts.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = pts[i]
		pts[i] = pts[j]
		pts[j] = tmp
	return pts


func _spawn_online() -> void:
	var pts := _seeded_spawns()
	var idx := 0
	for h in session["humans"]:
		var id := int(h["id"])
		var pos := _spawn_at(pts, idx)
		idx += 1
		if id == my_id:
			player = PLAYER_SCENE.instantiate()
			player.init_player(SaveSystem.customization(), str(h["name"]))
			player.net_id = id
			player.position = pos
			player.loot_mgr = loot
			player.ctl_enabled = false
			loot.viewer = player
			add_child(player)
			cam = ThirdPersonCamera.new()
			add_child(cam)
			cam.target = player
			player.cam = cam
			cam.enemies_provider = _enemies_of_player
			participants.append(player)
			by_id[id] = player
			if not is_host:
				player.net_hook = _net_hook
				player.net_pickup_cb = _client_pick
		else:
			var p := RemotePuppet.new()
			p.init_puppet(id, str(h["name"]), h["app"], not is_host, true)
			p.position = pos
			add_child(p)
			participants.append(p)
			by_id[id] = p
	if not is_host:
		return
	var names: Array = Bot.NAMES.duplicate()
	names.shuffle()
	var diff := str(session.get("difficulty", "mixed"))
	for i in int(session["bots"]):
		var level := diff
		if diff == "mixed":
			var r := _rng.randf()
			level = "beginner" if r < 0.35 else ("intermediate" if r < 0.75 else "advanced")
		var app := CosmeticsDB.random_appearance(_rng)
		var b: Bot = BOT_SCENE.instantiate()
		b.init_bot(str(names[i % names.size()]), level, app)
		b.net_id = 1000 + i
		b.position = _spawn_at(pts, idx)
		idx += 1
		b.map = map
		b.nav = map.nav
		b.loot_mgr = loot
		b.zone = zone
		add_child(b)
		b.set_physics_process(false)
		participants.append(b)
		by_id[b.net_id] = b
		_roster.append({"id": b.net_id, "name": b.display_name, "app": app})


# ------------------------------------------------------------------ rede: entrada
func _on_relay(from: int, d: Dictionary) -> void:
	if _loading:
		_pending.append([from, d])
	else:
		_handle(from, d)


func _handle(from: int, d: Dictionary) -> void:
	if is_host:
		_host_msg(from, str(d.get("k", "")), d)
	else:
		_client_msg(str(d.get("k", "")), d)


func _on_server_msg(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"peer_left":
			var p := by_id.get(int(m["id"])) as RemotePuppet
			if p != null and is_host:
				Events.notify.emit("%s saiu da partida" % p.display_name, "warn")
				if p.alive:
					p.die(null)
		"host_left":
			_net_lost("O anfitrião saiu. A partida foi encerrada.")


func _net_lost(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	Events.notify.emit(reason, "bad")
	await get_tree().create_timer(2.0).timeout
	leave()


func _host_msg(from: int, k: String, d: Dictionary) -> void:
	if k == "ready":
		_ready_ids[from] = true
		return
	var p := by_id.get(from) as RemotePuppet
	if p == null or not p.alive:
		return
	match k:
		"st":
			var a: Array = d["p"]
			var fl := int(a[7])
			p.apply_state(Vector3(a[0], a[1], a[2]), float(a[3]), float(a[4]), Vector3(a[5], 0.0, a[6]), (fl & 2) != 0, (fl & 4) != 0)
		"fire":
			var o: Array = d["o"]
			var dv: Array = d["d"]
			p.try_fire(Vector3(o[0], o[1], o[2]), Vector3(dv[0], dv[1], dv[2]).normalized())
		"pick":
			_host_pick(p, int(d["u"]))
		"eq":
			p.equip(int(d["a"]))
		"rl":
			p.start_reload()
		"heal":
			p.use_heal(str(d["a"]))


func _host_pick(p: RemotePuppet, uid: int) -> void:
	var it: LootItem = loot.by_uid.get(uid)
	if it == null or it.picked or p.global_position.distance_to(it.global_position) > 5.0:
		return
	var res := p.pickup_item(it.item_id, it.qty)
	if res["ok"]:
		loot.remove_item(it)
		_send_inv(p)
	else:
		NetClient.to_peer(p.net_id, {"k": "msg", "t": str(res["msg"])})


func _send_inv(p: Combatant) -> void:
	var inv := p.inv
	NetClient.to_peer(p.net_id, {"k": "inv", "w": inv.weapons, "a": inv.ammo, "i": inv.items,
		"v": [inv.vest_level, inv.vest_hp, inv.helmet_level, inv.pack_level, inv.suppressor], "m": p.mags,
		"s": p.slot, "ks": p.kills, "dm": p.damage_dealt})


func _on_damaged_net(victim: Node, attacker: Node, _amount: float, _head: bool) -> void:
	var v := victim as RemotePuppet
	if v != null and v.is_human and not v.view_only:
		var f := (attacker as Node3D).global_position if attacker is Node3D else v.global_position
		NetClient.to_peer(v.net_id, {"k": "hurt", "hp": v.hp, "f": [f.x, f.y, f.z]})
	var a := attacker as RemotePuppet
	if a != null and a.is_human and not a.view_only:
		NetClient.to_peer(a.net_id, {"k": "hm", "kill": (victim as Combatant).hp <= 0.0})


func _on_loot_spawned(it) -> void:
	if _sent_go:
		NetClient.to_all({"k": "ls", "l": _loot_row(it)})


func _on_loot_removed(it) -> void:
	if _sent_go:
		NetClient.to_all({"k": "lr", "u": it.uid})


func _loot_row(it) -> Array:
	var p: Vector3 = it.global_position
	return [it.uid, it.item_id, it.qty, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


# ------------------------------------------------------------------ rede: saída
func _process(delta: float) -> void:
	super._process(delta)
	if _loading:
		return
	_t_net += delta
	if is_host:
		_check_go(delta)
		if _t_net >= SNAP_DT:
			_t_net = 0.0
			_send_snapshot()
		_t_inv += delta
		if _t_inv >= 1.0:
			_t_inv = 0.0
			for p in participants:
				if p is RemotePuppet and is_instance_valid(p) and p.alive and p.is_human:
					_send_inv(p)
	elif _t_net >= STATE_DT and player != null and player.alive and state != "ended":
		_t_net = 0.0
		var pos := player.global_position
		var fl := (2 if player.crouching else 0) | (4 if player.want_aim else 0)
		NetClient.to_host({"k": "st", "p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01),
			snappedf(player.rotation.y, 0.01), snappedf(player.aim_pitch, 0.01), snappedf(player.velocity.x, 0.1),
			snappedf(player.velocity.z, 0.1), fl]})


func _check_go(delta: float) -> void:
	if _sent_go:
		return
	_go_wait += delta
	var all_ready := true
	for h in session["humans"]:
		if not _ready_ids.has(int(h["id"])):
			all_ready = false
	if not all_ready and _go_wait < 30.0:
		return
	_sent_go = true
	var rows: Array = []
	for it in loot.items:
		if is_instance_valid(it) and not it.picked:
			rows.append(_loot_row(it))
	NetClient.to_all({"k": "roster", "b": _roster})
	NetClient.to_all({"k": "loot", "l": rows})
	NetClient.to_all({"k": "go"})
	_begin_countdown()


func _begin_countdown() -> void:
	state = "countdown"
	_countdown = 4.0
	_last_count = 99


func _start_match() -> void:
	state = "running"
	if is_host:
		zone.start()
		for p in participants:
			if p is Bot and is_instance_valid(p):
				p.set_physics_process(true)
	if player != null:
		player.ctl_enabled = true
	hud.show_big("INICIAR!", 1.2)
	AudioManager.play_sfx("go", -2.0)


func _send_snapshot() -> void:
	var rows: Array = []
	for c in participants:
		if not is_instance_valid(c):
			continue
		var fl := (1 if c.alive else 0) | (2 if c.crouching else 0) | (4 if c.is_aiming() else 0)
		var p: Vector3 = c.global_position
		rows.append([c.net_id, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(c.rotation.y, 0.01),
			snappedf(c.aim_pitch, 0.01), int(c.hp), fl, c.weapon_id(), snappedf(c.velocity.x, 0.1), snappedf(c.velocity.z, 0.1),
			c.kills, c.fire_count])
	NetClient.to_all({"k": "snap", "c": rows, "z": [zone.center.x, zone.center.y, zone.radius, zone.next_center.x,
		zone.next_center.y, zone.next_radius, 1 if zone.shrinking else 0, zone.time_to_shrink()]})


func _on_eliminated(victim: Node, killer: Node) -> void:
	if not is_host:
		return
	super._on_eliminated(victim, killer)
	var v := victim as Combatant
	var k := killer as Combatant
	var txt := "%s foi eliminado pela zona" % v.display_name
	if k != null and k != v:
		txt = "%s eliminou %s" % [k.display_name, v.display_name]
	NetClient.to_all({"k": "elim", "id": v.net_id, "place": v.place, "t": txt})
	if _round_over and winner != null and not _end_sent:
		_end_sent = true
		NetClient.to_all({"k": "end", "w": winner.net_id})


# ------------------------------------------------------------------ cliente
func _net_hook(kind: String, arg: Variant) -> void:
	if kind == "fire":
		var o: Vector3 = arg[0]
		var d: Vector3 = arg[1]
		NetClient.to_host({"k": "fire", "o": [o.x, o.y, o.z], "d": [d.x, d.y, d.z]})
	else:
		NetClient.to_host({"k": kind, "a": arg})


func _client_pick(item: Node3D) -> void:
	NetClient.to_host({"k": "pick", "u": item.uid})


func _add_bot_puppet(b: Dictionary) -> void:
	var id := int(b["id"])
	if by_id.has(id):
		return
	var p := RemotePuppet.new()
	p.init_puppet(id, str(b["name"]), b["app"], true, false)
	add_child(p)
	participants.append(p)
	by_id[id] = p


func _client_msg(k: String, d: Dictionary) -> void:
	match k:
		"roster":
			for b in d["b"]:
				_add_bot_puppet(b)
		"loot":
			for e in d["l"]:
				loot.spawn_remote(int(e[0]), str(e[1]), int(e[2]), Vector3(e[3], e[4], e[5]))
		"ls":
			var e: Array = d["l"]
			loot.spawn_remote(int(e[0]), str(e[1]), int(e[2]), Vector3(e[3], e[4], e[5]))
		"lr":
			var it: LootItem = loot.by_uid.get(int(d["u"]))
			if it != null and player != null and player.global_position.distance_to(it.global_position) < 4.0:
				AudioManager.play_sfx("pickup", -2.0)
			loot.remove_item(it)
		"go":
			_begin_countdown()
		"snap":
			_apply_snap(d)
		"inv":
			_apply_inv(d)
		"hurt":
			if player.alive:
				player.hp = float(d["hp"])
				var f: Array = d["f"]
				Events.player_hurt.emit(Vector3(f[0], f[1], f[2]))
				player.model.animator.trigger("hit")
				AudioManager.play_sfx("hurt", -2.0)
		"hm":
			Events.hit_marker.emit(bool(d["kill"]))
			AudioManager.play_sfx("hit_confirm", -4.0)
		"msg":
			Events.notify.emit(str(d["t"]), "warn")
		"elim":
			_client_elim(d)
		"end":
			var w := by_id.get(int(d["w"])) as Combatant
			_round_over = true
			winner = w
			if w == player and player.alive:
				_player_wins()


func _client_elim(d: Dictionary) -> void:
	Events.notify.emit(str(d["t"]), "kill")
	var c := by_id.get(int(d["id"])) as Combatant
	if c == null or not c.alive:
		return
	c.place = int(d["place"])
	if c == player:
		ended_data = {"won": false, "place": c.place}
		_end_wait = 2.6
		player.inv = Inventory.new()   # o loot do jogador é derrubado pelo host
	c.die(null)


func _apply_snap(d: Dictionary) -> void:
	for e in d["c"]:
		var id := int(e[0])
		var fl := int(e[7])
		if id == my_id:
			if player.alive:
				player.hp = float(e[6])
				player.kills = int(e[11])
			continue
		var p := by_id.get(id) as RemotePuppet
		if p == null:
			continue
		if (fl & 1) == 0:
			if p.alive:
				p.die(null)
			continue
		p.apply_state(Vector3(e[1], e[2], e[3]), float(e[4]), float(e[5]), Vector3(e[9], 0.0, e[10]), (fl & 2) != 0, (fl & 4) != 0)
		var wid := str(e[8])
		if wid != p.weapon_id():
			p.inv.weapons[0] = wid
			p.slot = 0 if wid != "" else -1
			p.model.set_weapon(wid)
		var fc := int(e[12])
		if fc > int(_fire_seen.get(id, fc)) and wid != "":
			Effects.muzzle_flash(self, p.model.muzzle_position())
			AudioManager.play_sfx_3d(str(WeaponDB.get_def(wid).get("sound", "shot_rifle")), p.global_position + Vector3.UP, 0.0, 1.0, 110.0)
		_fire_seen[id] = fc
	zone.apply_net(d["z"])


func _apply_inv(d: Dictionary) -> void:
	var inv := player.inv
	var before := player.weapon_id()
	inv.weapons = d["w"]
	for k in inv.ammo:
		inv.ammo[k] = int(d["a"].get(k, 0))
	for k in inv.items:
		inv.items[k] = int(d["i"].get(k, 0))
	var v: Array = d["v"]
	inv.vest_level = int(v[0])
	inv.vest_hp = float(v[1])
	inv.helmet_level = int(v[2])
	inv.pack_level = int(v[3])
	inv.suppressor = bool(v[4])
	player.mags = d["m"]
	player.damage_dealt = float(d["dm"])
	var s := int(d["s"])
	if player.slot < 0 or str(inv.weapons[player.slot]) == "" or player.weapon_id() != before:
		player.slot = -1
		if s >= 0:
			player.equip(s)


# ------------------------------------------------------------------ saída da partida
func leave() -> void:
	NetClient.leave_room()
	get_tree().paused = false
	SceneRouter.go_lobby()


func play_again() -> void:
	leave()


func _exit_tree() -> void:
	for pair in [[NetClient.relayed, _on_relay], [NetClient.server_message, _on_server_msg], [NetClient.disconnected, _net_lost],
			[Events.combatant_damaged, _on_damaged_net]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	super._exit_tree()
