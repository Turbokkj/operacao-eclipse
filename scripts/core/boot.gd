extends Node
## Inicialização: tema global, configurações, áudio e materiais. A barra de progresso reflete etapas REAIS
## (cada arquivo de áudio/textura carregado conta). Em caso de arquivo ausente exibe aviso e continua.

func _ready() -> void:
	get_tree().root.theme = ThemeFactory.build()
	SceneRouter.show_loading("Inicializando")
	await get_tree().process_frame
	await _boot()


func _boot() -> void:
	var steps: Array = []
	steps.append(["Aplicando configurações", func(): GameSettings.apply_all()])
	for n in AudioManager.SOUNDS:
		steps.append(["Carregando áudio: %s" % n, AudioManager.get_stream.bind(n)])
	for n in ["music_menu", "amb_field", "amb_city"]:
		steps.append(["Carregando trilha: %s" % n, AudioManager.get_stream.bind(n)])
	for k in MaterialLibrary.DEFS:
		steps.append(["Preparando material: %s" % k, MaterialLibrary.get_mat.bind(k)])
	steps.append(["Preparando terreno", func(): MaterialLibrary.terrain_mat()])
	steps.append(["Preparando personagens", func(): _warm_character()])
	var total := steps.size()
	for i in total:
		SceneRouter.report(float(i) / total, str(steps[i][0]))
		var fn: Callable = steps[i][1]
		fn.call()
		if i % 6 == 0:
			await get_tree().process_frame
	var problems: Array = []
	if AudioManager.missing.size() > 0:
		problems.append("%d arquivos de áudio ausentes (rode tools/gen_audio.py)" % AudioManager.missing.size())
	SceneRouter.report(1.0, "Pronto")
	if not problems.is_empty():
		push_warning("Boot: " + "; ".join(problems))
		SceneRouter.overlay.show_error("Aviso: " + "; ".join(problems))
		await get_tree().create_timer(2.5).timeout
	else:
		await get_tree().create_timer(0.35).timeout
	if SaveSystem.has_profile():
		SceneRouter.go_lobby()
	else:
		SceneRouter.go_login()


func _warm_character() -> void:
	var rig := CharacterBuilder.compute_rig(CosmeticsDB.BODIES[0])
	CharacterBuilder.build_mesh(CosmeticsDB.default_appearance(), rig)
