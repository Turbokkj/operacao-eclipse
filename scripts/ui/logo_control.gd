class_name LogoControl
extends Control
## Logotipo original desenhado por código: eclipse com corona + título.

@export var show_text := true


func _init() -> void:
	custom_minimum_size = Vector2(520, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 72.0)
	var r := 46.0
	for i in 8:
		draw_arc(c, r + 4.0 + i * 3.4, 0.0, TAU, 72, Color(1.0, 0.55, 0.15, 0.55 - i * 0.065), 3.0)
	draw_circle(c, r + 2.0, Color(1.0, 0.72, 0.35, 0.9))
	draw_circle(c + Vector2(3.0, 0.0), r, Color(0.015, 0.02, 0.04))
	draw_arc(c, r + 1.0, -0.9, 0.9, 32, Color(1.0, 0.85, 0.55), 4.0)
	if show_text:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 156), "OPERAÇÃO ECLIPSE", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(1, 1, 1))
		draw_string(font, Vector2(0, 186), "B A T T L E   R O Y A L E", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UIKit.ACCENT)
