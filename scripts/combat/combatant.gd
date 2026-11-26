class_name Combatant
extends CharacterBody3D
## Base comum de jogador e bots. As MESMAS regras valem para todos: vida, proteção, inventário, armas,
## recarga, cura, tiro por raycast (hitscan), ruído audível pelos bots e eliminação.

const L_WORLD := 1
const L_CHAR := 2
const L_TARGET := 4
const RAY_MASK := 7
const GRAVITY := 20.0

var display_name := "Jogador"
var hp := 100.0
var max_hp := 100.0
var alive := true
var kills := 0
var damage_dealt := 0.0
var shots := 0
var hits := 0
var inv := Inventory.new()
var slot := -1
var mags: Array = [0, 0, 0]
var model: CharacterModel
var crouching := false
var aim_pitch := 0.0
var fire_cd := 0.0
var reload_left := 0.0
var heal_left := 0.0
var heal_item := ""
var boost_left := 0.0
var is_player := false
var invulnerable := false
var anim_interval := 1
var survive_time := 0.0
var place := 0
var capsule: CapsuleShape3D
var col_shape: CollisionShape3D
var net_id := 0                 # id de rede (jogadores humanos = id do servidor; bots = 1000+)
var fire_count := 0             # contador de disparos (sincronizado para efeitos remotos)
var net_hook := Callable()      # (kind: String, arg) -> void; usado pelo cliente online para avisar o host
var _bloom := 0.0
var _anim_acc := 0.0
var _anim_off := 0


func setup_body(appearance: Dictionary) -> void:
	collision_layer = L_CHAR
	collision_mask = L_WORLD | L_CHAR
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	max_slides = 6
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	col_shape = CollisionShape3D.new()
	col_shape.shape = capsule
	col_shape.position.y = 0.875
	add_child(col_shape)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.setup(appearance)
	model.animator.footstep.connect(_on_footstep)
	add_to_group("combatants")
	_anim_off = randi() % 4


# ------------------------------------------------------------------ ciclo
func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		if is_on_floor():
			set_physics_process(false)
		return
	survive_time += delta
	fire_cd = maxf(0.0, fire_cd - delta)
	_bloom = maxf(0.0, _bloom - delta * 1.4)
	if boost_left > 0.0:
		boost_left -= delta
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	if heal_left > 0.0:
		heal_left -= delta
		if heal_left <= 0.0:
			_finish_heal()
	_control(delta)


func _process(delta: float) -> void:
	if model == null or model.animator == null:
		return
	_anim_acc += delta
	if anim_interval > 1 and (Engine.get_process_frames() + _anim_off) % anim_interval != 0:
		return
	var a := model.animator
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var local := global_basis.inverse() * hv
	a.move = Vector2(local.x, -local.z) / 5.5
	a.speed = hv.length()
	a.crouching = crouching
	a.grounded = is_on_floor() or not alive
	a.vy = velocity.y
	a.armed = weapon_id() != "" and alive
	a.aiming = is_aiming()
	a.pitch = aim_pitch
	a.update(_anim_acc)
	_anim_acc = 0.0


# ganchos para Player / Bot
func _control(_delta: float) -> void:
	pass


func is_aiming() -> bool:
	return false


func _movement_spread() -> float:
	return 1.0 + Vector2(velocity.x, velocity.z).length() * 0.10


func _on_damaged(_attacker: Node) -> void:
	pass


func _on_died(_killer: Node) -> void:
	pass


func _on_footstep(foot: int) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	if crouching or spd < 1.0 or not alive:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(global_position) < 45.0:
		AudioManager.play_sfx_3d("step_a" if foot == 0 else "step_b", global_position, -14.0 + (4.0 if spd > 4.5 else 0.0), randf_range(0.9, 1.1), 40.0)
	if spd > 4.5:
		Events.sound_emitted.emit(global_position, 24.0, self)
	elif spd > 2.0:
		Events.sound_emitted.emit(global_position, 10.0, self)


# ------------------------------------------------------------------ utilidades
func eye_pos() -> Vector3:
	return global_position + Vector3(0.0, 0.95 if crouching else 1.55, 0.0)


func chest_pos() -> Vector3:
	return global_position + Vector3(0.0, 0.7 if crouching else 1.2, 0.0)


func head_line() -> float:
	return 1.05 if crouching else 1.52


func set_crouch(c: bool) -> void:
	if c == crouching:
		return
	if not c and test_move(global_transform, Vector3.UP * 0.62):
		return
	crouching = c
	capsule.height = 1.15 if c else 1.75
	col_shape.position.y = capsule.height * 0.5


func _net(kind: String, arg: Variant) -> void:
	if net_hook.is_valid():
		net_hook.call(kind, arg)


func hp_ratio() -> float:
	return hp / max_hp


# ------------------------------------------------------------------ armas
func weapon_id() -> String:
	if slot < 0:
		return ""
	return str(inv.weapons[slot])


func weapon_def() -> Dictionary:
	return WeaponDB.get_def(weapon_id())


