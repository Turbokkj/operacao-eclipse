class_name HudEditor
extends CanvasLayer
## Editor de HUD: mostra os botões touch sobre um fundo escurecido; arraste para mover, use +/- para o
## tamanho do botão selecionado. As posições são salvas (SaveSystem.data.hud_layout) e usadas na partida.

var _tc: TouchControls
var _info: Label


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tc = TouchControls.new()
	_tc.editing = true
	add_child(_tc)
	_tc.changed.connect(_refresh)
	var bar := UIKit.panel(UIKit.BG, 14, 10.0)
	var h := UIKit.hbox(10)
	_info = UIKit.label("Arraste um botão para movê-lo", 16)
	h.add_child(_info)
	h.add_child(UIKit.button("-", _tc.resize_selected.bind(-0.1), Vector2(46, 42)))
	h.add_child(UIKit.button("+", _tc.resize_selected.bind(0.1), Vector2(46, 42)))
	h.add_child(UIKit.button("RESTAURAR", _tc.reset_layout, Vector2(130, 42)))
	h.add_child(UIKit.button("CONCLUIR", _done, Vector2(130, 42), true))
	bar.add_child(h)
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _refresh() -> void:
	_info.text = "Selecionado: %s" % (str(TouchControls.DEFAULTS[_tc.selected]["label"]) if _tc.selected != "" else "nenhum")


func _done() -> void:
	SaveSystem.save_data()
	queue_free()
