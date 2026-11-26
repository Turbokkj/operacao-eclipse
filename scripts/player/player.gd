class_name Player
extends Combatant
## Jogador humano. Movimento relativo à câmera com aceleração/desaceleração suaves, buffer de pulo e
## "coyote time", agachar com checagem de teto, correr, mirar, atirar, recarregar, curar e coletar itens.
## Lê teclado/mouse e o estado touch (GameSettings.t_*) pelo mesmo caminho.

const WALK := 3.2
const RUN := 5.6
const CROUCH_SPEED := 1.9
const AIM_WALK := 2.4
const JUMP_V := 6.4
const ACCEL := 34.0
const DECEL := 44.0
const AIR_CONTROL := 0.35

var cam: ThirdPersonCamera
var net_pickup_cb := Callable()   # cliente online: pede a coleta ao host em vez de coletar localmente
var loot_mgr: Node
var ctl_enabled := true
var nearest_item: Node3D
var want_aim := false
var want_fire := false
var _fire_prev := false
var _coyote := 0.0
var _jump_buf := 0.0
var _interact_t := 0.0
var _pending: Node3D
var _fire_clock := -10.0
var _was_air := false
var _fall_speed := 0.0


func init_player(app: Dictionary, p_name: String) -> void:
	is_player = true
	display_name = p_name
	setup_body(app)


func is_aiming() -> bool:
	return want_aim


func _movement_spread() -> float:
	var s := 1.0 + Vector2(velocity.x, velocity.z).length() * 0.10
	if want_aim:
		s *= 0.6
	if crouching:
		s *= 0.8
	return s


func _control(delta: float) -> void:
	var touch := GameSettings.touch_mode
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var mv := Vector2.ZERO
	var jump_pressed := false
	if ctl_enabled:
		mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if mv.length() < 0.05 and GameSettings.t_move.length() > 0.05:
			mv = GameSettings.t_move
		jump_pressed = Input.is_action_just_pressed("jump")
	want_fire = ctl_enabled and ((captured and Input.is_action_pressed("fire")) or GameSettings.t_fire)
	want_aim = ctl_enabled and ((captured and Input.is_action_pressed("aim")) or GameSettings.t_aim)
	var want_crouch := ctl_enabled and (Input.is_action_pressed("crouch") or GameSettings.t_crouch)
	var want_sprint := ctl_enabled and (Input.is_action_pressed("sprint") or GameSettings.t_sprint \
		or (touch and bool(GameSettings.get_s("auto_sprint")) and mv.length() > 0.92))
	set_crouch(want_crouch)
	if cam != null:
		cam.aiming = want_aim
		cam.firing = want_fire
		cam.weapon_zoom = float(weapon_def().get("zoom", 1.0))
		cam.look_locked = not ctl_enabled
		aim_pitch = clampf(cam.pitch, -1.0, 1.0)

	# ---------------- movimento horizontal (relativo ao yaw da câmera)
	var yaw := cam.yaw if cam != null else rotation.y
	var wish := Basis(Vector3.UP, yaw) * Vector3(mv.x, 0.0, mv.y)
	var spd := WALK
	if crouching:
		spd = CROUCH_SPEED
	elif want_aim:
		spd = AIM_WALK
	elif want_sprint and mv.length() > 0.1 and not want_fire:
		spd = RUN
	if boost_left > 0.0:
		spd *= 1.25
	if heal_left > 0.0:
		spd *= 0.55
	var target_v := wish * spd * minf(mv.length(), 1.0)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL if target_v.length() > hv.length() * 0.95 else DECEL
	if not is_on_floor():
		rate *= AIR_CONTROL
	hv = hv.move_toward(target_v, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z

	# ---------------- vertical: gravidade, coyote time, buffer de pulo
	if is_on_floor():
		_coyote = 0.12
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		_coyote -= delta
		velocity.y -= GRAVITY * delta
	_jump_buf = 0.12 if jump_pressed else _jump_buf - delta
	if _jump_buf > 0.0 and _coyote > 0.0 and not crouching:
		velocity.y = JUMP_V
		_coyote = 0.0
		_jump_buf = 0.0
		AudioManager.play_sfx("jump", -8.0)

	# ---------------- orientação do corpo
	var now := Time.get_ticks_msec() / 1000.0
	var target_yaw := rotation.y
	if want_aim or want_fire or now - _fire_clock < 0.8:
		target_yaw = yaw
	elif hv.length() > 0.4:
		target_yaw = atan2(-hv.x, -hv.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))

	_fall_speed = minf(_fall_speed, velocity.y)
	move_and_slide()
	var on_floor := is_on_floor()
	if _was_air and on_floor:
		if _fall_speed < -6.0:
			AudioManager.play_sfx("land", -6.0)
		_fall_speed = 0.0
	_was_air = not on_floor

	# ---------------- ações
	if ctl_enabled:
		_handle_actions()
		_handle_fire(now)
	_handle_pickup(delta)


func _handle_actions() -> void:
	if Input.is_action_just_pressed("weapon_1"):
		equip(0)
	if Input.is_action_just_pressed("weapon_2"):
		equip(1)
	if Input.is_action_just_pressed("weapon_3"):
		equip(2)
	if Input.is_action_just_pressed("next_weapon"):
		next_weapon()
	if Input.is_action_just_pressed("reload"):
		start_reload()
	if Input.is_action_just_pressed("use_bandage"):
		if not use_heal("bandage"):
			use_heal("energy")
	if Input.is_action_just_pressed("use_medkit"):
		use_heal("medkit")


func _handle_fire(now: float) -> void:
	if want_fire and slot >= 0 and cam != null:
		var w := weapon_def()
		if bool(w["auto"]) or not _fire_prev:
			_fire_clock = now
			var dir := cam.aim_dir()
			var origin := cam.camera.global_position + dir * cam.current_length()
			if try_fire(origin, dir):
				cam.add_recoil(float(w["recoil"]))
	_fire_prev = want_fire


func _handle_pickup(delta: float) -> void:
	if loot_mgr != null and alive:
		nearest_item = loot_mgr.nearest(global_position, 2.6)
	else:
		nearest_item = null
	if ctl_enabled and Input.is_action_just_pressed("interact") and nearest_item != null and _pending == null:
		_pending = nearest_item
		_interact_t = 0.3
		model.animator.trigger("interact", 0.5)
	if _pending != null:
		_interact_t -= delta
		if _interact_t <= 0.0:
			_complete_pickup()


func _complete_pickup() -> void:
	var item := _pending
	_pending = null
	if item == null or not is_instance_valid(item) or global_position.distance_to(item.global_position) > 3.4:
		return
	if net_pickup_cb.is_valid():
		net_pickup_cb.call(item)
		return
	var res := pickup_item(str(item.item_id), int(item.qty))
	if res["ok"]:
		loot_mgr.remove_item(item)
		AudioManager.play_sfx("pickup", -2.0)
		Events.notify.emit("Coletou: %s" % str(res["msg"]), "good")
	else:
		Events.notify.emit(str(res["msg"]), "warn")


func _on_died(_killer: Node) -> void:
	ctl_enabled = false
	want_fire = false
	want_aim = false
	GameSettings.clear_touch_state()
