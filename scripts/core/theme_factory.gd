class_name ThemeFactory
extends RefCounted
## Tema global (botões, painéis, campos, sliders, abas) aplicado na janela raiz.

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	var normal := UIKit.style(Color(0.14, 0.16, 0.22, 0.95), 10, Color(1, 1, 1, 0.10), 1, 10.0)
	var hover := UIKit.style(Color(0.22, 0.25, 0.34, 0.98), 10, UIKit.ACCENT, 1, 10.0)
	var pressed := UIKit.style(Color(0.30, 0.20, 0.10, 1.0), 10, UIKit.ACCENT, 2, 10.0)
	var disabled := UIKit.style(Color(0.10, 0.11, 0.14, 0.7), 10, Color(1, 1, 1, 0.04), 1, 10.0)
	for tn in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", tn, normal)
		t.set_stylebox("hover", tn, hover)
		t.set_stylebox("pressed", tn, pressed)
		t.set_stylebox("disabled", tn, disabled)
		t.set_stylebox("focus", tn, StyleBoxEmpty.new())
		t.set_color("font_color", tn, UIKit.TEXT)
		t.set_color("font_hover_color", tn, Color.WHITE)
		t.set_color("font_pressed_color", tn, UIKit.ACCENT)
		t.set_color("font_disabled_color", tn, Color(0.5, 0.5, 0.55))
	t.set_stylebox("panel", "PanelContainer", UIKit.style(UIKit.BG, 16, Color(1, 1, 1, 0.08), 1, 14.0))
	t.set_stylebox("panel", "Panel", UIKit.style(UIKit.BG, 16, Color(1, 1, 1, 0.08), 1, 14.0))
	t.set_stylebox("normal", "LineEdit", UIKit.style(Color(0.08, 0.09, 0.13, 0.95), 10, Color(1, 1, 1, 0.18), 1, 12.0))
	t.set_stylebox("focus", "LineEdit", UIKit.style(Color(0.08, 0.09, 0.13, 0.95), 10, UIKit.ACCENT, 2, 12.0))
	t.set_color("font_color", "LineEdit", UIKit.TEXT)
	var slider_bg := UIKit.style(Color(1, 1, 1, 0.14), 4, Color(0, 0, 0, 0), 0, 4.0)
	var slider_fill := UIKit.style(UIKit.ACCENT, 4, Color(0, 0, 0, 0), 0, 4.0)
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	t.set_stylebox("panel", "TabContainer", UIKit.style(Color(0.07, 0.08, 0.12, 0.9), 12, Color(1, 1, 1, 0.06), 1, 14.0))
	t.set_stylebox("tab_selected", "TabContainer", UIKit.style(UIKit.ACCENT_DARK, 8, UIKit.ACCENT, 1, 10.0))
	t.set_stylebox("tab_unselected", "TabContainer", UIKit.style(Color(0.14, 0.16, 0.22, 0.9), 8, Color(1, 1, 1, 0.06), 1, 10.0))
	t.set_stylebox("tab_hovered", "TabContainer", UIKit.style(Color(0.22, 0.25, 0.34, 0.98), 8, UIKit.ACCENT, 1, 10.0))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", UIKit.MUTED)
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_stylebox("panel", "PopupMenu", UIKit.style(Color(0.08, 0.09, 0.13, 0.98), 8, UIKit.ACCENT, 1, 8.0))
	t.set_stylebox("hover", "PopupMenu", UIKit.style(Color(0.3, 0.2, 0.1, 1.0), 6, Color(0, 0, 0, 0), 0, 6.0))
	t.set_stylebox("background", "ProgressBar", UIKit.style(Color(1, 1, 1, 0.12), 6, Color(0, 0, 0, 0), 0, 2.0))
	t.set_stylebox("fill", "ProgressBar", UIKit.style(UIKit.ACCENT, 6, Color(0, 0, 0, 0), 0, 2.0))
	return t
