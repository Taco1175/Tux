extends Node
# DialogueManager — Hades-style NPC dialogue and relationship system.
# Tracks NPC affinity, rotating dialogue pools, and gift thresholds.
# Persisted via UnlockManager save file.
# Theme: TUX is a penguin metal band. NPCs are music industry characters.

# -------------------------------------------------------
# NPC Definitions
# -------------------------------------------------------
enum NPC {
	ROADIE_RICK,     # Grizzled veteran roadie, combat mentor
	MELODY,          # Young merch girl, runs the shop
	DJ_SCRATCH,      # Sound engineer / music historian, lore keeper
	MAMA_KRILL,      # Band mom, gives food buffs before shows
	THE_PRODUCER,    # Mysterious industry figure, appears after deep runs
}

const NPC_NAMES := {
	NPC.ROADIE_RICK: "Roadie Rick",
	NPC.MELODY: "Melody",
	NPC.DJ_SCRATCH: "DJ Scratch",
	NPC.MAMA_KRILL: "Mama Krill",
	NPC.THE_PRODUCER: "The Producer",
}

const NPC_COLORS := {
	NPC.ROADIE_RICK: Color(0.7, 0.5, 0.3),
	NPC.MELODY: Color(1.0, 0.6, 0.85),
	NPC.DJ_SCRATCH: Color(0.4, 0.7, 0.9),
	NPC.MAMA_KRILL: Color(1.0, 0.6, 0.4),
	NPC.THE_PRODUCER: Color(0.5, 0.9, 0.8),
}

# -------------------------------------------------------
# Affinity (relationship level, 0-100)
# -------------------------------------------------------
var affinity: Dictionary = {
	NPC.ROADIE_RICK: 0,
	NPC.MELODY: 0,
	NPC.DJ_SCRATCH: 0,
	NPC.MAMA_KRILL: 0,
	NPC.THE_PRODUCER: 0,
}

var talk_count: Dictionary = {
	NPC.ROADIE_RICK: 0,
	NPC.MELODY: 0,
	NPC.DJ_SCRATCH: 0,
	NPC.MAMA_KRILL: 0,
	NPC.THE_PRODUCER: 0,
}

# Which gifts have been given (never give twice)
var gifts_given: Dictionary = {}

signal dialogue_started(npc_id: int, text: String, speaker: String)
signal dialogue_ended(npc_id: int)
signal gift_received(npc_id: int, gift: Dictionary)

# -------------------------------------------------------
# Dialogue Pools — each NPC has dialogue gated by conditions
# -------------------------------------------------------
# Format: { "text": String, "condition": Callable or null, "affinity_gain": int }

func get_dialogue(npc_id: int) -> Dictionary:
	var pool := _get_pool(npc_id)
	# Filter to eligible lines
	var eligible: Array = []
	for entry in pool:
		if entry.get("condition") == null or entry["condition"].call():
			eligible.append(entry)
	if eligible.is_empty():
		return {"text": "...", "speaker": NPC_NAMES.get(npc_id, "???"), "affinity_gain": 0}

	# Pick based on talk count (cycle through eligible lines)
	var idx: int = talk_count.get(npc_id, 0) % eligible.size()
	var chosen: Dictionary = eligible[idx]

	# Advance talk counter and affinity
	talk_count[npc_id] = talk_count.get(npc_id, 0) + 1
	var gain: int = chosen.get("affinity_gain", 1)
	affinity[npc_id] = mini(affinity.get(npc_id, 0) + gain, 100)

	return {
		"text": chosen["text"],
		"speaker": NPC_NAMES.get(npc_id, "???"),
		"affinity_gain": gain,
		"npc_id": npc_id,
	}


func check_gift(npc_id: int) -> Dictionary:
	var gifts := _get_gifts(npc_id)
	for gift in gifts:
		var key: String = "%d_%s" % [npc_id, gift["id"]]
		if gifts_given.has(key):
			continue
		if affinity.get(npc_id, 0) >= gift["affinity_required"]:
			gifts_given[key] = true
			gift_received.emit(npc_id, gift)
			return gift
	return {}


