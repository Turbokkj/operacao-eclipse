class_name SettingsMenu
extends Control
## Menu de configurações com abas (Gráficos, Controles, Áudio, Jogabilidade). Tudo é salvo localmente e
## aplicado imediatamente, sem reiniciar. Inclui remapeamento de teclas e acesso ao editor de HUD touch.

signal closed

const QUALITY_KEYS := ["auto", "low", "medium", "high", "custom"]
const FPS_VALUES := [30, 45, 60, 0]

var _rebinding := ""
var _rebind_btn: Button
var _key_btns := {}
var _editor: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel(UIKit.BG, 18, 18.0)
	p.custom_minimum_size = Vector2(780, 520)
	var v := UIKit.vbox(10)
	var head := UIKit.hbox(10)
	head.add_child(UIKit.label("CONFIGURAÇÕES", 28, UIKit.ACCENT))
	head.add_child(UIKit.spacer(0.0, true))
	head.add_child(UIKit.button("FECHAR", close, Vector2(130, 42), true))
	v.add_child(head)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(740, 410)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	var pages := [["Gráficos", _page_graphics()], ["Controles", _page_controls()], ["Áudio", _page_audio()], ["Jogabilidade", _page_gameplay()]]
	for i in pages.size():
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box: VBoxContainer = pages[i][1]
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(box)
		tabs.add_child(sc)
		tabs.set_tab_title(i, str(pages[i][0]))
	p.add_child(v)
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


func close() -> void:
	if _editor != null and is_instance_valid(_editor):
		return
	SaveSystem.save_data()
	closed.emit()


func _make_custom() -> void:
	if str(GameSettings.get_s("quality")) != "custom":
		var e := QualityManager.effective()
		GameSettings.set_s("render_scale", float(e["render_scale"]))
		GameSettings.set_s("shadows", int(e["shadows"]))
		GameSettings.set_s("render_distance", float(e["render_distance"]))
		GameSettings.set_s("quality", "custom")


func _on_scale(x: float) -> void:
	_make_custom()
	GameSettings.set_s("render_scale", x)


func _on_shadows(i: int) -> void:
	_make_custom()
	GameSettings.set_s("shadows", i)


func _on_distance(x: float) -> void:
	_make_custom()
	GameSettings.set_s("render_distance", x)


func _page_graphics() -> VBoxContainer:
	var b := UIKit.vbox(8)
	var e := QualityManager.effective()
	var qi := QUALITY_KEYS.find(str(GameSettings.get_s("quality")))
	b.add_child(UIKit.option_row("Qualidade gráfica", ["Automático", "Baixo", "Médio", "Alto", "Personalizado"], maxi(qi, 0),
		func(i: int): GameSettings.set_s("quality", QUALITY_KEYS[i])))
	b.add_child(UIKit.slider_row("Resolução interna", 0.5, 1.0, 0.05, float(e["render_scale"]), _on_scale, "%.2f"))
	b.add_child(UIKit.option_row("Sombras", ["Desligadas", "Baixas", "Médias", "Altas"], int(e["shadows"]), _on_shadows))
	b.add_child(UIKit.slider_row("Distância de renderização (m)", 150.0, 600.0, 10.0, float(e["render_distance"]), _on_distance, "%d"))
	var fi := FPS_VALUES.find(int(GameSettings.get_s("fps_limit")))
	b.add_child(UIKit.option_row("Limite de FPS", ["30", "45", "60", "Sem limite"], maxi(fi, 2),
		func(i: int): GameSettings.set_s("fps_limit", FPS_VALUES[i])))
	b.add_child(UIKit.label("Resolução, sombras e distância valem imediatamente. A vegetação é reduzida nas próximas partidas.", 14, UIKit.MUTED))
	return b


