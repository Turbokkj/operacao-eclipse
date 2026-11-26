class_name MapGenerator
extends RefCounted
## Gera o Mapa 1 (800 x 800 m): relevo com colinas, estradas, três cidades com identidade própria
## (Nova Aurora = centro urbano, Vale Verde = bairro residencial em relevo, Porto Ferro = zona industrial),
## construções isoladas, vegetação, loot, spawns, navegação e minimapa. Reporta progresso REAL por etapa.

const URBAN_COLS := [Color(0.88, 0.84, 0.76), Color(0.80, 0.76, 0.70), Color(0.74, 0.60, 0.52), Color(0.66, 0.70, 0.76),
	Color(0.90, 0.82, 0.64), Color(0.62, 0.62, 0.64)]
const HOUSE_COLS := [Color(0.95, 0.90, 0.80), Color(0.85, 0.75, 0.60), Color(0.70, 0.80, 0.75), Color(0.90, 0.70, 0.60),
	Color(0.80, 0.82, 0.88)]
const ROOF_COLS := [Color(0.62, 0.32, 0.22), Color(0.45, 0.30, 0.25), Color(0.35, 0.38, 0.42), Color(0.50, 0.25, 0.20)]
const IND_COLS := [Color(0.55, 0.62, 0.70), Color(0.70, 0.72, 0.74), Color(0.50, 0.55, 0.50), Color(0.72, 0.62, 0.45)]

var map := MapData.new()
var root: Node3D
var world: Node3D
var rng := RandomNumberGenerator.new()
var report := Callable()
var noise := FastNoiseLite.new()
var forest := FastNoiseLite.new()
var specs: Array = []
var props: Array = []
var batches := {}
var tree_pts: Array = []
var rock_pts: Array = []
var _occ := PackedByteArray()
var _cityflat := {}


func _step(v: float, msg: String) -> void:
	if report.is_valid():
		report.call(v, msg)
	await root.get_tree().process_frame


func generate(p_root: Node3D, p_report: Callable, seed_value: int = 0) -> MapData:
	root = p_root
	report = p_report
	rng.seed = seed_value if seed_value != 0 else int(Time.get_ticks_usec())
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.0035
	noise.fractal_octaves = 3
	forest.seed = rng.randi()
	forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	forest.frequency = 0.007
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	for k in ["aurora", "valeverde", "porto", "wild"]:
		batches[k] = WorldBatch.new()
	_occ.resize(MapData.N * MapData.N)
	_occ.fill(0)
	await _step(0.02, "Gerando relevo")
	_heights_base()
	await _step(0.08, "Planejando cidades e estradas")
	_plan_all()
	_flatten()
	await _step(0.20, "Modelando o terreno")
	_build_terrain()
	await _step(0.30, "Pavimentando estradas")
	_build_roads()
	await _step(0.38, "Erguendo Nova Aurora")
	_build_specs("aurora")
	await _step(0.48, "Erguendo Vale Verde")
	_build_specs("valeverde")
	await _step(0.57, "Erguendo Porto Ferro")
	_build_specs("porto")
	await _step(0.64, "Construindo áreas rurais")
	_build_specs("wild")
	_place_props()
	for k in batches:
		(batches[k] as WorldBatch).build(world, str(k).capitalize())
	await _step(0.74, "Plantando vegetação")
	_vegetation()
	_boundary()
	await _step(0.84, "Preparando navegação da IA")
	_nav()
	await _step(0.92, "Gerando minimapa")
	_outdoor_loot()
	_spawns()
	_minimap()
	await _step(1.0, "Mapa pronto")
	return map


# ------------------------------------------------------------------ relevo
func _heights_base() -> void:
	var n := MapData.N
	map.hm.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -MapData.HALF + i * MapData.CELL
			var z := -MapData.HALF + j * MapData.CELL
			var h := noise.get_noise_2d(x, z) * 8.0 + 5.0
			var edge := maxf(absf(x), absf(z)) - (MapData.HALF - 45.0)
			if edge > 0.0:
				h += edge * 0.16
			map.hm[map.idx(i, j)] = h


func _plan_all() -> void:
	var ha := clampf(map.height_at(-170.0, -150.0), 2.0, 9.0)
	var hp := clampf(map.height_at(20.0, 200.0) * 0.6, 1.0, 5.0)
	var vw := clampf(map.height_at(70.0, -90.0), 1.5, 12.0)
	var ve := clampf(map.height_at(310.0, -90.0), 1.5, 12.0)
	var vn := clampf(map.height_at(190.0, -190.0), 1.5, 12.0)
	var vs := clampf(map.height_at(190.0, 10.0), 1.5, 12.0)
	_plan_aurora(ha)
	_plan_valeverde(vw, ve, vn, vs)
	_plan_porto(hp)
	# estradas principais entre as cidades (curvas suaves)
	_road([Vector2(-50, -118), Vector2(10, -150), Vector2(40, -120), Vector2(70, -90)], 8.0, _ramp4(ha, vw), true, "wild")
	_road([Vector2(-138, -30), Vector2(-135, 60), Vector2(-100, 150), Vector2(-95, 200)], 8.0, _ramp4(ha, hp), true, "wild")
	_road([Vector2(190, 10), Vector2(170, 80), Vector2(120, 150), Vector2(115, 200)], 8.0, _ramp4(vs, hp), true, "wild")
	_plan_wild()


