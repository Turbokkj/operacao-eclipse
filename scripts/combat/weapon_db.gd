class_name WeaponDB
extends RefCounted
## Equipamentos virtuais de combate (originais). Todos os parâmetros de gameplay ficam aqui.
## dmg = dano por projétil | rate = disparos/s | spread = dispersão em graus | range = alcance em metros
## noise = raio (m) em que bots podem ouvir o disparo | zoom = multiplicador de FOV ao mirar

const WEAPONS := {
	"pistol": {"name": "Pulsar P9", "kind": "pistol", "ammo": "light", "dmg": 20.0, "rate": 5.0, "mag": 15,
		"reload": 1.4, "spread": 1.3, "range": 70.0, "auto": false, "pellets": 1, "noise": 50.0, "zoom": 0.92,
		"recoil": 1.1, "tracer": Color(1.0, 0.85, 0.4), "sound": "shot_pistol", "pref_dist": 14.0},
	"smg": {"name": "Vespa SMG-7", "kind": "rifle", "ammo": "light", "dmg": 12.0, "rate": 13.0, "mag": 30,
		"reload": 1.8, "spread": 2.4, "range": 55.0, "auto": true, "pellets": 1, "noise": 58.0, "zoom": 0.88,
		"recoil": 0.7, "tracer": Color(1.0, 0.7, 0.3), "sound": "shot_smg", "pref_dist": 12.0},
	"rifle": {"name": "Falcon AR-4", "kind": "rifle", "ammo": "medium", "dmg": 22.0, "rate": 8.0, "mag": 30,
		"reload": 2.3, "spread": 1.6, "range": 130.0, "auto": true, "pellets": 1, "noise": 85.0, "zoom": 0.80,
		"recoil": 1.0, "tracer": Color(1.0, 0.8, 0.35), "sound": "shot_rifle", "pref_dist": 30.0},
	"shotgun": {"name": "Trovão-12", "kind": "shotgun", "ammo": "shell", "dmg": 9.0, "rate": 1.15, "mag": 6,
		"reload": 2.8, "spread": 5.5, "range": 28.0, "auto": false, "pellets": 9, "noise": 95.0, "zoom": 0.90,
		"recoil": 4.0, "tracer": Color(1.0, 0.6, 0.25), "sound": "shot_shotgun", "pref_dist": 7.0},
	"dmr": {"name": "Lince DMR", "kind": "long", "ammo": "medium", "dmg": 52.0, "rate": 1.8, "mag": 10,
		"reload": 2.6, "spread": 0.35, "range": 240.0, "auto": false, "pellets": 1, "noise": 100.0, "zoom": 0.50,
		"recoil": 3.0, "tracer": Color(0.8, 0.95, 1.0), "sound": "shot_dmr", "pref_dist": 55.0},
}

## Prioridade usada pelos bots para escolher a arma equipada.
const PRIORITY := ["rifle", "dmr", "smg", "shotgun", "pistol"]


static func get_def(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func ids() -> Array:
	return WEAPONS.keys()
