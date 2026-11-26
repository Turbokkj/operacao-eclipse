class_name CharacterBuilder
extends RefCounted
## Geração procedural dos personagens: esqueleto de 18 ossos + malha única com skinning
## (cabeça com rosto 3D, torso, braços, mãos, pernas, pés, cabelo, roupas, calçados, acessórios).
## Frente do personagem = -Z (convenção do Godot); direita = +X.

enum B { ROOT, HIPS, SPINE, CHEST, NECK, HEAD, UARM_L, LARM_L, HAND_L, UARM_R, LARM_R, HAND_R,
	ULEG_L, LLEG_L, FOOT_L, ULEG_R, LLEG_R, FOOT_R }
const BONE_NAMES := ["Root", "Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L",
	"UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R"]
const BONE_PARENT := [-1, 0, 1, 2, 3, 4, 3, 6, 7, 3, 9, 10, 1, 12, 13, 1, 15, 16]


# ---------------------------------------------------------------- esqueleto
static func compute_rig(body: Dictionary) -> Dictionary:
	var H: float = body["height"]
	var sw: float = body["shoulder"]
	var hw: float = body["hip"]
	var pos: Array = []
	pos.resize(18)
	var hips_y := H * 0.53
	var shoulder_y := H * 0.815
	var knee_y := H * 0.285
	var ankle_y := H * 0.045
	var arm_x := sw * 0.5 - 0.015
	var hip_x := hw * 0.5 * 0.52
	var ua := H * 0.172
	var la := H * 0.150
	pos[B.ROOT] = Vector3.ZERO
	pos[B.HIPS] = Vector3(0, hips_y, 0)
	pos[B.SPINE] = Vector3(0, H * 0.585, 0)
	pos[B.CHEST] = Vector3(0, H * 0.68, 0)
	pos[B.NECK] = Vector3(0, H * 0.835, 0)
	pos[B.HEAD] = Vector3(0, H * 0.875, 0)
	pos[B.UARM_L] = Vector3(-arm_x, shoulder_y, 0)
	pos[B.LARM_L] = Vector3(-arm_x, shoulder_y - ua, 0)
	pos[B.HAND_L] = Vector3(-arm_x, shoulder_y - ua - la, 0)
	pos[B.UARM_R] = Vector3(arm_x, shoulder_y, 0)
	pos[B.LARM_R] = Vector3(arm_x, shoulder_y - ua, 0)
	pos[B.HAND_R] = Vector3(arm_x, shoulder_y - ua - la, 0)
	pos[B.ULEG_L] = Vector3(-hip_x, hips_y - 0.04, 0)
	pos[B.LLEG_L] = Vector3(-hip_x, knee_y, 0)
	pos[B.FOOT_L] = Vector3(-hip_x, ankle_y, 0)
	pos[B.ULEG_R] = Vector3(hip_x, hips_y - 0.04, 0)
	pos[B.LLEG_R] = Vector3(hip_x, knee_y, 0)
	pos[B.FOOT_R] = Vector3(hip_x, ankle_y, 0)
	return {"pos": pos, "H": H, "body": body, "ua": ua, "la": la, "lu": (hips_y - 0.04) - knee_y,
		"ll": knee_y - ankle_y, "hips_y": hips_y, "shoulder_y": shoulder_y, "hip_x": hip_x, "arm_x": arm_x}


# ------------------------------------------------------------ perfis do torso
static func _profile(rig: Dictionary, y: float) -> Vector2:
	var body: Dictionary = rig["body"]
	var H: float = rig["H"]
	var sw: float = body["shoulder"]
	var hw: float = body["hip"]
	var d: float = body["depth"]
	var wa: float = body["waist"]
	var pts := [
		Vector3(H * 0.455, hw * 0.5 * 0.80, d * 0.5 * 0.85),
		Vector3(H * 0.520, hw * 0.5 * 1.02, d * 0.5 * 0.98),
		Vector3(H * 0.600, wa * 0.5, d * 0.5 * 0.85),
		Vector3(H * 0.690, sw * 0.5 * 0.78, d * 0.5 * 1.00),
		Vector3(H * 0.775, sw * 0.5 * 0.90, d * 0.5 * 1.05),
		Vector3(H * 0.820, sw * 0.5 * 0.92, d * 0.5 * 0.80),
		Vector3(H * 0.845, 0.075, 0.07),
	]
	# cada ponto = (altura, meia-largura rx, meia-profundidade rz)
	if y <= pts[0].x:
		return Vector2(pts[0].y, pts[0].z)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if y <= b.x:
			var t := smoothstep(0.0, 1.0, (y - a.x) / (b.x - a.x))
			return Vector2(lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))
	var l: Vector3 = pts[pts.size() - 1]
	return Vector2(l.y, l.z)


