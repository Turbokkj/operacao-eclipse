class_name MaterialLibrary
extends RefCounted
## Materiais PBR otimizados (StandardMaterial3D) com texturas albedo geradas por tools/gen_textures.py.
## As texturas são carregadas em tempo de execução a partir de arquivos .bin (PNG) — sem depender do
## pipeline de importação do editor — e recebem mipmaps. Se um arquivo faltar, usa cor sólida.

const TEX_DIR := "res://assets/textures/"
const DEFS := {
	"plaster": {"tex": "plaster", "rough": 0.92, "metal": 0.0},
	"brick": {"tex": "brick", "rough": 0.88, "metal": 0.0},
	"concrete": {"tex": "concrete", "rough": 0.95, "metal": 0.0},
	"roof": {"tex": "roof", "rough": 0.80, "metal": 0.0},
	"wood": {"tex": "wood", "rough": 0.78, "metal": 0.0},
	"tile": {"tex": "tile", "rough": 0.45, "metal": 0.0},
	"metal": {"tex": "metal", "rough": 0.55, "metal": 0.65},
	"asphalt": {"tex": "asphalt", "rough": 0.93, "metal": 0.0},
	"road": {"tex": "road", "rough": 0.90, "metal": 0.0},
	"plain": {"tex": "", "rough": 0.80, "metal": 0.0},
}

static var _tex_cache := {}
static var _mat_cache := {}


static func get_texture(tname: String) -> Texture2D:
	if tname == "":
		return null
	if _tex_cache.has(tname):
		var cached: Variant = _tex_cache[tname]
		if cached != null and is_instance_valid(cached):
			return cached
	var path := TEX_DIR + tname + ".bin"
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var bytes := f.get_buffer(f.get_length())
			f.close()
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	_tex_cache[tname] = tex
	return tex


## Material com textura (tintável por cor de vértice).
static func get_mat(key: String) -> StandardMaterial3D:
	if _mat_cache.has(key) and is_instance_valid(_mat_cache[key]):
		return _mat_cache[key]
	var d: Dictionary = DEFS.get(key, DEFS["plain"])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = float(d["rough"])
	m.metallic = float(d["metal"])
	m.metallic_specular = 0.35
	var t := get_texture(str(d["tex"]))
	if t != null:
		m.albedo_texture = t
		m.binture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_mat_cache[key] = m
	return m


## Cor pura por vértice (personagens, armas, itens).
static func vertex_color_mat(rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "vc_%.2f_%.2f" % [rough, metal]
	if _mat_cache.has(key) and is_instance_valid(_mat_cache[key]):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


static func glow_mat(col: Color, energy: float = 2.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Folhagem com balanço de vento barato (vertex shader). A intensidade cai a zero no perfil BAIXO.
static func foliage_mat() -> ShaderMaterial:
	if _mat_cache.has("foliage") and is_instance_valid(_mat_cache["foliage"]):
		return _mat_cache["foliage"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float sway : hint_range(0.0, 1.0) = 0.12;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y * 0.18, 0.0, 1.0);
	VERTEX.x += sin(TIME * 1.6 + wp.x * 0.35 + wp.z * 0.2) * sway * h;
	VERTEX.z += cos(TIME * 1.3 + wp.z * 0.3) * sway * 0.6 * h;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sway", 0.12 if QualityManager.sway() else 0.0)
	_mat_cache["foliage"] = m
	return m


## Terreno com 3 texturas (grama, pavimento, terra) misturadas por máscaras em UV.
static func terrain_mat() -> ShaderMaterial:
	if _mat_cache.has("terrain") and is_instance_valid(_mat_cache["terrain"]):
		return _mat_cache["terrain"]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D paved_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_tex : source_color, repeat_enable, filter_linear_mipmap;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wpos.xz / 5.0;
	vec3 g = texture(grass_tex, uv).rgb;
	vec3 p = texture(paved_tex, uv * 0.8).rgb;
	vec3 d = texture(dirt_tex, uv * 0.9).rgb;
	vec3 base = mix(g, p, UV.x);
	base = mix(base, d, UV.y);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var gt := get_texture("grass")
	var pt := get_texture("concrete")
	var dt := get_texture("dirt")
	if gt != null:
		m.set_shader_parameter("grass_tex", gt)
	if pt != null:
		m.set_shader_parameter("paved_tex", pt)
	if dt != null:
		m.set_shader_parameter("dirt_tex", dt)
	_mat_cache["terrain"] = m
	return m


static func zone_mat(col: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.25, 0.55, 1.0, 0.35);
void fragment() {
	float stripes = 0.5 + 0.5 * sin(UV.x * 360.0 + TIME * 1.5);
	float band = 0.55 + 0.45 * sin(UV.y * 40.0 - TIME * 2.0);
	ALBEDO = tint.rgb * (0.75 + 0.25 * stripes);
	ALPHA = tint.a * (0.45 + 0.55 * band * stripes);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", col)
	return m
