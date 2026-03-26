extends Node

# Item type categories
enum ItemType { WEAPON, ARMOR, POTION, THROWABLE }

# Rarity tiers (Borderlands-style)
enum Rarity {
	COMMON,     # White  — 0–1 affixes
	UNCOMMON,   # Green  — 1 affix
	RARE,       # Blue   — 1–2 affixes
	EPIC,       # Purple — 2–3 affixes
	LEGENDARY   # Orange — 3 affixes + 1 unique fixed affix
}

# Weapon subtypes
enum WeaponType { FLIPPER_BLADE, FISH_LANCE, ICE_STAFF, BONE_BOW, CLAW_DAGGERS }

# Armor subtypes
enum ArmorType { HELMET, CHESTPLATE, BOOTS, SHIELD }

# Class affinities (which classes prefer which affixes)
enum PlayerClass { EMPEROR, GENTOO, LITTLE_BLUE, MACARONI }

const RARITY_COLORS := {
	Rarity.COMMON:    Color(0.85, 0.85, 0.85),
	Rarity.UNCOMMON:  Color(0.27, 0.80, 0.27),
	Rarity.RARE:      Color(0.20, 0.55, 1.00),
	Rarity.EPIC:      Color(0.65, 0.20, 0.90),
	Rarity.LEGENDARY: Color(1.00, 0.55, 0.05),
}

const RARITY_NAMES := {
	Rarity.COMMON:    "Common",
	Rarity.UNCOMMON:  "Uncommon",
	Rarity.RARE:      "Rare",
	Rarity.EPIC:      "Epic",
	Rarity.LEGENDARY: "Legendary",
}

# Base affix count per rarity
const RARITY_AFFIX_COUNTS := {
	Rarity.COMMON:    [0, 1],   # min, max
	Rarity.UNCOMMON:  [1, 1],
	Rarity.RARE:      [1, 2],
	Rarity.EPIC:      [2, 3],
	Rarity.LEGENDARY: [3, 3],
}

# Base drop weight per rarity (modified by floor depth)
const BASE_RARITY_WEIGHTS := {
	Rarity.COMMON:    50,
	Rarity.UNCOMMON:  25,
	Rarity.RARE:      15,
	Rarity.EPIC:       8,
	Rarity.LEGENDARY:  2,
}

# Weapon base templates: { display_name, damage_min, damage_max, speed, description }
const WEAPON_TEMPLATES := {
	WeaponType.FLIPPER_BLADE: {
		"name": "Flipper Blade",
		"damage_min": 8, "damage_max": 14,
		"speed": 1.0,
		"desc": "A blade fashioned from a hardened flipper. Disturbingly effective.",
		"classes": [PlayerClass.EMPEROR],
	},
	WeaponType.FISH_LANCE: {
		"name": "Fish Lance",
		"damage_min": 12, "damage_max": 18,
		"speed": 0.7,
		"desc": "A frozen swordfish on a stick. Somehow this is a real weapon.",
		"classes": [PlayerClass.EMPEROR, PlayerClass.LITTLE_BLUE],
	},
	WeaponType.ICE_STAFF: {
		"name": "Ice Staff",
		"damage_min": 6, "damage_max": 22,
		"speed": 0.8,
		"desc": "Crackles with ancient cold. Smells faintly of regret.",
		"classes": [PlayerClass.MACARONI],
	},
	WeaponType.BONE_BOW: {
		"name": "Bone Bow",
		"damage_min": 7, "damage_max": 13,
		"speed": 1.1,
		"desc": "Made from the skeleton of something that used to be friendly.",
		"classes": [PlayerClass.GENTOO, PlayerClass.LITTLE_BLUE],
	},
	WeaponType.CLAW_DAGGERS: {
		"name": "Claw Daggers",
		"damage_min": 5, "damage_max": 10,
		"speed": 1.6,
		"desc": "Two daggers. One per wing. Don't ask how.",
		"classes": [PlayerClass.GENTOO],
	},
}

