extends SceneTree
## Smoke test do modo clássico para builds CI/headless.
## Confirma que a geração termina e que mapa, pontos de spawn, jogador e bots existem.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/maps/classic_map_01/classic_map_01.tscn")
	if packed == null:
		printerr("SMOKE CLASSIC FAILED: não foi possível carregar a cena clássica.")
		quit(1)
		return

	var game = packed.instantiate()
	root.add_child(game)
	var started := Time.get_ticks_msec()
	var timeout_ms := 180000
	while game.state == "loading" and Time.get_ticks_msec() - started < timeout_ms:
		await process_frame

	if game.state == "loading":
		printerr("SMOKE CLASSIC FAILED: mapa ainda está carregando após %d ms." % timeout_ms)
		quit(1)
		return

	var bot_count := 0
	for participant in game.participants:
		if participant is Bot:
			bot_count += 1

	var errors: Array[String] = []
	if game.map == null:
		errors.append("MapData não foi criado")
	elif game.map.spawn_points.size() < 16:
		errors.append("pontos de spawn insuficientes: %d" % game.map.spawn_points.size())
	if game.player == null:
		errors.append("jogador não foi instanciado")
	if bot_count < 1:
		errors.append("nenhum bot foi instanciado")
	if game.participants.size() != bot_count + 1:
		errors.append("contagem de participantes inconsistente: %d" % game.participants.size())

	if not errors.is_empty():
		printerr("SMOKE CLASSIC FAILED: " + "; ".join(errors))
		quit(1)
		return

	print("SMOKE CLASSIC OK: mapa gerado, %d spawns, %d bots e jogador instanciados em %d ms." % [
		game.map.spawn_points.size(), bot_count, Time.get_ticks_msec() - started
	])
	game.queue_free()
	await process_frame
	quit(0)