# -------------------------------------------------------
# ROADIE RICK — The grizzled veteran roadie
# Been on every tour since the early days. Knows the venue
# (dungeon) better than anyone. Combat mentor.
# -------------------------------------------------------
func _pool_roadie_rick() -> Array:
	return [
		{"text": "Another gig, another crew of kids\nwho think they can play the deep venues.\nI've seen this before.", "condition": null, "affinity_gain": 2},
		{"text": "Your parents headlined the deepest stage.\nVolunteered for the tour. Nobody forced them.\nMake of that what you will.", "condition": null, "affinity_gain": 2},
		{"text": "The crabs in those venues?\nThey weren't always hostile.\nSomething in the sound system changed them.", "condition": null, "affinity_gain": 1},
		{"text": "You swing that instrument like you're\ntuning a radio.\nHit with PURPOSE. Play like you mean it.", "condition": null, "affinity_gain": 1},
		{"text": "Still standing after that set? Huh.\nMaybe this crew's got something after all.", "condition": func(): return _runs_completed() >= 2, "affinity_gain": 3},
		{"text": "I lost my whole crew at venue 5.\nThe Lobster Warlord doesn't fight fair.\nNeither should you.", "condition": func(): return _runs_completed() >= 3, "affinity_gain": 2},
		{"text": "You remind me of someone.\nNevermind. Doesn't matter anymore.", "condition": func(): return affinity.get(NPC.ROADIE_RICK, 0) >= 20, "affinity_gain": 2},
		{"text": "You found the backstage murals? Good.\nThe industry doesn't want you reading those.\nThat's how you know they matter.", "condition": func(): return UnlockManager.is_unlocked("lore_zone1"), "affinity_gain": 3},
		{"text": "DJ Scratch thinks the truth will set us free.\nI think the truth will get us killed.\nWe're both right.", "condition": func(): return UnlockManager.is_unlocked("lore_zone2"), "affinity_gain": 2},
		{"text": "Listen. I'm going to tell you something\nI haven't told anyone.\n\nI was there when they built the Silence.", "condition": func(): return affinity.get(NPC.ROADIE_RICK, 0) >= 50, "affinity_gain": 5},
		{"text": "Your mother... she was the greatest\nfrontwoman I ever worked with.\nDon't let anyone tell you otherwise.", "condition": func(): return affinity.get(NPC.ROADIE_RICK, 0) >= 70, "affinity_gain": 3},
	]


func _gifts_roadie_rick() -> Array:
	return [
		{
			"id": "rick_tuning_fork",
			"affinity_required": 15,
			"type": "buff",
			"buff_type": "damage",
			"value": 0.1,
			"name": "Rick's Tuning Fork",
			"desc": "\"Keep your instrument sharp, kid.\"\n+10% Damage this run.",
			"dialogue": "Here. Take this.\nIt's not much, but it's kept my acts alive\nlonger than most.",
		},
		{
			"id": "rick_earplugs",
			"affinity_required": 35,
			"type": "buff",
			"buff_type": "defense",
			"value": 5,
			"name": "Rick's Custom Earplugs",
			"desc": "Molded from years of standing next to amps.\n+5 Defense this run.",
			"dialogue": "These came out of my ears the day I lost\neveryone. Figured someone should wear them\nwho still has something to protect.",
		},
		{
			"id": "rick_guitar",
			"affinity_required": 60,
			"type": "item",
			"name": "Rick's Last Encore",
			"desc": "A legendary axe guitar, scarred by a hundred gigs.",
			"dialogue": "I'm too old to shred anymore.\nBut you... you might just be crazy enough\nto deserve this.",
			"item_data": {
				"display_name": "Rick's Last Encore",
				"base_name": "Veteran's Axe Guitar",
				"item_type": 0,  # WEAPON
				"weapon_type": 0,  # AXE_GUITAR
				"damage_min": 15,
				"damage_max": 25,
				"speed": 1.0,
				"rarity": 3,  # LEGENDARY
				"affixes": [
					{"type": "flat_damage", "value": 8, "label": "+8 Damage"},
					{"type": "lifesteal", "value": 0.05, "label": "5% Lifesteal"},
					{"type": "crit_chance", "value": 0.08, "label": "+8% Crit Chance"},
				],
				"desc": "\"The axe of a roadie who went to the deep venue\nand came back alone.\"",
			},
		},
	]


