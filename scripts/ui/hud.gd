class_name Hud
extends CanvasLayer
## HUD da partida (clássico e treinamento). Mostra minimapa real, sobreviventes, abates, estado da zona,
## bússola, retículo dinâmico, vida/proteção, arma/munição, itens de cura, aviso de interação, feed de
## notificações, inventário (Tab), mapa grande (M), menu de pausa e controles touch quando necessário.

var m: Node
var player: Player
var zone: ZoneController
var map: MapData
var ui: Control
var minimap: Minimap
var big_map: Minimap
var touch: TouchControls
var crosshair: Control
var compass: Control
var menu_open := false
var pause_tree := true          # online: o menu de pausa NÃO congela a simulação
var results_screen: Node
var _alive_l: Label
var _kills_l: Label
var _zone_l: Label
var _fps_l: Label
var _hp_bar: ProgressBar
var _hp_l: Label
var _ar_bar: ProgressBar
var _ar_l: Label
var _w_name: Label
var _w_ammo: Label
var _w_slots: Label
var _w_heal: Label
var _reload_bar: ProgressBar
var _prompt: Label
var _big: Label
var _click_hint: Label
var _feed: VBoxContainer
var _pause_panel: Control
var _inv_panel: Control
var _inv_list: VBoxContainer
var _inv_cap: Label
var _settings_layer: CanvasLayer
var _acc := 0.0
var _inv_acc := 0.0
var hit_t := 0.0
var hit_kill := false
var hurt: Array = []
var hurt_flash := 0.0


func setup(p_match: Node) -> void:
	m = p_match
	player = m.player
	zone = m.zone
	map = m.map
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")
	ui = Control.new()
	ui.name = "UI"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_top()
	_build_center()
	_build_bottom()
	_build_feed()
	_build_pause()
	if GameSettings.touch_mode:
		touch = TouchControls.new()
		ui.add_child(touch)
	Events.notify.connect(_on_notify)
	Events.hit_marker.connect(_on_hit_marker)
	Events.player_hurt.connect(_on_hurt)


# ------------------------------------------------------------------ construção
func _pin(c: Control, preset: int, margin: float = 12.0, grow_h: int = -1, grow_v: int = -1) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(margin))
	if grow_h >= 0:
		c.grow_horizontal = grow_h
	if grow_v >= 0:
		c.grow_vertical = grow_v


func _build_top() -> void:
	if map != null:
		minimap = Minimap.new()
		minimap.position = Vector2(14, 14)
		minimap.size = Vector2(170, 170)
		ui.add_child(minimap)
		minimap.setup(map, player, zone, m.cam)
		minimap.visible = bool(GameSettings.get_s("show_minimap"))
		big_map = Minimap.new()
		big_map.size = Vector2(520, 520)
		big_map.big = true
		big_map.visible = false
		ui.add_child(big_map)
		big_map.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
		big_map.setup(map, player, zone, m.cam)
	var top := UIKit.panel(Color(0.04, 0.05, 0.08, 0.72), 12, 8.0)
	var v := UIKit.vbox(2)
	var row := UIKit.hbox(18)
	_alive_l = UIKit.label("VIVOS 16", 20, UIKit.TEXT)
	_kills_l = UIKit.label("ABATES 0", 20, UIKit.ACCENT)
	row.add_child(_alive_l)
	row.add_child(_kills_l)
	v.add_child(row)
	compass = CompassDraw.new()
	compass.custom_minimum_size = Vector2(340, 24)
	compass.set("hud", self)
	v.add_child(compass)
	_zone_l = UIKit.label("", 15, UIKit.BLUE)
	_zone_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_zone_l)
	top.add_child(v)
	ui.add_child(top)
	_pin(top, Control.PRESET_CENTER_TOP, 8.0, Control.GROW_DIRECTION_BOTH)
	_fps_l = UIKit.label("", 14, UIKit.MUTED)
	ui.add_child(_fps_l)
	_pin(_fps_l, Control.PRESET_TOP_RIGHT, 10.0, Control.GROW_DIRECTION_BEGIN)
	_fps_l.position.y += 4


