class_name OnlinePanel
extends PanelContainer
## Painel ONLINE do lobby: conectar ao servidor, partida rápida (espera de ~15 s, bots completam as vagas),
## criar sala personalizada (código para os amigos) ou entrar por código.

signal closed

var _box: VBoxContainer
var _status: Label
var _url: LineEdit
var _code: LineEdit
var _bar: ProgressBar
var _queue_label: Label
var _cfg_label: Label
var _room_sig := ""
var _view := ""
var _cfg := {"capacity": 8, "fill_bots": true, "difficulty": "mixed"}


func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.style(Color(0.04, 0.05, 0.08, 0.92), 18, Color(1, 1, 1, 0.08), 1, 16))
	custom_minimum_size = Vector2(470, 0)
	_box = UIKit.vbox(8)
	add_child(_box)
	NetClient.connected.connect(_show_menu)
	NetClient.disconnected.connect(_on_disconnected)
	NetClient.server_message.connect(_on_msg)
	if NetClient.online:
		_show_menu()
	else:
		_show_connect("")


func _exit_tree() -> void:
	for pair in [[NetClient.connected, _show_menu], [NetClient.disconnected, _on_disconnected], [NetClient.server_message, _on_msg]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _reset(title: String, view: String) -> void:
	_view = view
	for c in _box.get_children():
		c.queue_free()
	_box.add_child(UIKit.label(title, 24, UIKit.ACCENT))


func _finish_view() -> void:
	_status = UIKit.label("", 15, UIKit.BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(430, 0)
	_box.add_child(_status)


func _close() -> void:
	closed.emit()


func _show_connect(msg: String) -> void:
	_reset("JOGAR ONLINE", "connect")
	_box.add_child(UIKit.label("Endereço do servidor de partidas:", 15, UIKit.MUTED))
	_url = LineEdit.new()
	_url.text = NetClient.default_url()
	_url.placeholder_text = "wss://seu-servidor.exemplo.com"
	_url.custom_minimum_size = Vector2(0, 44)
	_box.add_child(_url)
	_box.add_child(UIKit.button("CONECTAR", _connect, Vector2(0, 50), true))
	_box.add_child(UIKit.button("FECHAR", _close, Vector2(0, 42)))
	_finish_view()
	_status.text = msg


func _connect() -> void:
	_status.text = "Conectando…"
	if not NetClient.connect_to_server(_url.text):
		_status.text = NetClient.last_error


func _on_disconnected(reason: String) -> void:
	_show_connect(reason)


func _show_menu() -> void:
	_reset("JOGAR ONLINE", "menu")
	_box.add_child(UIKit.label("Conectado como %s" % str(SaveSystem.profile().get("name", "Jogador")), 16, UIKit.GOOD))
	_box.add_child(UIKit.button("PARTIDA RÁPIDA (espera 15 s, bots completam)", NetClient.quick_match, Vector2(0, 52), true, 16))
	_box.add_child(UIKit.button("CRIAR SALA PERSONALIZADA", NetClient.create_room.bind(_cfg), Vector2(0, 48)))
	var row := UIKit.hbox(8)
	_code = LineEdit.new()
	_code.placeholder_text = "CÓDIGO"
	_code.max_length = 5
	_code.custom_minimum_size = Vector2(150, 44)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_code)
	row.add_child(UIKit.button("ENTRAR NA SALA", _join, Vector2(190, 44)))
	_box.add_child(row)
	_box.add_child(UIKit.button("DESCONECTAR", _disconnect, Vector2(0, 42), false, 15))
	_finish_view()


func _join() -> void:
	NetClient.join_room(_code.text)


func _disconnect() -> void:
	NetClient.disconnect_from_server()
	_show_connect("")


func _show_queue(m: Dictionary) -> void:
	if _view != "queue":
		_reset("PARTIDA RÁPIDA", "queue")
		_queue_label = UIKit.label("", 18, UIKit.TEXT)
		_box.add_child(_queue_label)
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(0, 16)
		_bar.max_value = NetClient.mm_wait
		_box.add_child(_bar)
		_box.add_child(UIKit.label("Se faltar gente, bots completam as vagas até 16.", 14, UIKit.MUTED))
		_box.add_child(UIKit.button("CANCELAR", NetClient.cancel, Vector2(0, 46)))
		_finish_view()
	var left := int(m["seconds_left"])
	_queue_label.text = "Procurando jogadores… %d/%d  —  começa em %d s" % [int(m["players"]), int(m["capacity"]), left]
	_bar.value = NetClient.mm_wait - float(left)


func _show_room(m: Dictionary) -> void:
	var ids: Array = []
	for p in m["players"]:
		ids.append(int(p["id"]))
	var sig := "%s|%s|%d" % [str(m["code"]), str(ids), int(m["host"])]
	var cfg: Dictionary = m["cfg"]
	_cfg = cfg
	if _view == "room" and sig == _room_sig:
		_cfg_label.text = _cfg_text()
		return
	_room_sig = sig
	var is_host := int(m["host"]) == NetClient.my_id
	_reset("SALA %s" % str(m["code"]), "room")
	_box.add_child(UIKit.button("COPIAR CÓDIGO (envie aos amigos)", DisplayServer.clipboard_set.bind(str(m["code"])), Vector2(0, 40), false, 15))
	for p in m["players"]:
		var tag := "  (dono)" if int(p["id"]) == int(m["host"]) else ""
		_box.add_child(UIKit.label("• %s%s" % [str(p["name"]), tag], 17, UIKit.TEXT))
	_cfg_label = UIKit.label(_cfg_text(), 15, UIKit.MUTED)
	_box.add_child(_cfg_label)
	if is_host:
		_box.add_child(UIKit.slider_row("Vagas (jogadores + bots)", 2.0, 16.0, 1.0, float(cfg["capacity"]), _on_cap, "%d"))
		_box.add_child(UIKit.check_row("Completar vagas com bots", bool(cfg["fill_bots"]), _on_fill))
		var diffs := ["mixed", "beginner", "intermediate", "advanced"]
		_box.add_child(UIKit.option_row("Dificuldade dos bots", ["Mista", "Iniciante", "Intermediário", "Avançado"], maxi(diffs.find(str(cfg["difficulty"])), 0), _on_diff))
		_box.add_child(UIKit.button("INICIAR PARTIDA", NetClient.start_room, Vector2(0, 52), true))
	else:
		_box.add_child(UIKit.label("Aguardando o dono iniciar a partida…", 15, UIKit.MUTED))
	_box.add_child(UIKit.button("SAIR DA SALA", NetClient.leave_room, Vector2(0, 42)))
	_finish_view()


func _cfg_text() -> String:
	return "Vagas: %d | Bots: %s | Dificuldade: %s" % [int(_cfg["capacity"]), "sim" if bool(_cfg["fill_bots"]) else "não", str(_cfg["difficulty"])]


func _on_cap(x: float) -> void:
	_cfg["capacity"] = int(x)
	NetClient.update_cfg(_cfg)


func _on_fill(on: bool) -> void:
	_cfg["fill_bots"] = on
	NetClient.update_cfg(_cfg)


func _on_diff(i: int) -> void:
	_cfg["difficulty"] = ["mixed", "beginner", "intermediate", "advanced"][i]
	NetClient.update_cfg(_cfg)


func _on_msg(m: Dictionary) -> void:
	match str(m.get("t", "")):
		"queue":
			_show_queue(m)
		"room":
			_show_room(m)
		"left":
			_show_menu()
		"error":
			if _status != null:
				_status.text = str(m.get("msg", "Erro"))
		"start":
			SceneRouter.start_online()