# -------------------------------------------------------
# MELODY — Merch girl / young merchant
# -------------------------------------------------------
func _pool_melody() -> Array:
	return [
		{"text": "Welcome to the merch table!\nEverything's genuine — fell off a tour bus.\nProbably.", "condition": null, "affinity_gain": 2},
		{"text": "I found this really cool vinyl yesterday!\nIt plays backwards when you put it on.\nI'm sure that's normal.", "condition": null, "affinity_gain": 1},
		{"text": "The other vendors say I price things too low.\nI say they price things too 'corporate.'", "condition": null, "affinity_gain": 1},
		{"text": "You're going on AGAIN?\nI admire your commitment to bad setlists.", "condition": func(): return _runs_completed() >= 2, "affinity_gain": 2},
		{"text": "I heard the crabs have their own merch.\nThey sell broken strings and stolen picks.\nNot a great business model.", "condition": func(): return _runs_completed() >= 3, "affinity_gain": 2},
		{"text": "You know what? Take a discount.\nFriends-and-family pricing.\nWe ARE friends, right?", "condition": func(): return affinity.get(NPC.MELODY, 0) >= 25, "affinity_gain": 3},
		{"text": "My parents told me never to go below venue 3.\nI asked why.\nThey changed the subject.", "condition": func(): return affinity.get(NPC.MELODY, 0) >= 40, "affinity_gain": 2},
		{"text": "I've been saving up to start my own label.\nDon't tell anyone.\n...Please.", "condition": func(): return affinity.get(NPC.MELODY, 0) >= 60, "affinity_gain": 4},
	]


func _gifts_melody() -> Array:
	return [
		{
			"id": "melody_discount",
			"affinity_required": 20,
			"type": "unlock",
			"unlock_key": "pearl_shop_discount",
			"name": "Friend Discount",
			"desc": "All shop items cost 20% less.",
			"dialogue": "Here — I made you a VIP pass.\nIt's a guitar pick with your name on it.\nVery official.",
		},
		{
			"id": "melody_trinket",
			"affinity_required": 45,
			"type": "buff",
			"buff_type": "gold_find",
			"value": 0.25,
			"name": "Melody's Lucky Pick",
			"desc": "\"She swears it's lucky.\"\n+25% Tide Token Find this run.",
			"dialogue": "I found this backstage the day before\nyou first came to my table.\nI think it was waiting for you.",
		},
	]


# -------------------------------------------------------
# DJ SCRATCH — Sound engineer / music historian
# -------------------------------------------------------
func _pool_dj_scratch() -> Array:
	return [
		{"text": "Ah, another visitor to the archives!\nMost penguins avoid the old recordings.\nThey say the history is depressing.\nThey're not wrong.", "condition": null, "affinity_gain": 2},
		{"text": "Did you know TUX has only been a band\nfor two generations?\nWhat was playing before?\nExcellent question. I've been asking for decades.", "condition": null, "affinity_gain": 1},
		{"text": "The label sealed off the master tapes.\nSaid it was for 'legal reasons.'\nThe legals are fine. I checked.", "condition": null, "affinity_gain": 2},
		{"text": "You found a backstage mural! Magnificent!\nThe industry tried to paint over these.\nThey missed a few.", "condition": func(): return UnlockManager.is_unlocked("lore_zone1"), "affinity_gain": 3},
		{"text": "\"The Contract was signed in willing ink.\"\nWilling. That word does a lot of work\nin that sentence.", "condition": func(): return UnlockManager.is_unlocked("lore_zone2"), "affinity_gain": 4},
		{"text": "Your parents weren't the first band.\nEvery generation, someone plays the deep venues.\nThe industry calls them 'headliners.'\nI call them 'sacrifices.'", "condition": func(): return UnlockManager.is_unlocked("lore_zone3"), "affinity_gain": 5},
		{"text": "I've decoded the setlist scratched into the walls.\nIt's not counting songs.\nIt's counting souls.", "condition": func(): return UnlockManager.is_unlocked("lore_sanctum"), "affinity_gain": 5},
		{"text": "The truth is simple:\nThe music industry built its empire\non a deal with something ancient.\nAnd the royalties are coming due.", "condition": func(): return affinity.get(NPC.DJ_SCRATCH, 0) >= 50, "affinity_gain": 3},
	]


func _gifts_dj_scratch() -> Array:
	return [
		{
			"id": "scratch_xp_mix",
			"affinity_required": 15,
			"type": "buff",
			"buff_type": "xp_bonus",
			"value": 0.15,
			"name": "DJ's Practice Mix",
			"desc": "\"Knowledge is the only instrument that\ngrows sharper with use.\"\n+15% XP this run.",
			"dialogue": "Take my mixtape. It documents every enemy\nI've catalogued from tour reports.\nKnow thy audience.",
		},
		{
			"id": "scratch_backstage_key",
			"affinity_required": 40,
			"type": "unlock",
			"unlock_key": "archivist_secret_rooms",
			"name": "Backstage Pass",
			"desc": "Secret rooms now contain additional lore fragments.",
			"dialogue": "This pass opens the sealed sections\nof the deep venues.\nWhat you find... may change everything.",
		},
	]


