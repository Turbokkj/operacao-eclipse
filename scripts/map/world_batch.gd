class_name WorldBatch
extends RefCounted
## Acumula geometria estática (por material) + colisões de caixa, e cria os nós de uma vez.
## Reduz drawcalls: 1 MeshInstance3D por cidade/região e 1 StaticBody3D com várias caixas.

var kits := {}
var cols: Array = []
var ramps: Array = []
var nav_rects: Array = []


func kit(key: String) -> MeshKit:
	if not kits.has(key):
		kits[key] = MeshKit.new(false)
	return kits[key]


func box(key: String, c: Vector3, sz: Vector3, col: Color, collide: bool = true, nav: bool = false, uv_tile: float = 3.0) -> void:
	kit(key).box(c, sz, col, 0, uv_tile)
	if collide:
		cols.append([c, sz])
	if nav:
		nav_rects.append(Rect2(c.x - sz.x * 0.5, c.z - sz.z * 0.5, sz.x, sz.z))


func cylinder(key: String, base: Vector3, radius: float, height: float, col: Color, nav: bool = true) -> void:
	kit(key).cylinder(base, radius, height, col, 14, 3.0)
	cols.append([base + Vector3(0, height * 0.5, 0), Vector3(radius * 1.7, height, radius * 1.7)])
	if nav:
		nav_rects.append(Rect2(base.x - radius, base.z - radius, radius * 2.0, radius * 2.0))


func ramp(xf: Transform3D, size: Vector3) -> void:
	ramps.append([xf, size])


func build(parent: Node3D, node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var mesh := ArrayMesh.new()
	for key in kits:
		(kits[key] as MeshKit).commit(mesh, MaterialLibrary.get_mat(str(key)))
	if mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for c in cols:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.position = c[0]
		body.add_child(cs)
	for r in ramps:
		var cs2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		bs2.size = r[1]
		cs2.shape = bs2
		cs2.transform = r[0]
		body.add_child(cs2)
	return root
