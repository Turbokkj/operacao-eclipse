class_name Bot
extends Combatant
## Bot autônomo. Usa as MESMAS regras do jogador (mesmas armas, vida, velocidade, zona) e NÃO tem visão através
## de obstáculos: percebe por campo de visão + raio contra o cenário, e por sons emitidos no jogo.
## Estados: INIT, EXPLORE, SEEK_LOOT, LOOTING, MOVE, OBSERVE, COMBAT, REPOSITION, RECOVER, TO_ZONE, INVESTIGATE, DEAD.
## A decisão roda em intervalos escalonados (think); movimento/animação rodam por frame.

enum S { INIT, EXPLORE, SEEK_LOOT, LOOTING, MOVE, OBSERVE, COMBAT, REPOSITION, RECOVER, TO_ZONE, INVESTIGATE, DEAD }

# think = intervalo de decisão (s) | react = atraso de reação ao ver inimigo | aim_err = erro de mira (graus)
# vision = alcance (m) | fov = campo de visão (graus) | zone_lead = antecedência para ir à zona (s)
const PROFILES := {
	"beginner": {"think": 0.55, "react": 0.95, "aim_err": 8.5, "vision": 42.0, "fov": 100.0, "heal_at": 0.35,
		"zone_lead": 12.0, "loot_range": 45.0, "strafe": 0.3, "retreat_hp": 0.0, "pursue": false},
	"intermediate": {"think": 0.33, "react": 0.5, "aim_err": 4.5, "vision": 62.0, "fov": 110.0, "heal_at": 0.55,
		"zone_lead": 28.0, "loot_range": 70.0, "strafe": 0.6, "retreat_hp": 0.25, "pursue": true},
	"advanced": {"think": 0.2, "react": 0.28, "aim_err": 2.2, "vision": 80.0, "fov": 120.0, "heal_at": 0.65,
		"zone_lead": 45.0, "loot_range": 100.0, "strafe": 0.9, "retreat_hp": 0.35, "pursue": true},
}

const NAMES := ["Ravena", "Tigre", "Falcão", "Sombra", "Jaguar", "Vento", "Cobra", "Lobo", "Raio", "Pantera", "Corvo",
	"Estrela", "Trovão", "Fênix", "Gavião", "Onça", "Névoa", "Âmbar", "Cometa", "Zênite", "Aurora", "Basalto", "Cinzas",
	"Diesel", "Eclipse", "Faísca", "Granito", "Hélio", "Ícaro", "Júpiter", "Kraken", "Lince", "Mistral", "Nimbo", "Orion",
	"Pulsar", "Quasar", "Relâmpago", "Safira", "Tufão"]

var prof: Dictionary = {}
var level_name := "intermediate"
var state: int = S.INIT
var state_t := 0.0
var map: MapData
var nav: NavGrid
var loot_mgr: LootManager
var zone: ZoneController
var training := false
var path: Array = []
var path_i := 0
var has_goal := false
var target: Combatant
var target_visible := false
var target_seen_t := -100.0
var target_last_pos := Vector3.ZERO
var react_timer := 0.0
var heard_pos := Vector3.ZERO
var heard_t := -100.0
var think_cd := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var loot_target: LootItem
var observe_t := 0.0
var init_delay := 1.5
var sidestep_t := 0.0
var sidestep_dir := Vector3.ZERO
var visited := {}
var bad_loot := {}
var aim_vec := Vector3.FORWARD
var _clock := 0.0
var _want_run := false
var _stuck_acc := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_t := 0.0
var _lod_t := 0.0
var _combat_aiming := false
var _rng := RandomNumberGenerator.new()


func init_bot(p_name: String, level: String, app: Dictionary) -> void:
	display_name = p_name
	level_name = level
	prof = PROFILES[level]
	setup_body(app)
	Events.sound_emitted.connect(_on_sound)
	_rng.randomize()
	init_delay = randf_range(0.8, 3.0)
	think_cd = randf() * 0.4


func is_aiming() -> bool:
	return _combat_aiming


func _on_sound(pos: Vector3, radius: float, source: Node) -> void:
	if source == self or not alive or training:
		return
	if global_position.distance_to(pos) <= radius:
		heard_pos = pos
		heard_t = _clock


