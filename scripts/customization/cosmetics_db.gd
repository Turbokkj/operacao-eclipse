class_name CosmeticsDB
extends RefCounted
## Catálogo de personalização: 3 corpos-base, rosto, cabelo, roupas, calçados e acessórios de cabeça.

const BODIES := [
	{"name": "Atlas", "desc": "Atlético", "height": 1.82, "shoulder": 0.47, "hip": 0.31, "depth": 0.24, "waist": 0.35, "limb": 1.08, "head": 1.0},
	{"name": "Nara", "desc": "Ágil", "height": 1.68, "shoulder": 0.385, "hip": 0.335, "depth": 0.21, "waist": 0.27, "limb": 0.88, "head": 0.97},
	{"name": "Kenji", "desc": "Esguio", "height": 1.76, "shoulder": 0.415, "hip": 0.29, "depth": 0.20, "waist": 0.29, "limb": 0.95, "head": 1.03},
]
const SKIN_TONES := [Color(0.96, 0.80, 0.69), Color(0.89, 0.69, 0.53), Color(0.78, 0.57, 0.40),
	Color(0.62, 0.42, 0.29), Color(0.45, 0.30, 0.20), Color(0.30, 0.20, 0.14)]
const HAIR_STYLES := ["Careca", "Curto", "Espetado", "Rabo de cavalo", "Longo", "Moicano"]
const HAIR_COLORS := [Color(0.08, 0.06, 0.05), Color(0.25, 0.15, 0.08), Color(0.45, 0.28, 0.12), Color(0.78, 0.62, 0.30),
	Color(0.55, 0.12, 0.08), Color(0.70, 0.70, 0.72), Color(0.15, 0.35, 0.75), Color(0.85, 0.25, 0.55)]
const EYE_COLORS := [Color(0.25, 0.15, 0.08), Color(0.20, 0.45, 0.75), Color(0.20, 0.55, 0.35), Color(0.50, 0.50, 0.52)]
const FACES := [
	{"name": "Clássico", "jaw": 1.0, "eye": 1.0, "nose": 1.0, "brow": 1.0, "mouth": 1.0},
	{"name": "Anguloso", "jaw": 1.12, "eye": 0.9, "nose": 1.15, "brow": 1.4, "mouth": 0.9},
	{"name": "Suave", "jaw": 0.9, "eye": 1.15, "nose": 0.85, "brow": 0.7, "mouth": 1.1},
	{"name": "Marcante", "jaw": 1.05, "eye": 0.95, "nose": 1.3, "brow": 1.1, "mouth": 1.2},
]
const TOPS := [{"name": "Camiseta Urbana", "kind": "tee"}, {"name": "Jaqueta Esportiva", "kind": "jacket"},
	{"name": "Colete Tático", "kind": "vest"}, {"name": "Moletom com Capuz", "kind": "hoodie"}]
const TOP_COLORS := [Color(0.85, 0.30, 0.12), Color(0.18, 0.42, 0.75), Color(0.22, 0.55, 0.32),
	Color(0.20, 0.20, 0.24), Color(0.85, 0.82, 0.75), Color(0.55, 0.22, 0.55)]
const BOTTOMS := [{"name": "Jeans", "kind": "jeans"}, {"name": "Calça Cargo", "kind": "cargo"}, {"name": "Bermuda", "kind": "shorts"}]
const BOTTOM_COLORS := [Color(0.20, 0.28, 0.48), Color(0.18, 0.18, 0.20), Color(0.38, 0.36, 0.24),
	Color(0.50, 0.42, 0.30), Color(0.35, 0.18, 0.18)]
const SHOES := [{"name": "Tênis", "kind": "sneaker"}, {"name": "Botas", "kind": "boot"}, {"name": "Coturno Tático", "kind": "tactical"}]
const SHOE_COLORS := [Color(0.90, 0.90, 0.92), Color(0.15, 0.15, 0.17), Color(0.45, 0.28, 0.14), Color(0.85, 0.30, 0.15)]
const HEADWEAR := [{"name": "Nenhum", "kind": "none"}, {"name": "Boné", "kind": "cap"},
	{"name": "Gorro", "kind": "beanie"}, {"name": "Capacete", "kind": "helmet"}]
const HEAD_COLORS := [Color(0.15, 0.15, 0.17), Color(0.85, 0.30, 0.12), Color(0.18, 0.42, 0.75),
	Color(0.35, 0.42, 0.28), Color(0.85, 0.82, 0.75)]

## Número de opções de cada chave (usado em sanitização, randomização e UI).
const LIMITS := {"body": 3, "skin": 6, "face": 4, "hair": 6, "hair_color": 8, "eye_color": 4, "top": 4,
	"top_color": 6, "bottom": 3, "bottom_color": 5, "shoes": 3, "shoe_color": 4, "head": 4, "head_color": 5}


static func default_appearance() -> Dictionary:
	return {"body": 0, "skin": 1, "face": 0, "hair": 1, "hair_color": 1, "eye_color": 0, "top": 0, "top_color": 0,
		"bottom": 0, "bottom_color": 0, "shoes": 0, "shoe_color": 0, "head": 0, "head_color": 0}


static func sanitize(d: Dictionary) -> Dictionary:
	var def := default_appearance()
	var out := {}
	for k in def:
		var v: Variant = d.get(k, def[k])
		out[k] = clampi(int(v), 0, int(LIMITS[k]) - 1)
	return out


static func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for k in LIMITS:
		out[k] = rng.randi_range(0, int(LIMITS[k]) - 1)
	out["head"] = 0 if rng.randf() < 0.6 else out["head"]
	return out


## Paleta de cores por chave de aparência (usada pela UI de personalização).
static func palette(key: String) -> Array:
	match key:
		"skin":
			return SKIN_TONES
		"hair_color":
			return HAIR_COLORS
		"eye_color":
			return EYE_COLORS
		"top_color":
			return TOP_COLORS
		"bottom_color":
			return BOTTOM_COLORS
		"shoe_color":
			return SHOE_COLORS
		"head_color":
			return HEAD_COLORS
	return []
