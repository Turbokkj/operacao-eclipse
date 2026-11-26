class_name BuildingInfo
extends RefCounted
## Dados de uma construção usados por navegação, loot e bots: pegada, salas, portas e ligações entre salas.

var rect := Rect2()
var ground := 0.0
var rooms: Array = []
var doors: Array = []     # {pos, in_pt, out_pt, room}
var links: Array = []     # {a, b, pos, pa, pb}
var tier := 0
var city := "wild"
var kind := "house"
var uid := 0


func contains(p: Vector3, margin: float = 0.0) -> bool:
	return rect.grow(margin).has_point(Vector2(p.x, p.z))


func room_at(p: Vector3) -> int:
	var v := Vector2(p.x, p.z)
	for i in rooms.size():
		var rr: Rect2 = rooms[i]
		if rr.grow(0.2).has_point(v):
			return i
	return -1


func nearest_door(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for d in doors:
		var dd := (d["pos"] as Vector3).distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = d
	return best


func center() -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, ground, c.y)


## Caminho entre duas posições DENTRO da construção, passando pelas portas internas (BFS por salas).
func interior_path(from: Vector3, to: Vector3) -> Array:
	var ra := room_at(from)
	var rb := room_at(to)
	if ra < 0 or rb < 0 or ra == rb:
		return [to]
	var prev := {ra: -1}
	var via := {}
	var queue: Array = [ra]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == rb:
			break
		for l in links:
			var nxt := -1
			if int(l["a"]) == cur:
				nxt = int(l["b"])
			elif int(l["b"]) == cur:
				nxt = int(l["a"])
			if nxt >= 0 and not prev.has(nxt):
				prev[nxt] = cur
				via[nxt] = l
				queue.append(nxt)
	if not prev.has(rb):
		return [to]
	var chain: Array = []
	var r := rb
	while r != ra:
		chain.push_front(via[r])
		r = int(prev[r])
	var out: Array = []
	var at := ra
	for l in chain:
		if int(l["a"]) == at:
			out.append(l["pa"])
			out.append(l["pos"])
			out.append(l["pb"])
			at = int(l["b"])
		else:
			out.append(l["pb"])
			out.append(l["pos"])
			out.append(l["pa"])
			at = int(l["a"])
	out.append(to)
	return out
