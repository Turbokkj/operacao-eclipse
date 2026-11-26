class_name BuildingBuilder
extends RefCounted
## Gera uma construção alinhada aos eixos: paredes externas com portas e janelas (vãos reais), salas internas
## por divisão binária (BSP) com portas entre elas, piso, móveis com colisão, telhado (plano com platibanda ou
## de duas águas), escada externa até o telhado e pontos de loot. Retorna BuildingInfo (salas/portas p/ IA).
## Lados: "N" = -Z, "S" = +Z, "W" = -X, "E" = +X.

const T := 0.30
const IT := 0.20
const DOOR_H := 2.35
const WIN_W := 1.3
const WIN_SILL := 0.95
const WIN_TOP := 2.10
const INT_WALL := Color(0.90, 0.88, 0.82)

# spec: rect, ground, wall_h, style, wall_col, roof ("flat"|"gable_x"|"gable_z"), roof_col, doors [lados],
#       rooms, tier, city, kind, windows, roof_stairs, door_w, door_h, industrial


static func build(batch: WorldBatch, spec: Dictionary, rng: RandomNumberGenerator, loot_out: Array) -> BuildingInfo:
	var r: Rect2 = spec["rect"]
	var g: float = spec["ground"]
	var h: float = spec["wall_h"]
	var key: String = str(spec.get("style", "plaster"))
	var col: Color = spec["wall_col"]
	var door_w: float = float(spec.get("door_w", 1.4))
	var door_h: float = float(spec.get("door_h", DOOR_H))
	var tier: int = int(spec.get("tier", 0))
	var industrial: bool = bool(spec.get("industrial", false))
	var info := BuildingInfo.new()
	info.rect = r
	info.ground = g
	info.tier = tier
	info.city = str(spec.get("city", "wild"))
	info.kind = str(spec.get("kind", "house"))
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	var inner := Rect2(x0 + T, z0 + T, r.size.x - 2.0 * T, r.size.y - 2.0 * T)

	# ---------- 1) salas (BSP)
	var rooms: Array = [inner]
	var walls: Array = []
	_bsp(rooms, walls, int(spec.get("rooms", 3)), 3.2 if not industrial else 8.0, rng)
	info.rooms = rooms

	# ---------- 2) portas externas
	var openings := {"N": [], "S": [], "E": [], "W": []}
	var door_cs := {"N": [], "S": [], "E": [], "W": []}
	var sides: Array = spec["doors"]
	for side in sides:
		var c := _place_ext_door(str(side), inner, rooms, walls, door_w, rng, true)
		if is_nan(c):
			c = _place_ext_door(str(side), inner, rooms, walls, door_w, rng, false)
		if is_nan(c):
			continue
		openings[side].append({"c": c, "w": door_w, "sill": 0.0, "top": door_h})
		door_cs[side].append(c)
		var pos := Vector3.ZERO
		var inward := Vector3.ZERO
		match str(side):
			"N":
				pos = Vector3(c, g, z0 + T * 0.5)
				inward = Vector3(0, 0, 1)
			"S":
				pos = Vector3(c, g, z1 - T * 0.5)
				inward = Vector3(0, 0, -1)
			"W":
				pos = Vector3(x0 + T * 0.5, g, c)
				inward = Vector3(1, 0, 0)
			_:
				pos = Vector3(x1 - T * 0.5, g, c)
				inward = Vector3(-1, 0, 0)
		var in_pt := pos + inward * 1.4
		info.doors.append({"pos": pos, "in_pt": in_pt, "out_pt": pos - inward * 2.0, "room": info.room_at(in_pt)})
		# folha da porta aberta (visual, sem colisão), perpendicular à parede
		var perp := Vector3(inward.z, 0, -inward.x)
		var leaf_len := door_w - 0.2
		var leaf_c := pos + inward * (leaf_len * 0.5 + 0.2) + perp * (door_w * 0.5 - 0.06)
		var lsz := Vector3(absf(inward.x) * leaf_len + absf(inward.z) * 0.06, door_h - 0.1, absf(inward.z) * leaf_len + absf(inward.x) * 0.06)
		batch.box("wood", leaf_c + Vector3(0, door_h * 0.5, 0), lsz, Color(0.45, 0.30, 0.18), false, false, 2.0)

	# ---------- 3) janelas
	if bool(spec.get("windows", true)):
		var sill := WIN_SILL
		var top := WIN_TOP
		if h > 5.0:
			sill = h - 2.6
			top = h - 0.9
		for side in ["N", "S", "E", "W"]:
			var lo: float
			var hi: float
			if side == "N" or side == "S":
				lo = x0 + 1.6
				hi = x1 - 1.6
			else:
				lo = z0 + 1.6
				hi = z1 - 1.6
			var junc := _junctions(str(side), inner, walls)
			var wc := lo
			var spacing := 3.6 if not industrial else 6.0
			while wc <= hi:
				var ok := true
				for dc in door_cs[side]:
					if absf(wc - float(dc)) < float(door_w) * 0.5 + WIN_W * 0.5 + 0.5:
						ok = false
				for j in junc:
					if absf(wc - float(j)) < WIN_W * 0.5 + 0.45:
						ok = false
				if ok:
					openings[side].append({"c": wc, "w": WIN_W, "sill": sill, "top": top})
				wc += spacing

	# ---------- 4) paredes externas
	_wall(batch, key, col, "x", z0 + T * 0.5, x0, x1, g, h, T, openings["N"])
	_wall(batch, key, col, "x", z1 - T * 0.5, x0, x1, g, h, T, openings["S"])
	_wall(batch, key, col, "z", x0 + T * 0.5, z0 + T, z1 - T, g, h, T, openings["W"])
	_wall(batch, key, col, "z", x1 - T * 0.5, z0 + T, z1 - T, g, h, T, openings["E"])

	# ---------- 5) paredes internas com portas
	for w in walls:
		var a0: float = w["a0"]
		var a1: float = w["a1"]
		var dc := rng.randf_range(a0 + 1.0, a1 - 1.0) if a1 - a0 > 2.4 else (a0 + a1) * 0.5
		_wall(batch, "plaster", INT_WALL, str(w["axis"]), float(w["c"]), a0, a1, g, h, IT, [{"c": dc, "w": 1.15, "sill": 0.0, "top": 2.2}])
		var pos2 := Vector3(float(w["c"]), g, dc) if str(w["axis"]) == "z" else Vector3(dc, g, float(w["c"]))
		var d1 := Vector3(0.95, 0, 0) if str(w["axis"]) == "z" else Vector3(0, 0, 0.95)
		var pa := pos2 - d1
		var pb := pos2 + d1
		info.links.append({"a": info.room_at(pa), "b": info.room_at(pb), "pos": pos2, "pa": pa, "pb": pb})

	# ---------- 6) piso e teto/telhado
	var floor_key := "wood" if (info.kind == "house" or info.kind == "cabin") else ("concrete" if industrial else "tile")
	var floor_col := Color(0.85, 0.78, 0.68) if floor_key == "wood" else Color(0.82, 0.82, 0.80)
	batch.box(floor_key, Vector3(r.get_center().x, g, r.get_center().y), Vector3(r.size.x - 0.1, 0.12, r.size.y - 0.1), floor_col, true, false, 2.5)
	var roof_kind: String = str(spec.get("roof", "flat"))
	var roof_col: Color = spec.get("roof_col", Color(0.55, 0.55, 0.55))
	if roof_kind == "flat":
		batch.box("concrete", Vector3(r.get_center().x, g + h + 0.12, r.get_center().y), Vector3(r.size.x + 0.1, 0.24, r.size.y + 0.1), roof_col, true, false, 3.0)
		_parapet(batch, r, g + h + 0.24, bool(spec.get("roof_stairs", false)), str(sides[0]) if sides.size() > 0 else "N", roof_col)
	else:
		batch.box("concrete", Vector3(r.get_center().x, g + h + 0.1, r.get_center().y), Vector3(r.size.x - 0.05, 0.2, r.size.y - 0.05), Color(0.8, 0.8, 0.78), true, false, 3.0)
		_gable(batch, r, g + h, roof_kind == "gable_x", roof_col, key, col)

	# ---------- 7) escada externa para o telhado
	if bool(spec.get("roof_stairs", false)) and roof_kind == "flat":
		var opposite := {"N": "S", "S": "N", "E": "W", "W": "E"}
		var st_side: String = str(opposite.get(str(sides[0]), "E")) if sides.size() > 0 else "E"
		_stairs(batch, st_side, r, g, h + 0.24)
		loot_out.append({"pos": Vector3(r.get_center().x, g + h + 0.24 + 0.35, r.get_center().y), "tier": mini(tier + 1, 2),
			"city": info.city, "bot_ok": false, "indoor": false})

	# ---------- 8) móveis e loot
	var keepouts: Array = []
	for d in info.doors:
		keepouts.append(Rect2(d["pos"].x - 1.5, d["pos"].z - 1.5, 3.0, 3.0))
	for l in info.links:
		keepouts.append(Rect2(l["pos"].x - 1.3, l["pos"].z - 1.3, 2.6, 2.6))
	for rr in rooms:
		_furnish(batch, rr, g, rng, tier, info, keepouts, industrial, loot_out)
	return info


