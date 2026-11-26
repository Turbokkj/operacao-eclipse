class_name TouchControls
extends Control
## Controles touchscreen completos com múltiplos toques: joystick virtual flutuante (esquerda), câmera por
## arrasto (direita), botões (atirar, mirar, pular, agachar, recarregar, interagir, trocar arma, curar,
## correr, pausa, mochila). Posição/tamanho de cada botão são editáveis (modo de edição do HUD) e salvos.

signal changed

const DEFAULTS := {
	"fire": {"label": "ATIRAR", "x": 0.88, "y": 0.70, "r": 62.0},
	"aim": {"label": "MIRAR", "x": 0.76, "y": 0.55, "r": 40.0},
	"jump": {"label": "PULAR", "x": 0.95, "y": 0.45, "r": 38.0},
	"crouch": {"label": "AGACHAR", "x": 0.82, "y": 0.87, "r": 34.0},
	"reload": {"label": "RECARR.", "x": 0.68, "y": 0.80, "r": 34.0},
	"interact": {"label": "PEGAR", "x": 0.69, "y": 0.38, "r": 40.0},
	"switch": {"label": "TROCAR", "x": 0.57, "y": 0.90, "r": 28.0},
	"heal": {"label": "CURAR", "x": 0.57, "y": 0.72, "r": 28.0},
	"sprint": {"label": "CORRER", "x": 0.33, "y": 0.52, "r": 30.0},
	"inv": {"label": "MOCHILA", "x": 0.89, "y": 0.08, "r": 24.0},
	"pause": {"label": "II", "x": 0.96, "y": 0.08, "r": 22.0},
}

var editing := false
var selected := ""
var prompt_active := false
var _touches := {}
var _pressed := {}
var _stick_center := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_idx := -1
var _drag_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(queue_redraw)


func _layout(id: String) -> Dictionary:
	var d: Dictionary = DEFAULTS[id]
	var saved: Dictionary = SaveSystem.data["hud_layout"].get(id, {})
	return {"x": float(saved.get("x", d["x"])), "y": float(saved.get("y", d["y"])), "s": float(saved.get("s", 1.0))}


func _center_of(id: String) -> Vector2:
	var l := _layout(id)
	var vs := get_viewport_rect().size
	return Vector2(l["x"] * vs.x, l["y"] * vs.y)


func _radius_of(id: String) -> float:
	return float(DEFAULTS[id]["r"]) * _layout(id)["s"] * float(GameSettings.get_s("hud_scale"))


func _button_at(p: Vector2) -> String:
	var best := ""
	var bd := 1e9
	for id in DEFAULTS:
		var d := p.distance_to(_center_of(id))
		if d <= _radius_of(id) * 1.15 and d < bd:
			bd = d
			best = id
	return best


func reset_layout() -> void:
	SaveSystem.data["hud_layout"] = {}
	SaveSystem.mark_dirty()
	queue_redraw()


func resize_selected(delta: float) -> void:
	if selected == "":
		return
	var l: Dictionary = SaveSystem.data["hud_layout"].get(selected, {})
	l["s"] = clampf(float(l.get("s", 1.0)) + delta, 0.6, 1.8)
	l["x"] = _layout(selected)["x"]
	l["y"] = _layout(selected)["y"]
	SaveSystem.data["hud_layout"][selected] = l
	SaveSystem.mark_dirty()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if editing:
		_edit_input(event)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position, d.relative)


func _edit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_drag_id = _button_at(mb.position)
			if _drag_id != "":
				selected = _drag_id
				changed.emit()
				queue_redraw()
		else:
			_drag_id = ""
	elif event is InputEventMouseMotion and _drag_id != "":
		var vs := get_viewport_rect().size
		var l: Dictionary = SaveSystem.data["hud_layout"].get(_drag_id, {})
		var p := (event as InputEventMouseMotion).position
		l["x"] = clampf(p.x / vs.x, 0.03, 0.97)
		l["y"] = clampf(p.y / vs.y, 0.05, 0.95)
		l["s"] = _layout(_drag_id)["s"]
		SaveSystem.data["hud_layout"][_drag_id] = l
		SaveSystem.mark_dirty()
		queue_redraw()


func _touch_down(idx: int, pos: Vector2) -> void:
	var vs := get_viewport_rect().size
	var id := _button_at(pos)
	if id != "":
		_touches[idx] = {"kind": "btn", "id": id}
		_press(id)
		get_viewport().set_input_as_handled()
		return
	if pos.x < vs.x * 0.45 and pos.y > vs.y * 0.25 and _stick_idx == -1:
		_stick_idx = idx
		_stick_center = pos
		_stick_pos = pos
		_touches[idx] = {"kind": "stick"}
		get_viewport().set_input_as_handled()
	elif pos.x >= vs.x * 0.45:
		_touches[idx] = {"kind": "look"}
		get_viewport().set_input_as_handled()
	queue_redraw()