static func _tw(rig: Dictionary, y: float) -> Array:
	var pos: Array = rig["pos"]
	var ys := [pos[B.HIPS].y, pos[B.SPINE].y, pos[B.CHEST].y, pos[B.NECK].y]
	var bs := [B.HIPS, B.SPINE, B.CHEST, B.NECK]
	if y <= ys[0]:
		return [B.HIPS, 1.0, B.HIPS, 0.0]
	if y >= ys[3]:
		return [B.NECK, 1.0, B.NECK, 0.0]
	for i in 3:
		if y <= ys[i + 1]:
			var t: float = (y - ys[i]) / (ys[i + 1] - ys[i])
			return [bs[i], 1.0 - t, bs[i + 1], t]
	return [B.CHEST, 1.0, B.CHEST, 0.0]


static func _torso(k: MeshKit, rig: Dictionary, y0: float, y1: float, off: float, col: Color, steps: int = 6, segs: int = 14) -> void:
	var secs: Array = []
	for i in steps + 1:
		var y := lerpf(y0, y1, float(i) / steps)
		var pr := _profile(rig, y)
		var w := _tw(rig, y)
		secs.append({"p": Vector3(0, y, 0), "rx": pr.x + off, "rz": pr.y + off, "c": col,
			"b0": w[0], "w0": w[1], "b1": w[2], "w1": w[3]})
	k.loft(secs, segs)


static func _limb(k: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, bone: int, prev_b: int, next_b: int, n: int = 4, bulge: float = 0.0) -> void:
	var secs: Array = []
	for i in n + 1:
		var t := float(i) / n
		var b1 := bone
		var w1 := 0.0
		if t > 0.72 and next_b >= 0:
			b1 = next_b
			w1 = 0.5 * smoothstep(0.72, 1.0, t)
		elif t < 0.28 and prev_b >= 0:
			b1 = prev_b
			w1 = 0.5 * (1.0 - smoothstep(0.0, 0.28, t))
		var r := lerpf(ra, rb, t) * (1.0 + bulge * sin(PI * t))
		secs.append({"p": a.lerp(b, t), "rx": r, "rz": r, "c": col, "b0": bone, "w0": 1.0 - w1, "b1": b1, "w1": w1})
	k.loft(secs, 10)


## Braço: t_end 0..1 = só parte do braço superior; 1..2 = inclui antebraço até o punho.
static func _arm(k: MeshKit, rig: Dictionary, side: int, col: Color, off: float, t_end: float, lim: float) -> void:
	var pos: Array = rig["pos"]
	var iu: int = B.UARM_L if side == 0 else B.UARM_R
	var sh: Vector3 = pos[iu]
	var el: Vector3 = pos[iu + 1]
	var wr: Vector3 = pos[iu + 2]
	var r_sh := 0.050 * lim
	var r_el := 0.040 * lim
	var r_wr := 0.031 * lim
	var t1 := minf(t_end, 1.0)
	_limb(k, sh, sh.lerp(el, t1), r_sh + off, lerpf(r_sh, r_el, t1) + off, col, iu, B.CHEST, (iu + 1) if t_end >= 1.0 else -1)
	if t_end > 1.0:
		var t2 := minf(t_end - 1.0, 1.0)
		_limb(k, el, el.lerp(wr, t2), r_el + off, lerpf(r_el, r_wr, t2) + off, col, iu + 1, iu, (iu + 2) if t2 >= 1.0 else -1)


