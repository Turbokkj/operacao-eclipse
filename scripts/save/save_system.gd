extends Node
## Persistência local em JSON (user://). A API é isolada para permitir trocar por um
## backend/autenticação real no futuro sem alterar o restante do jogo.

const SAVE_PATH := "user://operacao_eclipse_save.json"
const SAVE_VERSION := 1

var data: Dictionary = {}
var _dirty := false
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = _defaults()
	load_data()


func _defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile": {"name": "", "avatar": 0, "guest": false, "xp": 0},
		"customization": CosmeticsDB.default_appearance(),
		"settings": {},
		"controls": {},
		"hud_layout": {},
		"stats": {"matches": 0, "wins": 0, "kills": 0, "best_place": 0, "play_time": 0.0,
			"damage": 0.0, "train_shots": 0, "train_hits": 0, "train_best": 0},
		"prefs": {"mode": "classic", "bots": 15, "difficulty": "mixed", "training": "free"},
	}


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveSystem: não foi possível abrir o arquivo de save.")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_merge(data, parsed)
	else:
		push_warning("SaveSystem: save corrompido; usando valores padrão.")


func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveSystem: falha ao gravar o save.")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_dirty = false


func mark_dirty() -> void:
	_dirty = true
	_timer = 0.8


func _process(delta: float) -> void:
	if _dirty:
		_timer -= delta
		if _timer <= 0.0:
			save_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_data()


func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]


# ---- Acesso por seção -------------------------------------------------------
func profile() -> Dictionary:
	return data["profile"]


func customization() -> Dictionary:
	return CosmeticsDB.sanitize(data["customization"])


func settings_dict() -> Dictionary:
	return data["settings"]


func stats() -> Dictionary:
	return data["stats"]


func prefs() -> Dictionary:
	return data["prefs"]


func has_profile() -> bool:
	return str(data["profile"]["name"]).strip_edges() != ""


func set_profile(pname: String, avatar: int, guest: bool) -> void:
	data["profile"]["name"] = pname.strip_edges().substr(0, 16)
	data["profile"]["avatar"] = avatar
	data["profile"]["guest"] = guest
	save_data()
	Events.profile_changed.emit()


func set_customization(app: Dictionary) -> void:
	data["customization"] = CosmeticsDB.sanitize(app)
	save_data()
	Events.profile_changed.emit()


func level() -> int:
	return 1 + int(data["profile"]["xp"]) / 100


func add_xp(amount: int) -> void:
	data["profile"]["xp"] = int(data["profile"]["xp"]) + amount
	mark_dirty()


func record_match(place: int, kills: int, survived: float, won: bool, dmg: float) -> int:
	var s: Dictionary = data["stats"]
	s["matches"] = int(s["matches"]) + 1
	s["kills"] = int(s["kills"]) + kills
	s["play_time"] = float(s["play_time"]) + survived
	s["damage"] = float(s["damage"]) + dmg
	if won:
		s["wins"] = int(s["wins"]) + 1
	var best: int = int(s["best_place"])
	if best == 0 or place < best:
		s["best_place"] = place
	var gained := 20 + maxi(0, 17 - place) * 5 + kills * 10 + (50 if won else 0)
	add_xp(gained)
	save_data()
	return gained


func reset_all() -> void:
	data = _defaults()
	save_data()
	Events.profile_changed.emit()
	Events.settings_changed.emit()