# ----------------------------------------------------------------- paredes
static func _wall(batch: WorldBatch, key: String, col: Color, axis: String, fixed: float, a0: float, a1: float, g: float, h: float, thick: float, openings: Array) -> void:
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return float(p["c"]) < float(q["c"]))
	var cur := a0
	for o in ops:
		var lo := maxf(a0, float(o["c"]) - float(o["w"]) * 0.5)
		var hi := minf(a1, float(o["c"]) + float(o["w"]) * 0.5)
		if lo > cur + 0.01:
			_seg(batch, key, col, axis, fixed, cur, lo, g, 0.0, h, thick)
		if float(o["sill"]) > 0.01:
			_seg(batch, key, col, axis, fixed, lo, hi, g, 0.0, float(o["sill"]), thick)
		if float(o["top"]) < h - 0.01:
			_seg(batch, key, col, axis, fixed, lo, hi, g, float(o["top"]), h, thick)
		cur = maxf(cur, hi)
	if a1 > cur + 0.01:
		_seg(batch, key, col, axis, fixed, cur, a1, g, 0.0, h, thick)


static func _seg(batch: WorldBatch, key: String, col: Color, axis: String, fixed: float, u0: float, u1: float, g: float, y0: float, y1: float, thick: float) -> void:
	var cy := g + (y0 + y1) * 0.5
	var c := Vector3(fixed, cy, (u0 + u1) * 0.5)
	var sz := Vector3(thick, y1 - y0, u1 - u0)
	if axis == "x":
		c = Vector3((u0 + u1) * 0.5, cy, fixed)
		sz = Vector3(u1 - u0, y1 - y0, thick)
	batch.box(key, c, sz, col, true, false, 3.0)


