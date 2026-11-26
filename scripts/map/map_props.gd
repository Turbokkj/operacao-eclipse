class_name MapProps
extends RefCounted
## Props do cenário: carros abandonados, contêineres, cercas, tanques, guindaste decorativo, postes e a
## geometria (malhas) de árvores/arbustos/rochas usadas em MultiMesh.

const CAR_COLORS := [Color(0.65, 0.18, 0.15), Color(0.2, 0.35, 0.6), Color(0.75, 0.72, 0.65), Color(0.25, 0.4, 0.3), Color(0.8, 0.6, 0.2)]
const CONTAINER_COLORS := [Color(0.72, 0.25, 0.18), Color(0.2, 0.38, 0.62), Color(0.78, 0.6, 0.18), Color(0.25, 0.5, 0.35), Color(0.55, 0.55, 0.58)]


## Carro estilizado (corpo + cabine + rodas); 'along_x' define a orientação.
static func car(batch: WorldBatch, pos: Vector3, along_x: bool, col: Color) -> void:
	var l := Vector3(4.3, 0.8, 1.85) if along_x else Vector3(1.85, 0.8, 4.3)
	var cab := Vector3(2.1, 0.7, 1.6) if along_x else Vector3(1.6, 0.7, 2.1)
	batch.box("metal", pos + Vector3(0, 0.62, 0), l, col, true, true, 2.0)
	batch.box("metal", pos + Vector3(0, 1.32, 0), cab, col.darkened(0.15), false, false, 2.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var o := Vector3(sx * (1.4 if along_x else 0.85), 0.32, sz * (0.85 if along_x else 1.4))
			var ws := Vector3(0.7, 0.64, 0.3) if along_x else Vector3(0.3, 0.64, 0.7)
			batch.box("plain", pos + o, ws, Color(0.08, 0.08, 0.09), false, false, 1.0)


static func container(batch: WorldBatch, pos: Vector3, along_x: bool, col: Color, stack: int) -> void:
	var sz := Vector3(6.0, 2.6, 2.4) if along_x else Vector3(2.4, 2.6, 6.0)
	for i in stack:
		batch.box("metal", pos + Vector3(0, 1.3 + 2.6 * i, 0), sz, col.darkened(0.08 * i), true, i == 0, 2.0)


## Cerca em linha reta alinhada a um eixo (postes + trilho), com colisão.
static func fence(batch: WorldBatch, a: Vector3, b: Vector3, h: float = 1.1) -> void:
	var d := b - a
	var len_m := d.length()
	if len_m < 0.5:
		return
	var mid := (a + b) * 0.5
	var along_x := absf(d.x) >= absf(d.z)
	var sz := Vector3(len_m, 0.12, 0.08) if along_x else Vector3(0.08, 0.12, len_m)
	batch.box("wood", mid + Vector3(0, h * 0.85, 0), sz, Color(0.62, 0.5, 0.36), false, false, 1.5)
	var sz2 := Vector3(len_m, 0.12, 0.08) if along_x else Vector3(0.08, 0.12, len_m)
	batch.box("wood", mid + Vector3(0, h * 0.45, 0), sz2, Color(0.62, 0.5, 0.36), false, false, 1.5)
	# colisão fina para a cerca inteira
	var col_sz := Vector3(len_m, h, 0.12) if along_x else Vector3(0.12, h, len_m)
	batch.cols.append([mid + Vector3(0, h * 0.5, 0), col_sz])
	batch.nav_rects.append(Rect2(mid.x - col_sz.x * 0.5, mid.z - col_sz.z * 0.5, col_sz.x, col_sz.z))
	var steps := maxi(int(len_m / 2.5), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		batch.box("wood", p + Vector3(0, h * 0.5, 0), Vector3(0.12, h, 0.12), Color(0.5, 0.4, 0.28), false, false, 1.5)


static func lamp(batch: WorldBatch, pos: Vector3) -> void:
	batch.box("metal", pos + Vector3(0, 2.2, 0), Vector3(0.14, 4.4, 0.14), Color(0.25, 0.27, 0.3), true, true, 1.0)
	batch.box("plain", pos + Vector3(0.35, 4.4, 0), Vector3(0.8, 0.12, 0.3), Color(1.0, 0.92, 0.6), false, false, 1.0)


static func bench(batch: WorldBatch, pos: Vector3, along_x: bool) -> void:
	var sz := Vector3(1.8, 0.1, 0.5) if along_x else Vector3(0.5, 0.1, 1.8)
	batch.box("wood", pos + Vector3(0, 0.45, 0), sz, Color(0.55, 0.38, 0.22), true, false, 1.5)
	var bk := Vector3(1.8, 0.5, 0.08) if along_x else Vector3(0.08, 0.5, 1.8)
	var off := Vector3(0, 0.75, 0.25) if along_x else Vector3(0.25, 0.75, 0)
	batch.box("wood", pos + off, bk, Color(0.5, 0.35, 0.2), false, false, 1.5)


static func crane(batch: WorldBatch, pos: Vector3, height: float) -> void:
	batch.box("metal", pos + Vector3(-3.0, height * 0.5, 0), Vector3(0.9, height, 0.9), Color(0.85, 0.55, 0.1), true, true, 2.0)
	batch.box("metal", pos + Vector3(3.0, height * 0.5, 0), Vector3(0.9, height, 0.9), Color(0.85, 0.55, 0.1), true, true, 2.0)
	batch.box("metal", pos + Vector3(0, height, 0), Vector3(7.5, 1.0, 1.0), Color(0.85, 0.55, 0.1), true, false, 2.0)
	batch.box("metal", pos + Vector3(14.0, height, 0), Vector3(22.0, 0.8, 0.8), Color(0.8, 0.5, 0.1), false, false, 2.0)
	batch.box("metal", pos + Vector3(0, height * 0.5, 0), Vector3(6.0, 0.4, 0.4), Color(0.7, 0.45, 0.1), false, false, 2.0)


# ----------------------------------------------------------- malhas de vegetação
static func tree_mesh(kind: int) -> ArrayMesh:
	var k := MeshKit.new(false)
	var trunk := Color(0.36, 0.25, 0.15)
	if kind == 0:
		k.cylinder(Vector3(0, 0, 0), 0.24, 2.8, trunk, 6, 0.0, false)
		k.ellipsoid(Vector3(0, 3.9, 0), Vector3(1.9, 1.7, 1.9), Color(0.26, 0.52, 0.20), 0, 6, 9)
		k.ellipsoid(Vector3(0.8, 4.6, 0.3), Vector3(1.3, 1.2, 1.3), Color(0.32, 0.58, 0.24), 0, 5, 8)
		k.ellipsoid(Vector3(-0.8, 3.5, 0.6), Vector3(1.25, 1.1, 1.25), Color(0.22, 0.46, 0.18), 0, 5, 8)
	elif kind == 1:
		k.cylinder(Vector3(0, 0, 0), 0.2, 2.2, trunk, 6, 0.0, false)
		k.ellipsoid(Vector3(0, 3.0, 0), Vector3(1.5, 1.4, 1.5), Color(0.14, 0.38, 0.22), 0, 5, 8)
		k.ellipsoid(Vector3(0, 4.4, 0), Vector3(1.15, 1.3, 1.15), Color(0.16, 0.42, 0.24), 0, 5, 8)
		k.ellipsoid(Vector3(0, 5.6, 0), Vector3(0.8, 1.2, 0.8), Color(0.18, 0.46, 0.26), 0, 5, 8)
		k.ellipsoid(Vector3(0, 6.6, 0), Vector3(0.4, 1.0, 0.4), Color(0.2, 0.5, 0.28), 0, 4, 6)
	elif kind == 2:
		k.ellipsoid(Vector3(0, 0.45, 0), Vector3(0.95, 0.65, 0.95), Color(0.24, 0.5, 0.2), 0, 5, 8)
		k.ellipsoid(Vector3(0.5, 0.35, 0.3), Vector3(0.6, 0.45, 0.6), Color(0.3, 0.56, 0.24), 0, 4, 6)
	else:
		k.ellipsoid(Vector3(0, 0.35, 0), Vector3(1.1, 0.85, 0.95), Color(0.48, 0.48, 0.5), 0, 5, 8, -0.25)
		k.ellipsoid(Vector3(0.7, 0.2, 0.4), Vector3(0.6, 0.45, 0.55), Color(0.42, 0.42, 0.44), 0, 4, 6, -0.2)
	var m := ArrayMesh.new()
	k.commit(m)
	return m
