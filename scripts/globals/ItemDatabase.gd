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

# Weapon subtypes (musical instruments)
enum WeaponType { AXE_GUITAR, KEYTAR, BASS_GUITAR, MIC_STAND, DRUM_STICKS }

# Armor subtypes (band gear)
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

# Weapon base templates — musical instruments as weapons
const WEAPON_TEMPLATES := {
	WeaponType.AXE_GUITAR: {
		"name": "Axe Guitar",
		"damage_min": 8, "damage_max": 14,
		"speed": 1.0,
		"desc": "A six-string battle axe. Shreds enemies and eardrums.",
		"classes": [PlayerClass.EMPEROR],
	},
	WeaponType.KEYTAR: {
		"name": "Keytar",
		"damage_min": 12, "damage_max": 18,
		"speed": 0.7,
		"desc": "Part keyboard, part guitar, full weapon. Nobody respects it. Everyone fears it.",
		"classes": [PlayerClass.EMPEROR, PlayerClass.LITTLE_BLUE],
	},
	WeaponType.BASS_GUITAR: {
		"name": "Bass Guitar",
		"damage_min": 6, "damage_max": 22,
		"speed": 0.8,
		"desc": "The low end hits different. Literally vibrates organs.",
		"classes": [PlayerClass.MACARONI],
	},
	WeaponType.MIC_STAND: {
		"name": "Mic Stand",
		"damage_min": 7, "damage_max": 13,
		"speed": 1.1,
		"desc": "Chrome-plated and weaponized. Swing it like you mean it.",
		"classes": [PlayerClass.LITTLE_BLUE, PlayerClass.GENTOO],
	},
	WeaponType.DRUM_STICKS: {
		"name": "Drum Sticks",
		"damage_min": 5, "damage_max": 10,
		"speed": 1.6,
		"desc": "Two sticks. Impossibly fast. Every hit is a rimshot.",
		"classes": [PlayerClass.GENTOO],
	},
}

# Armor base templates — band gear and stage equipment
const ARMOR_TEMPLATES := {
	ArmorType.HELMET: {
		"name": "Spiked Headband",
		"defense": 3,
		"desc": "Part fashion, part protection. All metal.",
	},
	ArmorType.CHESTPLATE: {
		"name": "Leather Vest",
		"defense": 7,
		"desc": "Covered in patches from bands that don't exist yet.",
	},
	ArmorType.BOOTS: {
		"name": "Steel-Toe Boots",
		"defense": 2,
		"desc": "For stomping. And moshing. And surviving mosh pits.",
	},
	ArmorType.SHIELD: {
		"name": "Speaker Shield",
		"defense": 5,
		"desc": "A blown-out speaker cab repurposed as a shield. Still buzzes.",
	},
}

# Potion templates — energy drinks and backstage refreshments
const POTION_TEMPLATES := [
	{ "name": "Energy Drink", "effect": "heal", "power": 30, "desc": "Tastes like battery acid and broken dreams. Works though." },
	{ "name": "Throat Coat Tea", "effect": "heal_over_time", "power": 10, "desc": "Slow recovery. Every vocalist's secret weapon." },
	{ "name": "Rage Juice", "effect": "damage_boost", "power": 1.5, "desc": "\"Do NOT drink two of these.\" -- someone who did, mid-solo." },
	{ "name": "Ghost Note", "effect": "invincibility", "power": 3.0, "desc": "Briefly makes you someone else's problem. Like a drum fill nobody asked for." },
	{ "name": "Mystery Rider", "effect": "random", "power": 0, "desc": "Found on the tour bus. Label says 'probably fine.'" },
]

# Throwable templates — pyrotechnics and stage hazards
const THROWABLE_TEMPLATES := [
	{ "name": "Freeze Pedal", "effect": "freeze_aoe", "power": 2.0, "desc": "An effects pedal rigged to explode. Lands in ice-cold feedback." },
	{ "name": "Smoke Machine", "effect": "blind_aoe", "power": 3.0, "desc": "Portable fog. Stage presence optional." },
	{ "name": "Feedback Grenade", "effect": "slow_aoe", "power": 2.5, "desc": "That horrible amp screech, weaponized. You're welcome." },
	{ "name": "Cursed Demo Tape", "effect": "chaos_aoe", "power": 0, "desc": "Explodes into noise. Curses everyone nearby. Side B is worse." },
]

# Name prefix/suffix pools for procedural item naming
const WEAPON_PREFIXES := [
	"Distorted", "Feedback-Laced", "Shredding", "Detuned", "Overdriven",
	"Vintage", "Thrashing", "Screaming", "Cursed", "Whispering", "Doom",
	"Frostbitten", "Crackling", "Hollow-Body", "Vengeful",
]

const WEAPON_SUFFIXES := [
	"of the Mosh Pit", "of the Fallen Tour", "of Slightly Above Average Volume",
	"of the Final Encore", "of Uncertain Tuning", "of the Last Gig",
	"of the Underground", "of Forgotten Bands", "of the Groupie", "of Terrible Solos",
	"of the Warlord", "of Mild Tinnitus", "of the Abyss", "of Someone's Roadie",
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