# --------------------------------------------------------------------- BSP
static func _bsp(rooms: Array, walls: Array, target: int, min_s: float, rng: RandomNumberGenerator) -> void:
	for _k in 14:
		if rooms.size() >= target:
			return
		var bi := -1
		var ba := 0.0
		for i in rooms.size():
			var rr: Rect2 = rooms[i]
			if (rr.size.x >= min_s * 2.0 + IT or rr.size.y >= min_s * 2.0 + IT) and rr.get_area() > ba:
				bi = i
				ba = rr.get_area()
		if bi < 0:
			return
		var rr2: Rect2 = rooms[bi]
		var split_x := rr2.size.x >= rr2.size.y
		if split_x and rr2.size.x < min_s * 2.0 + IT:
			split_x = false
		elif not split_x and rr2.size.y < min_s * 2.0 + IT:
			split_x = true
		var a: Rect2
		var b: Rect2
		if split_x:
			var cut := rr2.position.x + rng.randf_range(min_s, rr2.size.x - min_s - IT)
			a = Rect2(rr2.position.x, rr2.position.y, cut - rr2.position.x, rr2.size.y)
			b = Rect2(cut + IT, rr2.position.y, rr2.end.x - cut - IT, rr2.size.y)
			walls.append({"axis": "z", "c": cut + IT * 0.5, "a0": rr2.position.y, "a1": rr2.end.y})
		else:
			var cut2 := rr2.position.y + rng.randf_range(min_s, rr2.size.y - min_s - IT)
			a = Rect2(rr2.position.x, rr2.position.y, rr2.size.x, cut2 - rr2.position.y)
			b = Rect2(rr2.position.x, cut2 + IT, rr2.size.x, rr2.end.y - cut2 - IT)
			walls.append({"axis": "x", "c": cut2 + IT * 0.5, "a0": rr2.position.x, "a1": rr2.end.x})
		rooms[bi] = a
		rooms.append(b)


## Coordenadas (ao longo da parede externa) onde paredes internas se encontram com ela.
static func _junctions(side: String, inner: Rect2, walls: Array) -> Array:
	var out: Array = []
	for w in walls:
		var axis := str(w["axis"])
		var a0: float = w["a0"]
		var a1: float = w["a1"]
		if side == "N" and axis == "z" and absf(a0 - inner.position.y) < 0.05:
			out.append(w["c"])
		elif side == "S" and axis == "z" and absf(a1 - inner.end.y) < 0.05:
			out.append(w["c"])
		elif side == "W" and axis == "x" and absf(a0 - inner.position.x) < 0.05:
			out.append(w["c"])
		elif side == "E" and axis == "x" and absf(a1 - inner.end.x) < 0.05:
			out.append(w["c"])
	return out