func _on_damaged(attacker: Node) -> void:
	var a := attacker as Combatant
	if a != null and a != self and not training:
		# sentiu o dano: sabe a direção geral do atirador (som do impacto), mas não a posição exata
		heard_pos = a.global_position
		heard_t = _clock
		if target == null:
			target = a
			target_seen_t = _clock - 1.0
			target_last_pos = a.global_position


func _on_died(_killer: Node) -> void:
	state = S.DEAD
	path.clear()
	_combat_aiming = false
	await get_tree().create_timer(9.0).timeout
	if is_inside_tree():
		queue_free()


# ------------------------------------------------------------------ decisão
func _control(delta: float) -> void:
	_clock += delta
	state_t += delta
	think_cd -= delta
	if think_cd <= 0.0:
		think_cd = float(prof["think"]) * randf_range(0.8, 1.25)
		_think()
	_act(delta)


func _enter(s: int) -> void:
	state = s
	state_t = 0.0
	_want_run = false
	match s:
		S.EXPLORE:
			_pick_explore_goal()
		S.SEEK_LOOT:
			if loot_target != null and is_instance_valid(loot_target):
				if not _set_goal(loot_target.global_position):
					bad_loot[loot_target.get_instance_id()] = _clock
					loot_target = null
					state = S.EXPLORE
			_want_run = true
		S.LOOTING:
			path.clear()
		S.RECOVER:
			path.clear()
			var h := "medkit" if (hp < 50.0 and int(inv.items["medkit"]) > 0) else ("bandage" if int(inv.items["bandage"]) > 0 else "energy")
			if not use_heal(h):
				use_heal("medkit")
		S.TO_ZONE:
			if zone != null:
				_set_goal(zone.safe_point(nav))
			_want_run = true
		S.INVESTIGATE:
			_set_goal(heard_pos)
		S.REPOSITION:
			_pick_reposition_goal()
			_want_run = true
		S.OBSERVE:
			observe_t = randf_range(1.5, 3.2)
			path.clear()
		S.COMBAT:
			strafe_t = 0.0
		S.MOVE:
			_want_run = true


func _perceive() -> void:
	var best: Combatant = null
	var bd := INF
	var eye := eye_pos()
	var fwd := -global_basis.z
	var vision := float(prof["vision"])
	var half_fov := deg_to_rad(float(prof["fov"]) * 0.5)
	var space := get_world_3d().direct_space_state
	for o in get_tree().get_nodes_in_group("combatants"):
		var c := o as Combatant
		if c == null or c == self or not c.alive:
			continue
		if training and not c.is_player:
			continue
		var to := c.chest_pos() - eye
		var dist := to.length()
		if dist > vision or dist >= bd:
			continue
		if dist > 7.0 and fwd.angle_to(to) > half_fov:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, c.chest_pos(), L_WORLD)
		if not space.intersect_ray(q).is_empty():
			continue
		bd = dist
		best = c
	target_visible = best != null
	if best != null:
		if target != best or _clock - target_seen_t > 2.5:
			react_timer = float(prof["react"])
		target = best
		target_seen_t = _clock
		target_last_pos = best.global_position
	elif target != null and (not is_instance_valid(target) or not target.alive or _clock - target_seen_t > 7.0):
		target = null


func _zone_danger() -> bool:
	if zone == null or training:
		return false
	var p := Vector2(global_position.x, global_position.z)
	if not zone.inside(p, 0.0):
		return true
	if zone.next_radius >= 0.0 and (zone.shrinking or zone.time_to_shrink() < float(prof["zone_lead"])):
		if not zone.inside_next(p, 6.0):
			return true
	return false


