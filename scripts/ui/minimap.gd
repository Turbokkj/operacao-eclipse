class_name Minimap
extends Control
## Minimapa: textura do terreno real (relevo, estradas, construções), posição/direção do jogador e círculos
## da zona (atual e próxima). Modo grande (tecla M) mostra o mapa inteiro.

var map: MapData
var player: Node3D
var zone: ZoneController
var cam: Node3D
var big := false


func setup(p_map: MapData, p_player: Node3D, p_zone: ZoneController, p_cam: Node3D) -> void:
	map = p_map
	player = p_player
	zone = p_zone
	cam = p_cam
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.10, 0.92))
	if map == null or map.minimap == null or player == null or not is_instance_valid(player):
		return
	var half := map.half
	var view := half * 1.02 if big else 140.0
	var ppm := size.x * 0.5 / view
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var focus := Vector2.ZERO if big else pp
	var tex_px := half * 2.0 * ppm
	var origin := size * 0.5 - (focus + Vector2(half, half)) * ppm
	draw_texture_rect(map.minimap, Rect2(origin, Vector2(tex_px, tex_px)), false)
	if zone != null:
		var cz := size * 0.5 + (zone.center - focus) * ppm
		draw_arc(cz, maxf(zone.radius * ppm, 1.0), 0.0, TAU, 128, Color(0.30, 0.62, 1.0), 2.5)
		if zone.next_radius >= 0.0:
			var nz := size * 0.5 + (zone.next_center - focus) * ppm
			draw_arc(nz, maxf(zone.next_radius * ppm, 1.0), 0.0, TAU, 96, Color(1, 1, 1, 0.9), 1.8)
	var pos := size * 0.5 + (pp - focus) * ppm
	var yaw := cam.rotation.y if cam != null else player.rotation.y
	var dir := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([pos + dir * 9.0, pos - dir * 6.0 + side * 6.0, pos - dir * 3.0, pos - dir * 6.0 - side * 6.0])
	draw_colored_polygon(pts, Color(1.0, 0.55, 0.14))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.8), 1.5)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.5 - 4.0, 14.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
