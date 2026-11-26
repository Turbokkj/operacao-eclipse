class_name MeshKit
extends RefCounted
## Acumulador de geometria procedural (elipsoides, "loft" de seções, caixas, cilindros).
## Usado para personagens (com pesos de ossos / skinning) e para o mundo (UV em escala de mundo).
## O sentido horário é a face frontal no Godot; tri() orienta cada triângulo pela normal informada.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var skinned := false


func _init(is_skinned: bool = false) -> void:
	skinned = is_skinned


func vert(p: Vector3, n: Vector3, c: Color, uv: Vector2 = Vector2.ZERO, b0: int = 0, w0: float = 1.0, b1: int = 0, w1: float = 0.0) -> int:
	var i := verts.size()
	verts.append(p)
	norms.append(n)
	cols.append(c)
	uvs.append(uv)
	if skinned:
		bones.append(b0)
		bones.append(b1)
		bones.append(0)
		bones.append(0)
		weights.append(w0)
		weights.append(w1)
		weights.append(0.0)
		weights.append(0.0)
	return i


func tri(a: int, b: int, c: int) -> void:
	var g := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if g.length_squared() < 0.0000001:
		return
	var n := norms[a] + norms[b] + norms[c]
	if g.dot(n) > 0.0:
		idx.append(a)
		idx.append(c)
		idx.append(b)
	else:
		idx.append(a)
		idx.append(b)
		idx.append(c)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


func is_empty() -> bool:
	return verts.is_empty()


## Elipsoide (ou calota, usando y_cut > -1). Pesos: osso principal + opcional b1/w1.
func ellipsoid(c: Vector3, r: Vector3, col: Color, bone: int = 0, rings: int = 8, segs: int = 12, y_cut: float = -1.0, b1: int = -1, w1: float = 0.0) -> void:
	var t_max := acos(clampf(y_cut, -1.0, 1.0))
	var rows: Array = []
	var sb := b1 if b1 >= 0 else bone
	for i in rings + 1:
		var th := t_max * float(i) / rings
		var y := cos(th)
		var rr := sin(th)
		var row: Array = []
		for j in segs:
			var ph := TAU * float(j) / segs
			var u := Vector3(rr * cos(ph), y, rr * sin(ph))
			var n := Vector3(u.x / r.x, u.y / r.y, u.z / r.z).normalized()
			row.append(vert(c + Vector3(u.x * r.x, u.y * r.y, u.z * r.z), n, col, Vector2(float(j) / segs, float(i) / rings), bone, 1.0 - w1, sb, w1))
		rows.append(row)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			var a: int = rows[i][j]
			var b: int = rows[i][j2]
			var cc: int = rows[i + 1][j]
			var d: int = rows[i + 1][j2]
			quad(a, b, d, cc)


## "Loft": anéis elípticos horizontais definidos por seções {p, rx, rz, c, b0, w0, b1, w1}.
func loft(secs: Array, segs: int = 10) -> void:
	var rows: Array = []
	for s in secs:
		var row: Array = []
		var p: Vector3 = s["p"]
		var rx: float = s["rx"]
		var rz: float = s["rz"]
		for j in segs:
			var ph := TAU * float(j) / segs
			var cx := cos(ph)
			var sz := sin(ph)
			var n := Vector3(cx / rx, 0.0, sz / rz).normalized()
			row.append(vert(p + Vector3(cx * rx, 0.0, sz * rz), n, s["c"], Vector2(float(j) / segs, p.y), s["b0"], s["w0"], s["b1"], s["w1"]))
		rows.append(row)
	for i in rows.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			quad(rows[i][j], rows[i][j2], rows[i + 1][j2], rows[i + 1][j])


## Caixa alinhada aos eixos. uv_tile > 0 => UV em escala de mundo (metros por repetição).
func box(c: Vector3, sz: Vector3, col: Color, bone: int = 0, uv_tile: float = 0.0) -> void:
	var h := sz * 0.5
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for ai in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = axes[ai] * sgn
			var u: Vector3 = axes[(ai + 1) % 3]
			var v: Vector3 = axes[(ai + 2) % 3]
			var fc := c + n * h[ai]
			var hu: float = h[(ai + 1) % 3]
			var hv: float = h[(ai + 2) % 3]
			var p0 := fc - u * hu - v * hv
			var p1 := fc + u * hu - v * hv
			var p2 := fc + u * hu + v * hv
			var p3 := fc - u * hu + v * hv
			var i0 := vert(p0, n, col, _uv(p0, n, uv_tile), bone)
			var i1 := vert(p1, n, col, _uv(p1, n, uv_tile), bone)
			var i2 := vert(p2, n, col, _uv(p2, n, uv_tile), bone)
			var i3 := vert(p3, n, col, _uv(p3, n, uv_tile), bone)
			quad(i0, i1, i2, i3)


## Quadrilátero com normal explícita (telhados inclinados etc.).
func quad_n(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, col: Color, uv_tile: float = 3.0) -> void:
	var i0 := vert(p0, n, col, _uv(p0, n, uv_tile))
	var i1 := vert(p1, n, col, _uv(p1, n, uv_tile))
	var i2 := vert(p2, n, col, _uv(p2, n, uv_tile))
	var i3 := vert(p3, n, col, _uv(p3, n, uv_tile))
	quad(i0, i1, i2, i3)


func tri_n(p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, col: Color, uv_tile: float = 3.0) -> void:
	var i0 := vert(p0, n, col, _uv(p0, n, uv_tile))
	var i1 := vert(p1, n, col, _uv(p1, n, uv_tile))
	var i2 := vert(p2, n, col, _uv(p2, n, uv_tile))
	tri(i0, i1, i2)


## Cilindro vertical (base em 'base', altura 'height').
func cylinder(base: Vector3, radius: float, height: float, col: Color, segs: int = 12, uv_tile: float = 0.0, cap: bool = true) -> void:
	var tile := uv_tile if uv_tile > 0.0 else 1.0
	var bot: Array = []
	var top: Array = []
	for j in segs:
		var ph := TAU * float(j) / segs
		var n := Vector3(cos(ph), 0.0, sin(ph))
		var u := float(j) / segs * TAU * radius / tile
		bot.append(vert(base + n * radius, n, col, Vector2(u, base.y / tile)))
		top.append(vert(base + n * radius + Vector3(0, height, 0), n, col, Vector2(u, (base.y + height) / tile)))
	for j in segs:
		var j2 := (j + 1) % segs
		quad(bot[j], bot[j2], top[j2], top[j])
	if cap:
		var cc := vert(base + Vector3(0, height, 0), Vector3.UP, col, Vector2(0.5, 0.5))
		var ring: Array = []
		for j in segs:
			var ph := TAU * float(j) / segs
			ring.append(vert(base + Vector3(cos(ph) * radius, height, sin(ph) * radius), Vector3.UP, col, Vector2(0.5 + cos(ph) * 0.5, 0.5 + sin(ph) * 0.5)))
		for j in segs:
			tri(cc, ring[j], ring[(j + 1) % segs])


func _uv(p: Vector3, n: Vector3, tile: float) -> Vector2:
	if tile <= 0.0:
		return Vector2.ZERO
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return Vector2(p.x, p.z) / tile
	if an.x >= an.z:
		return Vector2(p.z, -p.y) / tile
	return Vector2(p.x, -p.y) / tile


func commit(mesh: ArrayMesh, mat: Material = null) -> void:
	if verts.is_empty() or idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	if skinned:
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if mat != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