func _think() -> void:
	if not alive:
		return
	_lod_update()
	if state == S.INIT:
		if state_t > init_delay:
			_enter(S.EXPLORE)
		return
	_perceive()
	var hr := hp_ratio()
	var armed := has_usable_weapon()
	var fighting := target != null and is_instance_valid(target) and target.alive and (target_visible or _clock - target_seen_t < 3.0)
	var retreat := float(prof["retreat_hp"])
	if fighting:
		if armed and hr > retreat:
			if state != S.COMBAT:
				_enter(S.COMBAT)
			return
		if state != S.REPOSITION:
			_enter(S.REPOSITION)
		return
	if state == S.COMBAT:
		# perdeu o alvo: perseguir a última posição conhecida (perfis intermediário/avançado) ou observar
		if bool(prof["pursue"]) and armed and target_last_pos != Vector3.ZERO and _clock - target_seen_t < 7.0:
			_set_goal(target_last_pos)
			state = S.MOVE
			state_t = 0.0
			_want_run = true
		else:
			_enter(S.OBSERVE)
		return
	if _zone_danger():
		if state != S.TO_ZONE:
			_enter(S.TO_ZONE)
		return
	if state == S.TO_ZONE:
		_enter(S.OBSERVE)
		return
	if hr < float(prof["heal_at"]) and inv.has_heal() and heal_left <= 0.0:
		if state != S.RECOVER:
			_enter(S.RECOVER)
		return
	if state == S.RECOVER:
		return
	if armed and mag_now() < int(weapon_def()["mag"]) * 0.4 and reserve_now() > 0:
		start_reload()
	if not training and _clock - heard_t < 4.0 and armed and hr > 0.5 and level_name != "beginner" and state != S.INVESTIGATE and state != S.SEEK_LOOT:
		_enter(S.INVESTIGATE)
		return
	if not training and state != S.LOOTING:
		var it := _find_loot()
		if it != null and (state != S.SEEK_LOOT or it != loot_target):
			loot_target = it
			_enter(S.SEEK_LOOT)
			return
	if state == S.MOVE or state == S.REPOSITION or state == S.INVESTIGATE:
		if path.is_empty():
			_enter(S.OBSERVE)
	elif state == S.EXPLORE:
		if path.is_empty() and state_t > 1.0:
			_enter(S.OBSERVE if randf() < 0.45 else S.EXPLORE)
	elif state == S.OBSERVE and observe_t <= 0.0:
		_enter(S.EXPLORE)
	elif state == S.SEEK_LOOT and (loot_target == null or not is_instance_valid(loot_target)):
		_enter(S.EXPLORE)


func _lod_update() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	anim_interval = 1 if d < 40.0 else (2 if d < 90.0 else (4 if d < 200.0 else 8))
	model.visible = d < QualityManager.render_distance() + 20.0


func _loot_score(id: String) -> float:
	var d := ItemDB.get_def(id)
	match str(d["cat"]):
		"weapon":
			if not inv.has_any_weapon():
				return 100.0
			var rank_new := WeaponDB.PRIORITY.find(id)
			var cur := weapon_id()
			var rank_cur := WeaponDB.PRIORITY.find(cur) if cur != "" else 9
			if inv.weapons.has("") and rank_new < 9:
				return 35.0
			return 45.0 if rank_new < rank_cur else 0.0
		"ammo":
			var need := 0.0
			for i in 3:
				var wid := str(inv.weapons[i])
				if wid != "" and str(WeaponDB.get_def(wid)["ammo"]) == str(d["ammo"]):
					need = maxf(need, 70.0 - inv.ammo_count(str(d["ammo"])))
			return clampf(need, 0.0, 60.0) * 0.9
		"heal":
			return 40.0 if int(inv.items["bandage"]) + int(inv.items["medkit"]) < 3 else 10.0
		"armor":
			if str(d["slot"]) == "vest":
				return 45.0 + 5.0 * int(d["level"]) if int(d["level"]) > inv.vest_level else 0.0
			return 40.0 + 5.0 * int(d["level"]) if int(d["level"]) > inv.helmet_level else 0.0
		"pack":
			return 25.0 if int(d["level"]) > inv.pack_level else 0.0
		"acc":
			return 12.0 if not inv.suppressor else 0.0
	return 0.0


func _find_loot() -> LootItem:
	if loot_mgr == null:
		return null
	var best: LootItem = null
	var best_s := 8.0
	for it in loot_mgr.query(global_position, float(prof["loot_range"])):
		var li := it as LootItem
		if not li.bot_ok or bad_loot.has(li.get_instance_id()):
			continue
		var s := _loot_score(li.item_id) - global_position.distance_to(li.global_position) * 0.45
		if s > best_s:
			best_s = s
			best = li
	return best


