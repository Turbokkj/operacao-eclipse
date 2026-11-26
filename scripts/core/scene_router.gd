extends Node
## Troca de cenas com tela de carregamento / fade e fluxo login -> lobby -> partida -> lobby.

const SCENE_LOGIN := "res://scenes/login/login.tscn"
const SCENE_LOBBY := "res://scenes/lobby/lobby.tscn"
const SCENE_CLASSIC := "res://scenes/maps/classic_map_01/classic_map_01.tscn"
const SCENE_TRAINING := "res://scenes/maps/training/training.tscn"
const SCENE_ONLINE := "res://scenes/maps/online/online_map.tscn"

var overlay: LoadingOverlay
var current_mode := "classic"
var busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = LoadingOverlay.new()
	add_child(overlay)
	overlay.hide_immediately()
	Events.loading_progress.connect(_on_progress)


func _on_progress(v: float, msg: String) -> void:
	overlay.set_progress(v, msg)


func show_loading(title: String) -> void:
	overlay.show_overlay(title)


func report(v: float, msg: String) -> void:
	Events.loading_progress.emit(v, msg)


func hide_loading() -> void:
	overlay.hide_overlay()


func go_login() -> void:
	await _goto(SCENE_LOGIN, true)


func go_lobby() -> void:
	await _goto(SCENE_LOBBY, true)


func start_mode(mode: String) -> void:
	current_mode = mode
	show_loading("Preparando partida")
	report(0.0, "Verificando modo de jogo")
	await get_tree().process_frame
	await _goto(SCENE_CLASSIC if mode == "classic" else SCENE_TRAINING, false)


func start_online() -> void:
	current_mode = "online"
	show_loading("Entrando na partida online")
	report(0.0, "Preparando a partida")
	await get_tree().process_frame
	await _goto(SCENE_ONLINE, false)


func _goto(path: String, with_fade: bool) -> void:
	if busy:
		return
	busy = true
	get_tree().paused = false
	GameSettings.clear_touch_state()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	QualityManager.unregister_world()
	if with_fade:
		await overlay.fade_to(1.0, 0.22)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		overlay.show_error("Não foi possível carregar a cena: " + path)
		busy = false
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if with_fade:
		overlay.hide_overlay()
		await overlay.fade_to(0.0, 0.25)
	busy = false