func _page_controls() -> VBoxContainer:
	var b := UIKit.vbox(8)
	b.add_child(UIKit.slider_row("Sensibilidade horizontal", 0.2, 3.0, 0.05, float(GameSettings.get_s("sens_h")), func(x: float): GameSettings.set_s("sens_h", x)))
	b.add_child(UIKit.slider_row("Sensibilidade vertical", 0.2, 3.0, 0.05, float(GameSettings.get_s("sens_v")), func(x: float): GameSettings.set_s("sens_v", x)))
	b.add_child(UIKit.slider_row("Sensibilidade ao mirar", 0.2, 1.5, 0.05, float(GameSettings.get_s("sens_aim")), func(x: float): GameSettings.set_s("sens_aim", x)))
	b.add_child(UIKit.check_row("Inverter eixo vertical", bool(GameSettings.get_s("invert_y")), func(x: bool): GameSettings.set_s("invert_y", x)))
	b.add_child(UIKit.option_row("Mira assistida", ["Automática", "Desativada", "Leve", "Normal", "Forte"], int(GameSettings.get_s("aim_assist")) + 1,
		func(i: int): GameSettings.set_s("aim_assist", i - 1)))
	b.add_child(UIKit.slider_row("Opacidade dos botões touch", 0.2, 1.0, 0.05, float(GameSettings.get_s("hud_opacity")), func(x: float): GameSettings.set_s("hud_opacity", x)))
	b.add_child(UIKit.slider_row("Tamanho dos botões touch", 0.7, 1.5, 0.05, float(GameSettings.get_s("hud_scale")), func(x: float): GameSettings.set_s("hud_scale", x)))
	b.add_child(UIKit.button("EDITAR POSIÇÃO / TAMANHO DOS BOTÕES (HUD)", _open_hud_editor, Vector2(0, 46)))
	b.add_child(UIKit.label("Teclado (clique e pressione a nova tecla):", 16, UIKit.MUTED))
	for action in GameSettings.KEY_ACTIONS:
		var row := UIKit.hbox(12)
		var l := UIKit.label(str(GameSettings.ACTION_LABELS[action]), 16)
		l.custom_minimum_size = Vector2(230, 0)
		row.add_child(l)
		var btn := UIKit.button(GameSettings.key_label(action), Callable(), Vector2(160, 34), false, 15)
		btn.pressed.connect(_start_rebind.bind(action, btn))
		_key_btns[action] = btn
		row.add_child(btn)
		b.add_child(row)
	return b


func _page_audio() -> VBoxContainer:
	var b := UIKit.vbox(8)
	for k in [["vol_master", "Volume geral"], ["vol_music", "Música"], ["vol_sfx", "Efeitos sonoros"], ["vol_ambient", "Ambiente"]]:
		var key: String = k[0]
		b.add_child(UIKit.slider_row(str(k[1]), 0.0, 1.0, 0.05, float(GameSettings.get_s(key)), func(x: float): GameSettings.set_s(key, x)))
	return b


func _page_gameplay() -> VBoxContainer:
	var b := UIKit.vbox(8)
	b.add_child(UIKit.check_row("Mostrar FPS", bool(GameSettings.get_s("show_fps")), func(x: bool): GameSettings.set_s("show_fps", x)))
	b.add_child(UIKit.check_row("Mostrar minimapa", bool(GameSettings.get_s("show_minimap")), func(x: bool): GameSettings.set_s("show_minimap", x)))
	b.add_child(UIKit.option_row("Lado da câmera", ["Ombro direito", "Ombro esquerdo"], 0 if int(GameSettings.get_s("camera_side")) >= 0 else 1,
		func(i: int): GameSettings.set_s("camera_side", 1 if i == 0 else -1)))
	b.add_child(UIKit.check_row("Correr automático (touch)", bool(GameSettings.get_s("auto_sprint")), func(x: bool): GameSettings.set_s("auto_sprint", x)))
	b.add_child(UIKit.check_row("Forçar controles touch", bool(GameSettings.get_s("force_touch")), func(x: bool): GameSettings.set_s("force_touch", x)))
	b.add_child(UIKit.label("AJUDA DOS CONTROLES", 16, UIKit.ACCENT))
	var help := "PC: W A S D mover | Mouse câmera | Clique esq. atirar | Clique dir. mirar | Espaço pular | Shift correr | C agachar\n" \
		+ "E coletar | R recarregar | 1-2-3 armas | Q trocar | 4 bandagem | 5 kit médico | Tab mochila | M mapa grande | Esc pausa\n" \
		+ "Touch: joystick à esquerda (empurre até a borda para correr), arraste à direita para a câmera, botões na tela."
	var hl := UIKit.label(help, 15, UIKit.MUTED)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size = Vector2(700, 0)
	b.add_child(hl)
	b.add_child(UIKit.button("RESTAURAR PADRÕES", _reset_defaults, Vector2(0, 46)))
	return b


func _reset_defaults() -> void:
	GameSettings.reset_defaults()
	GameSettings.apply_all()
	closed.emit()


func _start_rebind(action: String, btn: Button) -> void:
	_rebinding = action
	_rebind_btn = btn
	btn.text = "Pressione uma tecla..."


func _input(event: InputEvent) -> void:
	if _rebinding != "" and event is InputEventKey and event.pressed and not event.echo:
		GameSettings.rebind(_rebinding, event.physical_keycode)
		_rebind_btn.text = GameSettings.key_label(_rebinding)
		_rebinding = ""
		get_viewport().set_input_as_handled()


func _open_hud_editor() -> void:
	if _editor != null and is_instance_valid(_editor):
		return
	_editor = HudEditor.new()
	add_child(_editor)
	visible = true
