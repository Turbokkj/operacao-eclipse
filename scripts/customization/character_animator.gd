class_name CharacterAnimator
extends RefCounted
## Animador procedural do esqueleto de 18 ossos. A fase do ciclo de passada avança pela DISTÂNCIA percorrida
## (evita pés deslizando), todas as transições são amortecidas (sem mudanças bruscas) e os braços usam IK de
## 2 ossos para segurar a arma. Estados: parado, andar, correr, direções (frente/trás/lados), agachar,
## andar agachado, pular, aterrissar, equipar, interagir, recarregar, atirar, impacto, eliminado, vitória,
## descanso do lobby. Convenção: frente = -Z, rotação X positiva levanta braços/pernas para frente.

signal footstep(foot: int)

const B = CharacterBuilder.B

var sk: Skeleton3D
var rig: Dictionary = {}
var weapon_root: Node3D
var hips_rest := Vector3.ZERO

# --- entradas (preenchidas pelo dono do personagem a cada frame)
var move := Vector2.ZERO        # x = direita, y = frente (relativo ao corpo), módulo 0..1
var speed := 0.0
var crouching := false
var grounded := true
var vy := 0.0
var armed := false
var aiming := false
var pitch := 0.0                # radianos; positivo = olhando para cima
var lobby := false
var dead := false
var weapon_kind := ""
var grip_r := Vector3.ZERO
var grip_l := Vector3.ZERO

# --- estado interno
var _t := 0.0
var _phase := 0.0
var _last_half := 0
var _mv := 0.0
var _run := 0.0
var _crouch := 0.0
var _air := 0.0
var _armed := 0.0
var _aim := 0.0
var _dx := 0.0
var _dy := 1.0
var _recoil := 0.0
var _hit := 0.0
var _land := 0.0
var _death := 0.0
var _vic := 0.0
var _act := ""
var _act_t := 0.0
var _act_len := 1.0
var _was_air := false
var _lu := 0.43
var _ll := 0.43
var _ua := 0.31
var _la := 0.27


func setup(skeleton: Skeleton3D, p_rig: Dictionary, p_weapon_root: Node3D) -> void:
	sk = skeleton
	rig = p_rig
	weapon_root = p_weapon_root
	var pos: Array = rig["pos"]
	hips_rest = Vector3(pos[B.HIPS]) - Vector3(pos[B.ROOT])
	_lu = float(rig["lu"])
	_ll = float(rig["ll"])
	_ua = float(rig["ua"])
	_la = float(rig["la"])


func set_weapon_info(kind: String, gr: Vector3, gl: Vector3) -> void:
	weapon_kind = kind
	grip_r = gr
	grip_l = gl
	if weapon_root != null:
		weapon_root.visible = kind != ""


## Dispara uma ação pontual: shoot, hit, land, reload, equip, interact, victory, death.
func trigger(action: String, duration: float = 0.0) -> void:
	match action:
		"shoot":
			_recoil = 1.0
		"hit":
			_hit = 1.0
		"land":
			_land = 1.0
		"death":
			dead = true
		"reload":
			_start_action(action, maxf(duration, 0.8))
		"equip":
			_start_action(action, 0.55)
		"interact":
			_start_action(action, maxf(duration, 0.5))
		"victory":
			_start_action(action, 9999.0)
		"reset":
			_act = ""
			_vic = 0.0
			_death = 0.0
			dead = false


func _start_action(name: String, length: float) -> void:
	_act = name
	_act_t = 0.0
	_act_len = length


static func _damp(a: float, b: float, k: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-k * dt))


static func _q(x: float, y: float = 0.0, z: float = 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z)))


func _set(bone: int, q: Quaternion) -> void:
	sk.set_bone_pose_rotation(bone, q)