static func _place_ext_door(side: String, inner: Rect2, rooms: Array, walls: Array, door_w: float, rng: RandomNumberGenerator, avoid: bool) -> float:
	var cands: Array = []
	for rr in rooms:
		var rect: Rect2 = rr
		var touches := false
		var lo := 0.0
		var hi := 0.0
		match side:
			"N":
				touches = absf(rect.position.y - inner.position.y) < 0.05
				lo = rect.position.x
				hi = rect.end.x
			"S":
				touches = absf(rect.end.y - inner.end.y) < 0.05
				lo = rect.position.x
				hi = rect.end.x
			"W":
				touches = absf(rect.position.x - inner.position.x) < 0.05
				lo = rect.position.y
				hi = rect.end.y
			_:
				touches = absf(rect.end.x - inner.end.x) < 0.05
				lo = rect.position.y
				hi = rect.end.y
		if touches and hi - lo > door_w + 1.0:
			cands.append([lo, hi])
	if cands.is_empty():
		return NAN
	var junc := _junctions(side, inner, walls)
	for _t in 12:
		var pick: Array = cands[rng.randi() % cands.size()]
		var c := rng.randf_range(float(pick[0]) + door_w * 0.5 + 0.5, float(pick[1]) - door_w * 0.5 - 0.5)
		var ok := true
		if avoid:
			for j in junc:
				if absf(c - float(j)) < door_w * 0.5 + 0.4:
					ok = false
		if ok:
			return c
	if avoid:
		return NAN
	var p0: Array = cands[0]
	return (float(p0[0]) + float(p0[1])) * 0.5


# ----------------------------------------------------------------- telhados
static func _parapet(batch: WorldBatch, r: Rect2, y: float, with_gap: bool, door_side: String, col: Color) -> void:
	var ph := 0.9
	var pt := 0.25
	var cx := r.get_center().x
	var cz := r.get_center().y
	var gap_side := "none"
	if with_gap:
		gap_side = {"N": "S", "S": "N", "E": "W", "W": "E"}.get(door_side, "E")
	for side in ["N", "S", "E", "W"]:
		var along_x: bool = side == "N" or side == "S"
		var length: float = r.size.x if along_x else r.size.y
		var fixed: float
		match side:
			"N":
				fixed = r.position.y + pt * 0.5
			"S":
				fixed = r.end.y - pt * 0.5
			"W":
				fixed = r.position.x + pt * 0.5
			_:
				fixed = r.end.x - pt * 0.5
		var segs: Array = [[-length * 0.5, length * 0.5]]
		if side == gap_side:
			segs = [[-length * 0.5, -0.9], [0.9, length * 0.5]]
		for sg in segs:
			var u0: float = sg[0]
			var u1: float = sg[1]
			if along_x:
				batch.box("concrete", Vector3(cx + (u0 + u1) * 0.5, y + ph * 0.5, fixed), Vector3(u1 - u0, ph, pt), col.darkened(0.1), true, false, 3.0)
			else:
				batch.box("concrete", Vector3(fixed, y + ph * 0.5, cz + (u0 + u1) * 0.5), Vector3(pt, ph, u1 - u0), col.darkened(0.1), true, false, 3.0)