func mag_now() -> int:
	return int(mags[slot]) if slot >= 0 else 0


func reserve_now() -> int:
	var d := weapon_def()
	if d.is_empty():
		return 0
	return inv.ammo_count(str(d["ammo"]))


func has_usable_weapon() -> bool:
	return slot >= 0 and (mag_now() > 0 or reserve_now() > 0)


func equip(i: int) -> void:
	if i < 0 or i > 2 or i == slot or str(inv.weapons[i]) == "":
		return
	slot = i
	reload_left = 0.0
	model.set_weapon(str(inv.weapons[i]))
	model.animator.trigger("equip")
	fire_cd = maxf(fire_cd, 0.35)
	if is_player:
		AudioManager.play_sfx("equip", -6.0)
	_net("eq", i)


func equip_best() -> void:
	var best := -1
	var best_rank := 99
	for i in 3:
		var wid := str(inv.weapons[i])
		if wid == "":
			continue
		var d := WeaponDB.get_def(wid)
		var rank := WeaponDB.PRIORITY.find(wid)
		if int(mags[i]) <= 0 and inv.ammo_count(str(d["ammo"])) <= 0:
			rank += 10
		if rank < best_rank:
			best_rank = rank
			best = i
	if best >= 0:
		equip(best)


func next_weapon() -> void:
	for k in range(1, 4):
		var i := (maxi(slot, 0) + k) % 3
		if str(inv.weapons[i]) != "":
			equip(i)
			return


func start_reload() -> void:
	if slot < 0 or reload_left > 0.0 or heal_left > 0.0 or not alive:
		return
	var d := weapon_def()
	if int(mags[slot]) >= int(d["mag"]) or inv.ammo_count(str(d["ammo"])) <= 0:
		return
	reload_left = float(d["reload"])
	model.animator.trigger("reload", reload_left)
	_net("rl", 0)
	if is_player:
		AudioManager.play_sfx("reload", -4.0)
	else:
		AudioManager.play_sfx_3d("reload", global_position + Vector3.UP, -8.0, 1.0, 30.0)


func _finish_reload() -> void:
	var d := weapon_def()
	if d.is_empty():
		return
	var need := int(d["mag"]) - int(mags[slot])
	mags[slot] = int(mags[slot]) + inv.take_ammo(str(d["ammo"]), need)


## Coleta um item (usado por jogador e bots). Retorna o dicionário de Inventory.add().
func pickup_item(id: String, qty: int) -> Dictionary:
	var res := inv.add(id, qty, maxi(slot, 0))
	if not res["ok"]:
		return res
	if ItemDB.category(id) == "weapon":
		var s: int = res["slot"]
		mags[s] = int(WeaponDB.get_def(id)["mag"])
		var swapped := str(res["swap"])
		if swapped != "":
			get_tree().call_group("loot_manager", "drop_item", swapped, 1, global_position + Vector3(0.0, 0.3, 0.0))
		if slot < 0 or s == slot:
			slot = -1
			equip(s)
	Events.item_picked.emit(id, self)
	return res


# ------------------------------------------------------------------ tiro
func try_fire(origin: Vector3, dir: Vector3) -> bool:
	if not alive or heal_left > 0.0 or reload_left > 0.0 or fire_cd > 0.0 or slot < 0:
		return false
	var w := weapon_def()
	if w.is_empty():
		return false
	if int(mags[slot]) <= 0:
		fire_cd = 0.3
		if is_player:
			AudioManager.play_sfx("empty", -4.0)
		start_reload()
		return false
	mags[slot] = int(mags[slot]) - 1
	fire_cd = 1.0 / float(w["rate"])
	var spread := float(w["spread"]) * (1.0 + _bloom) * _movement_spread()
	for i in int(w["pellets"]):
		shots += 1
		_shoot_ray(origin, _spread_dir(dir, spread), w)
	_bloom = minf(_bloom + 0.16, 1.2)
	var mz := model.muzzle_position()
	Effects.muzzle_flash(self, mz)
	if is_player:
		AudioManager.play_sfx(str(w["sound"]), -2.0, randf_range(0.96, 1.04))
	else:
		AudioManager.play_sfx_3d(str(w["sound"]), mz, 0.0, randf_range(0.96, 1.04), 110.0)
	var noise := float(w["noise"]) * (0.35 if inv.suppressor else 1.0)
	Events.sound_emitted.emit(global_position, noise, self)
	model.animator.trigger("shoot")
	fire_count += 1
	_net("fire", [origin, dir])
	return true


func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.01:
		return dir
	var half := deg_to_rad(deg) * 0.5 * sqrt(randf())
	var th := randf() * TAU
	var b := dir.cross(Vector3.UP)
	if b.length() < 0.01:
		b = dir.cross(Vector3.RIGHT)
	b = b.normalized()
	var c := dir.cross(b).normalized()
	return (dir + (b * cos(th) + c * sin(th)) * tan(half)).normalized()


