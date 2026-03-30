extends Node

# Persistent unlock data (saved between runs)
# Currency: "Tide Tokens" — earned mid-run, spent in the surface hub shop

const SAVE_PATH := "user://unlocks.save"

var tide_tokens: int = 0

# Unlockable flags
var unlocks: Dictionary = {
	# Classes (all unlocked for testing)
	"class_emperor":    true,
	"class_gentoo":     true,
	"class_little_blue": true,
	"class_macaroni":   true,

	# Starting relic slots (first is free, extras unlocked)
	"relic_slot_2": false,
	"relic_slot_3": false,

	# Bonus item pool entries (more variety in drops)
	"item_pool_claw_daggers": false,
	"item_pool_bone_bow":     false,
	"item_pool_freeze_globe": false,
	"item_pool_cursed_mackerel": false,

	# Lore fragments (story collectibles that fill in colony history)
	"lore_zone1": false,
	"lore_zone2": false,
	"lore_zone3": false,
	"lore_sanctum": false,

	# Secret ending: Path C and D only unlock after you've seen Path A or B once
	"ending_expose_unlocked":     false,
	"ending_reimprision_unlocked": false,

	# Run tracking
	"runs_completed": 0,
	"deepest_floor": 0,
	"total_kills": 0,
	"ending_a_seen": false,
	"ending_b_seen": false,

	# NPC gift unlocks
	"pearl_shop_discount": false,
	"archivist_secret_rooms": false,
}

# Shop catalog: what you can buy and for how much
const SHOP := [
	{ "key": "class_gentoo",          "cost": 10, "label": "Unlock: Gentoo (Rogue)",         "desc": "The chaotic middle sibling. Fast. Reckless. Somehow always fine." },
	{ "key": "class_little_blue",     "cost": 10, "label": "Unlock: Little Blue (?)",          "desc": "The peacekeeper. Snaps exactly once. You do not want to be there for it." },
	{ "key": "class_macaroni",        "cost": 15, "label": "Unlock: Macaroni (Mage)",          "desc": "The youngest. Unnerving calm. Accidentally the most powerful one there." },
	{ "key": "relic_slot_2",          "cost": 8,  "label": "Relic Slot 2",                    "desc": "Carry one more cursed object into the deep. What could go wrong." },
	{ "key": "relic_slot_3",          "cost": 15, "label": "Relic Slot 3",                    "desc": "Three relics. You are fully unhinged. We respect it." },
	{ "key": "item_pool_claw_daggers","cost": 5,  "label": "Item Pool: Claw Daggers",         "desc": "Adds Claw Daggers to the loot pool. Gentoo's favourite." },
	{ "key": "item_pool_bone_bow",    "cost": 5,  "label": "Item Pool: Bone Bow",             "desc": "Adds Bone Bow to the loot pool. Made from something." },
	{ "key": "item_pool_freeze_globe","cost": 6,  "label": "Item Pool: Freeze Globe",         "desc": "Adds Freeze Globe throwables to the loot pool." },
	{ "key": "item_pool_cursed_mackerel", "cost": 8, "label": "Item Pool: Cursed Mackerel",  "desc": "You saw the description. You still want it unlocked. Respect." },
]

var saved_items: Array = []  # Permanently saved items from completed runs
const MAX_SAVED_ITEMS := 20

signal tokens_changed(new_total: int)
signal unlock_purchased(key: String)


func _ready() -> void:
	load_data()


func add_tokens(amount: int) -> void:
	tide_tokens += amount
	tokens_changed.emit(tide_tokens)
	save_data()


func can_purchase(key: String) -> bool:
	if unlocks.get(key, true):
		return false  # already unlocked
	for entry in SHOP:
		if entry["key"] == key:
			return tide_tokens >= entry["cost"]
	return false


func purchase(key: String) -> bool:
	if not can_purchase(key):
		return false
	for entry in SHOP:
		if entry["key"] == key:
			tide_tokens -= entry["cost"]
			unlocks[key] = true
			tokens_changed.emit(tide_tokens)
			unlock_purchased.emit(key)
			save_data()
			return true
	return false


func is_unlocked(key: String) -> bool:
	return unlocks.get(key, false)


# Called at run end — awards tokens and unlocks secret endings
func process_run_end(run_data: GameManager.RunData, choice: GameManager.EndingChoice) -> void:
	var base_tokens := run_data.floor_number * 2 + run_data.run_currency
	add_tokens(base_tokens)

	# Track run stats
	unlocks["runs_completed"] = unlocks.get("runs_completed", 0) + 1
	unlocks["total_kills"] = unlocks.get("total_kills", 0) + run_data.enemies_killed
	if run_data.floor_number > unlocks.get("deepest_floor", 0):
		unlocks["deepest_floor"] = run_data.floor_number

	# Track endings seen
	if choice == GameManager.EndingChoice.LET_PARENTS_GO:
		unlocks["ending_a_seen"] = true
	elif choice == GameManager.EndingChoice.SIBLING_STAYS:
		unlocks["ending_b_seen"] = true

	# Secret endings unlock after seeing A or B
	if choice == GameManager.EndingChoice.LET_PARENTS_GO or choice == GameManager.EndingChoice.SIBLING_STAYS:
		unlocks["ending_expose_unlocked"] = true
		unlocks["ending_reimprision_unlocked"] = true

	save_data()


# -------------------------------------------------------
# Saved items (persist between runs)
# -------------------------------------------------------
func save_item(item: Dictionary) -> bool:
	if saved_items.size() >= MAX_SAVED_ITEMS:
		return false
	saved_items.append(item.duplicate(true))
	save_data()
	return true


func get_saved_items() -> Array:
	return saved_items


# -------------------------------------------------------
# Persistence
# -------------------------------------------------------
func save_data() -> void:
	var dialogue_data: Dictionary = {}
	if Engine.has_singleton("DialogueManager") or get_node_or_null("/root/DialogueManager"):
		var dm := get_node_or_null("/root/DialogueManager")
		if dm and dm.has_method("get_save_data"):
			dialogue_data = dm.get_save_data()
	var data := {
		"tide_tokens": tide_tokens,
		"unlocks": unlocks,
		"saved_items": saved_items,
		"dialogue": dialogue_data,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(data)


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var data: Variant = file.get_var()
		if data is Dictionary:
			tide_tokens = data.get("tide_tokens", 0)
			var saved_unlocks: Variant = data.get("unlocks", {})
			if saved_unlocks is Dictionary:
				for key in saved_unlocks:
					if unlocks.has(key):
						unlocks[key] = saved_unlocks[key]
			var loaded_items: Variant = data.get("saved_items", [])
			if loaded_items is Array:
				saved_items = loaded_items
			# Load dialogue data
			var dialogue_data: Variant = data.get("dialogue", {})
			if dialogue_data is Dictionary:
				var dm := get_node_or_null("/root/DialogueManager")
				if dm and dm.has_method("load_save_data"):
					dm.load_save_data(dialogue_data)
