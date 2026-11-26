class_name CharacterModel
extends Node3D
## Personagem 3D completo: Skeleton3D (18 ossos) + malha com skinning + animador procedural + arma.
## Usado no lobby, na personalização, no jogador e nos bots (mesma aparência e mesmas animações).

var skeleton: Skeleton3D
var mesh_inst: MeshInstance3D
var animator: CharacterAnimator
var rig: Dictionary = {}
var appearance: Dictionary = {}
var weapon_root: Node3D
var weapon_node: Node3D
var weapon_id := ""


func setup(app: Dictionary) -> void:
	appearance = CosmeticsDB.sanitize(app)
	_build_all()


func _build_all() -> void:
	if skeleton != null:
		skeleton.queue_free()
		skeleton = null
	if weapon_root != null:
		weapon_root.queue_free()
		weapon_root = null
	rig = CharacterBuilder.compute_rig(CosmeticsDB.BODIES[appearance["body"]])
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	var pos: Array = rig["pos"]
	for i in 18:
		skeleton.add_bone(CharacterBuilder.BONE_NAMES[i])
	for i in 18:
		var par: int = CharacterBuilder.BONE_PARENT[i]
		skeleton.set_bone_parent(i, par)
		var parent_pos := Vector3.ZERO
		if par >= 0:
			parent_pos = pos[par]
		skeleton.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(pos[i]) - parent_pos))
	skeleton.reset_bone_poses()
	mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "Body"
	skeleton.add_child(mesh_inst)
	mesh_inst.skeleton = NodePath("..")
	mesh_inst.skin = skeleton.create_skin_from_rest_transforms()
	mesh_inst.mesh = CharacterBuilder.build_mesh(appearance, rig)
	mesh_inst.material_override = MaterialLibrary.vertex_color_mat(0.82, 0.0)
	mesh_inst.extra_cull_margin = 1.0
	weapon_root = Node3D.new()
	weapon_root.name = "WeaponRoot"
	add_child(weapon_root)
	animator = CharacterAnimator.new()
	animator.setup(skeleton, rig, weapon_root)
	var prev := weapon_id
	weapon_id = ""
	weapon_node = null
	if prev != "":
		set_weapon(prev)


## Aplica uma nova aparência (reconstrói só a malha, ou o esqueleto inteiro se o corpo-base mudou).
func set_appearance(app: Dictionary) -> void:
	var new_app := CosmeticsDB.sanitize(app)
	var body_changed: bool = int(new_app["body"]) != int(appearance.get("body", -1))
	appearance = new_app
	if body_changed or skeleton == null:
		_build_all()
	else:
		mesh_inst.mesh = CharacterBuilder.build_mesh(appearance, rig)


func set_weapon(wid: String) -> void:
	if weapon_node != null:
		weapon_node.queue_free()
		weapon_node = null
	weapon_id = wid
	if wid == "":
		animator.set_weapon_info("", Vector3.ZERO, Vector3.ZERO)
		return
	weapon_node = WeaponModels.build(wid)
	weapon_root.add_child(weapon_node)
	var gr: Vector3 = weapon_node.get_node("GripR").position
	var gl: Vector3 = weapon_node.get_node("GripL").position
	var kind: String = str(WeaponDB.get_def(wid).get("kind", "rifle"))
	animator.set_weapon_info(kind, gr, gl)


func muzzle_position() -> Vector3:
	if weapon_node != null and is_instance_valid(weapon_node) and weapon_node.is_inside_tree():
		return (weapon_node.get_node("Muzzle") as Node3D).global_position
	return global_position + Vector3(0, 1.45, 0)


func head_position() -> Vector3:
	return global_position + Vector3(0, float(rig["H"]) * 0.93, 0)
