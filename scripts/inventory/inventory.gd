class_name Inventory
extends RefCounted
## Inventário funcional com limite de capacidade e organização por categoria.
## 3 espaços de arma + munição por tipo + consumáveis + proteções + mochila + acessório.

const BASE_CAPACITY := 10
const PACK_BONUS := [0, 4, 8, 12]
const AMMO_PER_SLOT := 60

var weapons: Array = ["", "", ""]
var ammo := {"light": 0, "medium": 0, "shell": 0}
var items := {"bandage": 0, "medkit": 0, "energy": 0}
var vest_level := 0
var vest_hp := 0.0
var helmet_level := 0
var pack_level := 0
var suppressor := false


func capacity() -> int:
	return BASE_CAPACITY + PACK_BONUS[pack_level]


func used() -> int:
	var u := 0
	for k in ammo:
		u += ceili(float(ammo[k]) / AMMO_PER_SLOT)
	u += ceili(float(items["bandage"]) / 5.0) + ceili(float(items["medkit"]) / 2.0) + ceili(float(items["energy"]) / 3.0)
	if suppressor:
		u += 1
	return u


func ammo_count(kind: String) -> int:
	return int(ammo.get(kind, 0))


func take_ammo(kind: String, n: int) -> int:
	var have := ammo_count(kind)
	var t := mini(have, n)
	ammo[kind] = have - t
	return t


func has_any_weapon() -> bool:
	for w in weapons:
		if w != "":
			return true
	return false


func has_heal() -> bool:
	return int(items["bandage"]) + int(items["medkit"]) + int(items["energy"]) > 0


## Tenta adicionar um item. Retorna {ok, msg, swap (id de arma substituída), mag (balas extras)}.
func add(id: String, qty: int = 1, cur_slot: int = 0) -> Dictionary:
	var d := ItemDB.get_def(id)
	var res := {"ok": false, "msg": "Item inválido", "swap": ""}
	if d.is_empty():
		return res
	match str(d["cat"]):
		"weapon":
			var slot := -1
			for i in 3:
				if weapons[i] == "":
					slot = i
					break
			if slot < 0:
				slot = clampi(cur_slot, 0, 2)
				res["swap"] = weapons[slot]
			weapons[slot] = id
			var w := WeaponDB.get_def(id)
			ammo[w["ammo"]] = int(ammo[w["ammo"]]) + int(w["mag"])
			res["ok"] = true
			res["msg"] = ItemDB.item_name(id)
			res["slot"] = slot
		"ammo":
			if used() + 1 > capacity() and int(ammo[d["ammo"]]) % AMMO_PER_SLOT == 0:
				res["msg"] = "Mochila cheia"
				return res
			ammo[d["ammo"]] = int(ammo[d["ammo"]]) + qty
			res["ok"] = true
			res["msg"] = "%s +%d" % [ItemDB.item_name(id), qty]
		"heal":
			if used() >= capacity() and _stack_full(id):
				res["msg"] = "Mochila cheia"
				return res
			items[id] = int(items[id]) + qty
			res["ok"] = true
			res["msg"] = ItemDB.item_name(id)
		"armor":
			if str(d["slot"]) == "vest":
				if int(d["level"]) <= vest_level and vest_hp > 0.0:
					res["msg"] = "Você já tem proteção melhor"
					return res
				vest_level = int(d["level"])
				vest_hp = float(d["hp"])
			else:
				if int(d["level"]) <= helmet_level:
					res["msg"] = "Você já tem proteção melhor"
					return res
				helmet_level = int(d["level"])
			res["ok"] = true
			res["msg"] = ItemDB.item_name(id)
		"pack":
			if int(d["level"]) <= pack_level:
				res["msg"] = "Você já tem mochila melhor"
				return res
			pack_level = int(d["level"])
			res["ok"] = true
			res["msg"] = ItemDB.item_name(id)
		"acc":
			if suppressor:
				res["msg"] = "Você já tem um supressor"
				return res
			suppressor = true
			res["ok"] = true
			res["msg"] = ItemDB.item_name(id)
	return res


func _stack_full(id: String) -> bool:
	var per := {"bandage": 5, "medkit": 2, "energy": 3}
	return int(items[id]) % int(per[id]) == 0


func consume(id: String) -> bool:
	if int(items.get(id, 0)) <= 0:
		return false
	items[id] = int(items[id]) - 1
	return true


func helmet_reduce() -> float:
	return [0.0, 0.25, 0.45, 0.65][helmet_level]


## Lista (id, quantidade) agrupada por categoria para a UI de inventário.
func entries() -> Array:
	var out: Array = []
	for i in 3:
		if weapons[i] != "":
			out.append({"id": weapons[i], "qty": 1, "cat": "weapon", "slot": i})
	for k in ammo:
		if int(ammo[k]) > 0:
			out.append({"id": "ammo_" + k, "qty": int(ammo[k]), "cat": "ammo"})
	for k in items:
		if int(items[k]) > 0:
			out.append({"id": k, "qty": int(items[k]), "cat": "heal"})
	if vest_level > 0:
		out.append({"id": "vest_%d" % vest_level, "qty": 1, "cat": "armor"})
	if helmet_level > 0:
		out.append({"id": "helmet_%d" % helmet_level, "qty": 1, "cat": "armor"})
	if pack_level > 0:
		out.append({"id": "pack_%d" % pack_level, "qty": 1, "cat": "pack"})
	if suppressor:
		out.append({"id": "suppressor", "qty": 1, "cat": "acc"})
	return out
