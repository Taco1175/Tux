extends Node
# AffixPool — all possible affixes with weights for TUX
# Affixes are Dictionaries: { type, value, display_label }

# -------------------------------------------------------
# Offensive affixes (weapons)
# -------------------------------------------------------
const WEAPON_AFFIXES := [
	{ "type": "flat_damage",    "value_range": [3, 10],  "weight": 20, "label": "+{v} Damage" },
	{ "type": "percent_damage", "value_range": [0.1, 0.3], "weight": 15, "label": "+{v}% Damage" },
	{ "type": "fire_damage",    "value_range": [4, 12],  "weight": 12, "label": "+{v} Tide Burn" },
	{ "type": "ice_damage",     "value_range": [3, 10],  "weight": 12, "label": "+{v} Frost Damage, chance to Slow" },
	{ "type": "lifesteal",      "value_range": [0.02, 0.06], "weight": 8, "label": "{v}% Lifesteal" },
	{ "type": "crit_chance",    "value_range": [0.03, 0.10], "weight": 10, "label": "+{v}% Crit Chance" },
	{ "type": "attack_speed",   "value_range": [0.05, 0.20], "weight": 10, "label": "+{v}% Attack Speed" },
	{ "type": "knockback",      "value_range": [20, 60],  "weight": 6, "label": "+{v} Knockback" },
	{ "type": "poison",         "value_range": [2, 8],    "weight": 7, "label": "+{v} Poison/sec for 3s" },
]

# Defensive / utility affixes (armor, but some can roll on weapons too)
const ARMOR_AFFIXES := [
	{ "type": "flat_defense",   "value_range": [2, 8],   "weight": 20, "label": "+{v} Defense" },
	{ "type": "max_health",     "value_range": [10, 35], "weight": 18, "label": "+{v} Max HP" },
	{ "type": "max_mana",       "value_range": [8, 25],  "weight": 12, "label": "+{v} Max Mana" },
	{ "type": "move_speed",     "value_range": [0.05, 0.15], "weight": 10, "label": "+{v}% Move Speed" },
	{ "type": "dodge_chance",   "value_range": [0.02, 0.08], "weight": 8, "label": "+{v}% Dodge" },
	{ "type": "thorns",         "value_range": [3, 10],  "weight": 6, "label": "Reflect {v} damage to attackers" },
	{ "type": "xp_bonus",       "value_range": [0.05, 0.20], "weight": 6, "label": "+{v}% XP Gained" },
	{ "type": "gold_find",      "value_range": [0.08, 0.25], "weight": 8, "label": "+{v}% Tide Token Find" },
	{ "type": "crit_chance",    "value_range": [0.02, 0.06], "weight": 6, "label": "+{v}% Crit Chance" },
	{ "type": "regen",          "value_range": [1, 4],   "weight": 10, "label": "+{v} HP Regen/sec" },
]

# Class-specific affix biases — these affixes get boosted weight when rolling for that class
const CLASS_BIASES := {
	ItemDatabase.PlayerClass.EMPEROR: ["flat_damage", "flat_defense", "max_health", "thorns"],
	ItemDatabase.PlayerClass.GENTOO:  ["crit_chance", "attack_speed", "dodge_chance", "move_speed"],
	ItemDatabase.PlayerClass.LITTLE_BLUE: ["max_mana", "regen", "xp_bonus", "max_health"],
	ItemDatabase.PlayerClass.MACARONI: ["fire_damage", "ice_damage", "max_mana", "percent_damage"],
}

const CLASS_BIAS_MULTIPLIER := 2.5


# -------------------------------------------------------
# Roll N affixes for an item
# -------------------------------------------------------
static func roll_affixes(count: int, item_type: int, class_bias: int) -> Array:
	if count <= 0:
		return []

	var pool := _get_pool(item_type)
	var biased_pool := _apply_class_bias(pool, class_bias)
	var rolled: Array = []
	var used_types: Array = []

	for _i in count:
		var affix := _roll_one(biased_pool, used_types)
		if affix.is_empty():
			break
		rolled.append(affix)
		used_types.append(affix["type"])

	return rolled


static func _get_pool(item_type: int) -> Array:
	if item_type == ItemDatabase.ItemType.WEAPON:
		return WEAPON_AFFIXES + ARMOR_AFFIXES.filter(
			func(a): return a["type"] in ["crit_chance", "move_speed", "xp_bonus"]
		)
	return ARMOR_AFFIXES


static func _apply_class_bias(pool: Array, class_bias: int) -> Array:
	if class_bias < 0:
		return pool
	var biased_types: Array = CLASS_BIASES.get(class_bias, [])
	return pool.map(func(entry: Dictionary) -> Dictionary:
		var copy := entry.duplicate()
		if copy["type"] in biased_types:
			copy["weight"] = int(copy["weight"] * CLASS_BIAS_MULTIPLIER)
		return copy
	)


static func _roll_one(pool: Array, exclude_types: Array) -> Dictionary:
	var filtered := pool.filter(func(a): return not (a["type"] in exclude_types))
	if filtered.is_empty():
		return {}

	var total := 0
	for entry in filtered:
		total += entry["weight"]
	var roll := randi() % total
	var cumulative := 0
	for entry in filtered:
		cumulative += entry["weight"]
		if roll < cumulative:
			return _instantiate_affix(entry)
	return {}


static func _instantiate_affix(template: Dictionary) -> Dictionary:
	var value_range: Array = template["value_range"]
	var value: float

	if value_range[0] is float or value_range[1] is float:
		value = randf_range(value_range[0], value_range[1])
		value = snappedf(value, 0.01)
	else:
		value = float(randi_range(int(value_range[0]), int(value_range[1])))

	var label: String = template["label"].replace("{v}", _format_value(template["type"], value))

	return {
		"type": template["type"],
		"value": value,
		"label": label,
	}


static func _format_value(affix_type: String, value: float) -> String:
	match affix_type:
		"percent_damage", "attack_speed", "move_speed", "dodge_chance", \
		"crit_chance", "lifesteal", "xp_bonus", "gold_find":
			return "%d%%" % int(value * 100)
		_:
			return str(int(value))