func update(dt: float) -> void:
	if sk == null:
		return
	dt = minf(dt, 0.1)
	_t += dt
	var act_p := 0.0
	if _act != "":
		_act_t += dt
		act_p = clampf(_act_t / _act_len, 0.0, 1.0)
		if _act_t >= _act_len:
			_act = ""
			act_p = 0.0
	var vic_on := _act == "victory" and not dead
	# ---- suavização dos fatores de mistura
	_mv = _damp(_mv, clampf(speed / 1.2, 0.0, 1.0) if grounded else 0.0, 10.0, dt)
	_run = _damp(_run, clampf((speed - 3.2) / 2.2, 0.0, 1.0), 6.0, dt)
	_crouch = _damp(_crouch, 1.0 if crouching else 0.0, 9.0, dt)
	_air = _damp(_air, 0.0 if grounded else 1.0, 12.0, dt)
	var arm_target := 1.0 if (armed and not lobby and not vic_on and not dead) else 0.0
	_armed = _damp(_armed, arm_target, 8.0, dt)
	_aim = _damp(_aim, 1.0 if aiming else 0.0, 12.0, dt)
	_recoil = _damp(_recoil, 0.0, 14.0, dt)
	_hit = _damp(_hit, 0.0, 7.0, dt)
	_land = _damp(_land, 0.0, 5.0, dt)
	_death = _damp(_death, 1.0 if dead else 0.0, 4.0, dt)
	_vic = _damp(_vic, 1.0 if vic_on else 0.0, 6.0, dt)
	var dirv := move
	if dirv.length() > 0.05:
		dirv = dirv.normalized()
	else:
		dirv = Vector2(0.0, 1.0)
	_dx = _damp(_dx, dirv.x, 9.0, dt)
	_dy = _damp(_dy, dirv.y, 9.0, dt)
	if _was_air and grounded and vy > -0.5:
		_land = maxf(_land, 0.8)
	_was_air = not grounded
	# ---- fase do passo: distância percorrida / comprimento do ciclo
	var cyc := lerpf(1.55, 3.4, _run) * lerpf(1.0, 0.72, _crouch)
	if grounded:
		_phase += speed * dt / cyc * TAU
	var half := int(floorf(_phase / PI))
	if half != _last_half:
		_last_half = half
		if grounded and speed > 1.0:
			footstep.emit(posmod(half, 2))
	var land_c := _land * _land
	var life := 1.0 - _death
	# ---- pernas
	var amp := lerpf(22.0, 40.0, _run) * _mv * lerpf(1.0, 0.6, _crouch)
	var lat := lerpf(9.0, 15.0, _run) * _mv * lerpf(1.0, 0.7, _crouch)
	var kamp := lerpf(28.0, 64.0, _run) * _mv * lerpf(1.0, 0.7, _crouch)
	var drop := 0.30 * _crouch + 0.20 * land_c
	var lh := 0.5 * (_lu + _ll)
	var phi := rad_to_deg(acos(clampf(1.0 - drop / (2.0 * lh), -1.0, 1.0)))
	for side in 2:
		var ph := _phase + (PI if side == 1 else 0.0)
		var sw := sin(ph)
		var cw := cos(ph)
		var hp := amp * _dy * sw + phi
		var hr := lat * _dx * sw
		var kn := kamp * maxf(0.0, cw) + 2.0 * phi + 6.0 * _mv
		hp += _air * (28.0 if vy > 0.0 else 12.0)
		kn += _air * (58.0 if vy > 0.0 else 20.0)
		hp = lerpf(hp, 8.0 * (1.0 if side == 0 else -0.5), _death)
		kn = lerpf(kn, 25.0, _death)
		var iu: int = B.ULEG_L if side == 0 else B.ULEG_R
		_set(iu, _q(hp, 0.0, hr))
		_set(iu + 1, _q(-kn))
		_set(iu + 2, _q(0.6 * (kn - hp) * life))
	# ---- quadril e torso
	var bob := 0.025 * _mv * absf(sin(_phase))
	var hip_y := -drop - bob
	hip_y += 0.13 * _vic * absf(sin(_t * 5.0))
	hip_y -= (hips_rest.y - 0.16) * _death
	sk.set_bone_pose_position(B.HIPS, hips_rest + Vector3(0.0, hip_y, 0.0))
	var breathe := sin(_t * 1.7) * 0.8
	var lean := lerpf(2.0, 9.0, _run) * _mv + 13.0 * _crouch + 8.0 * land_c
	var twist := 7.0 * _mv * _dy * sin(_phase)
	var p_deg := rad_to_deg(pitch)
	var sway := 0.0
	var head_yaw := 0.0
	var head_pit := 0.0
	if lobby:
		sway = 2.0 * sin(_t * 0.7)
		head_yaw = 16.0 * sin(_t * 0.35) * (0.5 + 0.5 * sin(_t * 0.11))
		head_pit = 3.0 * sin(_t * 0.5)
		breathe *= 1.5
	var hit_t := _hit
	var interact_bow := 0.0
	if _act == "interact":
		interact_bow = 14.0 * sin(PI * act_p)
	var hips_pitch := 86.0 * _death
	_set(B.HIPS, _q(hips_pitch, 0.0, sway))
	_set(B.SPINE, _q(-lean * 0.5 - interact_bow * 0.5 + 6.0 * hit_t - 8.0 * _vic + p_deg * 0.15, twist * 0.5, -sway * 0.5))
	_set(B.CHEST, _q(-lean * 0.5 - interact_bow * 0.5 + p_deg * 0.40 + breathe + 5.0 * hit_t - 6.0 * _recoil, twist * 0.5, 0.0))
	_set(B.NECK, _q(p_deg * 0.15 + 2.0 * lean * 0.1, -twist * 0.4 + head_yaw * 0.4))
	_set(B.HEAD, _q(p_deg * 0.25 + head_pit + 6.0 * hit_t - 8.0 * _vic, -twist * 0.4 + head_yaw * 0.6))
	# ---- braços livres (sem arma) e IK quando armado
	var arm_amp := lerpf(16.0, 42.0, _run) * _mv
	var elbow := 10.0 + (14.0 + 40.0 * _run) * _mv + 14.0 * _crouch
	var swing_l := -arm_amp * _dy * sin(_phase)
	var swing_r := arm_amp * _dy * sin(_phase)
	var idle_sway := 2.5 * sin(_t * 1.3)
	var fl := Quaternion.IDENTITY
	var fr := Quaternion.IDENTITY
	var el_l := Quaternion.IDENTITY
	var el_r := Quaternion.IDENTITY
	var up_l := swing_l + _air * 45.0 + idle_sway * (1.0 - _mv) + 165.0 * _vic
	var up_r := swing_r + _air * 45.0 - idle_sway * (1.0 - _mv) + 165.0 * _vic
	var roll_l := -5.0 - lat * 0.4 - _air * 25.0 - 14.0 * _vic
	var roll_r := 5.0 + lat * 0.4 + _air * 25.0 + 14.0 * _vic
	if _act == "interact" and not lobby:
		up_r = lerpf(up_r, 70.0, sin(PI * act_p))
	if dead or _death > 0.01:
		up_l = lerpf(up_l, 25.0, _death)
		up_r = lerpf(up_r, -15.0, _death)
		roll_l = lerpf(roll_l, -32.0, _death)
		roll_r = lerpf(roll_r, 32.0, _death)
	fl = _q(up_l, 0.0, roll_l)
	fr = _q(up_r, 0.0, roll_r)
	var elb_v := elbow * (1.0 - _vic) + 20.0 * _vic
	el_l = _q(elb_v + 12.0 * hit_t)
	el_r = _q(elb_v + 12.0 * hit_t)
	_set(B.UARM_L, fl)
	_set(B.UARM_R, fr)
	_set(B.LARM_L, el_l)
	_set(B.LARM_R, el_r)
	if weapon_root != null and weapon_kind != "" and _armed > 0.01:
		_hold_weapon(act_p, fl, fr, el_l, el_r)


