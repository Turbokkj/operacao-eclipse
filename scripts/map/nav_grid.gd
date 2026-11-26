class_name NavGrid
extends RefCounted
## Navegação em dois níveis (não depende de bake de NavMesh no navegador):
##  - EXTERNO: AStarGrid2D (células de 2,5 m) com pegadas de construções, props e declives bloqueados;
##    caminhos suavizados por linha de visão.
##  - INTERNO: grafo de salas/portas de cada construção (BuildingInfo.interior_path).
## find_path() combina os dois: sala -> porta -> rua -> porta -> sala.

var half := 400.0
var cs := 2.5
var n := 320
var astar := AStarGrid2D.new()
var buildings: Array = []


func setup(p_half: float, p_cell: float) -> void:
	half = p_half
	cs = p_cell
	n = int(ceil(half * 2.0 / cs))
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(cs, cs)
	astar.offset = Vector2(-half + cs * 0.5, -half + cs * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori((x + half) / cs), 0, n - 1), clampi(floori((z + half) / cs), 0, n - 1))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(-half + (c.x + 0.5) * cs, 0.0, -half + (c.y + 0.5) * cs)


func block_rect(r: Rect2) -> void:
	var a := cell_of(r.position.x, r.position.y)
	var b := cell_of(r.end.x, r.end.y)
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			astar.set_point_solid(Vector2i(i, j), true)


func block_cell_at(x: float, z: float) -> void:
	astar.set_point_solid(cell_of(x, z), true)


func is_free_at(x: float, z: float) -> bool:
	return not astar.is_point_solid(cell_of(x, z))


func nearest_free(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 12):
		for i in range(c.x - r, c.x + r + 1):
			for j in range(c.y - r, c.y + r + 1):
				if absi(i - c.x) != r and absi(j - c.y) != r:
					continue
				var cc := Vector2i(i, j)
				if i >= 0 and j >= 0 and i < n and j < n and not astar.is_point_solid(cc):
					return cc
	return c


func building_at(p: Vector3) -> BuildingInfo:
	for b in buildings:
		if (b as BuildingInfo).contains(p, 0.0):
			return b
	return null


func _los(a: Vector3, b: Vector3) -> bool:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var dist := d.length()
	if dist < 0.1:
		return true
	var dir := d / dist
	var perp := Vector3(-dir.z, 0.0, dir.x) * 0.6
	var t := 0.0
	while t <= dist:
		var p := a + dir * t
		if not is_free_at(p.x, p.z) or not is_free_at(p.x + perp.x, p.z + perp.z) or not is_free_at(p.x - perp.x, p.z - perp.z):
			return false
		t += 0.9
	return true


func _smooth(pts: Array) -> Array:
	if pts.size() <= 2:
		return pts
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var j := mini(i + 14, pts.size() - 1)
		while j > i + 1:
			if _los(pts[i], pts[j]):
				break
			j -= 1
		out.append(pts[j])
		i = j
	return out


func find_path_outdoor(a: Vector3, b: Vector3) -> Array:
	var ca := nearest_free(cell_of(a.x, a.z))
	var cb := nearest_free(cell_of(b.x, b.z))
	var pts: PackedVector2Array = astar.get_point_path(ca, cb)
	if pts.is_empty():
		return []
	var out: Array = []
	for p in pts:
		out.append(Vector3(p.x, 0.0, p.y))
	out = _smooth(out)
	if is_free_at(b.x, b.z) and _los(out[out.size() - 1], b):
		out.append(Vector3(b.x, 0.0, b.z))
	return out


## Caminho completo (lista de Vector3; só x/z importam). Vazio = inacessível.
func find_path(from: Vector3, to: Vector3) -> Array:
	var bf := building_at(from)
	var bt := building_at(to)
	if bf != null and bf == bt:
		return bf.interior_path(from, to)
	var path: Array = []
	var start := from
	if bf != null:
		var d: Dictionary = bf.nearest_door(from)
		if d.is_empty():
			return []
		path.append_array(bf.interior_path(from, d["in_pt"]))
		path.append(d["pos"])
		path.append(d["out_pt"])
		start = d["out_pt"]
	var goal := to
	var tail: Array = []
	if bt != null:
		var d2: Dictionary = bt.nearest_door(start)
		if d2.is_empty():
			return []
		tail.append(d2["out_pt"])
		tail.append(d2["pos"])
		tail.append(d2["in_pt"])
		tail.append_array(bt.interior_path(d2["in_pt"], to))
		goal = d2["out_pt"]
	var mid := find_path_outdoor(start, goal)
	if mid.is_empty() and start.distance_to(goal) > 3.0:
		return []
	path.append_array(mid)
	path.append_array(tail)
	return path


func random_free_point(rng: RandomNumberGenerator, center: Vector3, radius: float) -> Vector3:
	for _i in 20:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := center + Vector3(cos(a), 0.0, sin(a)) * r
		if absf(p.x) < half - 6.0 and absf(p.z) < half - 6.0 and is_free_at(p.x, p.z):
			return p
	return center
