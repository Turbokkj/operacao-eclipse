class_name LoadingOverlay
extends CanvasLayer
## Tela de carregamento: logotipo, barra de progresso REAL (alimentada por etapas concluídas),
## mensagens, dicas, tratamento de erro e fade de transição.

const TIPS := [
	"Dica: a zona segura sempre fecha — comece a se deslocar antes do aviso final.",
	"Dica: bots ouvem tiros e passos rápidos. Agache para ficar discreto.",
	"Dica: o supressor reduz o alcance do barulho dos disparos.",
	"Dica: use a bandagem longe de combate; curar leva alguns segundos.",
	"Dica: no celular, a mira assistida pode ser ajustada em Configurações > Controles.",
]

var root: Control
var fill: ColorRect
var pct_label: Label
var msg_label: Label
var title_label: Label
var tip_label: Label
var err_label: Label
var fade_rect: ColorRect
var _target := 0.0
var _shown := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.45, 0.1, 0.06)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.55
	root.add_child(glow)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -90
	root.add_child(center)
	var cv := UIKit.vbox(10)
	center.add_child(cv)
	cv.add_child(LogoControl.new())
	title_label = UIKit.label("Carregando", 24, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(title_label)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 80
	bottom.offset_right = -80
	bottom.offset_bottom = -34
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	var row := UIKit.hbox(8)
	bottom.add_child(row)
	msg_label = UIKit.label("", 16, UIKit.TEXT)
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(msg_label)
	pct_label = UIKit.label("0%", 16, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(pct_label)
	var track := Control.new()
	track.custom_minimum_size = Vector2(0, 12)
	bottom.add_child(track)
	var track_bg := ColorRect.new()
	track_bg.color = Color(1, 1, 1, 0.12)
	track_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(track_bg)
	fill = ColorRect.new()
	fill.color = UIKit.ACCENT
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = 0.0
	track.add_child(fill)
	tip_label = UIKit.label(TIPS[0], 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	bottom.add_child(tip_label)
	err_label = UIKit.label("", 17, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
	err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err_label.visible = false
	bottom.add_child(err_label)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)


func _process(delta: float) -> void:
	if not root.visible:
		return
	_shown = move_toward(_shown, _target, delta * 1.2)
	fill.anchor_right = _shown
	pct_label.text = "%d%%" % int(round(_shown * 100.0))


func show_overlay(title: String) -> void:
	visible = true
	root.visible = true
	title_label.text = title
	_target = 0.0
	_shown = 0.0
	err_label.visible = false
	fill.color = UIKit.ACCENT
	tip_label.text = TIPS[randi() % TIPS.size()]


func hide_overlay() -> void:
	root.visible = false


func hide_immediately() -> void:
	root.visible = false
	fade_rect.color.a = 0.0


func set_progress(v: float, msg: String) -> void:
	_target = clampf(v, 0.0, 1.0)
	msg_label.text = msg


func show_error(msg: String) -> void:
	visible = true
	root.visible = true
	err_label.text = msg
	err_label.visible = true
	fill.color = UIKit.BAD


func fade_to(alpha: float, dur: float) -> void:
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", alpha, dur)
	await tw.finished
	if alpha <= 0.01:
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