static func _gable(batch: WorldBatch, r: Rect2, base_y: float, ridge_x: bool, roof_col: Color, wall_key: String, wall_col: Color) -> void:
	var over := 0.45
	var span := (r.size.y if ridge_x else r.size.x) * 0.5
	var rise := span * 0.52
	var half := span + over
	var ang := atan2(rise, span)
	var plane_len := sqrt(half * half + rise * rise)
	var k := batch.kit("roof")
	var cx := r.get_center().x
	var cz := r.get_center().y
	var ry := base_y + rise
	if ridge_x:
		var xa := r.position.x - over
		var xb := r.end.x + over
		var n_n := Vector3(0, cos(ang), -sin(ang))
		var n_s := Vector3(0, cos(ang), sin(ang))
		k.quad_n(Vector3(xa, base_y, cz - half), Vector3(xb, base_y, cz - half), Vector3(xb, ry, cz), Vector3(xa, ry, cz), n_n, roof_col, 3.0)
		k.quad_n(Vector3(xa, base_y, cz + half), Vector3(xb, base_y, cz + half), Vector3(xb, ry, cz), Vector3(xa, ry, cz), n_s, roof_col, 3.0)
		var wk := batch.kit(wall_key)
		wk.tri_n(Vector3(r.position.x, base_y, r.position.y), Vector3(r.position.x, base_y, r.end.y), Vector3(r.position.x, ry, cz), Vector3(-1, 0, 0), wall_col, 3.0)
		wk.tri_n(Vector3(r.end.x, base_y, r.position.y), Vector3(r.end.x, base_y, r.end.y), Vector3(r.end.x, ry, cz), Vector3(1, 0, 0), wall_col, 3.0)
		var sz := Vector3(r.size.x + over * 2.0, 0.15, plane_len)
		batch.ramp(Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(cx, base_y + rise * 0.5 + 0.05, cz - half * 0.5)), sz)
		batch.ramp(Transform3D(Basis(Vector3.RIGHT, ang), Vector3(cx, base_y + rise * 0.5 + 0.05, cz + half * 0.5)), sz)
	else:
		var za := r.position.y - over
		var zb := r.end.y + over
		var n_w := Vector3(-sin(ang), cos(ang), 0)
		var n_e := Vector3(sin(ang), cos(ang), 0)
		k.quad_n(Vector3(cx - half, base_y, za), Vector3(cx - half, base_y, zb), Vector3(cx, ry, zb), Vector3(cx, ry, za), n_w, roof_col, 3.0)
		k.quad_n(Vector3(cx + half, base_y, za), Vector3(cx + half, base_y, zb), Vector3(cx, ry, zb), Vector3(cx, ry, za), n_e, roof_col, 3.0)
		var wk2 := batch.kit(wall_key)
		wk2.tri_n(Vector3(r.position.x, base_y, r.position.y), Vector3(r.end.x, base_y, r.position.y), Vector3(cx, ry, r.position.y), Vector3(0, 0, -1), wall_col, 3.0)
		wk2.tri_n(Vector3(r.position.x, base_y, r.end.y), Vector3(r.end.x, base_y, r.end.y), Vector3(cx, ry, r.end.y), Vector3(0, 0, 1), wall_col, 3.0)
		var sz2 := Vector3(plane_len, 0.15, r.size.y + over * 2.0)
		batch.ramp(Transform3D(Basis(Vector3.BACK, ang), Vector3(cx - half * 0.5, base_y + rise * 0.5 + 0.05, cz)), sz2)
		batch.ramp(Transform3D(Basis(Vector3.BACK, -ang), Vector3(cx + half * 0.5, base_y + rise * 0.5 + 0.05, cz)), sz2)


## Escada externa (degraus visuais + rampa de colisão suave) até o nível do telhado.
static func _stairs(batch: WorldBatch, side: String, r: Rect2, g: float, top_h: float) -> void:
	var o := Vector3.ZERO
	var m := Vector3.ZERO
	match side:
		"N":
			o = Vector3(0, 0, -1)
			m = Vector3(r.get_center().x, 0, r.position.y)
		"S":
			o = Vector3(0, 0, 1)
			m = Vector3(r.get_center().x, 0, r.end.y)
		"W":
			o = Vector3(-1, 0, 0)
			m = Vector3(r.position.x, 0, r.get_center().y)
		_:
			o = Vector3(1, 0, 0)
			m = Vector3(r.end.x, 0, r.get_center().y)
	var run := top_h / tan(deg_to_rad(33.0))
	var width := 1.7
	var steps := maxi(int(top_h / 0.19), 6)
	var a := o.cross(Vector3.UP)
	for i in steps:
		var d_out := run - (float(i) + 0.5) * run / steps
		var hgt := (float(i) + 1.0) * top_h / steps
		var c := m + o * d_out
		var sz := Vector3(absf(o.x) * run / steps + absf(a.x) * width, hgt, absf(o.z) * run / steps + absf(a.z) * width)
		batch.box("concrete", Vector3(c.x, g + hgt * 0.5, c.z), sz, Color(0.62, 0.62, 0.6), false, false, 1.5)
	var p_low := m + o * run + Vector3(0, g, 0)
	var p_high := m + Vector3(0, g + top_h, 0)
	var dvec := p_high - p_low
	var len_r := dvec.length()
	var n := (o * top_h + Vector3.UP * run) / len_r
	var center := (p_low + p_high) * 0.5 - n * 0.1
	batch.ramp(Transform3D(Basis(a, n, dvec / len_r), center), Vector3(width, 0.2, len_r))
	var fp := Rect2(m.x, m.z, 0, 0)
	fp = fp.expand(Vector2(m.x + o.x * run, m.z + o.z * run)).grow(width * 0.5 + 0.3)
	batch.nav_rects.append(fp)