# -------------------------------------------------------
# MAMA KRILL — Band mom / cook
# -------------------------------------------------------
func _pool_mama_krill() -> Array:
	return [
		{"text": "Eat something before the show!\nYou're all skin and feathers.", "condition": null, "affinity_gain": 2},
		{"text": "I packed extra sardine rolls for the tour bus.\nDon't tell the others — they're for you four.", "condition": null, "affinity_gain": 2},
		{"text": "Your mother used to help me prep backstage.\nBest sous chef I ever had.\nTerrible at peeling shrimp, though.", "condition": null, "affinity_gain": 1},
		{"text": "The eldest — Emperor, right? — \nhe used to sneak extra portions for his siblings.\nThought I didn't notice.\nI always notice.", "condition": null, "affinity_gain": 2},
		{"text": "I hear the catering gets... strange,\nbelow venue 5.\nThings that glow. Things that move.\nDon't eat anything down there.\nI mean it.", "condition": func(): return _runs_completed() >= 2, "affinity_gain": 2},
		{"text": "You look tired, dear.\nSit down. Eat. Rest.\nThe next gig isn't going anywhere.", "condition": func(): return _runs_completed() >= 4, "affinity_gain": 3},
		{"text": "I've been cooking for bands for 40 years.\nI've fed every act that played the deep venues.\nMost of them came back.", "condition": func(): return affinity.get(NPC.MAMA_KRILL, 0) >= 30, "affinity_gain": 2},
		{"text": "...Not all of them came back.\n\nEat your sardines.", "condition": func(): return affinity.get(NPC.MAMA_KRILL, 0) >= 35, "affinity_gain": 3},
		{"text": "When your parents finish their tour,\nI'm going to cook them the biggest feast\nbackstage has ever seen.\n\nWhen.", "condition": func(): return affinity.get(NPC.MAMA_KRILL, 0) >= 50, "affinity_gain": 4},
	]


func _gifts_mama_krill() -> Array:
	return [
		{
			"id": "krill_sardine_rolls",
			"affinity_required": 10,
			"type": "buff",
			"buff_type": "heal",
			"value": 30,
			"name": "Sardine Rolls",
			"desc": "\"Eat before you play, not after.\"\nHeal 30 HP at run start.",
			"dialogue": "Here — fresh sardine rolls.\nThey're still warm.\nDon't you dare share them with the crabs.",
		},
		{
			"id": "krill_hearty_stew",
			"affinity_required": 30,
			"type": "buff",
			"buff_type": "max_hp",
			"value": 20,
			"name": "Hearty Krill Stew",
			"desc": "\"My special recipe. Don't ask what's in it.\"\n+20 Max HP this run.",
			"dialogue": "My grandmother's recipe.\nShe said it could bring a penguin back\nfrom the edge.\nShe wasn't exaggerating.",
		},
		{
			"id": "krill_packed_lunch",
			"affinity_required": 55,
			"type": "consumable",
			"name": "Mama's Packed Lunch",
			"desc": "A lovingly packed meal. Heals 50% of max HP when used.",
			"dialogue": "I packed you a proper tour lunch this time.\nSandwiches, a thermos, and a note that says\n'Come home safe.'\n\nI mean it.",
		},
	]


# -------------------------------------------------------
# THE PRODUCER — Mysterious music industry figure
# Appears after reaching deep venues. Knows more than they should.
# -------------------------------------------------------
func _pool_producer() -> Array:
	return [
		{"text": "...\n\nYou can hear me?", "condition": func(): return _deepest_floor() >= 6, "affinity_gain": 3},
		{"text": "The others can't hear me.\nOr they choose not to.\nIt's hard to tell with penguins.", "condition": func(): return _deepest_floor() >= 6, "affinity_gain": 2},
		{"text": "I've been in the industry longer than TUX.\nLonger than the Silence.\nLonger than whatever's behind it.", "condition": func(): return affinity.get(NPC.THE_PRODUCER, 0) >= 10, "affinity_gain": 3},
		{"text": "Your parents signed their contract.\nYou'll sign yours.\nI'm not here to judge.\n\nI'm here to listen.", "condition": func(): return affinity.get(NPC.THE_PRODUCER, 0) >= 20, "affinity_gain": 3},
		{"text": "The thing beneath the venues isn't evil.\nIt's not good, either.\nIt's just... hungry for sound.\nIt's been silent for a very long time.", "condition": func(): return affinity.get(NPC.THE_PRODUCER, 0) >= 35, "affinity_gain": 4},
		{"text": "There's a fifth track.\nOne nobody recorded.\nBecause nobody knew the frequency existed.\n\n...Yet.", "condition": func(): return affinity.get(NPC.THE_PRODUCER, 0) >= 60 and _endings_seen() >= 2, "affinity_gain": 5},
		{"text": "When the final encore comes,\nlook at the Silence.\nReally listen.\n\nIt wasn't built to keep something quiet.", "condition": func(): return affinity.get(NPC.THE_PRODUCER, 0) >= 80, "affinity_gain": 5},
	]