static func _leg(k: MeshKit, rig: Dictionary, side: int, col: Color, off: float, t_end: float, lim: float) -> void:
	var pos: Array = rig["pos"]
	var iu: int = B.ULEG_L if side == 0 else B.ULEG_R
	var hp: Vector3 = pos[iu]
	var kn: Vector3 = pos[iu + 1]
	var an: Vector3 = pos[iu + 2]
	var r_hp := 0.088 * lim
	var r_kn := 0.058 * lim
	var r_an := 0.043 * lim
	var t1 := minf(t_end, 1.0)
	_limb(k, hp, hp.lerp(kn, t1), r_hp + off, lerpf(r_hp, r_kn, t1) + off, col, iu, B.HIPS, (iu + 1) if t_end >= 1.0 else -1, 4, 0.05)
	if t_end > 1.0:
		var t2 := minf(t_end - 1.0, 1.0)
		_limb(k, kn, kn.lerp(an, t2), r_kn + off, lerpf(r_kn, r_an, t2) + off, col, iu + 1, iu, (iu + 2) if t2 >= 1.0 else -1, 4, 0.06)


# ---------------------------------------------------------------- cabeça
static func _head_dims(rig: Dictionary) -> Dictionary:
	var body: Dictionary = rig["body"]
	var hs: float = body["head"]
	var H: float = rig["H"]
	return {"c": Vector3(0, H * 0.937, 0), "rx": 0.088 * hs, "ry": 0.118 * hs, "rz": 0.100 * hs, "hs": hs}


