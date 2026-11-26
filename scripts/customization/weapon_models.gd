class_name WeaponModels
extends RefCounted
## Modelos 3D procedurais das armas virtuais (originais, estilizadas). Cano apontando para -Z.
## Cada modelo tem marcadores: Muzzle (boca), GripR (mão direita), GripL (mão esquerda).

const DARK := Color(0.12, 0.13, 0.15)
const MID := Color(0.22, 0.24, 0.27)
const METAL := Color(0.45, 0.47, 0.5)
const WOOD := Color(0.42, 0.28, 0.16)


static func _spec(id: String) -> Dictionary:
	match id:
		"pistol":
			return {"len": 0.22, "gr": Vector3(0, -0.06, -0.02), "gl": Vector3(0, -0.055, -0.035), "parts": [
				[Vector3(0, 0.02, -0.10), Vector3(0.034, 0.046, 0.20), MID],
				[Vector3(0, -0.04, -0.015), Vector3(0.032, 0.095, 0.045), DARK],
				[Vector3(0, 0.02, -0.215), Vector3(0.018, 0.018, 0.04), METAL]]}
		"smg":
			return {"len": 0.44, "gr": Vector3(0, -0.07, 0.0), "gl": Vector3(0, -0.035, -0.22), "parts": [
				[Vector3(0, 0.0, -0.15), Vector3(0.05, 0.07, 0.30), MID],
				[Vector3(0, -0.10, -0.12), Vector3(0.030, 0.12, 0.040), DARK],
				[Vector3(0, -0.065, 0.0), Vector3(0.034, 0.085, 0.04), DARK],
				[Vector3(0, 0.012, -0.37), Vector3(0.022, 0.022, 0.14), METAL],
				[Vector3(0, 0.0, 0.12), Vector3(0.03, 0.05, 0.13), DARK],
				[Vector3(0, 0.045, -0.12), Vector3(0.02, 0.02, 0.06), Color(1.0, 0.5, 0.1)]]}
		"rifle":
			return {"len": 0.80, "gr": Vector3(0, -0.08, -0.02), "gl": Vector3(0, -0.03, -0.30), "parts": [
				[Vector3(0, 0.0, -0.22), Vector3(0.055, 0.08, 0.44), MID],
				[Vector3(0, -0.005, -0.52), Vector3(0.05, 0.06, 0.20), DARK],
				[Vector3(0, 0.012, -0.71), Vector3(0.022, 0.022, 0.18), METAL],
				[Vector3(0, -0.11, -0.20), Vector3(0.036, 0.14, 0.07), DARK],
				[Vector3(0, -0.075, -0.02), Vector3(0.035, 0.09, 0.045), DARK],
				[Vector3(0, -0.01, 0.20), Vector3(0.045, 0.09, 0.28), DARK],
				[Vector3(0, 0.06, -0.25), Vector3(0.03, 0.03, 0.08), Color(1.0, 0.5, 0.1)]]}
		"shotgun":
			return {"len": 0.78, "gr": Vector3(0, -0.075, -0.02), "gl": Vector3(0, -0.035, -0.30), "parts": [
				[Vector3(0, 0.0, -0.20), Vector3(0.055, 0.07, 0.40), MID],
				[Vector3(0, 0.016, -0.58), Vector3(0.036, 0.036, 0.40), METAL],
				[Vector3(0, -0.04, -0.46), Vector3(0.05, 0.05, 0.17), WOOD],
				[Vector3(0, -0.015, 0.20), Vector3(0.05, 0.09, 0.30), WOOD],
				[Vector3(0, -0.07, -0.02), Vector3(0.034, 0.08, 0.045), DARK]]}
		_:
			return {"len": 1.05, "gr": Vector3(0, -0.08, -0.02), "gl": Vector3(0, -0.03, -0.32), "parts": [
				[Vector3(0, 0.0, -0.25), Vector3(0.055, 0.08, 0.50), MID],
				[Vector3(0, 0.012, -0.86), Vector3(0.020, 0.020, 0.42), METAL],
				[Vector3(0, 0.095, -0.22), Vector3(0.036, 0.042, 0.24), Color(0.15, 0.2, 0.3)],
				[Vector3(0, -0.095, -0.25), Vector3(0.030, 0.10, 0.06), DARK],
				[Vector3(0, -0.075, -0.02), Vector3(0.035, 0.09, 0.045), DARK],
				[Vector3(0, -0.01, 0.22), Vector3(0.045, 0.09, 0.30), DARK]]}


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"
	var spec := _spec(id)
	var k := MeshKit.new(false)
	for p in spec["parts"]:
		k.box(p[0], p[1], p[2])
	var mesh := ArrayMesh.new()
	k.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MaterialLibrary.vertex_color_mat(0.45, 0.35)
	root.add_child(mi)
	var mz := Marker3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, 0.015, -float(spec["len"]) - 0.02)
	root.add_child(mz)
	var gr := Marker3D.new()
	gr.name = "GripR"
	gr.position = spec["gr"]
	root.add_child(gr)
	var gl := Marker3D.new()
	gl.name = "GripL"
	gl.position = spec["gl"]
	root.add_child(gl)
	return root