func _build_center() -> void:
	crosshair = CrosshairDraw.new()
	crosshair.set("hud", self)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt = UIKit.label("", 22, UIKit.TEXT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_prompt)
	_pin(_prompt, Control.PRESET_CENTER, 0.0, Control.GROW_DIRECTION_BOTH)
	_prompt.position.y += 120
	_big = UIKit.label("", 64, UIKit.TEXT)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_big.add_theme_constant_override("outline_size", 8)
	_big.visible = false
	ui.add_child(_big)
	_pin(_big, Control.PRESET_CENTER, 0.0, Control.GROW_DIRECTION_BOTH)
	_big.position.y -= 130
	_click_hint = UIKit.label("Clique para jogar (o mouse será capturado)", 22, UIKit.ACCENT)
	_click_hint.visible = false
	ui.add_child(_click_hint)
	_pin(_click_hint, Control.PRESET_CENTER, 0.0, Control.GROW_DIRECTION_BOTH)
	_click_hint.position.y += 200


func _bar(color: Color, w: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, 14)
	b.show_percentage = false
	b.max_value = 100.0
	b.add_theme_stylebox_override("fill", UIKit.style(color, 6, Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("background", UIKit.style(Color(0, 0, 0, 0.55), 6, Color(1, 1, 1, 0.15), 1, 0))
	return b


func _build_bottom() -> void:
	var vit := UIKit.panel(Color(0.04, 0.05, 0.08, 0.72), 12, 10.0)
	var vb := UIKit.vbox(4)
	_hp_l = UIKit.label("VIDA 100", 16, UIKit.GOOD)
	_hp_bar = _bar(UIKit.GOOD, 250.0)
	_ar_l = UIKit.label("SEM PROTEÇÃO", 14, UIKit.MUTED)
	_ar_bar = _bar(UIKit.BLUE, 250.0)
	for c in [_hp_l, _hp_bar, _ar_l, _ar_bar]:
		vb.add_child(c)
	vit.add_child(vb)
	ui.add_child(vit)
	_pin(vit, Control.PRESET_BOTTOM_LEFT, 14.0, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	var wp := UIKit.panel(Color(0.04, 0.05, 0.08, 0.72), 12, 10.0)
	var wv := UIKit.vbox(2)
	_w_name = UIKit.label("DESARMADO", 18, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_w_ammo = UIKit.label("", 30, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_reload_bar = _bar(UIKit.ACCENT, 220.0)
	_reload_bar.visible = false
	_w_slots = UIKit.label("", 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_w_heal = UIKit.label("", 14, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	for c in [_w_name, _w_ammo, _reload_bar, _w_slots, _w_heal]:
		wv.add_child(c)
	wp.add_child(wv)
	ui.add_child(wp)
	_pin(wp, Control.PRESET_CENTER_BOTTOM, 14.0, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 3)
	ui.add_child(_feed)
	_pin(_feed, Control.PRESET_TOP_RIGHT, 12.0, Control.GROW_DIRECTION_BEGIN)
	_feed.position.y += 58
	if not GameSettings.touch_mode:
		var pb := UIKit.button("II", open_pause, Vector2(44, 40))
		ui.add_child(pb)
		_pin(pb, Control.PRESET_TOP_RIGHT, 10.0, Control.GROW_DIRECTION_BEGIN)
		pb.position.y += 24


func _build_pause() -> void:
	_pause_panel = Control.new()
	_pause_panel.visible = false
	ui.add_child(_pause_panel)
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_pause_panel.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel(UIKit.BG, 18, 24.0)
	var v := UIKit.vbox(12)
	v.add_child(UIKit.label("PAUSADO", 32, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.button("CONTINUAR", close_pause, Vector2(300, 54), true))
	v.add_child(UIKit.button("CONFIGURAÇÕES", _open_settings, Vector2(300, 54)))
	if m.has_method("extra_pause_items"):
		for it in m.extra_pause_items():
			v.add_child(UIKit.button(str(it[0]), it[1], Vector2(300, 46), false, 16))
	v.add_child(UIKit.button("SAIR DA PARTIDA", _leave, Vector2(300, 54)))
	p.add_child(v)
	_pause_panel.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


# ------------------------------------------------------------------ menus
func open_pause() -> void:
	if menu_open or results_screen != null:
		return
	menu_open = true
	_pause_panel.visible = true
	if pause_tree:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.clear_touch_state()


func close_pause() -> void:
	_pause_panel.visible = false
	menu_open = false
	if pause_tree:
		get_tree().paused = false
	_recapture()


func _recapture() -> void:
	if not GameSettings.touch_mode and results_screen == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	if _settings_layer != null:
		return
	_settings_layer = CanvasLayer.new()
	_settings_layer.layer = 40
	_settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_settings_layer)
	var sm := SettingsMenu.new()
	_settings_layer.add_child(sm)
	sm.closed.connect(_on_settings_closed)


func _on_settings_closed() -> void:
	if _settings_layer != null:
		_settings_layer.queue_free()
		_settings_layer = null


func _leave() -> void:
	m.leave()


func _again() -> void:
	m.play_again()


func toggle_inventory() -> void:
	if _inv_panel != null and _inv_panel.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	if menu_open or results_screen != null or player == null or not player.alive:
		return
	menu_open = true
	player.ctl_enabled = false
	GameSettings.clear_touch_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _inv_panel == null:
		_build_inventory()
	_inv_panel.visible = true
	_refresh_inventory()


func close_inventory() -> void:
	if _inv_panel != null:
		_inv_panel.visible = false
	menu_open = false
	if player != null and player.alive and str(m.state) == "running":
		player.ctl_enabled = true
	_recapture()


func _build_inventory() -> void:
	_inv_panel = Control.new()
	_inv_panel.visible = false
	ui.add_child(_inv_panel)
	_inv_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	_inv_panel.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel(UIKit.BG, 18, 20.0)
	p.custom_minimum_size = Vector2(640, 420)
	var v := UIKit.vbox(10)
	var head := UIKit.hbox(12)
	head.add_child(UIKit.label("MOCHILA", 28, UIKit.ACCENT))
	head.add_child(UIKit.spacer(0.0, true))
	_inv_cap = UIKit.label("", 18, UIKit.TEXT)
	head.add_child(_inv_cap)
	head.add_child(UIKit.button("FECHAR [Tab]", close_inventory, Vector2(150, 40)))
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(600, 320)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inv_list = UIKit.vbox(4)
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_inv_list)
	v.add_child(sc)
	p.add_child(v)
	_inv_panel.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


func _refresh_inventory() -> void:
	if _inv_list == null or player == null:
		return
	for c in _inv_list.get_children():
		c.queue_free()
	var inv := player.inv
	_inv_cap.text = "Capacidade %d / %d" % [inv.used(), inv.capacity()]
	var entries := inv.entries()
	for cat in ItemDB.CAT_ORDER:
		var rows: Array = []
		for e in entries:
			if e["cat"] == cat:
				rows.append(e)
		if rows.is_empty():
			continue
		_inv_list.add_child(UIKit.label(str(ItemDB.CAT_NAMES[cat]).to_upper(), 14, UIKit.MUTED))
		for e in rows:
			var row := UIKit.hbox(8)
			var qty_txt := (" x%d" % int(e["qty"])) if int(e["qty"]) > 1 else ""
			var equipped := " (equipada)" if (cat == "weapon" and int(e["slot"]) == player.slot) else ""
			row.add_child(UIKit.label(ItemDB.item_name(str(e["id"])) + qty_txt + equipped, 18, ItemDB.rarity_color(str(e["id"]))))
			row.add_child(UIKit.spacer(0.0, true))
			if cat == "weapon":
				row.add_child(UIKit.button("Equipar", _inv_equip.bind(e), Vector2(96, 34), false, 15))
			elif cat == "heal":
				row.add_child(UIKit.button("Usar", _inv_use.bind(e), Vector2(96, 34), false, 15))
			row.add_child(UIKit.button("Largar", _inv_drop.bind(e), Vector2(96, 34), false, 15))
			_inv_list.add_child(row)
	if entries.is_empty():
		_inv_list.add_child(UIKit.label("Mochila vazia. Colete itens pelo mapa.", 18, UIKit.MUTED))


func _inv_equip(e: Dictionary) -> void:
	player.equip(int(e["slot"]))
	_refresh_inventory()


func _inv_use(e: Dictionary) -> void:
	if player.use_heal(str(e["id"])):
		close_inventory()


func _inv_drop(e: Dictionary) -> void:
	var inv := player.inv
	var id := str(e["id"])
	var qty := int(e["qty"])
	match str(e["cat"]):
		"weapon":
			var s := int(e["slot"])
			inv.weapons[s] = ""
			if s == player.slot:
				player.slot = -1
				player.model.set_weapon("")
				player.equip_best()
		"ammo":
			inv.ammo[id.trim_prefix("ammo_")] = 0
		"heal":
			inv.items[id] = 0
		"armor":
			if id.begins_with("vest"):
				inv.vest_level = 0
				inv.vest_hp = 0.0
			else:
				inv.helmet_level = 0
		"pack":
			inv.pack_level = 0
		"acc":
			inv.suppressor = false
	get_tree().call_group("loot_manager", "drop_item", id, qty, player.global_position)
	_refresh_inventory()


# ------------------------------------------------------------------ eventos
func show_big(text: String, secs: float = 1.0) -> void:
	_big.text = text
	_big.visible = true
	_big.modulate = Color(1, 1, 1, 1)
	_big.pivot_offset = _big.size * 0.5
	_big.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_big, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(secs)
	tw.tween_property(_big, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _big.visible = false)


func _on_notify(text: String, kind: String) -> void:
	var col := UIKit.TEXT
	match kind:
		"good":
			col = UIKit.GOOD
		"warn":
			col = Color(1.0, 0.85, 0.3)
		"bad":
			col = UIKit.BAD
		"kill":
			col = UIKit.ACCENT
		"zone":
			col = UIKit.BLUE
	var l := UIKit.label(text, 17, col, HORIZONTAL_ALIGNMENT_RIGHT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	_feed.add_child(l)
	_feed.move_child(l, 0)
	while _feed.get_child_count() > 6:
		_feed.get_child(_feed.get_child_count() - 1).queue_free()
		_feed.remove_child(_feed.get_child(_feed.get_child_count() - 1))
	var tw := l.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _on_hit_marker(is_kill: bool) -> void:
	hit_t = 0.22
	hit_kill = is_kill


func _on_hurt(from_pos: Vector3) -> void:
	hurt_flash = 0.35
	if player == null or m.cam == null:
		return
	var to := from_pos - player.global_position
	if to.length() < 1.0:
		return
	var world_yaw := atan2(-to.x, -to.z)
	hurt.append({"ang": -wrapf(world_yaw - m.cam.yaw, -PI, PI), "t": 1.0})


func show_results(data: Dictionary) -> void:
	if results_screen != null:
		return
	if _inv_panel != null:
		_inv_panel.visible = false
	_pause_panel.visible = false
	menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.clear_touch_state()
	var rs := ResultsScreen.new()
	add_child(rs)
	results_screen = rs
	rs.show_results(data, _leave, _again)


# ------------------------------------------------------------------ atualização
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and results_screen == null:
		if _pause_panel.visible:
			close_pause()
		elif _inv_panel != null and _inv_panel.visible:
			close_inventory()
		else:
			open_pause()
	elif event.is_action_pressed("inventory") and results_screen == null and not _pause_panel.visible:
		toggle_inventory()
	elif event.is_action_pressed("big_map") and big_map != null:
		big_map.visible = not big_map.visible
	elif event is InputEventMouseButton and event.pressed and not menu_open and not GameSettings.touch_mode:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and str(m.state) == "running":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	hit_t = maxf(0.0, hit_t - delta)
	hurt_flash = maxf(0.0, hurt_flash - delta)
	for h in hurt:
		h["t"] = float(h["t"]) - delta * 1.2
	hurt = hurt.filter(func(h): return float(h["t"]) > 0.0)
	crosshair.queue_redraw()
	compass.queue_redraw()
	_acc += delta
	if _acc >= 0.07:
		_acc = 0.0
		_refresh()
	if _inv_panel != null and _inv_panel.visible:
		_inv_acc += delta
		if _inv_acc > 0.5:
			_inv_acc = 0.0
			_refresh_inventory()


func _refresh() -> void:
	if "alive_count" in m:
		_alive_l.text = "VIVOS %d" % int(m.alive_count)
	else:
		_alive_l.text = "TREINAMENTO"
	_kills_l.text = "ABATES %d" % player.kills
	_zone_l.text = zone.status_text() if zone != null else ""
	_hp_bar.value = player.hp
	_hp_l.text = "VIDA %d" % ceili(player.hp)
	var inv := player.inv
	_ar_bar.value = inv.vest_hp
	var parts: Array = []
	if inv.vest_level > 0:
		parts.append("COLETE Nv.%d" % inv.vest_level)
	if inv.helmet_level > 0:
		parts.append("CAPACETE Nv.%d" % inv.helmet_level)
	_ar_l.text = " | ".join(parts) if not parts.is_empty() else "SEM PROTEÇÃO"
	var w := player.weapon_def()
	if w.is_empty():
		_w_name.text = "DESARMADO"
		_w_ammo.text = ""
		_reload_bar.visible = false
	else:
		_w_name.text = str(w["name"]).to_upper()
		_w_ammo.text = "%d / %d" % [player.mag_now(), player.reserve_now()]
		_reload_bar.visible = player.reload_left > 0.0 or player.heal_left > 0.0
		if player.reload_left > 0.0:
			_reload_bar.value = 100.0 * (1.0 - player.reload_left / float(w["reload"]))
	if player.heal_left > 0.0:
		_reload_bar.visible = true
		_reload_bar.value = 100.0 * (1.0 - player.heal_left / maxf(float(ItemDB.get_def(player.heal_item).get("time", 1.0)), 0.1))
	var sl: Array = []
	for i in 3:
		var wid := str(inv.weapons[i])
		var nm := "—" if wid == "" else ItemDB.item_name(wid)
		sl.append(("[%d] %s" % [i + 1, nm]) if i != player.slot else ("[%d] > %s" % [i + 1, nm]))
	_w_slots.text = "   ".join(sl)
	_w_heal.text = "[4] Bandagem x%d   [5] Kit x%d   Energético x%d" % [int(inv.items["bandage"]), int(inv.items["medkit"]), int(inv.items["energy"])]
	var it := player.nearest_item
	if it != null and is_instance_valid(it) and player.alive:
		var verb := "[%s]" % GameSettings.key_label("interact") if not GameSettings.touch_mode else "[PEGAR]"
		_prompt.text = "%s %s" % [verb, ItemDB.item_name(str(it.item_id))]
		_prompt.add_theme_color_override("font_color", ItemDB.rarity_color(str(it.item_id)))
	else:
		_prompt.text = ""
	if touch != null:
		touch.prompt_active = it != null
	_fps_l.text = ("%d FPS" % Engine.get_frames_per_second()) if bool(GameSettings.get_s("show_fps")) else ""
	_click_hint.visible = not GameSettings.touch_mode and not menu_open and player.alive and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and str(m.state) == "running"


# ----------------------------------------------------- controles de desenho (internos)
class CrosshairDraw extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.player == null:
			return
		var p := hud.player
		var c := size * 0.5
		var spread := 10.0 + Vector2(p.velocity.x, p.velocity.z).length() * 1.6 + (0.0 if p.want_aim else 6.0) + p._bloom * 26.0
		var col := Color(1, 1, 1, 0.9)
		if p.slot >= 0 and p.alive:
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * spread, c + d * (spread + 9.0), Color(0, 0, 0, 0.6), 4.0)
				draw_line(c + d * spread, c + d * (spread + 9.0), col, 2.0)
		draw_circle(c, 2.0, col)
		if hud.hit_t > 0.0:
			var k := Color(1, 0.25, 0.2, 1) if hud.hit_kill else Color(1, 1, 1, 1)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 8.0, c + d * 17.0, k, 3.0)
		for h in hud.hurt:
			var a: float = h["ang"] - PI * 0.5
			draw_arc(c, 120.0, a - 0.32, a + 0.32, 12, Color(1, 0.15, 0.1, float(h["t"])), 8.0)
		if hud.hurt_flash > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.0, 0.0, hud.hurt_flash * 0.35))


class CompassDraw extends Control:
	var hud: Hud

	func _draw() -> void:
		if hud == null or hud.m == null or hud.m.cam == null:
			return
		var heading := fposmod(-rad_to_deg(hud.m.cam.yaw), 360.0)
		var c := size.x * 0.5
		var ppd := size.x / 140.0
		var font := ThemeDB.fallback_font
		var names := {0: "N", 45: "NE", 90: "L", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}
		for a in range(0, 360, 15):
			var diff := wrapf(float(a) - heading, -180.0, 180.0)
			if absf(diff) > 68.0:
				continue
			var x := c + diff * ppd
			var major := names.has(a)
			draw_line(Vector2(x, size.y - 4), Vector2(x, size.y - (12 if major else 7)), Color(1, 1, 1, 0.7), 1.5)
			if major:
				draw_string(font, Vector2(x - 12, 12), str(names[a]), HORIZONTAL_ALIGNMENT_CENTER, 24, 14, UIKit.ACCENT if a == 0 else Color(1, 1, 1, 0.9))
		draw_line(Vector2(c, 0), Vector2(c, 5), UIKit.ACCENT, 2.0)
