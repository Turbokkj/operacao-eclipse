class_name UIKit
extends RefCounted
## Fábrica de controles estilizados (consistência visual entre login, lobby, HUD e menus).

const ACCENT := Color(1.0, 0.55, 0.14)
const ACCENT_DARK := Color(0.78, 0.36, 0.06)
const BG := Color(0.05, 0.06, 0.09, 0.92)
const BG_LIGHT := Color(0.11, 0.13, 0.18, 0.94)
const TEXT := Color(0.93, 0.95, 1.0)
const MUTED := Color(0.62, 0.67, 0.76)
const GOOD := Color(0.35, 0.85, 0.5)
const BAD := Color(0.95, 0.3, 0.3)
const BLUE := Color(0.35, 0.65, 1.0)


static func style(color: Color, radius: int = 12, border: Color = Color(1, 1, 1, 0), border_w: int = 0, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_content_margin_all(margin)
	return s


static func label(text: String, size: int = 18, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_size: Vector2 = Vector2(0, 48), accent: bool = false, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	if accent:
		b.add_theme_stylebox_override("normal", style(ACCENT_DARK, 12, ACCENT, 2))
		b.add_theme_stylebox_override("hover", style(ACCENT, 12, Color(1, 0.8, 0.5), 2))
		b.add_theme_stylebox_override("pressed", style(Color(0.6, 0.26, 0.04), 12, ACCENT, 2))
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.0))
	b.pressed.connect(func(): AudioManager.play_sfx("ui_click", -4.0))
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel(color: Color = BG, radius: int = 16, pad: float = 16.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(color, radius, Color(1, 1, 1, 0.08), 1, pad))
	return p


static func spacer(h: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func slider_row(text: String, minv: float, maxv: float, step: float, value: float, cb: Callable, fmt: String = "%.2f") -> HBoxContainer:
	var row := hbox(12)
	var l := label(text, 17)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(180, 28)
	row.add_child(s)
	var vl := label(fmt % value, 17, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(64, 0)
	row.add_child(vl)
	s.value_changed.connect(func(v: float): _on_slider(v, vl, fmt, cb))
	return row


static func _on_slider(v: float, vl: Label, fmt: String, cb: Callable) -> void:
	vl.text = fmt % v
	cb.call(v)


static func option_row(text: String, options: Array, selected: int, cb: Callable) -> HBoxContainer:
	var row := hbox(12)
	var l := label(text, 17)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	for o in options:
		ob.add_item(str(o))
	ob.selected = selected
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(180, 40)
	ob.item_selected.connect(func(i: int): cb.call(i))
	row.add_child(ob)
	return row


static func check_row(text: String, value: bool, cb: Callable) -> HBoxContainer:
	var row := hbox(12)
	var l := label(text, 17)
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = value
	c.toggled.connect(func(v: bool): cb.call(v))
	row.add_child(c)
	return row