# Armor base templates: { display_name, defense, description }
const ARMOR_TEMPLATES := {
	ArmorType.HELMET: {
		"name": "Helmet",
		"defense": 3,
		"desc": "Protects the head. Allegedly.",
	},
	ArmorType.CHESTPLATE: {
		"name": "Chestplate",
		"defense": 7,
		"desc": "Heavy. Smells like the sea. Always smells like the sea.",
	},
	ArmorType.BOOTS: {
		"name": "Boots",
		"defense": 2,
		"desc": "Penguins already waddle. These make it worse, somehow.",
	},
	ArmorType.SHIELD: {
		"name": "Shield",
		"defense": 5,
		"desc": "A round disc of barnacled iron. Someone loved this once.",
	},
}

# Potion templates
const POTION_TEMPLATES := [
	{ "name": "Herring Flask", "effect": "heal", "power": 30, "desc": "Tastes exactly like you'd expect." },
	{ "name": "Brine Vial", "effect": "heal_over_time", "power": 10, "desc": "Slow. Effective. Deeply unpleasant." },
	{ "name": "Rage Draught", "effect": "damage_boost", "power": 1.5, "desc": "\"Do NOT drink two of these.\" — someone who did." },
	{ "name": "Ghost Tide", "effect": "invincibility", "power": 3.0, "desc": "Briefly makes you someone else's problem." },
	{ "name": "Murky Potion", "effect": "random", "power": 0, "desc": "Completely unknown. The label just says 'probably fine.'" },
]

# Throwable templates
const THROWABLE_TEMPLATES := [
	{ "name": "Freeze Globe", "effect": "freeze_aoe", "power": 2.0, "desc": "Throws like a dream. Lands like a nightmare." },
	{ "name": "Ink Bomb", "effect": "blind_aoe", "power": 3.0, "desc": "Octopus origin. Do not ask the octopus." },
	{ "name": "Barnacle Grenade", "effect": "slow_aoe", "power": 2.5, "desc": "Sticks to everything. Even things you didn't want it to." },
	{ "name": "Cursed Mackerel", "effect": "chaos_aoe", "power": 0, "desc": "Explodes. Also curses. Also smells. Truly the full experience." },
]

# Name prefix/suffix pools for procedural item naming
const WEAPON_PREFIXES := [
	"Barnacle-Encrusted", "Tide-Touched", "Drowned", "Corrupted", "Blessed",
	"Ancient", "Festering", "Glowing", "Cursed", "Whispering", "Abyssal",
	"Frozen", "Crackling", "Hollow", "Vengeful",
]

const WEAPON_SUFFIXES := [
	"of the Deep", "of the Fallen Colony", "of Slightly Above Average Power",
	"of the Drowned God", "of Uncertain Origin", "of the Last Dive",
	"of the Tide", "of Forgotten Kin", "of the Leech", "of Terrible Secrets",
	"of the Warlord", "of Mild Concern", "of the Abyss", "of Someone's Dad",
]

func _ready() -> void:
	pass


func get_rarity_color(rarity: Rarity) -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)


func get_rarity_name(rarity: Rarity) -> String:
	return RARITY_NAMES.get(rarity, "Unknown")


# Rolls a rarity tier, weighted by floor depth
func roll_rarity(floor_number: int) -> Rarity:
	var weights := BASE_RARITY_WEIGHTS.duplicate()
	# Deeper floors shift weight toward better loot
	var depth_bonus := floor_number * 0.5
	weights[Rarity.UNCOMMON] += int(depth_bonus)
	weights[Rarity.RARE]     += int(depth_bonus * 0.6)
	weights[Rarity.EPIC]     += int(depth_bonus * 0.3)
	weights[Rarity.LEGENDARY]+= int(depth_bonus * 0.1)

	var total := 0
	for w in weights.values():
		total += w
	var roll := randi() % total
	var cumulative := 0
	for rarity in weights:
		cumulative += weights[rarity]
		if roll < cumulative:
			return rarity
	return Rarity.COMMON