func _touch_move(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _touches.has(idx):
		return
	var k: String = _touches[idx]["kind"]
	if k == "stick":
		var maxr := 70.0 * float(GameSettings.get_s("hud_scale"))
		var off := (pos - _stick_center).limit_length(maxr)
		_stick_pos = _stick_center + off
		var v := off / maxr
		GameSettings.t_move = v if v.length() > 0.12 else Vector2.ZERO
		queue_redraw()
	elif k == "look":
		GameSettings.t_look += rel
	elif k == "btn" and str(_touches[idx]["id"]) == "fire":
		GameSettings.t_look += rel


func _touch_up(idx: int) -> void:
	if not _touches.has(idx):
		return
	var info: Dictionary = _touches[idx]
	_touches.erase(idx)
	match str(info["kind"]):
		"stick":
			_stick_idx = -1
			GameSettings.t_move = Vector2.ZERO
		"btn":
			_release(str(info["id"]))
	queue_redraw()


func _press(id: String) -> void:
	_pressed[id] = true
	match id:
		"fire":
			GameSettings.t_fire = true
		"aim":
			GameSettings.t_aim = not GameSettings.t_aim
		"crouch":
			GameSettings.t_crouch = not GameSettings.t_crouch
		"sprint":
			GameSettings.t_sprint = not GameSettings.t_sprint
		"jump":
			Input.action_press("jump")
		"reload":
			GameSettings.tap("reload")
		"interact":
			GameSettings.tap("interact")
		"switch":
			GameSettings.tap("next_weapon")
		"heal":
			GameSettings.tap("use_bandage")
		"inv":
			get_tree().call_group("hud", "toggle_inventory")
		"pause":
			get_tree().call_group("hud", "open_pause")
	queue_redraw()


func _release(id: String) -> void:
	_pressed.erase(id)
	if id == "fire":
		GameSettings.t_fire = false
	elif id == "jump":
		Input.action_release("jump")
	queue_redraw()


func _process(_delta: float) -> void:
	if editing or not _touches.is_empty():
		queue_redraw()


func _exit_tree() -> void:
	GameSettings.clear_touch_state()
	Input.action_release("jump")


func _draw() -> void:
	var op := float(GameSettings.get_s("hud_opacity"))
	var font := ThemeDB.fallback_font
	if editing:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.45))
	for id in DEFAULTS:
		var c := _center_of(id)
		var r := _radius_of(id)
		var on := _pressed.has(id) or (id == "aim" and GameSettings.t_aim) or (id == "crouch" and GameSettings.t_crouch) \
			or (id == "sprint" and GameSettings.t_sprint)
		var col := Color(1.0, 0.55, 0.14, op * (1.0 if on else 0.6)) if id == "fire" else Color(0.9, 0.93, 1.0, op * (0.85 if on else 0.35))
		if id == "interact" and not prompt_active and not editing:
			col.a *= 0.35
		draw_circle(c, r, Color(0.05, 0.07, 0.10, op * 0.55))
		draw_arc(c, r, 0.0, TAU, 40, col, 3.0 if not (editing and selected == id) else 5.0)
		if on:
			draw_circle(c, r * 0.86, Color(col.r, col.g, col.b, op * 0.35))
		var fs := int(clampf(r * 0.30, 9.0, 18.0))
		draw_string(font, c + Vector2(-r, fs * 0.35), str(DEFAULTS[id]["label"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, clampf(op + 0.2, 0.0, 1.0)))
	if _stick_idx != -1:
		draw_circle(_stick_center, 70.0 * float(GameSettings.get_s("hud_scale")), Color(1, 1, 1, op * 0.18))
		draw_arc(_stick_center, 70.0 * float(GameSettings.get_s("hud_scale")), 0.0, TAU, 40, Color(1, 1, 1, op * 0.5), 2.0)
		draw_circle(_stick_pos, 30.0 * float(GameSettings.get_s("hud_scale")), Color(1.0, 0.7, 0.3, op * 0.8))
	elif editing:
		var vs := get_viewport_rect().size
		draw_circle(Vector2(vs.x * 0.16, vs.y * 0.72), 70.0, Color(1, 1, 1, 0.12))
		draw_string(font, Vector2(vs.x * 0.16 - 60.0, vs.y * 0.72 + 5.0), "JOYSTICK", HORIZONTAL_ALIGNMENT_CENTER, 120.0, 14, Color(1, 1, 1, 0.7))