func _ramp4(a: float, b: float) -> Array:
	return [a, lerpf(a, b, 0.33), lerpf(a, b, 0.66), b]


func _road(ctrl: Array, width: float, hts: Array, curved: bool, city: String) -> void:
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	for i in ctrl.size() - 1:
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var n := maxi(int(ceil(p1.distance_to(p2) / 5.0)), 1)
		for k in n:
			var t := float(k) / n
			pts.append(p1.cubic_interpolate(p2, p0, p3, t) if curved else p1.lerp(p2, t))
			hs.append(lerpf(float(hts[i]), float(hts[i + 1]), t))
	pts.append(ctrl[ctrl.size() - 1])
	hs.append(float(hts[hts.size() - 1]))
	map.roads.append({"pts": pts, "hs": hs, "width": width, "city": city})
	for p in pts:
		_mark_disc(p, width * 0.5 + 2.5)


func _mark_disc(p: Vector2, r: float) -> void:
	var n := MapData.N
	var c0 := Vector2i(floori((p.x - r + MapData.HALF) / MapData.CELL), floori((p.y - r + MapData.HALF) / MapData.CELL))
	var c1 := Vector2i(floori((p.x + r + MapData.HALF) / MapData.CELL), floori((p.y + r + MapData.HALF) / MapData.CELL))
	for i in range(maxi(c0.x, 0), mini(c1.x, n - 1) + 1):
		for j in range(maxi(c0.y, 0), mini(c1.y, n - 1) + 1):
			_occ[j * n + i] = 1


func _mark_rect(r: Rect2, margin: float) -> void:
	var g := r.grow(margin)
	var n := MapData.N
	var c0 := Vector2i(floori((g.position.x + MapData.HALF) / MapData.CELL), floori((g.position.y + MapData.HALF) / MapData.CELL))
	var c1 := Vector2i(floori((g.end.x + MapData.HALF) / MapData.CELL), floori((g.end.y + MapData.HALF) / MapData.CELL))
	for i in range(maxi(c0.x, 0), mini(c1.x, n - 1) + 1):
		for j in range(maxi(c0.y, 0), mini(c1.y, n - 1) + 1):
			_occ[j * n + i] = 1


func _is_occ(x: float, z: float) -> bool:
	var n := MapData.N
	var i := floori((x + MapData.HALF) / MapData.CELL)
	var j := floori((z + MapData.HALF) / MapData.CELL)
	if i < 0 or j < 0 or i >= n or j >= n:
		return true
	return _occ[j * n + i] != 0


func _add_building(city: String, rect: Rect2, o: Dictionary) -> void:
	var spec := {"city": city, "rect": rect, "style": "plaster", "wall_h": 3.4, "wall_col": Color(0.85, 0.8, 0.7), "roof": "flat",
		"roof_col": Color(0.55, 0.55, 0.55), "doors": ["S"], "rooms": 3, "tier": 0, "kind": "house", "windows": true,
		"roof_stairs": false, "door_w": 1.4, "door_h": 2.35, "industrial": false}
	for k in o:
		spec[k] = o[k]
	if _cityflat.has(city):
		spec["ground"] = float(_cityflat[city])
	specs.append(spec)
	_mark_rect(rect, 3.0)


func _urban(o: Dictionary) -> Dictionary:
	var d := {"style": ["plaster", "brick", "concrete", "plaster"][rng.randi() % 4], "wall_col": URBAN_COLS[rng.randi() % URBAN_COLS.size()]}
	for k in o:
		d[k] = o[k]
	return d


func _house(o: Dictionary) -> Dictionary:
	var d := {"style": ["plaster", "brick", "plaster"][rng.randi() % 3], "wall_col": HOUSE_COLS[rng.randi() % HOUSE_COLS.size()],
		"wall_h": 3.0, "roof_col": ROOF_COLS[rng.randi() % ROOF_COLS.size()]}
	for k in o:
		d[k] = o[k]
	return d


func _industrial(o: Dictionary) -> Dictionary:
	var d := {"style": "metal", "wall_col": IND_COLS[rng.randi() % IND_COLS.size()], "industrial": true, "kind": "warehouse",
		"roof_col": Color(0.5, 0.55, 0.58), "windows": true}
	for k in o:
		d[k] = o[k]
	return d


func _prop(type: String, city: String, pos: Vector2, extra: Dictionary = {}) -> void:
	var d := {"type": type, "city": city, "pos": pos}
	for k in extra:
		d[k] = extra[k]
	props.append(d)


# ------------------------------------------------------------ Nova Aurora
func _plan_aurora(h: float) -> void:
	var c := Vector2(-170.0, -150.0)
	map.cities.append({"id": "aurora", "name": "Nova Aurora", "center": c, "radius": 125.0, "height": h, "flat": true, "paved": 0.85, "tier": 1})
	_cityflat["aurora"] = h
	for d in [-32.0, 32.0]:
		_road([Vector2(c.x + d, c.y - 125.0), Vector2(c.x + d, c.y + 125.0)], 8.0, [h, h], false, "aurora")
		_road([Vector2(c.x - 125.0, c.y + d), Vector2(c.x + 125.0, c.y + d)], 8.0, [h, h], false, "aurora")
	for gi in [-1, 0, 1]:
		for gj in [-1, 0, 1]:
			_aurora_block(Vector2(c.x + gi * 64.0, c.y + gj * 64.0), gi == 0 and gj == 0)
	for _k in 9:
		var street := rng.randi() % 4
		var along := rng.randf_range(-100.0, 100.0)
		var lane := 2.2 if rng.randf() < 0.5 else -2.2
		var pos := Vector2(c.x + (-32.0 if street == 0 else 32.0) + lane, c.y + along) if street < 2 else Vector2(c.x + along, c.y + (-32.0 if street == 2 else 32.0) + lane)
		_prop("car", "aurora", pos, {"along_x": street >= 2, "col": MapProps.CAR_COLORS[rng.randi() % MapProps.CAR_COLORS.size()]})