func _weapon_offset(act_p: float) -> Vector3:
	var hip := Vector3(0.16, 0.10, -0.22)
	var aim := Vector3(0.05, 0.19, -0.27)
	if weapon_kind == "pistol":
		hip = Vector3(0.10, 0.10, -0.32)
		aim = Vector3(0.03, 0.20, -0.38)
	var off := hip.lerp(aim, _aim)
	off.z += 0.05 * _recoil
	if _act == "equip":
		off.y -= 0.35 * (1.0 - smoothstep(0.0, 1.0, act_p))
	elif _act == "interact":
		off.y -= 0.18 * sin(PI * act_p)
	elif _act == "reload":
		off.y -= 0.06 * sin(PI * act_p)
	return off


func _hold_weapon(act_p: float, free_l: Quaternion, free_r: Quaternion, free_el_l: Quaternion, free_el_r: Quaternion) -> void:
	var cg: Transform3D = sk.get_bone_global_pose(B.CHEST)
	var tilt := deg_to_rad(-6.0 * (1.0 - _aim) + 4.0 * _recoil)
	var wb := cg.basis * Basis(Vector3.RIGHT, tilt)
	var wxf := Transform3D(wb, cg.origin + cg.basis * _weapon_offset(act_p))
	weapon_root.transform = wxf
	var gr_w: Vector3 = wxf * grip_r
	var gl_w: Vector3 = wxf * grip_l
	var sh_r: Vector3 = sk.get_bone_global_pose(B.UARM_R).origin
	var sh_l: Vector3 = sk.get_bone_global_pose(B.UARM_L).origin
	gr_w -= (gr_w - sh_r).normalized() * 0.07
	gl_w -= (gl_w - sh_l).normalized() * 0.07
	if _act == "interact":
		var reach: Vector3 = cg * Vector3(0.14, -0.12, -0.50)
		gr_w = gr_w.lerp(reach, sin(PI * act_p))
	elif _act == "reload":
		var k := _reload_curve(act_p)
		var mag_pt: Vector3 = cg * Vector3(-0.05, -0.16, -0.16)
		gl_w = gl_w.lerp(mag_pt, k)
	_solve_arm(1, gr_w, _armed, free_r, free_el_r)
	_solve_arm(0, gl_w, _armed, free_l, free_el_l)


