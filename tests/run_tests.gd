extends SceneTree
## Testes automatizados do jogo. Execute (Godot 4.3+, após abrir o projeto uma vez no editor ou rodar --import):
##   godot --headless --path . --script res://tests/run_tests.gd
## Cobre: inicialização, persistência, personalização, inventário, loot, mapa/navegação, zona, uma PARTIDA
## SIMULADA só com bots até o fim, modo treinamento, perfis gráficos e arquivos de exportação.
## Código de saída 0 = tudo passou. Estes testes foram ESCRITOS mas só rodam onde há o executável do Godot.

var failures := 0
var checks := 0
var _save_backup := PackedByteArray()
var _had_save := false
var _progress := {}
var _match_result := {"ended": false, "winner": null}


func _initialize() -> void:
	print("== Operação Eclipse: testes automatizados ==")
	_backup_save()
	await _run()
	_restore_save()
	print("\n%d verificações, %d falha(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)


func ok(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [OK]    ", msg)
	else:
		failures += 1
		printerr("  [FALHA] ", msg)


func _on_progress(v: float, _m: String) -> void:
	_progress["n"] += 1
	if v < _progress["last"] - 0.001:
		_progress["monotonic"] = false
	_progress["last"] = v


func _on_match_ended(w: Node) -> void:
	_match_result["ended"] = true
	_match_result["winner"] = w


func _backup_save() -> void:
	var p := "user://operacao_eclipse_save.json"
	_had_save = FileAccess.file_exists(p)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(p)


func _restore_save() -> void:
	var p := "user://operacao_eclipse_save.json"
	if _had_save:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _run() -> void:
	_t_autoloads()
	_t_settings_and_save()
	_t_cosmetics()
	_t_inventory_and_items()
	_t_quality()
	_t_export_files()
	await _t_map_and_loot()
	_t_zone()
	await _t_training()
	await _t_simulated_match()


# ------------------------------------------------------------------ 1) inicialização
func _t_autoloads() -> void:
	print("\n[1] Inicialização / autoloads")
	for n in ["Events", "SaveSystem", "GameSettings", "AudioManager", "QualityManager", "SceneRouter"]:
		ok(root.get_node_or_null(n) != null, "autoload presente: " + n)
	ok(ResourceLoader.exists("res://scenes/boot.tscn"), "cena principal existe")
	for s in ["login/login", "lobby/lobby", "maps/classic_map_01/classic_map_01", "maps/training/training", "player/player", "bots/bot"]:
		var sc: PackedScene = load("res://scenes/%s.tscn" % s)
		ok(sc != null and sc.can_instantiate(), "cena carrega: " + s)
	var missing: Array = []
	for n in AudioManager.SOUNDS:
		if AudioManager.get_stream(n) == null:
			missing.append(n)
	ok(missing.is_empty(), "todos os sons carregam (faltando: %s)" % str(missing))
	for k in MaterialLibrary.DEFS:
		ok(MaterialLibrary.get_mat(k) != null, "material: " + k)


# ------------------------------------------------------------------ 2) configurações e save
func _t_settings_and_save() -> void:
	print("\n[2] Configurações e persistência")
	GameSettings.set_s("sens_h", 1.7)
	GameSettings.set_s("vol_music", 0.3)
	SaveSystem.set_profile("TesteBot", 3, false)
	var app: Dictionary = SaveSystem.customization().duplicate()
	app["top"] = 2
	app["hair"] = 4
	SaveSystem.set_customization(app)
	SaveSystem.save_data()
	SaveSystem.data = {}
	SaveSystem.data = SaveSystem._defaults()
	SaveSystem.load_data()
	ok(is_equal_approx(float(GameSettings.get_s("sens_h")), 1.7), "sensibilidade persistiu")
	ok(is_equal_approx(float(GameSettings.get_s("vol_music")), 0.3), "volume persistiu")
	ok(str(SaveSystem.profile()["name"]) == "TesteBot" and int(SaveSystem.profile()["avatar"]) == 3, "perfil persistiu")
	ok(int(SaveSystem.customization()["top"]) == 2 and int(SaveSystem.customization()["hair"]) == 4, "personalização persistiu")
	GameSettings.rebind("jump", KEY_J)
	ok(GameSettings.key_label("jump") == OS.get_keycode_string(KEY_J), "remapeamento de tecla")
	GameSettings.reset_defaults()
	ok(is_equal_approx(float(GameSettings.get_s("sens_h")), 1.0), "restaurar padrões")
	var xp0 := int(SaveSystem.profile()["xp"])
	SaveSystem.record_match(3, 4, 120.0, false, 200.0)
	ok(int(SaveSystem.profile()["xp"]) > xp0 and int(SaveSystem.stats()["matches"]) >= 1, "estatísticas e XP registrados")


# ------------------------------------------------------------------ 3) personalização
func _t_cosmetics() -> void:
	print("\n[3] Personagens e personalização")
	var bad := CosmeticsDB.sanitize({"body": 99, "hair": -4, "top": "x", "skin": 1000})
	ok(int(bad["body"]) < CosmeticsDB.BODIES.size() and int(bad["hair"]) >= 0, "sanitize corrige valores inválidos")
	var combos := 0
	var broken := 0
	for b in CosmeticsDB.BODIES.size():
		var rig := CharacterBuilder.compute_rig(CosmeticsDB.BODIES[b])
		for top in CosmeticsDB.TOPS.size():
			for bottom in CosmeticsDB.BOTTOMS.size():
				for head in CosmeticsDB.HEADWEAR.size():
					var app := CosmeticsDB.default_appearance()
					app["body"] = b
					app["top"] = top
					app["bottom"] = bottom
					app["head"] = head
					app["shoes"] = (top + bottom) % CosmeticsDB.SHOES.size()
					app["hair"] = (top + head) % CosmeticsDB.HAIR_STYLES.size()
					var m := CharacterBuilder.build_mesh(app, rig)
					combos += 1
					var arr := m.surface_get_arrays(0)
					if m.get_surface_count() == 0 or (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() % 3 != 0 or (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < 200:
						broken += 1
	ok(broken == 0, "%d combinações de roupa/corpo geram malha válida" % combos)
	var cm := CharacterModel.new()
	cm.setup(CosmeticsDB.default_appearance())
	root.add_child(cm)
	cm.set_weapon("rifle")
	for i in 30:
		cm.animator.speed = 5.0
		cm.animator.move = Vector2(0, 1)
		cm.animator.update(0.016)
	ok(cm.skeleton.get_bone_count() == 18 and cm.weapon_node != null, "esqueleto de 18 ossos + arma + animador executam")
	cm.queue_free()


# ------------------------------------------------------------------ 4) inventário e itens
func _t_inventory_and_items() -> void:
	print("\n[4] Inventário, armas e loot")
	var inv := Inventory.new()
	var r := inv.add("rifle", 1, 0)
	ok(r["ok"] and inv.weapons[0] == "rifle" and inv.ammo_count("medium") >= 30, "coletar arma adiciona munição")
	inv.add("pistol", 1, 0)
	inv.add("smg", 1, 0)
	var swap := inv.add("shotgun", 1, 1)
	ok(swap["ok"] and str(swap["swap"]) != "", "arma extra troca a equipada")
	ok(inv.add("vest_1", 1)["ok"] and not inv.add("vest_1", 1)["ok"], "colete não duplica")
	ok(inv.add("vest_3", 1)["ok"] and inv.vest_level == 3, "colete melhor substitui")
	var filled := 0
	for i in 40:
		if inv.add("medkit", 1)["ok"]:
			filled += 1
	ok(filled < 40 and inv.used() <= inv.capacity() + 1, "limite de capacidade respeitado (%d kits)" % filled)
	ok(inv.add("pack_2", 1)["ok"] and inv.capacity() == 18, "mochila aumenta a capacidade")
	for id in ItemDB.ITEMS:
		var d := ItemDB.get_def(id)
		if str(d["cat"]) == "weapon":
			ok(WeaponDB.WEAPONS.has(d["weapon"]), "arma do catálogo existe no WeaponDB: " + id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {}
	for i in 3000:
		var id := ItemDB.roll(rng, 2)
		counts[ItemDB.category(id)] = int(counts.get(ItemDB.category(id), 0)) + 1
	ok(counts.size() >= 5 and int(counts.get("weapon", 0)) > 300, "tabela de loot gera todas as categorias %s" % str(counts))


# ------------------------------------------------------------------ 5) qualidade
func _t_quality() -> void:
	print("\n[5] Perfis gráficos")
	for q in ["low", "medium", "high", "auto", "custom"]:
		GameSettings.set_s("quality", q)
		var e := QualityManager.effective()
		ok(float(e["render_scale"]) >= 0.4 and float(e["render_distance"]) > 100.0, "perfil aplicável: " + q)
	GameSettings.set_s("quality", "low")


# ------------------------------------------------------------------ 6) exportação
func _t_export_files() -> void:
	print("\n[6] Arquivos de exportação web")
	ok(FileAccess.file_exists("res://export_presets.cfg"), "export_presets.cfg presente")
	var shell := FileAccess.get_file_as_string("res://web/shell.html")
	ok(shell.contains("$GODOT_URL") and shell.contains("$GODOT_CONFIG") and shell.contains("onProgress"), "shell HTML com progresso real")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	ok(presets.contains("thread_support=false") and presets.contains("assets/audio/*.pcm"), "preset single-thread inclui áudio/texturas")


# ------------------------------------------------------------------ 7) mapa, navegação e loot
func _t_map_and_loot() -> void:
	print("\n[7] Mapa, navegação e distribuição de loot")
	var holder := Node3D.new()
	root.add_child(holder)
	_progress = {"n": 0, "last": 0.0, "monotonic": true}
	var gen := MapGenerator.new()
	var map: MapData = await gen.generate(holder, _on_progress, 4242)
	var progress := _progress
	ok(progress["n"] >= 10 and progress["monotonic"] and progress["last"] >= 0.99, "progresso de geração real e monotônico (%d etapas)" % progress["n"])
	ok(map.cities.size() == 3, "três cidades: " + ", ".join(map.cities.map(func(c): return c["name"])))
	ok(map.buildings.size() >= 40, "construções geradas: %d" % map.buildings.size())
	ok(map.roads.size() >= 9, "estradas: %d" % map.roads.size())
	ok(map.loot_points.size() >= 250, "pontos de loot: %d" % map.loot_points.size())
	ok(map.spawn_points.size() >= 16, "pontos de spawn: %d" % map.spawn_points.size())
	var floating := 0
	for pt in map.loot_points:
		var y: float = pt["pos"].y
		var gh := map.height_at(pt["pos"].x, pt["pos"].z)
		if y < gh - 0.2 or y > gh + 12.0:
			floating += 1
	ok(floating == 0, "nenhum item abaixo do solo ou flutuando alto demais (%d)" % floating)
	var reach := 0
	var tries := 0
	for i in range(0, mini(map.spawn_points.size() - 1, 12)):
		var p := map.nav.find_path(map.spawn_points[i], map.spawn_points[i + 1])
		tries += 1
		if not p.is_empty():
			reach += 1
	ok(reach >= tries - 1, "navegação conecta pontos de spawn (%d/%d)" % [reach, tries])
	var door_ok := 0
	var door_total := 0
	for b in map.buildings:
		if b.doors.is_empty() or b.rooms.is_empty():
			continue
		door_total += 1
		var inside := Vector3(b.rooms[0].get_center().x, b.ground, b.rooms[0].get_center().y)
		var p2 := map.nav.find_path(map.spawn_points[0], inside)
		if not p2.is_empty():
			door_ok += 1
	ok(door_total > 30 and door_ok >= door_total - 3, "rota da rua até o interior das construções (%d/%d)" % [door_ok, door_total])
	var loot := LootManager.new()
	holder.add_child(loot)
	var n := loot.populate(map, 16)
	var cats := loot.count_by_category()
	ok(n >= 250 and int(cats.get("weapon", 0)) >= 35 and int(cats.get("heal", 0)) >= 48, "loot distribuído com mínimos garantidos: %s" % str(cats))
	var it := loot.nearest(loot.items[0].global_position, 3.0)
	ok(it != null, "consulta espacial de loot")
	holder.queue_free()
	await process_frame


# ------------------------------------------------------------------ 8) zona
func _t_zone() -> void:
	print("\n[8] Zona segura")
	var z := ZoneController.new()
	root.add_child(z)
	z.start()
	var r0 := z.radius
	var min_r := r0
	for i in 500:
		z._process(1.0)
		min_r = minf(min_r, z.radius)
	ok(r0 > 400.0 and z.radius <= 0.5 and z.phase >= ZoneController.PHASES.size(), "a zona encolhe por todas as fases (raio final %.1f)" % z.radius)
	ok(z.inside(Vector2.ZERO, 0.0) == (z.radius >= 0.0 and z.center.length() <= z.radius), "teste de pertencimento coerente")
	z.queue_free()


# ------------------------------------------------------------------ 9) treinamento
func _t_training() -> void:
	print("\n[9] Modo treinamento")
	var scene: PackedScene = load("res://scenes/maps/training/training.tscn")
	var t: TrainingMatch = scene.instantiate()
	root.add_child(t)
	var guard := 0
	while t.state != "running" and guard < 600:
		await process_frame
		guard += 1
	ok(t.state == "running", "treino inicia (%d frames)" % guard)
	var targets := get_nodes_in_group("training_targets")
	ok(targets.size() >= 17, "alvos físicos existem no mundo: %d" % targets.size())
	var before := t.score
	var tg: TrainingTarget = null
	for x in targets:
		if (x as TrainingTarget).kind == "static":
			tg = x
			break
	tg.take_damage(10.0, t.player, tg.global_position + Vector3(0, tg.center_height, 0), false)
	ok(t.score > before, "acerto no centro soma pontos (%d)" % t.score)
	ok(t.player.slot >= 0 and t.player.weapon_id() != "", "jogador começa armado")
	t.mode = "bots"
	t._restart_current()
	for i in 40:
		await process_frame
	ok(t.bots.size() == 4 and t.bots[0].alive, "bots de treino em campo (%d)" % t.bots.size())
	t.queue_free()
	await process_frame


# ------------------------------------------------------------------ 10) partida simulada
func _t_simulated_match() -> void:
	print("\n[10] Partida simulada só com bots (até o fim)")
	ClassicMatch.autoplay_next = true
	ClassicMatch.bots_override = 10
	var scene: PackedScene = load("res://scenes/maps/classic_map_01/classic_map_01.tscn")
	var m: ClassicMatch = scene.instantiate()
	_match_result = {"ended": false, "winner": null}
	Events.match_ended.connect(_on_match_ended)
	root.add_child(m)
	var t0 := Time.get_ticks_msec()
	Engine.time_scale = 12.0
	var frames := 0
	while not _match_result["ended"] and Time.get_ticks_msec() - t0 < 600000 and frames < 200000:
		await process_frame
		frames += 1
		if frames % 600 == 0:
			print("    ... t=%.0fs vivos=%d zona=%.0fm" % [m.elapsed, m.alive_count, m.zone.radius if m.zone != null else -1.0])
	Engine.time_scale = 1.0
	Events.match_ended.disconnect(_on_match_ended)
	ok(m.state != "loading", "mapa completo carregou e a partida iniciou")
	ok(_match_result["ended"], "a partida atingiu uma condição válida de encerramento (%.0f s simulados)" % m.elapsed)
	ok(_match_result["winner"] != null and m.count_alive() <= 1, "há um vencedor / no máximo 1 sobrevivente")
	var any_loot := false
	for p in m.participants:
		if is_instance_valid(p) and p.has_method("has_usable_weapon") and (p.kills > 0 or p.inv.has_any_weapon()):
			any_loot = true
	ok(any_loot, "bots coletaram equipamentos e/ou eliminaram adversários")
	m.queue_free()
	await process_frame