func _shoot_ray(origin: Vector3, d: Vector3, w: Dictionary) -> void:
	var rng_m := float(w["range"])
	var space := get_world_3d().direct_space_state
	var far_pt := origin + d * rng_m
	var q := PhysicsRayQueryParameters3D.create(origin, far_pt, RAY_MASK, [get_rid()])
	var hit := space.intersect_ray(q)
	var end := far_pt
	var normal := Vector3.UP
	var victim: Object = null
	if not hit.is_empty():
		end = hit["position"]
		normal = hit["normal"]
		victim = hit["collider"]
	var mz := model.muzzle_position()
	if mz.distance_to(end) > 0.6:
		# bloqueio entre a boca da arma e o impacto (quinas, paredes coladas)
		var stop := end - (end - mz).normalized() * 0.1
		var q2 := PhysicsRayQueryParameters3D.create(mz, stop, L_WORLD, [get_rid()])
		var h2 := space.intersect_ray(q2)
		if not h2.is_empty():
			end = h2["position"]
			normal = h2["normal"]
			victim = null
	if victim != null and victim.has_method("take_damage"):
		var dist := origin.distance_to(end)
		var fall := lerpf(1.0, 0.5, clampf((dist - rng_m * 0.35) / (rng_m * 0.65), 0.0, 1.0))
		var head := false
		if victim is Combatant:
			head = (end.y - (victim as Combatant).global_position.y) > (victim as Combatant).head_line()
		elif victim.has_method("is_head_hit"):
			head = victim.is_head_hit(end)
		var dmg := float(w["dmg"]) * fall * (2.0 if head else 1.0)
		hits += 1
		victim.take_damage(dmg, self, end, head)
	else:
		Effects.impact(self, end, normal)
	Effects.tracer(self, mz, end, w["tracer"])


# ------------------------------------------------------------------ dano e cura
func take_damage(amount: float, attacker: Node, hit_pos: Vector3, head: bool) -> void:
	if not alive or invulnerable:
		return
	var dmg := amount
	if head and inv.helmet_level > 0:
		dmg *= 1.0 - inv.helmet_reduce()
	elif not head and inv.vest_hp > 0.0:
		var absorbed := minf(inv.vest_hp, dmg * 0.55)
		inv.vest_hp -= absorbed
		dmg -= absorbed
		if inv.vest_hp <= 0.0:
			inv.vest_level = 0
	hp -= dmg
	var atk := attacker as Combatant
	if atk != null:
		atk.damage_dealt += dmg
	Events.combatant_damaged.emit(self, attacker, dmg, head)
	if is_player:
		Events.player_hurt.emit(attacker.global_position if attacker is Node3D else global_position)
	model.animator.trigger("hit")
	AudioManager.play_sfx_3d("hurt" if is_player else "hit", hit_pos, -2.0, 1.0, 40.0)
	if atk != null and atk.is_player:
		Events.hit_marker.emit(hp <= 0.0)
		AudioManager.play_sfx("hit_confirm", -4.0)
	_on_damaged(attacker)
	if hp <= 0.0:
		die(attacker)


## Dano da zona: ignora proteções.
func zone_damage(amount: float) -> void:
	if not alive or invulnerable:
		return
	hp -= amount
	if is_player:
		Events.player_hurt.emit(global_position)
	if hp <= 0.0:
		die(null)


func use_heal(id: String) -> bool:
	if heal_left > 0.0 or reload_left > 0.0 or not alive:
		return false
	var d := ItemDB.get_def(id)
	if d.is_empty() or int(inv.items.get(id, 0)) <= 0:
		return false
	if hp >= float(d["max_hp"]) - 0.5:
		if is_player:
			Events.notify.emit("Vida já está alta para usar %s" % str(d["name"]), "info")
		return false
	heal_item = id
	heal_left = float(d["time"])
	_net("heal", id)
	model.animator.trigger("interact", heal_left)
	if is_player:
		AudioManager.play_sfx("heal", -2.0)
	return true


func _finish_heal() -> void:
	var d := ItemDB.get_def(heal_item)
	if d.is_empty() or not inv.consume(heal_item):
		return
	hp = maxf(hp, minf(hp + float(d["heal"]), float(d["max_hp"])))
	if d.has("boost"):
		boost_left = float(d["boost"])
	if is_player:
		Events.notify.emit("+%d vida" % int(d["heal"]), "good")


func die(killer: Node) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	collision_layer = 0
	collision_mask = L_WORLD
	heal_left = 0.0
	reload_left = 0.0
	model.animator.trigger("death")
	AudioManager.play_sfx_3d("death", global_position + Vector3.UP, -2.0, 1.0, 50.0)
	var k := killer as Combatant
	if k != null and k != self:
		k.kills += 1
	get_tree().call_group("loot_manager", "drop_from", self)
	model.set_weapon("")
	inv = Inventory.new()
	slot = -1
	Events.combatant_eliminated.emit(self, killer)
	_on_died(killer)