static func _reload_curve(p: float) -> float:
	if p < 0.25:
		return smoothstep(0.0, 0.25, p)
	if p < 0.72:
		return 1.0
	return 1.0 - smoothstep(0.72, 1.0, p)


## IK analítico de 2 ossos (lei dos cossenos) com "polo" para o cotovelo apontar para baixo/fora.
func _solve_arm(side: int, target: Vector3, w: float, free_u: Quaternion, free_l: Quaternion) -> void:
	var iu: int = B.UARM_L if side == 0 else B.UARM_R
	var chest_g: Transform3D = sk.get_bone_global_pose(B.CHEST)
	var sh: Vector3 = sk.get_bone_global_pose(iu).origin
	var to_t := target - sh
	if to_t.length() < 0.001:
		return
	var d := clampf(to_t.length(), 0.10, _ua + _la - 0.003)
	var dir := to_t.normalized()
	var cos_a := clampf((_ua * _ua + d * d - _la * _la) / (2.0 * _ua * d), -1.0, 1.0)
	var a := acos(cos_a)
	var side_sign := -1.0 if side == 0 else 1.0
	var pole := chest_g.basis * Vector3(0.40 * side_sign, -0.75, 0.30)
	pole = pole - dir * pole.dot(dir)
	if pole.length() < 0.001:
		return
	pole = pole.normalized()
	var upper_dir := (dir * cos(a) + pole * sin(a)).normalized()
	var elbow_p := sh + upper_dir * _ua
	var lower_dir := (sh + dir * d - elbow_p).normalized()
	var qu_g := Quaternion(Vector3.DOWN, upper_dir)
	var ql_g := Quaternion(Vector3.DOWN, lower_dir)
	var pq := chest_g.basis.get_rotation_quaternion()
	var qu_l := pq.inverse() * qu_g
	var ql_l := qu_g.inverse() * ql_g
	_set(iu, free_u.slerp(qu_l, w))
	_set(iu + 1, free_l.slerp(ql_l, w))
