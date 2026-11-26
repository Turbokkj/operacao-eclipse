class_name ResultsScreen
extends CanvasLayer
## Tela de resultados: VITÓRIA com texto oficial ou colocação final, estatísticas e botões.

func show_results(data: Dictionary, on_lobby: Callable, on_again: Callable) -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var won := bool(data.get("won", false))
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55 if won else 0.78)
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel(UIKit.BG, 20, 26.0)
	var v := UIKit.vbox(12)
	var banner_text := "VITÓRIA! VOCÊ É O ÚLTIMO SOBREVIVENTE!" if won else "VOCÊ FOI ELIMINADO"
	var banner := UIKit.label(banner_text, 34, Color(1.0, 0.82, 0.25) if won else UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.custom_minimum_size = Vector2(620, 0)
	v.add_child(banner)
	v.add_child(UIKit.label("Colocação: #%d de %d" % [int(data.get("place", 0)), int(data.get("total", 16))], 26, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var t := int(float(data.get("survive", 0.0)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	for row in [["Abates", str(int(data.get("kills", 0)))], ["Dano causado", str(int(float(data.get("damage", 0.0))))],
			["Tempo sobrevivido", "%d:%02d" % [t / 60, t % 60]], ["XP ganho", "+%d" % int(data.get("xp", 0))],
			["Nível", str(SaveSystem.level())]]:
		grid.add_child(UIKit.label(str(row[0]), 20, UIKit.MUTED))
		grid.add_child(UIKit.label(str(row[1]), 20, UIKit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	var gc := CenterContainer.new()
	gc.add_child(grid)
	v.add_child(gc)
	var br := UIKit.hbox(14)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_child(UIKit.button("VOLTAR AO LOBBY", on_lobby, Vector2(240, 56), false))
	br.add_child(UIKit.button("JOGAR NOVAMENTE", on_again, Vector2(240, 56), true))
	v.add_child(br)
	p.add_child(v)
	root.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	if not won:
		AudioManager.play_sfx("lose")