func _gifts_producer() -> Array:
	return [
		{
			"id": "producer_deep_mix",
			"affinity_required": 25,
			"type": "buff",
			"buff_type": "reveal",
			"value": 1,
			"name": "Deep Mix",
			"desc": "\"Hear what's really there.\"\nReveals secret rooms on the minimap.",
			"dialogue": "Take this.\nIt's a frequency only I can produce.\nDon't ask what that means.",
		},
		{
			"id": "producer_sound_ward",
			"affinity_required": 50,
			"type": "buff",
			"buff_type": "damage_resist",
			"value": 0.15,
			"name": "Sonic Ward",
			"desc": "\"The deep frequencies recognize you now.\"\n15% damage reduction this run.",
			"dialogue": "The creatures below won't hit you\nas hard anymore.\nThey sense something familiar in your sound.\nDon't think about why.",
		},
	]


# -------------------------------------------------------
# Routing
# -------------------------------------------------------
func _get_pool(npc_id: int) -> Array:
	match npc_id:
		NPC.ROADIE_RICK:   return _pool_roadie_rick()
		NPC.MELODY:        return _pool_melody()
		NPC.DJ_SCRATCH:    return _pool_dj_scratch()
		NPC.MAMA_KRILL:    return _pool_mama_krill()
		NPC.THE_PRODUCER:  return _pool_producer()
	return []


func _get_gifts(npc_id: int) -> Array:
	match npc_id:
		NPC.ROADIE_RICK:   return _gifts_roadie_rick()
		NPC.MELODY:        return _gifts_melody()
		NPC.DJ_SCRATCH:    return _gifts_dj_scratch()
		NPC.MAMA_KRILL:    return _gifts_mama_krill()
		NPC.THE_PRODUCER:  return _gifts_producer()
	return []


# -------------------------------------------------------
# Condition helpers
# -------------------------------------------------------
func _runs_completed() -> int:
	return UnlockManager.unlocks.get("runs_completed", 0)

func _deepest_floor() -> int:
	return UnlockManager.unlocks.get("deepest_floor", 0)

func _endings_seen() -> int:
	var count := 0
	if UnlockManager.is_unlocked("ending_a_seen"): count += 1
	if UnlockManager.is_unlocked("ending_b_seen"): count += 1
	if UnlockManager.is_unlocked("ending_expose_unlocked"): count += 1
	if UnlockManager.is_unlocked("ending_reimprision_unlocked"): count += 1
	return count


func is_npc_available(npc_id: int) -> bool:
	match npc_id:
		NPC.THE_PRODUCER:
			return _deepest_floor() >= 6
	return true


# -------------------------------------------------------
# Run buffs — active buffs granted by NPC gifts
# -------------------------------------------------------
var active_run_buffs: Array[Dictionary] = []

func get_run_buffs() -> Array[Dictionary]:
	return active_run_buffs

func clear_run_buffs() -> void:
	active_run_buffs.clear()

func add_run_buff(buff: Dictionary) -> void:
	active_run_buffs.append(buff)


# -------------------------------------------------------
# Persistence (called from UnlockManager)
# -------------------------------------------------------
func get_save_data() -> Dictionary:
	return {
		"affinity": affinity.duplicate(),
		"talk_count": talk_count.duplicate(),
		"gifts_given": gifts_given.duplicate(),
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("affinity"):
		for key in data["affinity"]:
			affinity[key] = data["affinity"][key]
	if data.has("talk_count"):
		for key in data["talk_count"]:
			talk_count[key] = data["talk_count"][key]
	if data.has("gifts_given"):
		gifts_given = data["gifts_given"].duplicate()
