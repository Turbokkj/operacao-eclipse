extends Node
## Perfis gráficos (BAIXO / MÉDIO / ALTO / AUTOMÁTICO / personalizado).
## Aplica escala 3D interna, sombras, distância de renderização e limite de FPS em tempo real.

const PROFILES := {
	"low": {"render_scale": 0.6, "shadows": 0, "render_distance": 240.0, "vegetation": 0.35,
		"msaa": 0, "sway": false, "particles": 0.4, "bot_anim_dist": 45.0},
	"medium": {"render_scale": 0.8, "shadows": 2, "render_distance": 380.0, "vegetation": 0.7,
		"msaa": 0, "sway": true, "particles": 0.7, "bot_anim_dist": 80.0},
	"high": {"render_scale": 1.0, "shadows": 3, "render_distance": 540.0, "vegetation": 1.0,
		"msaa": 2, "sway": true, "particles": 1.0, "bot_anim_dist": 140.0},
}
const SHADOW_SIZES := [1024, 1024, 2048, 4096]
const SHADOW_DIST := [0.0, 50.0, 90.0, 150.0]

var in_match := false
var _auto_level := ""
var _light: DirectionalLight3D
var _cam: Camera3D
var _acc := 0.0
var _low_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _detect_auto() -> String:
	if GameSettings.touch_mode:
		return "low"
	if OS.has_feature("web"):
		var cores: Variant = JavaScriptBridge.eval("navigator.hardwareConcurrency || 4", true)
		if (typeof(cores) == TYPE_FLOAT or typeof(cores) == TYPE_INT) and float(cores) <= 4.0:
			return "low"
		return "medium"
	return "high"


func level_name() -> String:
	var q: String = str(GameSettings.get_s("quality"))
	if q == "auto":
		if _auto_level == "":
			_auto_level = _detect_auto()
		return _auto_level
	return q


func effective() -> Dictionary:
	var q := level_name()
	if PROFILES.has(q):
		return PROFILES[q]
	var rd: float = float(GameSettings.get_s("render_distance"))
	var veg := clampf((rd - 150.0) / 400.0, 0.2, 1.0)
	return {"render_scale": float(GameSettings.get_s("render_scale")), "shadows": int(GameSettings.get_s("shadows")),
		"render_distance": rd, "vegetation": veg, "msaa": 0, "sway": veg > 0.5, "particles": veg,
		"bot_anim_dist": rd * 0.25}


func vegetation() -> float:
	return float(effective()["vegetation"])


func sway() -> bool:
	return bool(effective()["sway"])


func particles() -> float:
	return float(effective()["particles"])


func render_distance() -> float:
	return float(effective()["render_distance"])


func bot_anim_dist() -> float:
	return float(effective()["bot_anim_dist"])


func apply() -> void:
	var p := effective()
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(p["render_scale"]), 0.4, 1.0)
		vp.msaa_3d = Viewport.MSAA_2X if int(p["msaa"]) > 0 else Viewport.MSAA_DISABLED
	var sh: int = clampi(int(p["shadows"]), 0, 3)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[sh], true)
	Engine.max_fps = int(GameSettings.get_s("fps_limit"))
	_apply_world()


func register_world(light: DirectionalLight3D, cam: Camera3D) -> void:
	_light = light
	_cam = cam
	_apply_world()


func unregister_world() -> void:
	_light = null
	_cam = null
	in_match = false


func _apply_world() -> void:
	var p := effective()
	var sh: int = clampi(int(p["shadows"]), 0, 3)
	if _light != null and is_instance_valid(_light):
		_light.shadow_enabled = sh > 0
		_light.directional_shadow_max_distance = SHADOW_DIST[sh]
		_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh <= 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if _cam != null and is_instance_valid(_cam):
		_cam.far = float(p["render_distance"])


## Ajuste automático: se o FPS medido ficar abaixo da meta, reduz o perfil (apenas em AUTOMÁTICO).
func _process(delta: float) -> void:
	if not in_match or str(GameSettings.get_s("quality")) != "auto":
		return
	_acc += delta
	if _acc < 4.0:
		return
	_acc = 0.0
	var fps := Engine.get_frames_per_second()
	var target := 26.0 if GameSettings.touch_mode else 48.0
	if fps < target:
		_low_count += 1
		if _low_count >= 2:
			_low_count = 0
			_downgrade()
	else:
		_low_count = 0


func _downgrade() -> void:
	var cur := level_name()
	if cur == "high":
		_auto_level = "medium"
	elif cur == "medium":
		_auto_level = "low"
	else:
		return
	apply()
	Events.notify.emit("Desempenho baixo: qualidade gráfica reduzida (%s)." % _auto_level.to_upper(), "info")
