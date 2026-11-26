class_name LootItem
extends Node3D
## Item físico no mundo (visível, com anel de raridade e feixe de luz para itens raros).
## A coleta é feita pelo Combatant (jogador com [E]/botão, bots por proximidade).

static var _mesh_cache := {}

var uid := 0
var item_id := ""
var qty := 1
var bot_ok := true
var picked := false
var visual: Node3D
var phase := 0.0


func setup(id: String, p_qty: int, p_bot_ok: bool = true) -> void:
	item_id = id
	qty = p_qty
	bot_ok = p_bot_ok
	phase = randf() * TAU
	add_to_group("loot")
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var col := ItemDB.rarity_color(id)
	var cat := ItemDB.category(id)
	if cat == "weapon":
		var w := WeaponModels.build(id)
		w.scale = Vector3(0.9, 0.9, 0.9)
		w.position = Vector3(0, 0.0, 0.25)
		visual.add_child(w)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = _item_mesh(id)
		mi.material_override = MaterialLibrary.vertex_color_mat(0.55, 0.1)
		visual.add_child(mi)
	# anel de raridade no chão
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.02
	cm.radial_segments = 16
	cm.rings = 1
	ring.mesh = cm
	ring.material_override = MaterialLibrary.glow_mat(col, 1.6, 0.7)
	ring.position = Vector3(0, -0.28, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if int(ItemDB.get_def(id).get("rarity", 0)) >= 2:
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 7.0, 0.12)
		beam.mesh = bm
		beam.material_override = MaterialLibrary.glow_mat(col, 1.5, 0.35)
		beam.position = Vector3(0, 3.2, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)


static func _item_mesh(id: String) -> ArrayMesh:
	if _mesh_cache.has(id) and is_instance_valid(_mesh_cache[id]):
		return _mesh_cache[id]
	var k := MeshKit.new(false)
	var cat := ItemDB.category(id)
	match cat:
		"ammo":
			k.box(Vector3(0, 0, 0), Vector3(0.26, 0.15, 0.34), Color(0.85, 0.65, 0.2))
			k.box(Vector3(0, 0.08, 0), Vector3(0.27, 0.02, 0.10), Color(0.2, 0.2, 0.22))
		"heal":
			k.box(Vector3(0, 0, 0), Vector3(0.34, 0.22, 0.24), Color(0.95, 0.95, 0.95))
			k.box(Vector3(0, 0, -0.121), Vector3(0.20, 0.06, 0.01), Color(0.9, 0.15, 0.15))
			k.box(Vector3(0, 0, -0.121), Vector3(0.06, 0.20, 0.01), Color(0.9, 0.15, 0.15))
			k.box(Vector3(0, 0, 0.121), Vector3(0.20, 0.06, 0.01), Color(0.9, 0.15, 0.15))
		"armor":
			if str(ItemDB.get_def(id)["slot"]) == "vest":
				k.box(Vector3(0, 0, 0), Vector3(0.42, 0.46, 0.18), Color(0.2, 0.28, 0.42))
				k.box(Vector3(0, -0.08, -0.095), Vector3(0.30, 0.12, 0.03), Color(0.12, 0.16, 0.24))
			else:
				k.ellipsoid(Vector3(0, 0, 0), Vector3(0.20, 0.17, 0.22), Color(0.3, 0.38, 0.3), 0, 6, 10, 0.0)
		"pack":
			k.box(Vector3(0, 0, 0), Vector3(0.36, 0.46, 0.22), Color(0.25, 0.42, 0.28))
			k.box(Vector3(0, -0.10, -0.12), Vector3(0.28, 0.16, 0.05), Color(0.18, 0.3, 0.2))
		_:
			k.cylinder(Vector3(0, -0.12, 0), 0.07, 0.24, Color(0.35, 0.36, 0.4), 8)
			k.box(Vector3(0, 0.0, 0), Vector3(0.20, 0.06, 0.06), Color(0.8, 0.45, 0.1))
	var m := ArrayMesh.new()
	k.commit(m)
	_mesh_cache[id] = m
	return m
