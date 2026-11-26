extends Node
## Camada de áudio: barramentos (Música/Efeitos/Ambiente), cache de sons PCM gerados por
## tools/gen_audio.py (originais, sem material protegido) e reprodução 2D/3D com pool.

const RATE := 22050
const AUDIO_DIR := "res://assets/audio/"
const SOUNDS := ["ui_click", "ui_back", "ui_confirm", "pickup", "equip", "empty", "reload", "heal",
	"shot_pistol", "shot_smg", "shot_rifle", "shot_shotgun", "shot_dmr", "hit", "hit_confirm", "hurt",
	"step_a", "step_b", "jump", "land", "zone_warning", "countdown", "go", "win", "lose", "death",
	"music_menu", "amb_city", "amb_field"]

var missing: Array = []
var _cache := {}
var _players: Array = []
var _players3d: Array = []
var _music: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _music_name := ""
var _amb_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambient")
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	for i in 20:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.max_distance = 80.0
		p3.unit_size = 10.0
		add_child(p3)
		_players3d.append(p3)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Ambient"
	add_child(_amb)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func apply_volumes() -> void:
	_set_bus("Master", float(GameSettings.get_s("vol_master")))
	_set_bus("Music", float(GameSettings.get_s("vol_music")))
	_set_bus("SFX", float(GameSettings.get_s("vol_sfx")))
	_set_bus("Ambient", float(GameSettings.get_s("vol_ambient")))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


func get_stream(sname: String) -> AudioStreamWAV:
	if _cache.has(sname):
		return _cache[sname]
	var path := AUDIO_DIR + sname + ".pcm"
	if not FileAccess.file_exists(path):
		_cache[sname] = null
		if not missing.has(sname):
			missing.append(sname)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[sname] = null
		return null
	var bytes := f.get_buffer(f.get_length())
	f.close()
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if sname.begins_with("music_") or sname.begins_with("amb_"):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = bytes.size() / 2
	_cache[sname] = s
	return s


func play_sfx(sname: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := get_stream(sname)
	if s == null:
		return
	var chosen: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _players[0]
	chosen.stream = s
	chosen.volume_db = vol_db
	chosen.pitch_scale = pitch
	chosen.play()


func play_sfx_3d(sname: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0, max_dist: float = 80.0) -> void:
	var s := get_stream(sname)
	if s == null:
		return
	var chosen: AudioStreamPlayer3D = null
	for p in _players3d:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _players3d[0]
	chosen.stream = s
	chosen.global_position = pos
	chosen.volume_db = vol_db
	chosen.pitch_scale = pitch
	chosen.max_distance = max_dist
	chosen.play()


func play_music(sname: String) -> void:
	if _music_name == sname and _music.playing:
		return
	var s := get_stream(sname)
	if s == null:
		return
	_music_name = sname
	_music.stream = s
	_music.play()


func stop_music() -> void:
	_music.stop()
	_music_name = ""


func play_ambient(sname: String) -> void:
	if _amb_name == sname and _amb.playing:
		return
	var s := get_stream(sname)
	if s == null:
		return
	_amb_name = sname
	_amb.stream = s
	_amb.play()


func stop_ambient() -> void:
	_amb.stop()
	_amb_name = ""
