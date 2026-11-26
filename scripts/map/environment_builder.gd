class_name EnvironmentBuilder
extends Node3D
## Ambientação diurna: céu procedural, luz direcional com sombras controladas, luz ambiente, névoa em
## profundidade e nuvens simples (malhas achatadas) que derivam lentamente. Compatível com WebGL 2.0.

var sun: DirectionalLight3D
var env: Environment
var clouds: Array = []
var _t := 0.0


func build(extent: float) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.80)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.92)
	sky_mat.ground_horizon_color = Color(0.62, 0.68, 0.72)
	sky_mat.ground_bottom_color = Color(0.30, 0.34, 0.36)
	sky_mat.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.82, 0.92)
	env.fog_density = 0.0011
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	_clouds(extent)


func _clouds(extent: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var mat := MaterialLibrary.glow_mat(Color(1, 1, 1), 0.9, 0.85)
	for i in 14:
		var cl := Node3D.new()
		var base := Vector3(rng.randf_range(-extent * 1.3, extent * 1.3), rng.randf_range(170.0, 240.0), rng.randf_range(-extent * 1.3, extent * 1.3))
		cl.position = base
		for j in rng.randi_range(3, 5):
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radial_segments = 8
			sm.rings = 4
			sm.radius = 1.0
			sm.height = 2.0
			mi.mesh = sm
			mi.material_override = mat
			mi.scale = Vector3(rng.randf_range(30.0, 55.0), rng.randf_range(7.0, 11.0), rng.randf_range(20.0, 38.0))
			mi.position = Vector3(rng.randf_range(-45.0, 45.0), rng.randf_range(-3.0, 4.0), rng.randf_range(-25.0, 25.0))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cl.add_child(mi)
		add_child(cl)
		clouds.append(cl)


func _process(delta: float) -> void:
	_t += delta
	for c in clouds:
		c.position.x += delta * 2.5
		if c.position.x > 700.0:
			c.position.x = -700.0