func _set_goal(p: Vector3) -> bool:
	has_goal = true
	path = nav.find_path(global_position, p) if nav != null else [p]
	path_i = 0
	if path.is_empty():
		has_goal = false
		return false
	return true


func _pick_explore_goal() -> void:
	if training or map == null or map.buildings.is_empty():
		var p := Vector3(-52.0 + randf_range(-22.0, 22.0), 0.0, 4.0 + randf_range(-22.0, 22.0))
		if map != null and nav != null:
			p = nav.random_free_point(_rng, global_position, 35.0)
		_set_goal(p)
		return
	var best: BuildingInfo = null
	var best_s := -INF
	for b in map.buildings:
		var bi := b as BuildingInfo
		if visited.has(bi.uid) and _clock - float(visited[bi.uid]) < 120.0:
			continue
		var c := bi.center()
		var s := float(bi.tier + 1) * 25.0 - c.distance_to(global_position) * 0.22 + randf() * 45.0
		if zone != null and not zone.inside_next(Vector2(c.x, c.z), 0.0):
			s -= 140.0
		if s > best_s:
			best_s = s
			best = bi
	if best == null:
		_set_goal(nav.random_free_point(_rng, global_position, 60.0))
		return
	visited[best.uid] = _clock
	var room: Rect2 = best.rooms[randi() % best.rooms.size()]
	if not _set_goal(Vector3(room.get_center().x, best.ground, room.get_center().y)):
		_set_goal(nav.random_free_point(_rng, global_position, 50.0))


func _pick_reposition_goal() -> void:
	var away := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	if target != null and is_instance_valid(target):
		away = (global_position - target.global_position)
		away.y = 0.0
		away = away.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8))
	var p := nav.random_free_point(_rng, global_position + away * 22.0, 8.0) if nav != null else global_position + away * 20.0
	_set_goal(p)