func _aurora_block(bc: Vector2, center: bool) -> void:
	var lot := Rect2(bc.x - 23.0, bc.y - 23.0, 46.0, 46.0)
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_prop("tree", "aurora", bc + s * 21.0, {"kind": 0})
		_prop("lamp", "aurora", bc + s * 25.0)
	if center:
		_add_building("aurora", Rect2(bc.x - 4.0, bc.y + 9.0, 8.0, 6.0), _urban({"wall_h": 3.2, "rooms": 2, "tier": 1, "kind": "kiosk", "doors": ["N"]}))
		_prop("tank", "aurora", bc, {"r": 3.2, "h": 0.8, "col": Color(0.6, 0.62, 0.66)})
		for s in [Vector2(-8, 0), Vector2(8, 0)]:
			_prop("bench", "aurora", bc + s, {"along_x": false})
		for k in 6:
			var a := TAU * k / 6.0
			_prop("tree", "aurora", bc + Vector2(cos(a), sin(a)) * 16.0, {"kind": 0})
		return
	var t := rng.randf()
	if t < 0.28:
		var side: String = ["N", "S", "E", "W"][rng.randi() % 4]
		var wh := 6.4 if rng.randf() < 0.45 else 3.8
		_add_building("aurora", Rect2(bc.x - 13.0 + rng.randf_range(-2.0, 2.0), bc.y - 12.0 + rng.randf_range(-2.0, 2.0), 26.0, 24.0),
			_urban({"wall_h": wh, "rooms": 4, "tier": 1 + (1 if rng.randf() < 0.5 else 0), "kind": "office", "doors": [side], "roof_stairs": wh < 5.0}))
	elif t < 0.55:
		_add_building("aurora", Rect2(lot.position.x, lot.position.y, 21.0, 17.0), _urban({"wall_h": 3.6, "rooms": 3, "tier": 1, "kind": "shop", "doors": ["S"]}))
		_add_building("aurora", Rect2(lot.end.x - 21.0, lot.end.y - 17.0, 21.0, 17.0), _urban({"wall_h": 3.6, "rooms": 3, "tier": 1, "kind": "shop", "doors": ["N"]}))
	elif t < 0.80:
		for i in 3:
			_add_building("aurora", Rect2(lot.position.x + i * 15.3, lot.position.y, 14.0, 12.0), _urban({"wall_h": 3.4, "rooms": 2, "tier": 1, "kind": "shop", "doors": ["N"]}))
		_add_building("aurora", Rect2(lot.end.x - 14.0, lot.end.y - 11.0, 14.0, 11.0), _urban({"wall_h": 3.2, "rooms": 2, "tier": 0, "kind": "garage", "doors": ["W"]}))
	else:
		_add_building("aurora", Rect2(bc.x - 20.0, bc.y - 15.0, 40.0, 30.0), _urban({"wall_h": 3.8, "rooms": 5, "tier": 2, "kind": "mall", "doors": ["N", "S"], "roof_stairs": true}))


# ------------------------------------------------------------- Vale Verde
func _plan_valeverde(vw: float, ve: float, vn: float, vs: float) -> void:
	var c := Vector2(190.0, -90.0)
	map.cities.append({"id": "valeverde", "name": "Vale Verde", "center": c, "radius": 125.0, "height": lerpf(vw, ve, 0.5), "flat": false, "paved": 0.0, "tier": 0})
	var hm_ := lerpf(vw, ve, 0.5)
	_road([Vector2(c.x - 120.0, c.y), Vector2(c.x + 120.0, c.y)], 7.0, [vw, ve], false, "valeverde")
	_road([Vector2(c.x, c.y - 100.0), Vector2(c.x, c.y), Vector2(c.x, c.y + 100.0)], 7.0, [vn, hm_, vs], false, "valeverde")
	for ox in [-92.0, -63.0, -34.0, 34.0, 63.0, 92.0]:
		_vv_house(Rect2(c.x + ox - 5.5, c.y - 20.5, 11.0, 9.0), "S", true)
		_vv_house(Rect2(c.x + ox - 5.5, c.y + 11.5, 11.0, 9.0), "N", true)
	for oz in [-80.0, -52.0, 52.0, 80.0]:
		_vv_house(Rect2(c.x + 11.5, c.y + oz - 5.5, 9.0, 11.0), "W", false)
		_vv_house(Rect2(c.x - 20.5, c.y + oz - 5.5, 9.0, 11.0), "E", false)
	for p in [Vector2(-60, -34), Vector2(75, 36), Vector2(-100, 30)]:
		_add_building("valeverde", Rect2(c.x + p.x, c.y + p.y, 7.0, 6.0), _house({"wall_h": 2.8, "rooms": 1, "kind": "shed", "doors": ["S"], "roof": "gable_x"}))
	for s in [Vector2(-9, -9), Vector2(9, 9)]:
		_prop("bench", "valeverde", c + s, {"along_x": true})
	for k in 6:
		var a := TAU * k / 6.0
		_prop("tree", "valeverde", c + Vector2(cos(a), sin(a)) * 12.0, {"kind": 0})


