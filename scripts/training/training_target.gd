class_name TrainingTarget
extends StaticBody3D
## Alvo físico de treino (existe no mundo 3D e responde a raycasts): disco de tiro com anéis, poste,
## movimento opcional (alvo móvel) e modo "pop-up" (sobe/desce). Pontuação por anel: 10/8/6/4/2.

signal scored(points: int, ring: int, target: TrainingTarget)

var kind := "static"        # static | moving | popup
var is_up := true
var move_range := 0.0
var move_speed := 2.0
var center_height := 1.4
var _origin := Vector3.ZERO
var _phase := 0.0
var _disc: Node3D
var _flash := 0.0
var _mats: Array = []


func build(height: float, radius: float = 0.5) -> void:
	center_height = height
	collision_layer = 1 | 4
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(radius * 2.0, radius * 2.0, 0.14)
	cs.shape = bs
	cs.position = Vector3(0, height, 0)
	add_child(cs)
	# poste
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.1, height, 0.1)
	post.mesh = pm
	post.position = Vector3(0, height * 0.5, -0.1)
	post.material_override = MaterialLibrary.vertex_color_mat(0.8, 0.2)
	add_child(post)
	# disco com anéis concêntricos (cilindros finos empilhados no eixo Z)
	_disc = Node3D.new()
	_disc.position = Vector3(0, height, 0)
	add_child(_disc)
	var ring_cols := [Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.12), Color(0.2, 0.45, 0.85), Color(0.9, 0.2, 0.15), Color(1.0, 0.85, 0.15)]
	for i in 5:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := radius * (1.0 - float(i) * 0.2)
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.04
		cm.radial_segments = 24
		cm.rings = 1
		mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ring_cols[i]
		mat.roughness = 0.7
		mat.emission_enabled = true
		mat.emission = Color(0, 0, 0)
		mi.material_override = mat
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = Vector3(0, 0, 0.05 + float(i) * 0.012)
		_disc.add_child(mi)
		_mats.append(mat)
	_origin = position
	add_to_group("training_targets")


func configure(p_kind: String, rng_range: float = 0.0, spd: float = 2.0) -> void:
	kind = p_kind
	move_range = rng_range
	move_speed = spd
	_origin = position
	_phase = randf() * TAU


func set_up(up: bool, instant: bool = false) -> void:
	is_up = up
	collision_layer = (1 | 4) if up else 0
	var target_rot := 0.0 if up else -90.0
	if instant:
		_disc.rotation_degrees.x = target_rot
		_disc.visible = up
		return
	_disc.visible = true
	var tw := create_tween()
	tw.tween_property(_disc, "rotation_degrees:x", target_rot, 0.18)
	if not up:
		tw.tween_callback(func(): _disc.visible = false)


func take_damage(_amount: float, attacker: Node, hit_pos: Vector3, _head: bool) -> void:
	if not is_up:
		return
	var center := global_position + Vector3(0, center_height, 0)
	var d := hit_pos.distance_to(center)
	var ring := 0
	var pts := 0
	if d < 0.1:
		ring = 5
		pts = 10
	elif d < 0.2:
		ring = 4
		pts = 8
	elif d < 0.3:
		ring = 3
		pts = 6
	elif d < 0.4:
		ring = 2
		pts = 4
	elif d < 0.5:
		ring = 1
		pts = 2
	_flash = 0.25
	AudioManager.play_sfx_3d("hit", hit_pos, -4.0, 1.2, 80.0)
	if attacker is Player:
		AudioManager.play_sfx("hit_confirm", -6.0)
		Events.hit_marker.emit(false)
	scored.emit(pts, ring, self)


func _physics_process(delta: float) -> void:
	if kind == "moving" and move_range > 0.0:
		_phase += delta * move_speed / maxf(move_range, 1.0)
		position = _origin + Vector3(sin(_phase) * move_range, 0.0, 0.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		for m in _mats:
			(m as StandardMaterial3D).emission = Color(1, 1, 1) * (_flash * 2.0)
