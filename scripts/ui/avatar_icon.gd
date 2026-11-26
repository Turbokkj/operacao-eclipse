class_name AvatarIcon
extends Control
## Avatar de perfil desenhado em código (6 variações originais), com destaque quando selecionado.

signal picked(id: int)

const PALETTES := [
	[Color(0.95, 0.45, 0.12), Color(0.30, 0.12, 0.05)], [Color(0.25, 0.60, 0.95), Color(0.06, 0.16, 0.32)],
	[Color(0.35, 0.80, 0.45), Color(0.08, 0.25, 0.12)], [Color(0.85, 0.35, 0.65), Color(0.28, 0.08, 0.20)],
	[Color(0.95, 0.80, 0.25), Color(0.30, 0.24, 0.05)], [Color(0.60, 0.50, 0.95), Color(0.15, 0.10, 0.32)],
]

var avatar_id := 0:
	set(v):
		avatar_id = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var clickable := true


func _init() -> void:
	custom_minimum_size = Vector2(84, 84)


func _gui_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(avatar_id)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var pal: Array = PALETTES[avatar_id % PALETTES.size()]
	var fg: Color = pal[0]
	var bg: Color = pal[1]
	draw_circle(c, s * 0.5, bg)
	draw_circle(c + Vector2(0, -s * 0.04), s * 0.44, bg.lightened(0.12))
	# emblema (varia por avatar)
	var ec := c + Vector2(0, -s * 0.02)
	match avatar_id % 6:
		0:
			draw_arc(ec, s * 0.30, 0.0, TAU, 40, fg, s * 0.05)
			draw_circle(ec, s * 0.18, Color(0.02, 0.02, 0.04))
		1:
			draw_colored_polygon(PackedVector2Array([ec + Vector2(-s * 0.08, -s * 0.30), ec + Vector2(s * 0.14, -s * 0.04), ec + Vector2(0, -s * 0.04),
				ec + Vector2(s * 0.08, s * 0.30), ec + Vector2(-s * 0.14, s * 0.04), ec + Vector2(0, s * 0.04)]), fg)
		2:
			draw_colored_polygon(PackedVector2Array([ec + Vector2(0, -s * 0.32), ec + Vector2(s * 0.26, -s * 0.15), ec + Vector2(s * 0.2, s * 0.2),
				ec + Vector2(0, s * 0.32), ec + Vector2(-s * 0.2, s * 0.2), ec + Vector2(-s * 0.26, -s * 0.15)]), fg)
		3:
			draw_circle(ec + Vector2(-s * 0.06, 0), s * 0.26, fg)
			draw_circle(ec + Vector2(s * 0.06, -s * 0.03), s * 0.24, bg.lightened(0.12))
		4:
			var pts := PackedVector2Array()
			for i in 10:
				var r := s * (0.32 if i % 2 == 0 else 0.14)
				var a := -PI * 0.5 + TAU * i / 10.0
				pts.append(ec + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, fg)
		_:
			draw_colored_polygon(PackedVector2Array([ec + Vector2(0, -s * 0.32), ec + Vector2(s * 0.22, s * 0.05), ec + Vector2(0, s * 0.3),
				ec + Vector2(-s * 0.22, s * 0.05)]), fg)
			draw_circle(ec + Vector2(0, s * 0.06), s * 0.08, bg)
	draw_arc(c, s * 0.47, 0.0, TAU, 48, UIKit.ACCENT if selected else Color(1, 1, 1, 0.25), 4.0 if selected else 2.0)