func _vv_house(r: Rect2, door: String, along_x: bool) -> void:
	_add_building("valeverde", r, _house({"rooms": 3 + (1 if rng.randf() < 0.3 else 0), "tier": 1 if rng.randf() < 0.25 else 0,
		"doors": [door], "roof": "gable_x" if along_x else "gable_z", "kind": "house"}))
	var cc := r.get_center()
	var back := Vector2.ZERO
	match door:
		"S":
			back = Vector2(0, -1)
		"N":
			back = Vector2(0, 1)
		"W":
			back = Vector2(1, 0)
		_:
			back = Vector2(-1, 0)
	var side := Vector2(-back.y, back.x)
	var far := cc + back * 12.0
	_prop("fence", "valeverde", far - side * 9.0, {"to": far + side * 9.0})
	_prop("fence", "valeverde", far - side * 9.0, {"to": far - side * 9.0 - back * 17.0})
	for k in 2:
		_prop("tree", "valeverde", cc + back * rng.randf_range(7.0, 11.0) + side * rng.randf_range(-8.0, 8.0), {"kind": rng.randi() % 2})


# -------------------------------------------------------------- Porto Ferro
func _plan_porto(h: float) -> void:
	var c := Vector2(20.0, 200.0)
	map.cities.append({"id": "porto", "name": "Porto Ferro", "center": c, "radius": 135.0, "height": h, "flat": true, "paved": 1.0, "tier": 1})
	_cityflat["porto"] = h
	_road([Vector2(c.x - 135.0, c.y), Vector2(c.x + 135.0, c.y)], 10.0, [h, h], false, "porto")
	for dx in [-45.0, 45.0]:
		_road([Vector2(c.x + dx, c.y - 70.0), Vector2(c.x + dx, c.y + 70.0)], 8.0, [h, h], false, "porto")
	var north := [[-88.0, 36.0], [-10.0, 34.0], [78.0, 30.0]]
	for i in north.size():
		var w: float = north[i][1]
		_add_building("porto", Rect2(c.x + float(north[i][0]) - w * 0.5, c.y - 40.0, w, 24.0), _industrial({"wall_h": 6.0, "rooms": 2, "tier": 1 + (i % 2),
			"doors": ["S", "E" if i % 2 == 0 else "W"], "door_w": 3.2, "door_h": 3.4, "roof_stairs": i != 1}))
	for cx in [-85.0, -5.0]:
		_add_building("porto", Rect2(c.x + cx - 15.0, c.y + 16.0, 30.0, 22.0), _industrial({"wall_h": 5.5, "rooms": 2, "tier": 1,
			"doors": ["N", "S"], "door_w": 3.2, "door_h": 3.4, "roof_stairs": cx < -50.0}))
	_add_building("porto", Rect2(c.x + 58.0, c.y + 16.0, 20.0, 13.0), {"style": "plaster", "wall_col": Color(0.82, 0.80, 0.74), "wall_h": 3.6,
		"rooms": 4, "tier": 2, "kind": "office", "doors": ["N"], "roof_stairs": true, "roof_col": Color(0.5, 0.52, 0.55)})
	for p in [Vector2(-120, -22), Vector2(112, 30), Vector2(100, -8)]:
		_add_building("porto", Rect2(c.x + p.x, c.y + p.y, 8.0, 6.0), _industrial({"wall_h": 3.0, "rooms": 1, "kind": "shed", "doors": ["S"], "industrial": false}))
	for ix in 4:
		for iz in 3:
			if rng.randf() < 0.8:
				_prop("container", "porto", Vector2(c.x + 94.0 + ix * 7.4, c.y - 68.0 + iz * 3.4), {"along_x": true, "col": MapProps.CONTAINER_COLORS[rng.randi() % 5], "stack": rng.randi_range(1, 3)})
	for tp in [Vector2(-112, 30), Vector2(-112, 46), Vector2(-127, 38)]:
		_prop("tank", "porto", c + tp, {"r": 5.5, "h": 9.0, "col": Color(0.78, 0.78, 0.8)})
	_prop("crane", "porto", Vector2(c.x + 10.0, c.y - 66.0), {"h": 22.0})
	for _k in 6:
		var sx := rng.randf_range(-110.0, 110.0)
		_prop("car", "porto", Vector2(c.x + sx, c.y + (3.0 if rng.randf() < 0.5 else -3.0)), {"along_x": true, "col": MapProps.CAR_COLORS[rng.randi() % 5]})


