extends Node3D
## Lobby 3D: personagem no centro (animação de descanso), plataforma, iluminação cinematográfica,
## cenário (skyline + eclipse), partículas, câmera com movimento sutil e interface completa:
## perfil, modos de jogo, personagem (personalização ao vivo), inventário/arsenal, configurações e INICIAR PARTIDA.

var cam: Camera3D
var model: CharacterModel
var pivot: Node3D
var ui: CanvasLayer
var root_ui: Control
var panel: Control
var _t := 0.0
var _cam_dist := 4.3
var _cam_goal := 4.3
var _yaw_goal := PI
var _dragging := false
var _app: Dictionary = {}
var _mode_label: Label
var _name_label: Label
var _lvl_label: Label
var _avatar: AvatarIcon
var _swatch_rows := {}
var _opt_rows := {}
var _avatar_pick := 0
var _avatar_icons: Array = []
var _settings_layer: CanvasLayer


func _ready() -> void:
	AudioManager.stop_ambient()
	AudioManager.play_music("music_menu")
	_build_world()
	_build_character()
	_build_ui()
	SceneRouter.hide_loading()


# ------------------------------------------------------------------ mundo 3D
func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
	sky_mat.sky_horizon_color = Color(0.55, 0.22, 0.08)
	sky_mat.ground_horizon_color = Color(0.30, 0.12, 0.06)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.30, 0.42)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.13, 0.07)
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28.0, 38.0, 0.0)
	key.light_color = Color(1.0, 0.82, 0.62)
	key.light_energy = 1.25
	key.shadow_enabled = QualityManager.effective()["shadows"] > 0
	add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-3.0, 2.6, -3.2)
	rim.light_color = Color(0.35, 0.55, 1.0)
	rim.light_energy = 2.6
	rim.omni_range = 9.0
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.6, 1.0, 3.0)
	fill.light_color = Color(1.0, 0.55, 0.25)
	fill.light_energy = 0.9
	fill.omni_range = 8.0
	add_child(fill)
	# chão e plataforma
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.04, 0.04, 0.05)
	gmat.roughness = 0.9
	ground.material_override = gmat
	ground.position = Vector3(0, -0.25, 0)
	add_child(ground)
	var glow := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 1.62
	gm.bottom_radius = 1.62
	gm.height = 0.1
	glow.mesh = gm
	glow.material_override = MaterialLibrary.glow_mat(Color(1.0, 0.5, 0.12), 2.2)
	glow.position = Vector3(0, -0.16, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	var plat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.45
	cm.height = 0.22
	cm.radial_segments = 48
	plat.mesh = cm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.12, 0.13, 0.16)
	pmat.metallic = 0.8
	pmat.roughness = 0.35
	plat.material_override = pmat
	plat.position = Vector3(0, -0.11, 0)
	add_child(plat)
	_build_skyline()
	_build_particles()
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 300.0
	add_child(cam)
	cam.make_current()


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bk := MeshKit.new(false)
	var wk := MeshKit.new(false)
	for i in 80:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 38.0)
		var w := rng.randf_range(2.0, 5.5)
		var h := rng.randf_range(4.0, 24.0)
		var c := Vector3(cos(a) * r, h * 0.5 - 0.3, sin(a) * r - 8.0)
		if c.z > -3.0 and absf(c.x) < 9.0:
			continue
		var tint := rng.randf_range(0.0, 0.05)
		bk.box(c, Vector3(w, h, w), Color(0.05 + tint, 0.06 + tint, 0.09 + tint))
		var to_c := Vector3(-c.x, 0, -c.z).normalized()
		var side := Vector3(-to_c.z, 0, to_c.x)
		for j in rng.randi_range(3, 8):
			var wy := rng.randf_range(-h * 0.45, h * 0.45)
			var off := side * rng.randf_range(-w * 0.35, w * 0.35)
			wk.box(c + to_c * (w * 0.5) + off + Vector3(0, wy, 0), Vector3(0.45, 0.35, 0.45), Color.WHITE)
	var m1 := ArrayMesh.new()
	bk.commit(m1, MaterialLibrary.vertex_color_mat(0.95, 0.0))
	var mi1 := MeshInstance3D.new()
	mi1.mesh = m1
	add_child(mi1)
	var m2 := ArrayMesh.new()
	wk.commit(m2, MaterialLibrary.glow_mat(Color(1.0, 0.72, 0.35), 2.0))
	var mi2 := MeshInstance3D.new()
	mi2.mesh = m2
	mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi2)
	# eclipse ao fundo: coroa + disco escuro
	var corona := MeshInstance3D.new()
	var s1 := SphereMesh.new()
	s1.radius = 8.2
	s1.height = 16.4
	corona.mesh = s1
	corona.material_override = MaterialLibrary.glow_mat(Color(1.0, 0.55, 0.15), 2.5, 0.85)
	corona.position = Vector3(-10.0, 13.0, -44.0)
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(corona)
	var disc := MeshInstance3D.new()
	var s2 := SphereMesh.new()
	s2.radius = 7.2
	s2.height = 14.4
	disc.mesh = s2
	disc.material_override = MaterialLibrary.glow_mat(Color(0.005, 0.005, 0.01), 0.0, 1.0)
	disc.position = Vector3(-10.0, 13.0, -42.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


func _build_particles() -> void:
	var p := CPUParticles3D.new()
	p.amount = maxi(int(60.0 * QualityManager.particles()), 8)
	p.lifetime = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(3.5, 0.1, 3.5)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.55
	p.gravity = Vector3.ZERO
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	sm.radial_segments = 4
	sm.rings = 2
	p.mesh = sm
	p.material_override = MaterialLibrary.glow_mat(Color(1.0, 0.65, 0.25), 2.5, 0.8)
	p.position = Vector3(0, 0.1, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


func _build_character() -> void:
	pivot = Node3D.new()
	pivot.rotation.y = PI
	add_child(pivot)
	model = CharacterModel.new()
	pivot.add_child(model)
	model.setup(SaveSystem.customization())
	model.animator.lobby = true


# ------------------------------------------------------------------ processamento
func _process(delta: float) -> void:
	_t += delta
	if model != null and model.animator != null:
		model.animator.update(delta)
	pivot.rotation.y = lerp_angle(pivot.rotation.y, _yaw_goal, 1.0 - exp(-9.0 * delta))
	_cam_dist = lerpf(_cam_dist, _cam_goal, 1.0 - exp(-7.0 * delta))
	var close := clampf((4.3 - _cam_dist) / 2.5, 0.0, 1.0)
	var sway := Vector3(sin(_t * 0.30) * 0.16, sin(_t * 0.45) * 0.04, sin(_t * 0.2) * 0.06)
	cam.position = Vector3(0.0, 1.2 + 0.25 * close, _cam_dist) + sway
	cam.look_at(Vector3(0.0, 0.98 + 0.40 * close, 0.0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_goal = clampf(_cam_goal - 0.3, 1.6, 6.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_goal = clampf(_cam_goal + 0.3, 1.6, 6.0)
	elif event is InputEventMouseMotion and _dragging:
		_yaw_goal -= (event as InputEventMouseMotion).relative.x * 0.012


# ------------------------------------------------------------------ interface
func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	root_ui = Control.new()
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root_ui)
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ---- barra superior
	var top := UIKit.panel(Color(0.04, 0.05, 0.08, 0.78), 14, 10.0)
	var th := UIKit.hbox(12)
	_avatar = AvatarIcon.new()
	_avatar.avatar_id = int(SaveSystem.profile().get("avatar", 0))
	_avatar.clickable = false
	_avatar.custom_minimum_size = Vector2(64, 64)
	th.add_child(_avatar)
	var tv := UIKit.vbox(2)
	_name_label = UIKit.label(str(SaveSystem.profile().get("name", "Jogador")), 24, UIKit.TEXT)
	_lvl_label = UIKit.label("", 16, UIKit.ACCENT)
	tv.add_child(_name_label)
	tv.add_child(_lvl_label)
	th.add_child(tv)
	top.add_child(th)
	root_ui.add_child(top)
	top.position = Vector2(14, 14)
	var right := UIKit.panel(Color(0.04, 0.05, 0.08, 0.78), 14, 10.0)
	var rh := UIKit.hbox(10)
	_mode_label = UIKit.label("", 18, UIKit.TEXT)
	rh.add_child(_mode_label)
	rh.add_child(UIKit.button("CONFIGURAÇÕES", _open_settings, Vector2(0, 42), false, 15))
	rh.add_child(UIKit.button("TROCAR PERFIL", _switch_profile, Vector2(0, 42), false, 15))
	right.add_child(rh)
	root_ui.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# ---- ângulos / zoom (lado esquerdo do personagem)
	var side := UIKit.hbox(8)
	side.add_child(UIKit.button("<", _rotate.bind(0.8), Vector2(54, 48)))
	side.add_child(UIKit.button(">", _rotate.bind(-0.8), Vector2(54, 48)))
	side.add_child(UIKit.button("+", _zoom.bind(-0.5), Vector2(54, 48)))
	side.add_child(UIKit.button("-", _zoom.bind(0.5), Vector2(54, 48)))
	root_ui.add_child(side)
	side.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 0)
	side.grow_horizontal = Control.GROW_DIRECTION_BOTH
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.position.y -= 118
	# ---- barra inferior
	var bottom := UIKit.vbox(8)
	bottom.add_child(UIKit.button("INICIAR PARTIDA", _start, Vector2(420, 66), true, 28))
	var br := UIKit.hbox(8)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_child(UIKit.button("ONLINE", _open_online, Vector2(150, 44), true, 15))
	br.add_child(UIKit.button("MODOS DE JOGO", _open_modes, Vector2(150, 44), false, 15))
	br.add_child(UIKit.button("PERSONAGEM", _open_character, Vector2(150, 44), false, 15))
	br.add_child(UIKit.button("INVENTÁRIO", _open_inventory, Vector2(150, 44), false, 15))
	br.add_child(UIKit.button("CONFIGURAÇÕES", _open_settings, Vector2(150, 44), false, 15))
	bottom.add_child(br)
	root_ui.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_refresh_profile()


func _refresh_profile() -> void:
	var pr := SaveSystem.profile()
	_name_label.text = str(pr.get("name", "Jogador"))
	_lvl_label.text = "Nível %d  •  %d XP" % [SaveSystem.level(), int(pr.get("xp", 0))]
	_avatar.avatar_id = int(pr.get("avatar", 0))
	var prefs := SaveSystem.prefs()
	var mode := str(prefs.get("mode", "classic"))
	var names := {"free": "Livre", "precision": "Precisão", "bots": "Contra bots"}
	_mode_label.text = "MODO: CLÁSSICO" if mode == "classic" else "MODO: TREINO — %s" % names.get(str(prefs.get("training", "free")), "Livre")


func _rotate(d: float) -> void:
	_yaw_goal += d


func _zoom(d: float) -> void:
	_cam_goal = clampf(_cam_goal + d, 1.6, 6.0)


func _switch_profile() -> void:
	SceneRouter.go_login()


func _start() -> void:
	AudioManager.play_sfx("ui_confirm")
	SceneRouter.start_mode(str(SaveSystem.prefs().get("mode", "classic")))


func _open_settings() -> void:
	if _settings_layer != null:
		return
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 40
	add_child(_settings_layer)
	var sm := SettingsMenu.new()
	_settings_layer.add_child(sm)
	sm.closed.connect(_close_settings)


func _close_settings() -> void:
	if _settings_layer != null:
		_settings_layer.queue_free()
		_settings_layer = null


# ------------------------------------------------------------------ painel lateral
func _close_panel() -> void:
	if panel != null:
		panel.queue_free()
		panel = null
	_cam_goal = 4.3
	_swatch_rows.clear()
	_opt_rows.clear()


func _new_panel(title: String, width: float = 440.0) -> VBoxContainer:
	_close_panel()
	var p := UIKit.panel(Color(0.04, 0.05, 0.08, 0.90), 18, 16.0)
	p.custom_minimum_size = Vector2(width, 0)
	var v := UIKit.vbox(8)
	var head := UIKit.hbox(8)
	head.add_child(UIKit.label(title, 24, UIKit.ACCENT))
	head.add_child(UIKit.spacer(0.0, true))
	p.add_child(v)
	v.add_child(head)
	root_ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel = p
	return v


func _open_online() -> void:
	_close_panel()
	var p := OnlinePanel.new()
	root_ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.closed.connect(_close_panel)
	panel = p


# ---- modos de jogo ------------------------------------------------
func _open_modes() -> void:
	var v := _new_panel("MODOS DE JOGO")
	var prefs := SaveSystem.prefs()
	var cur := str(prefs.get("mode", "classic"))
	v.add_child(UIKit.label("CLÁSSICO — Mapa 1: Três Cidades\n1 jogador + bots, loot, zona segura que fecha.", 16, UIKit.MUTED))
	v.add_child(UIKit.button("SELECIONAR CLÁSSICO" if cur != "classic" else "CLÁSSICO (SELECIONADO)", _set_mode.bind("classic"), Vector2(0, 46), cur == "classic"))
	v.add_child(UIKit.slider_row("Bots na partida", 1.0, 15.0, 1.0, float(prefs.get("bots", 15)), _set_bots, "%d"))
	var diffs := ["mixed", "beginner", "intermediate", "advanced"]
	v.add_child(UIKit.option_row("Dificuldade dos bots", ["Mista", "Iniciante", "Intermediário", "Avançado"], maxi(diffs.find(str(prefs.get("difficulty", "mixed"))), 0), _set_diff))
	v.add_child(UIKit.spacer(8.0))
	v.add_child(UIKit.label("TREINAMENTO DE MIRA\nCampo com alvos físicos, precisão e bots.", 16, UIKit.MUTED))
	var tr := ["free", "precision", "bots"]
	v.add_child(UIKit.option_row("Tipo de treino", ["Livre", "Precisão", "Contra bots"], maxi(tr.find(str(prefs.get("training", "free"))), 0), _set_training))
	v.add_child(UIKit.button("SELECIONAR TREINAMENTO" if cur != "training" else "TREINAMENTO (SELECIONADO)", _set_mode.bind("training"), Vector2(0, 46), cur == "training"))
	v.add_child(UIKit.button("FECHAR", _close_panel, Vector2(0, 44)))


func _set_mode(mode: String) -> void:
	SaveSystem.prefs()["mode"] = mode
	SaveSystem.mark_dirty()
	_refresh_profile()
	_open_modes()


func _set_bots(x: float) -> void:
	SaveSystem.prefs()["bots"] = int(x)
	SaveSystem.mark_dirty()


func _set_diff(i: int) -> void:
	SaveSystem.prefs()["difficulty"] = ["mixed", "beginner", "intermediate", "advanced"][i]
	SaveSystem.mark_dirty()


func _set_training(i: int) -> void:
	SaveSystem.prefs()["training"] = ["free", "precision", "bots"][i]
	SaveSystem.mark_dirty()
	_refresh_profile()


# ---- personagem / personalização ------------------------------------
func _open_character() -> void:
	_app = SaveSystem.customization().duplicate()
	_avatar_pick = int(SaveSystem.profile().get("avatar", 0))
	var v := _new_panel("PERSONAGEM", 470.0)
	_cam_goal = 2.7
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(440, 430)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := UIKit.vbox(6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	v.add_child(sc)
	box.add_child(UIKit.label("Avatar de perfil", 15, UIKit.MUTED))
	var ar := HFlowContainer.new()
	_avatar_icons.clear()
	for i in 6:
		var a := AvatarIcon.new()
		a.avatar_id = i
		a.selected = i == _avatar_pick
		a.custom_minimum_size = Vector2(56, 56)
		a.picked.connect(_pick_avatar)
		ar.add_child(a)
		_avatar_icons.append(a)
	box.add_child(ar)
	_opts(box, "Modelo base", "body", _body_names())
	_swatches(box, "Tom de pele", "skin", CosmeticsDB.SKIN_TONES)
	_opts(box, "Rosto", "face", _names_of(CosmeticsDB.FACES, "Rosto"))
	_opts(box, "Penteado", "hair", CosmeticsDB.HAIR_STYLES)
	_swatches(box, "Cor do cabelo", "hair_color", CosmeticsDB.HAIR_COLORS)
	_swatches(box, "Cor dos olhos", "eye_color", CosmeticsDB.EYE_COLORS)
	_opts(box, "Camiseta / jaqueta", "top", _names_of(CosmeticsDB.TOPS, "Peça"))
	_swatches(box, "Cor da peça", "top_color", CosmeticsDB.TOP_COLORS)
	_opts(box, "Calça", "bottom", _names_of(CosmeticsDB.BOTTOMS, "Calça"))
	_swatches(box, "Cor da calça", "bottom_color", CosmeticsDB.BOTTOM_COLORS)
	_opts(box, "Calçado", "shoes", _names_of(CosmeticsDB.SHOES, "Calçado"))
	_swatches(box, "Cor do calçado", "shoe_color", CosmeticsDB.SHOE_COLORS)
	_opts(box, "Acessório de cabeça", "head", _names_of(CosmeticsDB.HEADWEAR, "Acessório"))
	_swatches(box, "Cor do acessório", "head_color", CosmeticsDB.HEAD_COLORS)
	var row := UIKit.hbox(8)
	row.add_child(UIKit.button("REMOVER ACESSÓRIO", _remove_head, Vector2(0, 42), false, 14))
	row.add_child(UIKit.button("ALEATÓRIO", _random_look, Vector2(0, 42), false, 14))
	v.add_child(row)
	var row2 := UIKit.hbox(8)
	row2.add_child(UIKit.button("CANCELAR", _cancel_character, Vector2(0, 48)))
	var sv := UIKit.button("SALVAR", _save_character, Vector2(0, 48), true)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(sv)
	v.add_child(row2)


func _body_names() -> Array:
	var out: Array = []
	for b in CosmeticsDB.BODIES:
		out.append("%s (%s)" % [str(b["name"]), str(b.get("desc", ""))])
	return out


func _names_of(arr: Array, fallback: String) -> Array:
	var out: Array = []
	for i in arr.size():
		out.append(str(arr[i].get("name", "%s %d" % [fallback, i + 1])) if arr[i] is Dictionary else str(arr[i]))
	return out


func _opts(box: VBoxContainer, title: String, key: String, names: Array) -> void:
	box.add_child(UIKit.label(title, 15, UIKit.MUTED))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 6)
	fl.add_theme_constant_override("v_separation", 6)
	var btns: Array = []
	for i in names.size():
		var b := UIKit.button(str(names[i]), _set_appearance.bind(key, i), Vector2(0, 36), false, 14)
		fl.add_child(b)
		btns.append(b)
	_opt_rows[key] = btns
	box.add_child(fl)
	_mark_opts(key)


func _swatches(box: VBoxContainer, title: String, key: String, colors: Array) -> void:
	box.add_child(UIKit.label(title, 15, UIKit.MUTED))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 6)
	var btns: Array = []
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(38, 38)
		var c: Color = colors[i]
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, UIKit.style(c, 19, Color(1, 1, 1, 0.25), 2, 0))
		b.pressed.connect(_set_appearance.bind(key, i))
		fl.add_child(b)
		btns.append(b)
	_swatch_rows[key] = btns
	box.add_child(fl)
	_mark_swatches(key, colors)


func _mark_opts(key: String) -> void:
	var btns: Array = _opt_rows.get(key, [])
	for i in btns.size():
		var on := int(_app.get(key, 0)) == i
		(btns[i] as Button).add_theme_stylebox_override("normal", UIKit.style(UIKit.ACCENT_DARK if on else Color(0.14, 0.16, 0.22, 0.95), 10, UIKit.ACCENT if on else Color(1, 1, 1, 0.1), 2 if on else 1, 8))


func _mark_swatches(key: String, colors: Array) -> void:
	var btns: Array = _swatch_rows.get(key, [])
	for i in btns.size():
		var on := int(_app.get(key, 0)) == i
		var c: Color = colors[i]
		(btns[i] as Button).add_theme_stylebox_override("normal", UIKit.style(c, 19, UIKit.ACCENT if on else Color(1, 1, 1, 0.25), 4 if on else 2, 0))


const COLOR_KEYS := ["skin", "hair_color", "eye_color", "top_color", "bottom_color", "shoe_color", "head_color"]


func _set_appearance(key: String, idx: int) -> void:
	_app[key] = idx
	model.set_appearance(_app)
	if COLOR_KEYS.has(key):
		_mark_swatches(key, CosmeticsDB.palette(key))
	else:
		_mark_opts(key)
	AudioManager.play_sfx("ui_click", -6.0)


func _pick_avatar(id: int) -> void:
	_avatar_pick = id
	for c in _avatar_icons:
		if is_instance_valid(c):
			(c as AvatarIcon).selected = (c as AvatarIcon).avatar_id == id


func _remove_head() -> void:
	_set_appearance("head", 0)


func _random_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_app = CosmeticsDB.random_appearance(rng)
	model.set_appearance(_app)
	for k in _opt_rows:
		_mark_opts(k)
	for k in _swatch_rows:
		_mark_swatches(k, CosmeticsDB.palette(k))


func _save_character() -> void:
	SaveSystem.set_customization(_app)
	var pr := SaveSystem.profile()
	SaveSystem.set_profile(str(pr.get("name", "Jogador")), _avatar_pick, bool(pr.get("guest", false)))
	AudioManager.play_sfx("ui_confirm")
	_refresh_profile()
	_close_panel()


func _cancel_character() -> void:
	model.set_appearance(SaveSystem.customization())
	_close_panel()


# ---- inventário / arsenal -----------------------------------------
func _open_inventory() -> void:
	var v := _new_panel("INVENTÁRIO E ARSENAL", 500.0)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(470, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := UIKit.vbox(5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	v.add_child(sc)
	var st := SaveSystem.stats()
	box.add_child(UIKit.label("ESTATÍSTICAS OFFLINE", 15, UIKit.ACCENT))
	var t := int(float(st.get("play_time", 0.0)))
	var lines := ["Partidas: %d   Vitórias: %d   Abates: %d" % [int(st["matches"]), int(st["wins"]), int(st["kills"])],
		"Melhor colocação: %s   Dano total: %d" % [("#%d" % int(st["best_place"])) if int(st["best_place"]) > 0 else "—", int(float(st["damage"]))],
		"Tempo jogado: %d min   Treino: %d tiros / %d acertos" % [t / 60, int(st["train_shots"]), int(st["train_hits"])]]
	for l in lines:
		box.add_child(UIKit.label(l, 15, UIKit.TEXT))
	box.add_child(UIKit.label("ARSENAL (equipamentos virtuais)", 15, UIKit.ACCENT))
	for wid in WeaponDB.ids():
		var w := WeaponDB.get_def(wid)
		var txt := "%s — dano %d, %d tiros/s, carregador %d, alcance %d m%s" % [str(w["name"]), int(w["dmg"]), int(round(float(w["rate"]))), int(w["mag"]), int(w["range"]),
			(" (x%d)" % int(w["pellets"])) if int(w["pellets"]) > 1 else ""]
		var l2 := UIKit.label(txt, 14, ItemDB.rarity_color(str(wid)))
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l2.custom_minimum_size = Vector2(440, 0)
		box.add_child(l2)
	box.add_child(UIKit.label("PROTEÇÕES E ITENS", 15, UIKit.ACCENT))
	for id in ItemDB.ITEMS:
		var d := ItemDB.get_def(id)
		if str(d["cat"]) in ["armor", "heal", "pack", "acc"]:
			box.add_child(UIKit.label("• " + str(d["name"]) + "  [" + str(ItemDB.RARITY_NAMES[int(d["rarity"])]) + "]", 14, ItemDB.rarity_color(str(id))))
	v.add_child(UIKit.button("FECHAR", _close_panel, Vector2(0, 44)))