# ------------------------------------------------------------------- ação
func _act(delta: float) -> void:
	var desired := Vector3.ZERO
	var speed := 5.4 if _want_run else 3.2
	var face_dir := Vector3.ZERO
	_combat_aiming = false
	match state:
		S.INIT, S.LOOTING, S.RECOVER:
			if state == S.LOOTING and state_t > 0.55:
				_do_pickup()
			if state == S.RECOVER and heal_left <= 0.0 and state_t > 0.2:
				_enter(S.EXPLORE)
		S.OBSERVE:
			observe_t -= delta
			face_dir = (-global_basis.z).rotated(Vector3.UP, sin(state_t * 1.4) * 0.7)
		S.COMBAT:
			var r := _combat(delta)
			desired = r[0]
			face_dir = r[1]
			speed = 3.2
		_:
			desired = _follow_path()
			if state == S.SEEK_LOOT and loot_target != null and is_instance_valid(loot_target):
				var dd := loot_target.global_position - global_position
				dd.y = 0.0
				if dd.length() < 1.6:
					_enter(S.LOOTING)
				elif path.is_empty() and state_t > 0.5:
					_set_goal(loot_target.global_position)
					if state_t > 25.0:
						bad_loot[loot_target.get_instance_id()] = _clock
						_enter(S.EXPLORE)
			if state == S.REPOSITION and target != null and is_instance_valid(target) and target_visible and has_usable_weapon():
				face_dir = target.chest_pos() - eye_pos()
	# --------- aplicação do movimento
	desired = _avoid(desired)
	if sidestep_t > 0.0:
		sidestep_t -= delta
		desired = sidestep_dir
	var tv := desired * speed
	if boost_left > 0.0:
		tv *= 1.25
	if heal_left > 0.0:
		tv *= 0.5
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(tv, 30.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	var yaw_t := rotation.y
	if face_dir.length() > 0.01:
		yaw_t = atan2(-face_dir.x, -face_dir.z)
		aim_pitch = asin(clampf(face_dir.normalized().y, -1.0, 1.0)) if state == S.COMBAT else 0.0
	elif hv.length() > 0.4:
		yaw_t = atan2(-hv.x, -hv.z)
		aim_pitch = 0.0
	rotation.y = lerp_angle(rotation.y, yaw_t, 1.0 - exp(-10.0 * delta))
	move_and_slide()
	_check_stuck(delta, desired.length() > 0.1)


func _follow_path() -> Vector3:
	if path.is_empty() or path_i >= path.size():
		return Vector3.ZERO
	var tgt: Vector3 = path[path_i]
	var to := tgt - global_position
	to.y = 0.0
	if to.length() < 0.9:
		path_i += 1
		if path_i >= path.size():
			path.clear()
			return Vector3.ZERO
		tgt = path[path_i]
		to = tgt - global_position
		to.y = 0.0
	return to.normalized()


## Separação simples entre combatentes próximos (evita empilhar).
func _avoid(desired: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("combatants"):
		if o == self:
			continue
		var d := global_position - (o as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l < 1.3 and l > 0.01:
			push += d / l * (1.3 - l)
	if push == Vector3.ZERO:
		return desired
	var out := desired + push * 0.9
	return out.normalized() * minf(out.length(), 1.0)


func _check_stuck(delta: float, wants_move: bool) -> void:
	_stuck_t += delta
	if _stuck_t < 0.6:
		return
	_stuck_t = 0.0
	if wants_move and global_position.distance_to(_stuck_pos) < 0.25:
		_stuck_acc += 0.6
		if _stuck_acc >= 1.2:
			sidestep_t = 0.7
			sidestep_dir = (-global_basis.z).rotated(Vector3.UP, randf_range(1.2, 2.0) * (1.0 if randf() < 0.5 else -1.0))
			if _stuck_acc >= 3.0:
				_stuck_acc = 0.0
				path.clear()
				if state == S.SEEK_LOOT and loot_target != null and is_instance_valid(loot_target):
					bad_loot[loot_target.get_instance_id()] = _clock
					loot_target = null
					_enter(S.EXPLORE)
	else:
		_stuck_acc = maxf(0.0, _stuck_acc - 0.6)
	_stuck_pos = global_position


func _do_pickup() -> void:
	if loot_target != null and is_instance_valid(loot_target) and not loot_target.picked \
			and global_position.distance_to(loot_target.global_position) < 2.6:
		var res := pickup_item(loot_target.item_id, loot_target.qty)
		if res["ok"]:
			loot_mgr.remove_item(loot_target)
			equip_best()
		else:
			bad_loot[loot_target.get_instance_id()] = _clock
	loot_target = null
	_enter(S.EXPLORE)


## Comportamento de combate: mira com erro, reação, estratégia de distância e deslocamento lateral.
## Retorna [velocidade desejada, direção do olhar].
func _combat(delta: float) -> Array:
	if target == null or not is_instance_valid(target) or not target.alive:
		_enter(S.EXPLORE)
		return [Vector3.ZERO, Vector3.ZERO]
	var tpos := target.chest_pos()
	var to := tpos - eye_pos()
	var dist := maxf(to.length(), 0.1)
	var dirn := to / dist
	var desired := Vector3.ZERO
	if not target_visible:
		# sem visão: ir até a última posição conhecida
		if bool(prof["pursue"]):
			if path.is_empty() and _clock - target_seen_t > 0.5:
				_set_goal(target_last_pos)
			desired = _follow_path()
		return [desired, Vector3.ZERO]
	_combat_aiming = true
	aim_vec = dirn
	var w := weapon_def()
	var pref := float(w.get("pref_dist", 25.0))
	var flat := Vector3(dirn.x, 0.0, dirn.z).normalized()
	var side := flat.cross(Vector3.UP) * strafe_dir
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = randf_range(0.8, 2.0)
		strafe_dir = 1.0 if randf() < 0.5 else -1.0
	desired = side * float(prof["strafe"])
	if dist > pref + 8.0:
		desired += flat * 0.8
	elif dist < pref - 8.0:
		desired -= flat * 0.8
	if react_timer > 0.0:
		react_timer -= delta
		desired *= 0.3
	elif has_usable_weapon():
		if mag_now() <= 0:
			start_reload()
		else:
			var facing := (-global_basis.z).angle_to(dirn)
			if facing < deg_to_rad(14.0) and dist < float(w["range"]):
				var err := float(prof["aim_err"]) * (0.6 + dist / 70.0)
				var origin := chest_pos() + dirn * 0.5
				try_fire(origin, _spread_dir(dirn, err))
	return [desired, dirn]