# -------------------------------------------------------- áreas intermediárias
func _plan_wild() -> void:
	var kinds := ["farm", "cabin", "gas", "farm", "cabin", "hut", "gas", "cabin"]
	var placed: Array = []
	for kd in kinds:
		for _try in 40:
			var p := Vector2(rng.randf_range(-330.0, 330.0), rng.randf_range(-330.0, 330.0))
			var ok := true
			for c in map.cities:
				if (c["center"] as Vector2).distance_to(p) < float(c["radius"]) + 35.0:
					ok = false
			for q in placed:
				if (q as Vector2).distance_to(p) < 90.0:
					ok = false
			if not ok or _is_occ(p.x, p.y) or map.slope_at(p.x, p.y) > 0.16:
				continue
			placed.append(p)
			match kd:
				"farm":
					_add_building("wild", Rect2(p.x - 6.0, p.y - 4.5, 12.0, 9.0), _house({"rooms": 3, "tier": 1, "doors": ["S"], "roof": "gable_x", "kind": "house"}))
					_add_building("wild", Rect2(p.x + 14.0, p.y - 6.0, 16.0, 12.0), _industrial({"wall_h": 4.5, "rooms": 1, "tier": 0, "doors": ["S"], "door_w": 3.0, "door_h": 3.2, "roof": "gable_x", "kind": "barn"}))
				"cabin":
					_add_building("wild", Rect2(p.x - 4.5, p.y - 3.5, 9.0, 7.0), _house({"rooms": 2, "tier": 1, "doors": ["S"], "roof": "gable_x", "kind": "cabin", "wall_col": Color(0.7, 0.55, 0.38)}))
					_prop("tree", "wild", p + Vector2(9, 5), {"kind": 1})
				"gas":
					_add_building("wild", Rect2(p.x - 6.0, p.y - 4.0, 12.0, 8.0), _urban({"wall_h": 3.4, "rooms": 2, "tier": 1, "doors": ["S"], "kind": "shop"}))
					_prop("canopy", "wild", p + Vector2(0, 11))
				_:
					_add_building("wild", Rect2(p.x - 3.0, p.y - 2.5, 6.0, 5.0), _house({"rooms": 1, "tier": 0, "doors": ["S"], "roof": "gable_x", "kind": "shed", "wall_h": 2.8}))
			break


# --------------------------------------------------------------- aplainamento
func _flatten() -> void:
	var n := MapData.N
	for c in map.cities:
		if not bool(c["flat"]):
			continue
		var cc: Vector2 = c["center"]
		var r_in: float = float(c["radius"]) * 0.8
		var r_out: float = float(c["radius"]) * 1.4
		var hh: float = c["height"]
		for j in n + 1:
			for i in n + 1:
				var x := -MapData.HALF + i * MapData.CELL
				var z := -MapData.HALF + j * MapData.CELL
				var d := cc.distance_to(Vector2(x, z))
				if d < r_out:
					var w := 1.0 - smoothstep(r_in, r_out, d)
					var k := map.idx(i, j)
					map.hm[k] = lerpf(map.hm[k], hh, w)
	for r in map.roads:
		var pts: PackedVector2Array = r["pts"]
		var hs: PackedFloat32Array = r["hs"]
		var hw := float(r["width"]) * 0.5
		var reach := hw + 12.0
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var lo := Vector2(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach)
			var hi := Vector2(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach)
			var i0 := maxi(floori((lo.x + MapData.HALF) / MapData.CELL), 0)
			var i1 := mini(ceili((hi.x + MapData.HALF) / MapData.CELL), n)
			var j0 := maxi(floori((lo.y + MapData.HALF) / MapData.CELL), 0)
			var j1 := mini(ceili((hi.y + MapData.HALF) / MapData.CELL), n)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := Vector2(-MapData.HALF + i * MapData.CELL, -MapData.HALF + j * MapData.CELL)
					var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
					var d := cp.distance_to(p)
					if d >= reach:
						continue
					var seg_len := a.distance_to(b)
					var t := 0.0 if seg_len < 0.01 else a.distance_to(cp) / seg_len
					var w := 1.0 - smoothstep(hw + 1.0, reach, d)
					var k := map.idx(i, j)
					map.hm[k] = lerpf(map.hm[k], lerpf(hs[s], hs[s + 1], t), w)
	# plataformas (pads) das construções
	for sp in specs:
		var rect: Rect2 = sp["rect"]
		if not sp.has("ground"):
			sp["ground"] = snappedf(map.height_at(rect.get_center().x, rect.get_center().y), 0.25)
		var g: float = sp["ground"]
		var area := rect.grow(8.0)
		var i0 := maxi(floori((area.position.x + MapData.HALF) / MapData.CELL), 0)
		var i1 := mini(ceili((area.end.x + MapData.HALF) / MapData.CELL), n)
		var j0 := maxi(floori((area.position.y + MapData.HALF) / MapData.CELL), 0)
		var j1 := mini(ceili((area.end.y + MapData.HALF) / MapData.CELL), n)
		var core := rect.grow(2.5)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := Vector2(-MapData.HALF + i * MapData.CELL, -MapData.HALF + j * MapData.CELL)
				var dx := maxf(maxf(core.position.x - p.x, p.x - core.end.x), 0.0)
				var dz := maxf(maxf(core.position.y - p.y, p.y - core.end.y), 0.0)
				var d := sqrt(dx * dx + dz * dz)
				var w := 1.0 - smoothstep(0.0, 5.5, d)
				if w > 0.0:
					var k := map.idx(i, j)
					map.hm[k] = lerpf(map.hm[k], g, w)


