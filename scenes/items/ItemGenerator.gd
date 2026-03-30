extends Node
# ItemGenerator — the Borderlands loot engine for TUX
# Generates fully procedural items: type → rarity → base template → affixes → name

const AffixPool = preload("res://scenes/items/AffixPool.gd")

# Generate a complete item dictionary from scratch
# class_bias: PlayerClass enum (or -1 for no bias)
# floor_number: affects rarity weights
static func generate(floor_number: int = 0, class_bias: int = -1) -> Dictionary:
	var item_type := _roll_item_type()
	var rarity := ItemDatabase.roll_rarity(floor_number)
	var item: Dictionary

	match item_type:
		ItemDatabase.ItemType.WEAPON:    item = _generate_weapon(rarity, class_bias)
		ItemDatabase.ItemType.ARMOR:     item = _generate_armor(rarity)
		ItemDatabase.ItemType.POTION:    item = _generate_potion()
		ItemDatabase.ItemType.THROWABLE: item = _generate_throwable()
		_:                               item = _generate_weapon(rarity, class_bias)

	item["floor_found"] = floor_number
	item["item_type"] = item_type
	item["rarity"] = rarity
	return item


# -------------------------------------------------------
# Type rolling
# -------------------------------------------------------
static func _roll_item_type() -> int:
	# Weights: Weapon 35%, Armor 30%, Potion 20%, Throwable 15%
	var roll := randi() % 100
	if roll < 35:   return ItemDatabase.ItemType.WEAPON
	elif roll < 65: return ItemDatabase.ItemType.ARMOR
	elif roll < 85: return ItemDatabase.ItemType.POTION
	else:           return ItemDatabase.ItemType.THROWABLE


# -------------------------------------------------------
# Weapon generation
# -------------------------------------------------------
static func _generate_weapon(rarity: int, class_bias: int) -> Dictionary:
	var weapon_type := _roll_weapon_type(class_bias)
	var template: Dictionary = ItemDatabase.WEAPON_TEMPLATES[weapon_type].duplicate(true)

	# Randomize base stats within template range
	var damage_min: int = template["damage_min"]
	var damage_max: int = template["damage_max"]
	var rolled_min := randi_range(damage_min, damage_min + 3)
	var rolled_max := randi_range(damage_max - 2, damage_max + 4)

	var affix_count := _roll_affix_count(rarity)
	var affixes := AffixPool.roll_affixes(affix_count, ItemDatabase.ItemType.WEAPON, class_bias)

	var item := {
		"base_name": template["name"],
		"weapon_type": weapon_type,
		"damage_min": rolled_min,
		"damage_max": rolled_max,
		"speed": template["speed"] + randf_range(-0.1, 0.1),
		"affixes": affixes,
		"desc": template["desc"],
		"display_name": _generate_weapon_name(template["name"], rarity, affixes),
	}
	return item


static func _roll_weapon_type(class_bias: int) -> int:
	# All weapon types equally weighted, but class-preferred types get a bonus
	var weights := {}
	for wtype in ItemDatabase.WeaponType.values():
		weights[wtype] = 10

	# Bias toward class-preferred weapons
	if class_bias >= 0:
		for wtype in ItemDatabase.WEAPON_TEMPLATES:
			var template: Dictionary = ItemDatabase.WEAPON_TEMPLATES[wtype]
			if class_bias in template.get("classes", []):
				weights[wtype] = 25

	var total := 0
	for w in weights.values():
		total += w
	var roll := randi() % total
	var cumulative := 0
	for wtype in weights:
		cumulative += weights[wtype]
		if roll < cumulative:
			return wtype
	return ItemDatabase.WeaponType.AXE_GUITAR


# -------------------------------------------------------
# Armor generation
# -------------------------------------------------------
static func _generate_armor(rarity: int) -> Dictionary:
	var armor_type: int = ItemDatabase.ArmorType.values()[randi() % ItemDatabase.ArmorType.size()]
	var template: Dictionary = ItemDatabase.ARMOR_TEMPLATES[armor_type].duplicate(true)

	var rolled_defense := randi_range(template["defense"], template["defense"] + 4)
	var affix_count := _roll_affix_count(rarity)
	var affixes := AffixPool.roll_affixes(affix_count, ItemDatabase.ItemType.ARMOR, -1)

	return {
		"base_name": template["name"],
		"armor_type": armor_type,
		"defense": rolled_defense,
		"affixes": affixes,
		"desc": template["desc"],
		"display_name": _generate_armor_name(template["name"], rarity, affixes),
	}


# -------------------------------------------------------
# Potion generation
# -------------------------------------------------------
static func _generate_potion() -> Dictionary:
	var template: Dictionary = ItemDatabase.POTION_TEMPLATES[
		randi() % ItemDatabase.POTION_TEMPLATES.size()
	].duplicate(true)
	template["display_name"] = template["name"]
	template["affixes"] = []
	return template


# -------------------------------------------------------
# Throwable generation
# -------------------------------------------------------
static func _generate_throwable() -> Dictionary:
	var template: Dictionary = ItemDatabase.THROWABLE_TEMPLATES[
		randi() % ItemDatabase.THROWABLE_TEMPLATES.size()
	].duplicate(true)
	template["display_name"] = template["name"]
	template["affixes"] = []
	return template


# -------------------------------------------------------
# Affix count by rarity
# -------------------------------------------------------
static func _roll_affix_count(rarity: int) -> int:
	var range_pair: Array = ItemDatabase.RARITY_AFFIX_COUNTS[rarity]
	return randi_range(range_pair[0], range_pair[1])


# -------------------------------------------------------
# Procedural naming — the fun part
# -------------------------------------------------------
static func _generate_weapon_name(base: String, rarity: int, affixes: Array) -> String:
	if rarity == ItemDatabase.Rarity.COMMON and affixes.is_empty():
		return base  # "Flipper Blade" — nothing fancy

	var result: String = base
	if rarity >= ItemDatabase.Rarity.UNCOMMON:
		var prefix: String = ItemDatabase.WEAPON_PREFIXES[randi() % ItemDatabase.WEAPON_PREFIXES.size()]
		result = prefix + " " + result
	if rarity >= ItemDatabase.Rarity.RARE:
		var suffix: String = ItemDatabase.WEAPON_SUFFIXES[randi() % ItemDatabase.WEAPON_SUFFIXES.size()]
		result = result + " " + suffix
	return result


static func _generate_armor_name(base: String, rarity: int, _affixes: Array) -> String:
	if rarity == ItemDatabase.Rarity.COMMON:
		return base
	var prefix: String = ItemDatabase.WEAPON_PREFIXES[randi() % ItemDatabase.WEAPON_PREFIXES.size()]
	var result: String = prefix + " " + base
	if rarity >= ItemDatabase.Rarity.EPIC:
		var suffix: String = ItemDatabase.WEAPON_SUFFIXES[randi() % ItemDatabase.WEAPON_SUFFIXES.size()]
		result = result + " " + suffix
	return result


# -------------------------------------------------------
# Smart loot: bias affix pool toward player class
# Called by the loot drop system with killer's class
# -------------------------------------------------------
static func generate_for_class(floor_number: int, player_class: int) -> Dictionary:
	# 70% chance the item's primary stat aligns with the class
	var bias := player_class if randf() < 0.7 else -1
	return generate(floor_number, bias)
