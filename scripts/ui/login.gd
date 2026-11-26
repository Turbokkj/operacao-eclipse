extends Control
## Login DEMONSTRATIVO (offline): apelido + avatar, ou convidado. Nenhuma senha/e-mail é solicitado.
## Os dados ficam em user:// (SaveSystem). A arquitetura permite plugar autenticação real depois.

var _name_edit: LineEdit
var _avatars: Array = []
var _selected := 0
var _settings: Node
var _msg: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	AudioManager.play_music("music_menu")
	_selected = int(SaveSystem.profile().get("avatar", 0))
	var bg := LoginBackground.new()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel(Color(0.04, 0.05, 0.08, 0.82), 22, 28.0)
	var v := UIKit.vbox(14)
	var logo := LogoControl.new()
	logo.custom_minimum_size = Vector2(520, 190)
	v.add_child(logo)
	v.add_child(UIKit.label("Bem-vindo, sobrevivente!", 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Digite seu apelido (até 16 letras)"
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 52)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.text = str(SaveSystem.profile().get("name", ""))
	_name_edit.text_submitted.connect(func(_text: String): _enter(false))
	v.add_child(_name_edit)
	v.add_child(UIKit.label("Escolha seu avatar", 18, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 6:
		var a := AvatarIcon.new()
		a.avatar_id = i
		a.selected = i == _selected
		a.picked.connect(_pick)
		row.add_child(a)
		_avatars.append(a)
	v.add_child(row)
	_msg = UIKit.label("", 16, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_msg)
	v.add_child(UIKit.button("ENTRAR", _on_enter, Vector2(0, 58), true, 22))
	v.add_child(UIKit.button("JOGAR COMO CONVIDADO", _on_guest, Vector2(0, 52)))
	v.add_child(UIKit.button("CONFIGURAÇÕES", _open_settings, Vector2(0, 44), false, 16))
	v.add_child(UIKit.label("Login de demonstração: nenhum dado pessoal é coletado.", 13, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	p.add_child(v)
	center.add_child(p)
	SceneRouter.hide_loading()


func _pick(id: int) -> void:
	_selected = id
	for a in _avatars:
		(a as AvatarIcon).selected = (a as AvatarIcon).avatar_id == id
	AudioManager.play_sfx("ui_click", -4.0)


func _on_enter() -> void:
	_enter(false)


func _on_guest() -> void:
	_enter(true)


func _enter(guest: bool) -> void:
	var nm := _name_edit.text.strip_edges()
	if guest:
		nm = "Convidado%d" % randi_range(1000, 9999)
	if nm == "":
		_msg.text = "Digite um apelido ou jogue como convidado."
		AudioManager.play_sfx("ui_back")
		return
	SaveSystem.set_profile(nm, _selected, guest)
	AudioManager.play_sfx("ui_confirm")
	SceneRouter.go_lobby()


func _open_settings() -> void:
	if _settings != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_settings = layer
	var sm := SettingsMenu.new()
	layer.add_child(sm)
	sm.closed.connect(_close_settings)


func _close_settings() -> void:
	if _settings != null:
		_settings.queue_free()
		_settings = null


## Fundo animado: gradiente do eclipse com partículas flutuantes (desenhado em código).
class LoginBackground extends Control:
	var _t := 0.0
	var _dots: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 60:
			_dots.append(Vector3(randf(), randf(), randf_range(0.3, 1.0)))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var vs := size
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.07))
		for i in 12:
			var f := float(i) / 12.0
			draw_rect(Rect2(0, vs.y * f, vs.x, vs.y / 12.0 + 1.0), Color(0.12 + f * 0.25, 0.05 + f * 0.1, 0.04, 0.55 * f))
		var c := Vector2(vs.x * 0.72, vs.y * 0.34)
		var r := minf(vs.x, vs.y) * 0.22
		for k in 10:
			draw_arc(c, r + 4.0 + k * 5.0, 0.0, TAU, 80, Color(1.0, 0.55, 0.15, 0.30 - k * 0.028), 3.0)
		draw_circle(c, r, Color(0.01, 0.01, 0.02))
		for d in _dots:
			var x := fposmod(d.x * vs.x + _t * 12.0 * d.z, vs.x)
			var y := fposmod(d.y * vs.y - _t * 18.0 * d.z, vs.y)
			draw_circle(Vector2(x, y), 1.5 * d.z + 0.5, Color(1.0, 0.7, 0.35, 0.5 * d.z))
