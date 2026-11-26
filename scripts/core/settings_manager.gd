extends Node
## Configurações do jogador (gráficos, controles, áudio, jogabilidade) + mapa de entradas.
## Tudo é salvo localmente via SaveSystem e aplicado imediatamente.

const DEFAULTS := {
	"quality": "auto", "render_scale": 1.0, "shadows": 2, "render_distance": 450.0, "fps_limit": 60,
	"sens_h": 1.0, "sens_v": 1.0, "sens_aim": 0.6, "invert_y": false, "aim_assist": -1,
	"hud_opacity": 0.8, "hud_scale": 1.0, "force_touch": false, "auto_sprint": true, "camera_side": 1,
	"vol_master": 0.9, "vol_music": 0.55, "vol_sfx": 0.9, "vol_ambient": 0.7,
	"show_fps": false, "show_minimap": true,
}

const KEY_ACTIONS := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
	"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_C, "interact": KEY_E, "reload": KEY_R,
	"inventory": KEY_TAB, "pause": KEY_ESCAPE, "weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3,
	"use_bandage": KEY_4, "use_medkit": KEY_5, "big_map": KEY_M, "next_weapon": KEY_Q,
}

const ACTION_LABELS := {
	"move_forward": "Mover para frente", "move_back": "Mover para trás", "move_left": "Mover à esquerda",
	"move_right": "Mover à direita", "jump": "Pular", "sprint": "Correr", "crouch": "Agachar",
	"interact": "Interagir / coletar", "reload": "Recarregar", "inventory": "Inventário",
	"pause": "Pausa / configurações", "weapon_1": "Arma 1", "weapon_2": "Arma 2", "weapon_3": "Arma 3",
	"use_bandage": "Usar bandagem", "use_medkit": "Usar kit médico", "big_map": "Mapa grande",
	"next_weapon": "Trocar arma",
}

## Estado de entrada touch (escrito pela UI touch, lido por jogador e câmera).
var touch_mode := false
var t_move := Vector2.ZERO
var t_look := Vector2.ZERO
var t_fire := false
var t_aim := false
var t_crouch := false
var t_sprint := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()
	_refresh_touch()


func get_s(key: String) -> Variant:
	var s: Dictionary = SaveSystem.data["settings"]
	if s.has(key):
		return s[key]
	return DEFAULTS[key]


func set_s(key: String, value: Variant) -> void:
	SaveSystem.data["settings"][key] = value
	SaveSystem.mark_dirty()
	if key == "force_touch":
		_refresh_touch()
	if key.begins_with("vol_"):
		AudioManager.apply_volumes()
	elif key in ["quality", "render_scale", "shadows", "render_distance", "fps_limit"]:
		QualityManager.apply()
	Events.settings_changed.emit()


func apply_all() -> void:
	_refresh_touch()
	AudioManager.apply_volumes()
	QualityManager.apply()


func reset_defaults() -> void:
	SaveSystem.data["settings"] = {}
	SaveSystem.data["controls"] = {}
	SaveSystem.data["hud_layout"] = {}
	SaveSystem.save_data()
	_register_actions()
	apply_all()
	Events.settings_changed.emit()


func _refresh_touch() -> void:
	var t := false
	if bool(get_s("force_touch")):
		t = true
	elif OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios"):
		t = true
	touch_mode = t


func is_touch() -> bool:
	return touch_mode


## 0 = desativada, 1 = leve, 2 = normal, 3 = forte. Padrão automático: normal no touch, desativada no desktop.
func aim_assist_level() -> int:
	var v: int = int(get_s("aim_assist"))
	if v < 0:
		return 2 if touch_mode else 0
	return clampi(v, 0, 3)


func tap(action: String) -> void:
	Input.action_press(action)
	get_tree().create_timer(0.07).timeout.connect(func(): Input.action_release(action))


func clear_touch_state() -> void:
	t_move = Vector2.ZERO
	t_look = Vector2.ZERO
	t_fire = false
	t_aim = false
	t_crouch = false
	t_sprint = false


# ---- Mapa de entradas -------------------------------------------------------
func _register_actions() -> void:
	var saved: Dictionary = SaveSystem.data["controls"]
	for action in KEY_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		var code: int = int(saved.get(action, KEY_ACTIONS[action]))
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		InputMap.action_add_event(action, ev)
	_add_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("aim", MOUSE_BUTTON_RIGHT)


func _add_mouse_action(action: String, button: int) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func rebind(action: String, keycode: int) -> void:
	SaveSystem.data["controls"][action] = keycode
	SaveSystem.mark_dirty()
	_register_actions()


func key_label(action: String) -> String:
	var code: int = int(SaveSystem.data["controls"].get(action, KEY_ACTIONS[action]))
	return OS.get_keycode_string(code)
