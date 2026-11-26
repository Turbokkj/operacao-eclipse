extends Node
## Cliente do servidor de partidas ONLINE (server/server.js) via WebSocketPeer (funciona no navegador).
## Protocolo: mensagens JSON {t: tipo, ...}. Em partida, o jogador "host" roda a simulação e o servidor só
## repassa mensagens: to_host() / to_all() / to_peer() embrulham em {t:"relay", to, d}.

signal connected
signal disconnected(reason: String)
signal server_message(msg: Dictionary)
signal relayed(from_id: int, data: Dictionary)

const PROTOCOL := 1
const CONNECT_TIMEOUT := 10.0

var ws: WebSocketPeer
var url := ""
var my_id := 0
var online := false              # handshake concluído (recebeu "welcome")
var in_match := false
var session: Dictionary = {}
var rtt_ms := 0
var mm_wait := 15.0
var last_error := ""
var _connecting := false
var _hello_sent := false
var _t_connect := 0.0
var _t_ping := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## URL padrão: preferência salva > parâmetro ?server= (web) > res://server_url.txt
func default_url() -> String:
	var saved := str(SaveSystem.prefs().get("server_url", "")).strip_edges()
	if saved != "":
		return saved
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('server') || ''", true)
		if q != null and str(q).strip_edges() != "":
			return str(q).strip_edges()
	if FileAccess.file_exists("res://server_url.txt"):
		for line in FileAccess.get_file_as_string("res://server_url.txt").split("\n"):
			var l := line.strip_edges()
			if l != "" and not l.begins_with("#"):
				return l
	return ""


static func normalize_url(u: String) -> String:
	var s := u.strip_edges()
	if s == "":
		return ""
	if s.begins_with("https://"):
		s = "wss://" + s.substr(8)
	elif s.begins_with("http://"):
		s = "ws://" + s.substr(7)
	elif not s.begins_with("ws://") and not s.begins_with("wss://"):
		s = ("ws://" if (s.begins_with("localhost") or s.begins_with("127.")) else "wss://") + s
	return s.rstrip("/")


func connect_to_server(p_url: String) -> bool:
	disconnect_from_server()
	url = normalize_url(p_url)
	if url == "":
		last_error = "Informe o endereço do servidor."
		return false
	SaveSystem.prefs()["server_url"] = p_url.strip_edges()
	SaveSystem.mark_dirty()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 18
	ws.outbound_buffer_size = 1 << 18
	ws.max_queued_packets = 4096
	var err := ws.connect_to_url(url)
	if err != OK:
		last_error = "Não foi possível iniciar a conexão (erro %d)." % err
		ws = null
		return false
	_connecting = true
	_hello_sent = false
	online = false
	_t_connect = 0.0
	last_error = ""
	set_process(true)
	return true


func disconnect_from_server() -> void:
	if ws != null:
		ws.close(1000, "bye")
	ws = null
	online = false
	in_match = false
	_connecting = false
	set_process(false)


func send_msg(d: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))


func to_host(d: Dictionary) -> void:
	send_msg({"t": "relay", "to": "host", "d": d})


func to_all(d: Dictionary) -> void:
	send_msg({"t": "relay", "to": "all", "d": d})


func to_peer(id: int, d: Dictionary) -> void:
	send_msg({"t": "relay", "to": id, "d": d})


func quick_match() -> void:
	send_msg({"t": "quick"})


func cancel() -> void:
	send_msg({"t": "cancel"})


func create_room(cfg: Dictionary) -> void:
	send_msg({"t": "create", "cfg": cfg})


func join_room(code: String) -> void:
	send_msg({"t": "join", "code": code})


func leave_room() -> void:
	in_match = false
	send_msg({"t": "leave"})


func update_cfg(cfg: Dictionary) -> void:
	send_msg({"t": "cfg", "cfg": cfg})


func start_room() -> void:
	send_msg({"t": "start"})


func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_CONNECTING:
		_t_connect += delta
		if _t_connect > CONNECT_TIMEOUT:
			last_error = "Tempo esgotado ao conectar ao servidor."
			_drop(last_error)
		return
	if st == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_hello_sent = true
			send_msg({"t": "hello", "v": PROTOCOL, "name": str(SaveSystem.profile().get("name", "Jogador")),
				"app": SaveSystem.customization()})
		while ws != null and ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			_on_text(pkt.get_string_from_utf8())
		if ws != null:
			_t_ping += delta
			if _t_ping >= 5.0:
				_t_ping = 0.0
				send_msg({"t": "ping", "ts": Time.get_ticks_msec()})
	elif st == WebSocketPeer.STATE_CLOSED:
		var reason := "Conexão encerrada (%d)." % ws.get_close_code()
		if _connecting and not online:
			reason = "Não foi possível conectar ao servidor. Verifique o endereço e se ele está no ar."
		_drop(reason)


func _drop(reason: String) -> void:
	var was := online or _connecting
	ws = null
	online = false
	_connecting = false
	in_match = false
	set_process(false)
	if was:
		disconnected.emit(reason)


func _on_text(txt: String) -> void:
	var m: Variant = JSON.parse_string(txt)
	if not (m is Dictionary):
		return
	var d: Dictionary = m
	var t := str(d.get("t", ""))
	match t:
		"relay":
			relayed.emit(int(d.get("from", 0)), d.get("d", {}))
			return
		"welcome":
			my_id = int(d["id"])
			mm_wait = float(d.get("mm_wait", 15000)) / 1000.0
			online = true
			_connecting = false
			connected.emit()
		"pong":
			rtt_ms = Time.get_ticks_msec() - int(d.get("ts", 0))
			return
		"start":
			session = d
			in_match = true
	server_message.emit(d)