# ------------------------------------------------------------------ terreno
func _paved_mask(x: float, z: float) -> float:
	var best := 0.0
	for c in map.cities:
		var pv: float = c["paved"]
		if pv <= 0.0:
			continue
		var d := (c["center"] as Vector2).distance_to(Vector2(x, z))
		var rr: float = c["radius"]
		best = maxf(best, pv * (1.0 - smoothstep(rr * 0.85, rr * 1.1, d)))
	return best


func _build_terrain() -> void:
	var n := MapData.N
	var chunk := 25
	var cell := MapData.CELL
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = n + 1
	shape.map_depth = n + 1
	shape.map_data = map.hm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(cell, 1.0, cell)
	body.add_child(cs)
	world.add_child(body)
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	var mat := MaterialLibrary.terrain_mat()
	var chunks := n / chunk
	for cz in chunks:
		for cx in chunks:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			var uvs := PackedVector2Array()
			var idx := PackedInt32Array()
			for j in chunk + 1:
				for i in chunk + 1:
					var gi := cx * chunk + i
					var gj := cz * chunk + j
					var x := -MapData.HALF + gi * cell
					var z := -MapData.HALF + gj * cell
					var h := map.hm[map.idx(gi, gj)]
					var hl := map.hm[map.idx(maxi(gi - 1, 0), gj)]
					var hr := map.hm[map.idx(mini(gi + 1, n), gj)]
					var hu := map.hm[map.idx(gi, maxi(gj - 1, 0))]
					var hd := map.hm[map.idx(gi, mini(gj + 1, n))]
					verts.append(Vector3(x, h, z))
					norms.append(Vector3(hl - hr, 2.0 * cell, hu - hd).normalized())
					var slope := sqrt((hr - hl) * (hr - hl) + (hd - hu) * (hd - hu)) / (2.0 * cell)
					var tint := 0.90 + 0.20 * forest.get_noise_2d(x * 4.0, z * 4.0)
					cols.append(Color(tint * 0.96, tint, tint * 0.88))
					uvs.append(Vector2(_paved_mask(x, z), smoothstep(0.35, 0.8, slope)))
			for j in chunk:
				for i in chunk:
					var a := j * (chunk + 1) + i
					var b := a + 1
					var c := a + chunk + 2
					var d := a + chunk + 1
					idx.append(a)
					idx.append(b)
					idx.append(c)
					idx.append(a)
					idx.append(c)
					idx.append(d)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			terrain.add_child(mi)


func _build_roads() -> void:
	var k := MeshKit.new(false)
	var ri := 0
	for r in map.roads:
		var pts: PackedVector2Array = r["pts"]
		var hs: PackedFloat32Array = r["hs"]
		var hw := float(r["width"]) * 0.5
		var off := 0.045 + 0.008 * (ri % 5)
		var s := 0.0
		var prev_l := -1
		var prev_r := -1
		for i in pts.size():
			var tg := (pts[i + 1] - pts[i]).normalized() if i < pts.size() - 1 else (pts[i] - pts[i - 1]).normalized()
			var nrm := Vector2(-tg.y, tg.x)
			if i > 0:
				s += pts[i].distance_to(pts[i - 1])
			var l := pts[i] + nrm * hw
			var rt := pts[i] - nrm * hw
			var y := hs[i] + off
			var il := k.vert(Vector3(l.x, y, l.y), Vector3.UP, Color.WHITE, Vector2(0.0, s / 8.0))
			var ir := k.vert(Vector3(rt.x, y, rt.y), Vector3.UP, Color.WHITE, Vector2(1.0, s / 8.0))
			if prev_l >= 0:
				k.quad(prev_l, prev_r, ir, il)
			prev_l = il
			prev_r = ir
		ri += 1
	var mesh := ArrayMesh.new()
	k.commit(mesh, MaterialLibrary.get_mat("road"))
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


# ------------------------------------------------------------- construções
func _build_specs(city: String) -> void:
	var batch: WorldBatch = batches[city]
	for sp in specs:
		if str(sp["city"]) != city:
			continue
		var info := BuildingBuilder.build(batch, sp, rng, map.loot_points)
		info.uid = map.buildings.size()
		map.buildings.append(info)


func _gy(p: Vector2) -> float:
	return map.height_at(p.x, p.y)


func _place_props() -> void:
	for pr in props:
		var city := str(pr["city"])
		var batch: WorldBatch = batches[city]
		var p: Vector2 = pr["pos"]
		var y := _gy(p)
		match str(pr["type"]):
			"car":
				MapProps.car(batch, Vector3(p.x, y + 0.05, p.y), bool(pr["along_x"]), pr["col"])
			"container":
				MapProps.container(batch, Vector3(p.x, y, p.y), bool(pr["along_x"]), pr["col"], int(pr["stack"]))
			"fence":
				var q: Vector2 = pr["to"]
				var yy := (y + _gy(q)) * 0.5
				MapProps.fence(batch, Vector3(p.x, yy, p.y), Vector3(q.x, yy, q.y))
			"lamp":
				MapProps.lamp(batch, Vector3(p.x, y, p.y))
			"bench":
				MapProps.bench(batch, Vector3(p.x, y, p.y), bool(pr["along_x"]))
			"tank":
				batch.cylinder("metal", Vector3(p.x, y, p.y), float(pr["r"]), float(pr["h"]), pr["col"])
			"crane":
				MapProps.crane(batch, Vector3(p.x, y, p.y), float(pr["h"]))
			"canopy":
				batch.box("metal", Vector3(p.x, y + 4.6, p.y), Vector3(12.0, 0.4, 8.0), Color(0.85, 0.2, 0.15), true, false, 2.0)
				for sx in [-5.0, 5.0]:
					for sz in [-3.0, 3.0]:
						batch.box("metal", Vector3(p.x + sx, y + 2.2, p.y + sz), Vector3(0.4, 4.4, 0.4), Color(0.8, 0.8, 0.82), true, true, 2.0)
				for sx in [-2.5, 2.5]:
					batch.box("plain", Vector3(p.x + sx, y + 0.7, p.y), Vector3(0.7, 1.4, 0.5), Color(0.2, 0.25, 0.3), true, true, 1.0)
			"tree":
				tree_pts.append({"pos": Vector3(p.x, y, p.y), "kind": int(pr.get("kind", 0)), "s": rng.randf_range(0.9, 1.2)})


