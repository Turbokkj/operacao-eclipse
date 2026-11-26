class_name MapData
extends RefCounted
## Dados do mapa gerado: mapa de alturas, cidades, estradas, construções, pontos de loot/spawn e navegação.

const HALF := 400.0
const CELL := 4.0
const N := 200

var half := HALF
var cells := N
var hm := PackedFloat32Array()
var cities: Array = []
var roads: Array = []
var buildings: Array = []
var loot_points: Array = []
var spawn_points: Array = []
var nav: NavGrid
var minimap: ImageTexture
var extent := 400.0          # meia-largura jogável


func idx(i: int, j: int) -> int:
	return j * (cells + 1) + i


## Altura exatamente consistente com a malha (interpolação por triângulo).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + half) / CELL, 0.0, cells - 0.001)
	var fz := clampf((z + half) / CELL, 0.0, cells - 0.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var h00 := hm[idx(i, j)]
	var h10 := hm[idx(i + 1, j)]
	var h01 := hm[idx(i, j + 1)]
	var h11 := hm[idx(i + 1, j + 1)]
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func slope_at(x: float, z: float) -> float:
	var dx := height_at(x + 2.0, z) - height_at(x - 2.0, z)
	var dz := height_at(x, z + 2.0) - height_at(x, z - 2.0)
	return atan(sqrt(dx * dx + dz * dz) / 4.0)


func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= extent - margin and absf(z) <= extent - margin


func city_at(x: float, z: float) -> Dictionary:
	for c in cities:
		var cc: Vector2 = c["center"]
		if cc.distance_to(Vector2(x, z)) < float(c["radius"]):
			return c
	return {}


## Distância (2D) do ponto a qualquer estrada.
func road_distance(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for r in roads:
		var pts: PackedVector2Array = r["pts"]
		for i in pts.size() - 1:
			var cp := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, cp.distance_to(p) - float(r["width"]) * 0.5)
	return best
