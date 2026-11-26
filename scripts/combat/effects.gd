class_name Effects
extends RefCounted
## Efeitos visuais baratos e sem violência gráfica: clarão de boca, rastro do projétil, faíscas de impacto.
## Usa pequenos pools de nós reaproveitados para não gerar lixo a cada tiro.

static var _tracers: Array = []
static var _sparks: Array = []
static var _flashes: Array = []


static func _root(from: Node) -> Node:
	return from.get_tree().current_scene


static func tracer(from: Node, a: Vector3, b: Vector3, col: Color) -> void:
	var root := _root(from)
	if root == null or a.distance_to(b) < 0.5:
		return
	var mi: MeshInstance3D = null
	for t in _tracers:
		if is_instance_valid(t) and not t.visible and t.is_inside_tree():
			mi = t
			break
	if mi == null:
		mi = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		mi.mesh = bm
		mi.material_override = MaterialLibrary.glow_mat(Color(1, 1, 1), 3.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		_tracers.append(mi)
	(mi.material_override as StandardMaterial3D).albedo_color = col
	(mi.material_override as StandardMaterial3D).emission = col
	var len_m := a.distance_to(b)
	var start := a.lerp(b, minf(0.15, 1.0 / len_m * 2.0))
	var fwd := (b - a).normalized()
	var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.RIGHT
	var bas := Basis.looking_at(fwd, up) * Basis.from_scale(Vector3(1.0, 1.0, len_m * 0.85))
	mi.global_transform = Transform3D(bas, (start + b) * 0.5)
	mi.visible = true
	var tw := mi.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func(): mi.visible = false)


static func muzzle_flash(from: Node, pos: Vector3) -> void:
	var root := _root(from)
	if root == null:
		return
	var l: OmniLight3D = null
	for f in _flashes:
		if is_instance_valid(f) and not f.visible and f.is_inside_tree():
			l = f
			break
	if l == null:
		l = OmniLight3D.new()
		l.light_color = Color(1.0, 0.75, 0.4)
		l.light_energy = 2.5
		l.omni_range = 7.0
		l.shadow_enabled = false
		root.add_child(l)
		_flashes.append(l)
	l.global_position = pos
	l.visible = true
	var tw := l.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(func(): l.visible = false)


static func impact(from: Node, pos: Vector3, normal: Vector3) -> void:
	var root := _root(from)
	if root == null or QualityManager.particles() < 0.3:
		return
	var p: CPUParticles3D = null
	for s in _sparks:
		if is_instance_valid(s) and not s.emitting and s.is_inside_tree():
			p = s
			break
	if p == null:
		p = CPUParticles3D.new()
		p.one_shot = true
		p.amount = 8
		p.lifetime = 0.35
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 55.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -9.0, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		var sm := SphereMesh.new()
		sm.radius = 0.025
		sm.height = 0.05
		sm.radial_segments = 4
		sm.rings = 2
		p.mesh = sm
		p.material_override = MaterialLibrary.glow_mat(Color(1.0, 0.8, 0.4), 2.5)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(p)
		_sparks.append(p)
	p.global_position = pos + normal * 0.03
	if normal.length() > 0.1:
		p.direction = normal
	p.restart()
	p.emitting = true