# ---------------------------------------------------------------- vegetação
func _vegetation() -> void:
	var veg := QualityManager.vegetation()
	var ext := MapData.HALF - 8.0
	for _k in int(4200.0 * veg):
		var x := rng.randf_range(-ext, ext)
		var z := rng.randf_range(-ext, ext)
		if _is_occ(x, z) or _in_city_core(x, z) or map.slope_at(x, z) > 0.5:
			continue
		var f := forest.get_noise_2d(x, z)
		var p := 0.05 + 0.9 * smoothstep(0.05, 0.35, f)
		if rng.randf() > p:
			continue
		tree_pts.append({"pos": Vector3(x, map.height_at(x, z), z), "kind": 0 if rng.randf() < 0.55 else 1, "s": rng.randf_range(0.8, 1.45)})
	for _k in int(1300.0 * veg):
		var x := rng.randf_range(-ext, ext)
		var z := rng.randf_range(-ext, ext)
		if _is_occ(x, z) or _in_city_core(x, z):
			continue
		var f := forest.get_noise_2d(x, z)
		if f > -0.05 and f < 0.25 and rng.randf() < 0.55:
			tree_pts.append({"pos": Vector3(x, map.height_at(x, z) - 0.05, z), "kind": 2, "s": rng.randf_range(0.8, 1.5)})
	for _k in 700:
		var x := rng.randf_range(-ext, ext)
		var z := rng.randf_range(-ext, ext)
		if _is_occ(x, z) or _in_city_core(x, z):
			continue
		var sl := map.slope_at(x, z)
		if (sl > 0.18 and rng.randf() < 0.30) or rng.randf() < 0.012:
			rock_pts.append({"pos": Vector3(x, map.height_at(x, z) - 0.15, z), "kind": 3, "s": rng.randf_range(0.8, 2.1)})
	_spawn_multimeshes()


func _in_city_core(x: float, z: float) -> bool:
	for c in map.cities:
		if (c["center"] as Vector2).distance_to(Vector2(x, z)) < float(c["radius"]) * 0.92:
			return true
	return false


func _spawn_multimeshes() -> void:
	var groups := {}
	for t in tree_pts + rock_pts:
		var pos: Vector3 = t["pos"]
		var key := "%d_%d_%d" % [int(t["kind"]), floori(pos.x / 100.0), floori(pos.z / 100.0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	var meshes := {}
	for kd in 4:
		meshes[kd] = MapProps.tree_mesh(kd)
	var foliage := MaterialLibrary.foliage_mat()
	var rockmat := MaterialLibrary.vertex_color_mat(0.95, 0.0)
	var veg_root := Node3D.new()
	veg_root.name = "Vegetation"
	world.add_child(veg_root)
	var range_end := QualityManager.render_distance() * 1.05
	for key in groups:
		var arr: Array = groups[key]
		var kind: int = int(arr[0]["kind"])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = arr.size()
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for i in arr.size():
			var d: Dictionary = arr[i]
			var s: float = d["s"]
			var pos: Vector3 = d["pos"]
			var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(bas, pos))
			if kind == 0 or kind == 1:
				var cs := CollisionShape3D.new()
				var cy := CylinderShape3D.new()
				cy.radius = 0.32 * s
				cy.height = 4.5
				cs.shape = cy
				cs.position = pos + Vector3(0, 2.25, 0)
				body.add_child(cs)
			elif kind == 3:
				var cs2 := CollisionShape3D.new()
				var sp := SphereShape3D.new()
				sp.radius = 0.85 * s
				cs2.shape = sp
				cs2.position = pos + Vector3(0, 0.3 * s, 0)
				body.add_child(cs2)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rockmat if kind == 3 else foliage
		mmi.visibility_range_end = range_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		veg_root.add_child(mmi)
		if body.get_child_count() > 0:
			veg_root.add_child(body)
		else:
			body.free()


func _boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	body.collision_mask = 0
	var e := MapData.HALF
	for side in [Vector3(e + 1.0, 30.0, 0), Vector3(-e - 1.0, 30.0, 0), Vector3(0, 30.0, e + 1.0), Vector3(0, 30.0, -e - 1.0)]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.0, 80.0, e * 2.0 + 8.0) if absf(side.x) > 1.0 else Vector3(e * 2.0 + 8.0, 80.0, 2.0)
		cs.shape = bs
		cs.position = side
		body.add_child(cs)
	world.add_child(body)


