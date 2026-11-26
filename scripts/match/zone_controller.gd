class_name ZoneController
extends Node3D
## Zona segura circular dinâmica: círculo atual + próximo círculo marcado, fases com espera e fechamento,
## avisos ao jogador, dano por segundo fora da zona (aplicado a jogador E bots) e visual 3D (parede).

const PHASES := [
	{"wait": 40.0, "shrink": 40.0, "radius": 300.0, "dps": 1.0},
	{"wait": 32.0, "shrink": 32.0, "radius": 210.0, "dps": 2.0},
	{"wait": 26.0, "shrink": 28.0, "radius": 140.0, "dps": 3.5},
	{"wait": 20.0, "shrink": 25.0, "radius": 85.0, "dps": 5.0},
	{"wait": 15.0, "shrink": 20.0, "radius": 45.0, "dps": 8.0},
	{"wait": 10.0, "shrink": 15.0, "radius": 16.0, "dps": 12.0},
	{"wait": 5.0, "shrink": 15.0, "radius": 0.0, "dps": 20.0},
]

var center := Vector2.ZERO
var radius := 440.0
var next_center := Vector2.ZERO
var next_radius := -1.0
var shrinking := false
var phase := -1
var dps := 0.0
var running := false
var remote := false      # cliente online: estado vem do host (snapshots)
var elapsed := 0.0
var rng := RandomNumberGenerator.new()
var _timer := 0.0
var _dur := 1.0
var _from_center := Vector2.ZERO
var _from_radius := 0.0
var _tick := 0.0
var _warned := false
var _warn_player_t := 0.0
var _wall: MeshInstance3D
var _next_wall: MeshInstance3D


func _ready() -> void:
	rng.randomize()
	_wall = _make_ring(Color(0.25, 0.55, 1.0, 0.38))
	_next_wall = _make_ring(Color(1.0, 1.0, 1.0, 0.16))
	_update_visual()


func _make_ring(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 240.0
	cm.radial_segments = 96
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = MaterialLibrary.zone_mat(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func start() -> void:
	running = true
	phase = -1
	_advance()


func _advance() -> void:
	phase += 1
	if phase >= PHASES.size():
		next_radius = -1.0
		dps = 25.0
		_timer = 9999.0
		shrinking = false
		return
	var ph: Dictionary = PHASES[phase]
	var nr: float = ph["radius"]
	var max_off := maxf(radius - nr, 0.0) * 0.85
	var a := rng.randf() * TAU
	next_center = center + Vector2(cos(a), sin(a)) * rng.randf() * max_off
	next_radius = nr
	dps = float(ph["dps"])
	shrinking = false
	_timer = float(ph["wait"])
	_warned = false
	Events.zone_changed.emit(center, radius, next_center, next_radius, false)
	Events.notify.emit("Nova zona marcada. Fecha em %d s" % int(_timer), "zone")


func inside(p: Vector2, margin: float = 0.0) -> bool:
	return p.distance_to(center) <= radius - margin


func inside_next(p: Vector2, margin: float = 0.0) -> bool:
	if next_radius < 0.0:
		return inside(p, margin)
	return p.distance_to(next_center) <= next_radius - margin


func time_to_shrink() -> float:
	return 0.0 if shrinking else _timer


func status_text() -> String:
	if not running:
		return ""
	if next_radius < 0.0:
		return "ZONA FINAL"
	if shrinking:
		return "ZONA FECHANDO"
	return "ZONA FECHA EM %d:%02d" % [int(_timer) / 60, int(_timer) % 60]


func safe_point(nav: NavGrid) -> Vector3:
	var c := next_center if next_radius >= 0.0 else center
	var r := (next_radius if next_radius >= 0.0 else radius) * 0.6
	if nav == null:
		return Vector3(c.x, 0.0, c.y)
	return nav.random_free_point(rng, Vector3(c.x, 0.0, c.y), maxf(r, 4.0))


func apply_net(a: Array) -> void:
	# [cx, cz, r, ncx, ncz, nr, encolhendo(0/1), timer]
	running = true
	center = Vector2(float(a[0]), float(a[1]))
	radius = float(a[2])
	next_center = Vector2(float(a[3]), float(a[4]))
	next_radius = float(a[5])
	shrinking = int(a[6]) == 1
	_timer = float(a[7])
	_update_visual()


func _process(delta: float) -> void:
	if remote or not running:
		return
	elapsed += delta
	if phase < PHASES.size():
		_timer -= delta
		if shrinking:
			var t := clampf(1.0 - _timer / _dur, 0.0, 1.0)
			center = _from_center.lerp(next_center, t)
			radius = lerpf(_from_radius, next_radius, t)
			if _timer <= 0.0:
				center = next_center
				radius = next_radius
				_advance()
		else:
			if _timer <= 10.0 and not _warned and next_radius >= 0.0:
				_warned = true
				Events.notify.emit("A zona vai fechar em 10 segundos!", "warn")
				AudioManager.play_sfx("zone_warning", -3.0)
			if _timer <= 0.0 and next_radius >= 0.0:
				_from_center = center
				_from_radius = radius
				shrinking = true
				_dur = float(PHASES[phase]["shrink"])
				_timer = _dur
				Events.zone_changed.emit(center, radius, next_center, next_radius, true)
				Events.notify.emit("A zona está fechando! Vá para a área segura.", "warn")
	_update_visual()
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_apply_damage()


func _update_visual() -> void:
	if _wall == null:
		return
	var r := maxf(radius, 0.3)
	_wall.position = Vector3(center.x, 70.0, center.y)
	_wall.scale = Vector3(r, 1.0, r)
	var showing := next_radius >= 0.0 and not shrinking
	_next_wall.visible = showing
	if showing:
		var nr := maxf(next_radius, 0.3)
		_next_wall.position = Vector3(next_center.x, 70.0, next_center.y)
		_next_wall.scale = Vector3(nr, 1.0, nr)


func _apply_damage() -> void:
	_warn_player_t -= 1.0
	for o in get_tree().get_nodes_in_group("combatants"):
		var c := o as Combatant
		if c == null or not c.alive:
			continue
		if not inside(Vector2(c.global_position.x, c.global_position.z), 0.0):
			c.zone_damage(dps)
			if c.is_player and _warn_player_t <= 0.0:
				_warn_player_t = 5.0
				Events.notify.emit("Você está fora da zona segura! -%d/s" % int(dps), "bad")
