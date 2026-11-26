class_name ThirdPersonCamera
extends Node3D
## Câmera em terceira pessoa por cima do ombro: colisão com cenário (SpringArm3D), zoom ao mirar,
## sensibilidade horizontal/vertical/mira, recuo de arma e MIRA ASSISTIDA suave (4 níveis).
## A assistência só age ao mirar/atirar, só em alvos visíveis (raio contra o cenário) e nunca "trava".

var target: Combatant
var yaw := 0.0
var pitch := -0.12
var camera: Camera3D
var arm: SpringArm3D
var pivot: Node3D
var aiming := false
var firing := false
var weapon_zoom := 1.0
var enemies_provider := Callable()
var base_fov := 72.0
var look_locked := false
var _len := 3.4
var _side := 0.65
var _user_acc := 0.0
var _assist_active := false


func _ready() -> void:
	top_level = true
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.12
	var sh := SphereShape3D.new()
	sh.radius = 0.22
	arm.shape = sh
	arm.spring_length = _len
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.12
	camera.far = QualityManager.render_distance() + 60.0
	arm.add_child(camera)
	camera.make_current()


func aim_dir() -> Vector3:
	return -camera.global_basis.z


func current_length() -> float:
	return arm.get_hit_length()


func add_recoil(deg: float) -> void:
	pitch = clampf(pitch + deg_to_rad(deg) * 0.55, -1.2, 1.1)
	yaw += randf_range(-1.0, 1.0) * deg_to_rad(deg) * 0.22


func _input(event: InputEvent) -> void:
	if look_locked or target == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var k := 0.0022 * (float(GameSettings.get_s("sens_aim")) if aiming else 1.0) * _assist_friction()
		var inv := -1.0 if bool(GameSettings.get_s("invert_y")) else 1.0
		yaw -= mm.relative.x * k * float(GameSettings.get_s("sens_h"))
		pitch -= mm.relative.y * k * float(GameSettings.get_s("sens_v")) * inv
		_user_acc += mm.relative.length() * k


func _assist_friction() -> float:
	return 1.0 - 0.10 * float(GameSettings.aim_assist_level()) * (1.0 if _assist_active else 0.0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not look_locked:
		var t := GameSettings.t_look
		GameSettings.t_look = Vector2.ZERO
		if t != Vector2.ZERO:
			var k := 0.0042 * (float(GameSettings.get_s("sens_aim")) if aiming else 1.0) * _assist_friction()
			var inv := -1.0 if bool(GameSettings.get_s("invert_y")) else 1.0
			yaw -= t.x * k * float(GameSettings.get_s("sens_h"))
			pitch -= t.y * k * float(GameSettings.get_s("sens_v")) * inv
			_user_acc += t.length() * k
		var user_speed := rad_to_deg(_user_acc) / maxf(delta, 0.001)
		_user_acc = 0.0
		_apply_aim_assist(delta, user_speed)
	pitch = clampf(pitch, -1.2, 1.1)
	yaw = wrapf(yaw, -PI, PI)
	var want := target.global_position + Vector3(0.0, 1.05 if target.crouching else 1.55, 0.0)
	global_position = global_position.lerp(want, 1.0 - exp(-24.0 * delta))
	rotation.y = yaw
	pivot.rotation.x = pitch
	var aim_t := 1.0 if aiming else 0.0
	var k2 := 1.0 - exp(-12.0 * delta)
	_len = lerpf(_len, lerpf(3.4, 1.9, aim_t), k2)
	_side = lerpf(_side, lerpf(0.65, 0.48, aim_t), k2)
	arm.spring_length = _len
	arm.position.x = _side * float(GameSettings.get_s("camera_side"))
	camera.fov = lerpf(camera.fov, base_fov * (weapon_zoom if aiming else 1.0), k2)


func _apply_aim_assist(delta: float, user_speed: float) -> void:
	_assist_active = false
	var lvl := GameSettings.aim_assist_level()
	if lvl <= 0 or not (aiming or firing) or not enemies_provider.is_valid():
		return
	var cone: float = [0.0, 4.0, 6.0, 8.0][lvl]
	var pull: float = [0.0, 1.2, 2.4, 4.0][lvl]
	var cam_pos := camera.global_position
	var fwd := aim_dir()
	var best_err := 999.0
	var best_dir := Vector3.ZERO
	var space := get_world_3d().direct_space_state
	for e in enemies_provider.call():
		if not is_instance_valid(e) or not e.alive or e == target:
			continue
		var tp: Vector3 = e.global_position + Vector3(0.0, 0.8 if e.crouching else 1.25, 0.0)
		var to := tp - cam_pos
		var dist := to.length()
		if dist > 80.0 or dist < 2.0:
			continue
		var ang := rad_to_deg(fwd.angle_to(to))
		if ang > cone or ang >= best_err:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam_pos, tp, 1)
		if not space.intersect_ray(q).is_empty():
			continue  # cenário bloqueia: sem assistência através de paredes
		best_err = ang
		best_dir = to / dist
	if best_err > 900.0:
		return
	_assist_active = true
	var tyaw := atan2(-best_dir.x, -best_dir.z)
	var tpit := asin(clampf(best_dir.y, -1.0, 1.0))
	var falloff := (1.0 - best_err / cone) * (1.0 - clampf(user_speed / 150.0, 0.0, 0.85))
	var f := clampf(pull * delta * falloff, 0.0, 0.35)
	if best_err < 0.35:
		return
	yaw += wrapf(tyaw - yaw, -PI, PI) * f
	pitch += (tpit - pitch) * f