# -------------------------------------------------------------- navegação
func _nav() -> void:
	var nav := NavGrid.new()
	nav.setup(MapData.HALF, 2.5)
	map.nav = nav
	nav.buildings = map.buildings
	for b in map.buildings:
		nav.block_rect((b as BuildingInfo).rect.grow(0.9))
	for k in batches:
		for r in (batches[k] as WorldBatch).nav_rects:
			nav.block_rect((r as Rect2).grow(0.35))
	for t in tree_pts:
		if int(t["kind"]) <= 1:
			nav.block_cell_at(t["pos"].x, t["pos"].z)
	for t in rock_pts:
		nav.block_cell_at(t["pos"].x, t["pos"].z)
	var n := MapData.N
	for j in n + 1:
		for i in n + 1:
			var hl := map.hm[map.idx(maxi(i - 1, 0), j)]
			var hr := map.hm[map.idx(mini(i + 1, n), j)]
			var hu := map.hm[map.idx(i, maxi(j - 1, 0))]
			var hd := map.hm[map.idx(i, mini(j + 1, n))]
			var sl := sqrt((hr - hl) * (hr - hl) + (hd - hu) * (hd - hu)) / (2.0 * MapData.CELL)
			var x := -MapData.HALF + i * MapData.CELL
			var z := -MapData.HALF + j * MapData.CELL
			if sl > 0.8 or absf(x) > MapData.HALF - 6.0 or absf(z) > MapData.HALF - 6.0:
				nav.block_cell_at(x, z)


func _outdoor_loot() -> void:
	var spots := [["aurora", Vector2(-170, -150), 95.0, 26], ["valeverde", Vector2(190, -90), 95.0, 18],
		["porto", Vector2(20, 200), 100.0, 26], ["wild", Vector2(0, 0), 320.0, 28]]
	for sp in spots:
		var made := 0
		var tries := 0
		while made < int(sp[3]) and tries < 300:
			tries += 1
			var c: Vector2 = sp[1]
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * float(sp[2])
			var p := c + Vector2(cos(a), sin(a)) * r
			if not map.in_bounds(p.x, p.y, 15.0) or not map.nav.is_free_at(p.x, p.y) or map.nav.building_at(Vector3(p.x, 0, p.y)) != null:
				continue
			map.loot_points.append({"pos": Vector3(p.x, map.height_at(p.x, p.y) + 0.35, p.y), "tier": 0, "city": str(sp[0]), "bot_ok": true, "indoor": false})
			made += 1


func _spawns() -> void:
	var cand: Array = []
	for _k in 400:
		var p := Vector2(rng.randf_range(-340.0, 340.0), rng.randf_range(-340.0, 340.0))
		if map.nav.is_free_at(p.x, p.y) and map.slope_at(p.x, p.y) < 0.2 and map.nav.building_at(Vector3(p.x, 0, p.y)) == null:
			cand.append(p)
	var chosen: Array = []
	var min_d := 90.0
	while chosen.size() < 20 and min_d > 20.0:
		for p in cand:
			var ok := true
			for q in chosen:
				if (q as Vector2).distance_to(p) < min_d:
					ok = false
					break
			if ok:
				chosen.append(p)
				if chosen.size() >= 20:
					break
		min_d -= 15.0
	for p in chosen:
		map.spawn_points.append(Vector3(p.x, map.height_at(p.x, p.y) + 0.1, p.y))


# ------------------------------------------------------------------ minimapa
func _minimap() -> void:
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGB8)
	var half := MapData.HALF
	for py in sz:
		for px in sz:
			var x := -half + (px + 0.5) / sz * half * 2.0
			var z := -half + (py + 0.5) / sz * half * 2.0
			var h := map.height_at(x, z)
			var shade := clampf(0.78 + (h - 5.0) * 0.018, 0.55, 1.1)
			var col := Color(0.36, 0.52, 0.30) * shade
			var pv := _paved_mask(x, z)
			col = col.lerp(Color(0.52, 0.53, 0.50) * shade, pv * 0.8)
			if absf(map.height_at(x + 3.1, z) - h) > 0.9:
				col = col.lerp(Color(0.5, 0.42, 0.32), 0.6)
			col.a = 1.0
			img.set_pixel(px, py, col)
	for r in map.roads:
		var pts: PackedVector2Array = r["pts"]
		var wpx := maxi(int(float(r["width"]) / (half * 2.0) * sz * 1.3), 1)
		for p in pts:
			var cx := int((p.x + half) / (half * 2.0) * sz)
			var cy := int((p.y + half) / (half * 2.0) * sz)
			img.fill_rect(Rect2i(cx - wpx / 2, cy - wpx / 2, wpx, wpx), Color(0.78, 0.76, 0.70))
	for b in map.buildings:
		var rr: Rect2 = (b as BuildingInfo).rect
		var bx := int((rr.position.x + half) / (half * 2.0) * sz)
		var by := int((rr.position.y + half) / (half * 2.0) * sz)
		var bw := maxi(int(rr.size.x / (half * 2.0) * sz), 2)
		var bh := maxi(int(rr.size.y / (half * 2.0) * sz), 2)
		img.fill_rect(Rect2i(bx, by, bw, bh), Color(0.22, 0.24, 0.30))
	map.minimap = ImageTexture.create_from_image(img)