# ------------------------------------------------------------------ móveis
static func _furnish(batch: WorldBatch, room: Rect2, g: float, rng: RandomNumberGenerator, tier: int, info: BuildingInfo, keepouts: Array, industrial: bool, loot_out: Array) -> void:
	var floor_y := g + 0.06
	var placed: Array = []
	var count := clampi(int(room.get_area() / 16.0), 1, 4)
	var catalog: Array = [
		["table", 1.3, 0.8, 0.75, Color(0.62, 0.46, 0.30)], ["shelf", 1.6, 0.4, 1.9, Color(0.50, 0.38, 0.26)],
		["bed", 2.0, 1.0, 0.5, Color(0.55, 0.65, 0.80)], ["couch", 1.9, 0.85, 0.85, Color(0.45, 0.35, 0.50)],
		["counter", 2.4, 0.7, 1.05, Color(0.70, 0.66, 0.60)], ["cabinet", 0.8, 0.5, 1.8, Color(0.58, 0.50, 0.40)],
	]
	if industrial:
		catalog = [["crate", 1.0, 1.0, 1.0, Color(0.55, 0.42, 0.25)], ["shelf", 2.2, 0.6, 2.2, Color(0.35, 0.4, 0.5)],
			["crate", 1.4, 1.2, 1.4, Color(0.4, 0.5, 0.35)]]
	for _n in count:
		for _try in 8:
			var it: Array = catalog[rng.randi() % catalog.size()]
			var w: float = it[1]
			var dp: float = it[2]
			var ht: float = it[3]
			var side := rng.randi() % 4
			var sx := w
			var sz := dp
			var cx := 0.0
			var cz := 0.0
			if side < 2:
				if room.size.x < w + 1.0:
					continue
				cx = rng.randf_range(room.position.x + w * 0.5 + 0.4, room.end.x - w * 0.5 - 0.4)
				cz = room.position.y + dp * 0.5 + 0.05 if side == 0 else room.end.y - dp * 0.5 - 0.05
			else:
				sx = dp
				sz = w
				if room.size.y < w + 1.0:
					continue
				cz = rng.randf_range(room.position.y + w * 0.5 + 0.4, room.end.y - w * 0.5 - 0.4)
				cx = room.position.x + dp * 0.5 + 0.05 if side == 2 else room.end.x - dp * 0.5 - 0.05
			var fr := Rect2(cx - sx * 0.5, cz - sz * 0.5, sx, sz)
			var blocked := false
			for k in keepouts:
				if fr.intersects(k):
					blocked = true
			for p in placed:
				if fr.grow(0.4).intersects(p):
					blocked = true
			if blocked:
				continue
			placed.append(fr)
			batch.box("wood", Vector3(cx, floor_y + ht * 0.5, cz), Vector3(sx, ht, sz), it[4], true, false, 2.0)
			if str(it[0]) == "bed":
				batch.box("plaster", Vector3(cx, floor_y + ht + 0.05, cz - (0.3 if side < 2 else 0.0)), Vector3(sx * 0.9, 0.1, sz * 0.9), Color(0.9, 0.9, 0.95), false, false, 2.0)
			if ht >= 0.7 and ht <= 1.1 and rng.randf() < 0.65:
				loot_out.append({"pos": Vector3(cx, floor_y + ht + 0.32, cz), "tier": tier, "city": info.city, "bot_ok": true, "indoor": true})
			break
	# itens soltos no chão da sala
	var floor_pts := 1 + int(room.get_area() / 30.0)
	for _p in floor_pts:
		for _try in 6:
			var px := rng.randf_range(room.position.x + 0.9, room.end.x - 0.9) if room.size.x > 2.0 else room.get_center().x
			var pz := rng.randf_range(room.position.y + 0.9, room.end.y - 0.9) if room.size.y > 2.0 else room.get_center().y
			var pr := Rect2(px - 0.4, pz - 0.4, 0.8, 0.8)
			var bad := false
			for k in keepouts:
				if pr.intersects(k):
					bad = true
			for p in placed:
				if pr.intersects(p):
					bad = true
			if bad:
				continue
			loot_out.append({"pos": Vector3(px, floor_y + 0.35, pz), "tier": tier, "city": info.city, "bot_ok": true, "indoor": true})
			break
