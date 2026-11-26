class_name ItemDB
extends RefCounted
## Catálogo de itens (categorias: weapon, ammo, heal, armor, pack, acc) e tabelas de loot por nível.

const RARITY_NAMES := ["Comum", "Incomum", "Raro", "Épico"]
const RARITY_COLORS := [Color(0.85, 0.87, 0.92), Color(0.40, 0.90, 0.50), Color(0.35, 0.65, 1.0), Color(0.75, 0.45, 1.0)]
const CAT_NAMES := {"weapon": "Armas", "ammo": "Munição", "heal": "Cura", "armor": "Proteção", "pack": "Mochilas", "acc": "Acessórios"}
const CAT_ORDER := ["weapon", "ammo", "heal", "armor", "pack", "acc"]

const ITEMS := {
	"pistol": {"cat": "weapon", "name": "Pulsar P9", "rarity": 0, "weapon": "pistol"},
	"smg": {"cat": "weapon", "name": "Vespa SMG-7", "rarity": 1, "weapon": "smg"},
	"rifle": {"cat": "weapon", "name": "Falcon AR-4", "rarity": 2, "weapon": "rifle"},
	"shotgun": {"cat": "weapon", "name": "Trovão-12", "rarity": 1, "weapon": "shotgun"},
	"dmr": {"cat": "weapon", "name": "Lince DMR", "rarity": 3, "weapon": "dmr"},
	"ammo_light": {"cat": "ammo", "name": "Munição Leve", "rarity": 0, "ammo": "light", "qty": 30},
	"ammo_medium": {"cat": "ammo", "name": "Munição Média", "rarity": 0, "ammo": "medium", "qty": 30},
	"ammo_shell": {"cat": "ammo", "name": "Cartuchos 12", "rarity": 0, "ammo": "shell", "qty": 8},
	"bandage": {"cat": "heal", "name": "Bandagem", "rarity": 0, "heal": 20.0, "time": 1.6, "max_hp": 75.0},
	"medkit": {"cat": "heal", "name": "Kit Médico", "rarity": 1, "heal": 65.0, "time": 3.5, "max_hp": 100.0},
	"energy": {"cat": "heal", "name": "Energético", "rarity": 1, "heal": 25.0, "time": 1.2, "max_hp": 100.0, "boost": 8.0},
	"vest_1": {"cat": "armor", "name": "Colete Nv.1", "rarity": 0, "slot": "vest", "level": 1, "hp": 40.0},
	"vest_2": {"cat": "armor", "name": "Colete Nv.2", "rarity": 1, "slot": "vest", "level": 2, "hp": 70.0},
	"vest_3": {"cat": "armor", "name": "Colete Nv.3", "rarity": 2, "slot": "vest", "level": 3, "hp": 100.0},
	"helmet_1": {"cat": "armor", "name": "Capacete Nv.1", "rarity": 0, "slot": "helmet", "level": 1, "reduce": 0.25},
	"helmet_2": {"cat": "armor", "name": "Capacete Nv.2", "rarity": 1, "slot": "helmet", "level": 2, "reduce": 0.45},
	"helmet_3": {"cat": "armor", "name": "Capacete Nv.3", "rarity": 2, "slot": "helmet", "level": 3, "reduce": 0.65},
	"pack_1": {"cat": "pack", "name": "Mochila Pequena", "rarity": 0, "level": 1, "capacity": 14},
	"pack_2": {"cat": "pack", "name": "Mochila Média", "rarity": 1, "level": 2, "capacity": 18},
	"pack_3": {"cat": "pack", "name": "Mochila Grande", "rarity": 2, "level": 3, "capacity": 22},
	"suppressor": {"cat": "acc", "name": "Supressor Sônico", "rarity": 2},
}

## Pesos por nível do local (0 = comum, 1 = bom, 2 = rico).
const LOOT_TABLE := {
	"pistol": [8, 5, 2], "smg": [4, 6, 6], "rifle": [2, 5, 8], "shotgun": [4, 5, 5], "dmr": [0, 2, 4],
	"ammo_light": [14, 12, 10], "ammo_medium": [8, 12, 12], "ammo_shell": [5, 5, 5],
	"bandage": [14, 10, 6], "medkit": [3, 6, 8], "energy": [4, 5, 5],
	"vest_1": [6, 4, 2], "vest_2": [1, 5, 6], "vest_3": [0, 1, 4],
	"helmet_1": [5, 4, 2], "helmet_2": [1, 4, 5], "helmet_3": [0, 1, 3],
	"pack_1": [4, 3, 1], "pack_2": [0, 3, 4], "pack_3": [0, 0, 2], "suppressor": [1, 2, 3],
}


static func get_def(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func item_name(id: String) -> String:
	return str(get_def(id).get("name", id))


static func category(id: String) -> String:
	return str(get_def(id).get("cat", "acc"))


static func rarity_color(id: String) -> Color:
	return RARITY_COLORS[clampi(int(get_def(id).get("rarity", 0)), 0, 3)]


static func default_qty(id: String) -> int:
	var d := get_def(id)
	if d.has("qty"):
		return int(d["qty"])
	return 1


## Sorteia um item de acordo com o nível do local; 'boost' multiplica pesos por categoria.
static func roll(rng: RandomNumberGenerator, tier: int, boost: Dictionary = {}) -> String:
	var t := clampi(tier, 0, 2)
	var total := 0.0
	for id in LOOT_TABLE:
		total += _weight(id, t, boost)
	var r := rng.randf() * total
	for id in LOOT_TABLE:
		r -= _weight(id, t, boost)
		if r <= 0.0:
			return id
	return "bandage"


static func _weight(id: String, t: int, boost: Dictionary) -> float:
	var w := float(LOOT_TABLE[id][t])
	return w * float(boost.get(category(id), 1.0))
