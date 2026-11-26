class_name LootManager
extends Node
## Distribuição procedural e gerenciamento do loot: pontos ligados às construções, níveis de riqueza por
## cidade, garantia de quantidades mínimas, variação entre partidas e consultas espaciais (grade).
## Grupo "loot_manager": combatentes chamam drop_from()/drop_item() ao morrer ou trocar de arma.

const CELL := 12.0

signal spawned(item)
signal removed(item)

var by_uid := {}
var _next_uid := 1
var map: MapData
var rng := RandomNumberGenerator.new()
var items: Array = []
var viewer: Node3D
var _grid := {}
var _t := 0.0


func _ready() -> void:
	add_to_group("loot_manager")
	rng.randomize()


func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func spawn(id: String, qty: int, pos: Vector3, bot_ok: bool = true) -> LootItem:
	var it := LootItem.new()
	add_child(it)
	it.setup(id, qty, bot_ok)
	it.global_position = pos
	it.uid = _next_uid
	_next_uid += 1
	by_uid[it.uid] = it
	items.append(it)
	var k := _key(pos)
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(it)
	spawned.emit(it)
	return it


## Cliente online: cria um item com o uid definido pelo host (sem sorteio local).
func spawn_remote(uid: int, id: String, qty: int, pos: Vector3, bot_ok: bool = true) -> LootItem:
	var it := spawn(id, qty, pos, bot_ok)
	by_uid.erase(it.uid)
	it.uid = uid
	by_uid[uid] = it
	return it


func remove_item(it: Node) -> void:
	if it == null or not is_instance_valid(it):
		return
	var li := it as LootItem
	li.picked = true
	by_uid.erase(li.uid)
	removed.emit(li)
	items.erase(li)
	var k := _key(li.global_position)
	if _grid.has(k):
		_grid[k].erase(li)
	li.queue_free()


func query(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var c0 := _key(pos - Vector3(radius, 0, radius))
	var c1 := _key(pos + Vector3(radius, 0, radius))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var k := Vector2i(cx, cz)
			if _grid.has(k):
				for it in _grid[k]:
					if is_instance_valid(it) and not it.picked and it.global_position.distance_to(pos) <= radius:
						out.append(it)
	return out


func nearest(pos: Vector3, radius: float) -> LootItem:
	var best: LootItem = null
	var bd := radius + 1.0
	for it in query(pos, radius):
		var d := (it as LootItem).global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = it
	return best


func _ground(pos: Vector3) -> Vector3:
	if map != null:
		return Vector3(pos.x, maxf(pos.y, map.height_at(pos.x, pos.z) + 0.35), pos.z)
	return pos


func drop_item(id: String, qty: int, pos: Vector3) -> void:
	var a := rng.randf() * TAU
	var p := _ground(pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.5, 1.2))
	spawn(id, qty, p)


## Derruba o equipamento de um combatente eliminado (armas, munição, cura, proteções).
func drop_from(c: Node) -> void:
	var cb := c as Combatant
	if cb == null:
		return
	var inv := cb.inv
	var base := cb.global_position + Vector3(0, 0.4, 0)
	for w in inv.weapons:
		if str(w) != "":
			drop_item(str(w), 1, base)
	for k in inv.ammo:
		if int(inv.ammo[k]) > 0:
			drop_item("ammo_" + str(k), int(inv.ammo[k]), base)
	for k in inv.items:
		if int(inv.items[k]) > 0:
			drop_item(str(k), int(inv.items[k]), base)
	if inv.vest_level > 0 and inv.vest_hp > 10.0:
		drop_item("vest_%d" % inv.vest_level, 1, base)
	if inv.helmet_level > 0:
		drop_item("helmet_%d" % inv.helmet_level, 1, base)
	if inv.pack_level > 0:
		drop_item("pack_%d" % inv.pack_level, 1, base)
	if inv.suppressor:
		drop_item("suppressor", 1, base)


## Distribui o loot do mapa. Retorna o total de itens gerados.
func populate(p_map: MapData, participants: int) -> int:
	map = p_map
	rng.randomize()
	var boosts := {
		"aurora": {"weapon": 1.15, "acc": 1.5},
		"valeverde": {"heal": 1.5, "pack": 1.4},
		"porto": {"armor": 1.4, "ammo": 1.4},
		"wild": {"ammo": 1.1},
	}
	for pt in map.loot_points:
		var city := str(pt.get("city", "wild"))
		var id := ItemDB.roll(rng, int(pt.get("tier", 0)), boosts.get(city, {}))
		spawn(id, ItemDB.default_qty(id), pt["pos"], bool(pt.get("bot_ok", true)))
	# quantidades mínimas por categoria (recursos suficientes para a partida)
	var minimum := {"weapon": int(participants * 2.2), "ammo": int(participants * 2.5), "heal": int(participants * 3.0),
		"armor": int(participants * 1.2), "pack": int(participants * 0.5)}
	var counts := count_by_category()
	var pool: Array = map.loot_points
	if pool.is_empty():
		return items.size()
	for cat in minimum:
		var tries := 0
		while int(counts.get(cat, 0)) < int(minimum[cat]) and tries < 400:
			tries += 1
			var pt: Dictionary = pool[rng.randi() % pool.size()]
			var id := _roll_category(cat, int(pt.get("tier", 0)))
			if id == "":
				break
			if bool(pt.get("indoor", true)) == false and cat == "pack":
				continue
			var off := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
			spawn(id, ItemDB.default_qty(id), _ground(pt["pos"] + off), bool(pt.get("bot_ok", true)))
			counts[cat] = int(counts.get(cat, 0)) + 1
	return items.size()


func _roll_category(cat: String, tier: int) -> String:
	var total := 0.0
	for id in ItemDB.LOOT_TABLE:
		if ItemDB.category(id) == cat:
			total += float(ItemDB.LOOT_TABLE[id][clampi(tier, 0, 2)]) + 0.2
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for id in ItemDB.LOOT_TABLE:
		if ItemDB.category(id) == cat:
			r -= float(ItemDB.LOOT_TABLE[id][clampi(tier, 0, 2)]) + 0.2
			if r <= 0.0:
				return id
	return ""


func count_by_category() -> Dictionary:
	var out := {}
	for it in items:
		if is_instance_valid(it) and not it.picked:
			var c := ItemDB.category(it.item_id)
			out[c] = int(out.get(c, 0)) + 1
	return out


func _process(delta: float) -> void:
	if viewer == null or not is_instance_valid(viewer):
		return
	_t += delta
	var c := _key(viewer.global_position)
	for cx in range(c.x - 3, c.x + 4):
		for cz in range(c.y - 3, c.y + 4):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				continue
			for it in _grid[k]:
				if is_instance_valid(it) and it.visual != null:
					it.visual.rotation.y += delta * 1.3
					it.visual.position.y = sin(_t * 2.0 + it.phase) * 0.06