static func _skin_parts(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var body: Dictionary = rig["body"]
	var lim: float = body["limb"]
	var H: float = rig["H"]
	var skin: Color = CosmeticsDB.SKIN_TONES[app["skin"]]
	var pos: Array = rig["pos"]
	_torso(k, rig, H * 0.455, H * 0.845, 0.0, skin, 7)
	for side in 2:
		_arm(k, rig, side, skin, 0.0, 2.0, lim)
		_leg(k, rig, side, skin, 0.0, 2.0, lim)
		var ih: int = B.HAND_L if side == 0 else B.HAND_R
		var hp: Vector3 = pos[ih]
		k.ellipsoid(hp + Vector3(0, -0.045 * lim, 0), Vector3(0.036, 0.066, 0.030) * lim, skin, ih, 6, 10)
		var iu: int = B.UARM_L if side == 0 else B.UARM_R
		k.ellipsoid(pos[iu], Vector3(0.056, 0.056, 0.056) * lim, skin, iu, 5, 8)
	_limb(k, Vector3(0, H * 0.80, 0), Vector3(0, H * 0.895, 0), 0.052, 0.046, skin, B.NECK, B.CHEST, B.HEAD, 3)
	var d := _head_dims(rig)
	var c: Vector3 = d["c"]
	var hs: float = d["hs"]
	var f: Dictionary = CosmeticsDB.FACES[app["face"]]
	var jaw: float = f["jaw"]
	k.ellipsoid(c, Vector3(d["rx"], d["ry"], d["rz"]), skin, B.HEAD, 10, 14)
	k.ellipsoid(c + Vector3(0, -0.052 * hs, -0.012 * hs), Vector3(0.074 * hs * jaw, 0.062 * hs, 0.082 * hs), skin, B.HEAD, 6, 12)


static func _face(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var d := _head_dims(rig)
	var c: Vector3 = d["c"]
	var hs: float = d["hs"]
	var skin: Color = CosmeticsDB.SKIN_TONES[app["skin"]]
	var f: Dictionary = CosmeticsDB.FACES[app["face"]]
	var eye_col: Color = CosmeticsDB.EYE_COLORS[app["eye_color"]]
	var brow_col: Color = CosmeticsDB.HAIR_COLORS[app["hair_color"]].darkened(0.25)
	var es: float = f["eye"]
	var ns: float = f["nose"]
	var bs: float = f["brow"]
	var ms: float = f["mouth"]
	for s in [-1.0, 1.0]:
		var ex: float = 0.036 * hs * s
		k.ellipsoid(c + Vector3(ex, 0.012 * hs, -0.086 * hs), Vector3(0.0165, 0.012, 0.008) * hs * es, Color(0.96, 0.96, 0.96), B.HEAD, 5, 8)
		k.ellipsoid(c + Vector3(ex, 0.012 * hs, -0.0925 * hs), Vector3(0.0085, 0.0085, 0.004) * hs * es, eye_col, B.HEAD, 4, 8)
		k.ellipsoid(c + Vector3(ex, 0.012 * hs, -0.095 * hs), Vector3(0.004, 0.004, 0.002) * hs, Color(0.02, 0.02, 0.03), B.HEAD, 3, 6)
		k.ellipsoid(c + Vector3(ex * 1.05, 0.045 * hs, -0.082 * hs), Vector3(0.021, 0.0055 * bs, 0.006) * hs, brow_col, B.HEAD, 3, 8)
		k.ellipsoid(c + Vector3(0.091 * hs * s, -0.004 * hs, 0.0), Vector3(0.011, 0.024, 0.016) * hs, skin.darkened(0.04), B.HEAD, 4, 8)
	k.ellipsoid(c + Vector3(0, -0.012 * hs, -0.097 * hs), Vector3(0.013, 0.02, 0.016) * hs * ns, skin.darkened(0.06), B.HEAD, 4, 8)
	k.ellipsoid(c + Vector3(0, -0.056 * hs, -0.092 * hs), Vector3(0.024, 0.006, 0.006) * hs * ms, Color(0.55, 0.22, 0.24), B.HEAD, 3, 8)


static func _hair(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var style: int = app["hair"]
	if style == 0:
		return
	var d := _head_dims(rig)
	var c: Vector3 = d["c"]
	var rx: float = d["rx"]
	var ry: float = d["ry"]
	var rz: float = d["rz"]
	var hs: float = d["hs"]
	var col: Color = CosmeticsDB.HAIR_COLORS[app["hair_color"]]
	var hd := B.HEAD
	if style == 5:
		for i in 6:
			var z := -0.06 + i * 0.026
			k.ellipsoid(c + Vector3(0, ry * 0.98 - absf(z) * 0.18, z) * 1.0, Vector3(0.012, 0.034, 0.02) * hs, col, hd, 4, 8)
		return
	k.ellipsoid(c + Vector3(0, 0.014 * hs, 0.004 * hs), Vector3(rx + 0.010, ry + 0.010, rz + 0.012), col, hd, 8, 14, 0.42)
	k.ellipsoid(c + Vector3(0, -0.012 * hs, 0.030 * hs), Vector3(rx + 0.008, ry * 0.70, rz * 0.82 + 0.010), col, hd, 6, 12)
	if style == 2:
		for i in 7:
			var a := TAU * float(i) / 7.0
			var px := cos(a) * rx * 0.62
			var pz := sin(a) * rz * 0.62
			k.ellipsoid(c + Vector3(px, ry * 0.95, pz), Vector3(0.016, 0.042, 0.016) * hs, col, hd, 4, 6)
		k.ellipsoid(c + Vector3(0, ry * 1.02, 0), Vector3(0.02, 0.045, 0.02) * hs, col, hd, 4, 6)
	elif style == 3:
		k.ellipsoid(c + Vector3(0, -0.01 * hs, 0.118 * hs), Vector3(0.028, 0.034, 0.028) * hs, col, hd, 5, 8)
		k.ellipsoid(c + Vector3(0, -0.095 * hs, 0.138 * hs), Vector3(0.022, 0.078, 0.022) * hs, col, hd, 5, 8)
	elif style == 4:
		k.ellipsoid(c + Vector3(0, -0.12 * hs, 0.062 * hs), Vector3(rx * 0.98, 0.155 * hs, 0.052 * hs), col, hd, 6, 10)
		for s in [-1.0, 1.0]:
			k.ellipsoid(c + Vector3(0.088 * hs * s, -0.06 * hs, 0.012 * hs), Vector3(0.02, 0.092, 0.05) * hs, col, hd, 5, 8)


# ------------------------------------------------------------------ roupas
static func _top(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var kind: String = CosmeticsDB.TOPS[app["top"]]["kind"]
	var col: Color = CosmeticsDB.TOP_COLORS[app["top_color"]]
	var H: float = rig["H"]
	var lim: float = rig["body"]["limb"]
	var depth: float = rig["body"]["depth"]
	var accent := col.lightened(0.35)
	var dark := col.darkened(0.45)
	match kind:
		"tee":
			_torso(k, rig, H * 0.505, H * 0.842, 0.012, col, 6)
			for side in 2:
				_arm(k, rig, side, col, 0.012, 0.62, lim)
		"jacket":
			_torso(k, rig, H * 0.490, H * 0.845, 0.020, col, 6)
			for side in 2:
				_arm(k, rig, side, col, 0.018, 1.90, lim)
			k.ellipsoid(Vector3(0, H * 0.842, 0), Vector3(0.078, 0.022, 0.072), dark, B.NECK, 4, 12)
			k.box(Vector3(0, H * 0.67, -(depth * 0.5 + 0.024)), Vector3(0.014, H * 0.30, 0.008), accent, B.CHEST)
		"vest":
			var under := Color(0.78, 0.76, 0.70)
			_torso(k, rig, H * 0.505, H * 0.842, 0.010, under, 5)
			for side in 2:
				_arm(k, rig, side, under, 0.010, 0.55, lim)
			_torso(k, rig, H * 0.540, H * 0.805, 0.030, dark, 5)
			for px in [-0.075, 0.075]:
				k.box(Vector3(px, H * 0.705, -(depth * 0.5 + 0.052)), Vector3(0.062, 0.085, 0.038), col.darkened(0.6), B.CHEST)
			k.box(Vector3(0, H * 0.625, -(depth * 0.5 + 0.050)), Vector3(0.14, 0.07, 0.036), col.darkened(0.6), B.SPINE)
			for s in [-1.0, 1.0]:
				k.box(Vector3(0.10 * s, H * 0.812, 0), Vector3(0.05, 0.022, 0.2), dark, B.CHEST)
		"hoodie":
			_torso(k, rig, H * 0.480, H * 0.845, 0.034, col, 6)
			for side in 2:
				_arm(k, rig, side, col, 0.030, 1.95, lim)
			k.ellipsoid(Vector3(0, H * 0.852, 0.075), Vector3(0.105, 0.078, 0.088), col.darkened(0.12), B.NECK, 5, 12)
			k.box(Vector3(0, H * 0.575, -(depth * 0.5 + 0.042)), Vector3(0.20, 0.07, 0.016), col.darkened(0.15), B.SPINE)


static func _bottom(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var kind: String = CosmeticsDB.BOTTOMS[app["bottom"]]["kind"]
	var col: Color = CosmeticsDB.BOTTOM_COLORS[app["bottom_color"]]
	var H: float = rig["H"]
	var lim: float = rig["body"]["limb"]
	var hip_x: float = rig["hip_x"]
	var off := 0.012
	var t_end := 1.96
	if kind == "cargo":
		off = 0.026
	elif kind == "shorts":
		off = 0.022
		t_end = 0.96
	_torso(k, rig, H * 0.452, H * 0.575, off + 0.002, col, 4)
	for side in 2:
		_leg(k, rig, side, col, off, t_end, lim)
	if kind == "cargo":
		for s in [-1.0, 1.0]:
			k.box(Vector3((hip_x + 0.088 * lim + 0.026) * s, H * 0.40, -0.01), Vector3(0.030, 0.11, 0.09), col.darkened(0.2), B.ULEG_L if s < 0.0 else B.ULEG_R)
	var waist_w: float = rig["body"]["waist"]
	var depth: float = rig["body"]["depth"]
	k.box(Vector3(0, H * 0.58, 0), Vector3(waist_w + 0.05, 0.03, depth + 0.05), col.darkened(0.35), B.SPINE)


static func _shoes(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var kind: String = CosmeticsDB.SHOES[app["shoes"]]["kind"]
	var col: Color = CosmeticsDB.SHOE_COLORS[app["shoe_color"]]
	var lim: float = rig["body"]["limb"]
	var hip_x: float = rig["hip_x"]
	var sole := Color(0.12, 0.12, 0.13) if kind != "sneaker" else Color(0.95, 0.95, 0.95)
	for side in 2:
		var x := hip_x * (-1.0 if side == 0 else 1.0)
		var bone: int = B.FOOT_L if side == 0 else B.FOOT_R
		var lb: int = B.LLEG_L if side == 0 else B.LLEG_R
		k.ellipsoid(Vector3(x, 0.056, -0.045), Vector3(0.050 * lim, 0.052, 0.122), col, bone, 6, 10)
		k.ellipsoid(Vector3(x, 0.017, -0.045), Vector3(0.054 * lim, 0.019, 0.128), sole, bone, 4, 10)
		if kind == "boot" or kind == "tactical":
			_limb(k, Vector3(x, 0.07, 0.0), Vector3(x, 0.27, 0.0), 0.054 * lim, 0.060 * lim, col, lb, bone, -1, 2)
		if kind == "tactical":
			k.box(Vector3(x, 0.15, -0.058 * lim), Vector3(0.05, 0.012, 0.012), Color(0.08, 0.08, 0.09), lb)
			k.box(Vector3(x, 0.21, -0.062 * lim), Vector3(0.05, 0.012, 0.012), Color(0.08, 0.08, 0.09), lb)


static func _headwear(k: MeshKit, rig: Dictionary, app: Dictionary) -> void:
	var kind: String = CosmeticsDB.HEADWEAR[app["head"]]["kind"]
	if kind == "none":
		return
	var col: Color = CosmeticsDB.HEAD_COLORS[app["head_color"]]
	var d := _head_dims(rig)
	var c: Vector3 = d["c"]
	var rx: float = d["rx"]
	var ry: float = d["ry"]
	var rz: float = d["rz"]
	var hs: float = d["hs"]
	var hd := B.HEAD
	match kind:
		"cap":
			k.ellipsoid(c + Vector3(0, 0.050 * hs, 0.006 * hs), Vector3(rx + 0.016, ry * 0.75, rz + 0.016), col, hd, 8, 14, 0.0)
			k.ellipsoid(c + Vector3(0, 0.046 * hs, -0.105 * hs), Vector3(0.075, 0.006, 0.052) * hs, col.darkened(0.15), hd, 3, 12)
			k.ellipsoid(c + Vector3(0, ry * 0.75 + 0.05 * hs, 0.006 * hs), Vector3(0.012, 0.008, 0.012), col.lightened(0.3), hd, 3, 6)
		"beanie":
			k.ellipsoid(c + Vector3(0, 0.030 * hs, 0.004 * hs), Vector3(rx + 0.022, ry * 0.95, rz + 0.022), col, hd, 8, 14, 0.05)
			k.ellipsoid(c + Vector3(0, ry * 0.95 + 0.04 * hs, 0.0), Vector3(0.026, 0.026, 0.026), col.lightened(0.4), hd, 5, 8)
		"helmet":
			k.ellipsoid(c + Vector3(0, 0.020 * hs, 0.004 * hs), Vector3(rx + 0.026, ry * 0.92, rz + 0.030), col, hd, 8, 14, 0.25)
			k.ellipsoid(c + Vector3(0, 0.046 * hs, -0.01 * hs), Vector3(rx + 0.034, 0.008, rz + 0.040), col.darkened(0.25), hd, 3, 14)
			for s in [-1.0, 1.0]:
				k.box(c + Vector3(0.078 * hs * s, -0.040 * hs, -0.03 * hs), Vector3(0.010, 0.10, 0.016), Color(0.1, 0.1, 0.11), hd)


# ------------------------------------------------------------------ malha final
static func build_mesh(app: Dictionary, rig: Dictionary) -> ArrayMesh:
	var k := MeshKit.new(true)
	_skin_parts(k, rig, app)
	_face(k, rig, app)
	_hair(k, rig, app)
	_top(k, rig, app)
	_bottom(k, rig, app)
	_shoes(k, rig, app)
	_headwear(k, rig, app)
	var mesh := ArrayMesh.new()
	k.commit(mesh)
	mesh.custom_aabb = AABB(Vector3(-1.3, -0.4, -1.3), Vector3(2.6, 2.8, 2.6))
	return mesh
