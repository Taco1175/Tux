extends Node2D
# Hub World for TUX — Backstage area between gigs.
# Players walk around, interact with NPCs (merch, vault, mixing desk, venue entrance).

const SpriteFramesBuilder = preload("res://scenes/player/SpriteFramesBuilder.gd")
const PlayerScene := preload("res://scenes/player/Player.tscn")
const PlayerScripts := {
	ItemDatabase.PlayerClass.EMPEROR:    preload("res://scenes/player/classes/Emperor.gd"),
	ItemDatabase.PlayerClass.GENTOO:     preload("res://scenes/player/classes/Gentoo.gd"),
	ItemDatabase.PlayerClass.LITTLE_BLUE: preload("res://scenes/player/classes/LittleBlue.gd"),
	ItemDatabase.PlayerClass.MACARONI:   preload("res://scenes/player/classes/Macaroni.gd"),
}

const TILE_SIZE := 16

# Hub layout constants (tile coordinates)
const HUB_WIDTH := 30
const HUB_HEIGHT := 17

@onready var tilemap: TileMapLayer = $HubTileMap
@onready var players_node: Node2D = $Players
@onready var camera: Camera2D = $Camera2D
@onready var hud_layer: CanvasLayer = $HUDLayer
@onready var interact_label: Label = $HUDLayer/InteractLabel
@onready var shop_panel: Control = $HUDLayer/ShopPanel
@onready var vault_panel: Control = $HUDLayer/VaultPanel
@onready var inventory_ui: Control = $HUDLayer/InventoryUI

var local_player: CharacterBody2D = null
var nearby_station: Node2D = null
var nearby_npc: Node2D = null  # Named NPC (dialogue)
var _gift_queue: Array = []    # Gifts waiting to display after dialogue


func _ready() -> void:
	GameManager.change_state(GameManager.State.HUB)
	_build_hub_tilemap()
	_create_stations()
	_create_named_npcs()
	_spawn_players()
	shop_panel.hide()
	vault_panel.hide()
	interact_label.hide()
	if inventory_ui:
		inventory_ui.hide()
	MusicManager.play_zone("hub")
	# Note: We handle gifts via _gift_queue in _dismiss_hub_dialogue, not via signal


func _process(_delta: float) -> void:
	if local_player and is_instance_valid(local_player):
		camera.global_position = local_player.global_position
		_check_station_proximity()
		_check_npc_proximity()


# -------------------------------------------------------
# Hub tilemap — simple hand-crafted room
# -------------------------------------------------------
func _build_hub_tilemap() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/sprites/tiles/tileset.png") as Texture2D
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	for row in 2:
		for col in 6:
			source.create_tile(Vector2i(col, row))

	# Add source to tileset first so tile data can see physics layers
	ts.add_source(source, 0)
	tilemap.tile_set = ts

	# Wall collision — must be set after tileset is assigned
	var half := TILE_SIZE / 2.0
	var wall_polygon := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	])
	for coord in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(0, 1)]:
		var td := source.get_tile_data(coord, 0)
		if td:
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, wall_polygon)

	# Paint the hub: a cozy room with walls around the edges
	var wall_atlas := Vector2i(0, 0)  # Zone 1 wall (Flooded Ruins)
	var floor_atlas := Vector2i(1, 0) # Zone 1 floor
	for y in HUB_HEIGHT:
		for x in HUB_WIDTH:
			if x == 0 or x == HUB_WIDTH - 1 or y == 0 or y == HUB_HEIGHT - 1:
				tilemap.set_cell(Vector2i(x, y), 0, wall_atlas)
			else:
				tilemap.set_cell(Vector2i(x, y), 0, floor_atlas)
	# Decorative elements
	_add_hub_decor()


func _add_hub_decor() -> void:
	# Stage / practice area (center, near Roadie Rick)
	_add_decor_sprite(Vector2(10, 9) * TILE_SIZE, Color(0.4, 0.1, 0.1, 0.9), Vector2(10, 6))
	# Stage lights glow
	var glow := PointLight2D.new()
	glow.global_position = Vector2(10, 9) * TILE_SIZE
	glow.color = Color(1.0, 0.3, 0.5, 0.4)
	glow.energy = 0.6
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color.WHITE)
	grad.gradient.set_color(1, Color.TRANSPARENT)
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(0.5, 0.0)
	grad.width = 64
	grad.height = 64
	glow.texture = grad
	add_child(glow)

	# Backstage catering counter (near Mama Krill)
	_add_decor_sprite(Vector2(14, 3) * TILE_SIZE, Color(0.5, 0.35, 0.2), Vector2(16, 4))
	# Mixing desk / turntables (near DJ Scratch)
	_add_decor_sprite(Vector2(7, 13) * TILE_SIZE, Color(0.2, 0.2, 0.3), Vector2(12, 6))
	# Venue entrance archway (departure point)
	_add_decor_sprite(Vector2(24, 11) * TILE_SIZE, Color(0.6, 0.1, 0.1), Vector2(8, 14))


func _add_decor_sprite(pos: Vector2, color: Color, size: Vector2) -> void:
	var s := Sprite2D.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = size
	s.texture = tex
	s.modulate = color
	s.global_position = pos
	add_child(s)


# -------------------------------------------------------
# NPC stations
# -------------------------------------------------------
var stations: Array[Dictionary] = []

func _create_stations() -> void:
	# Shop NPC — top left area
	_add_station("Shop", Vector2i(5, 4), "Shop — Spend Tide Tokens")
	# Vault — top right area
	_add_station("Vault", Vector2i(24, 4), "Vault — Saved Items")
	# Lore Keeper — bottom left
	_add_station("Lore", Vector2i(5, 12), "Lore Keeper — Colony History")
	# Departure — bottom right (gateway to dungeon)
	_add_station("Departure", Vector2i(24, 12), "Depart — Begin Expedition")


func _add_station(station_name: String, tile_pos: Vector2i, prompt_text: String) -> void:
	var npc := Area2D.new()
	npc.name = station_name
	npc.global_position = Vector2(tile_pos) * TILE_SIZE
	npc.add_to_group("hub_station")
	npc.set_meta("station_type", station_name)
	npc.set_meta("prompt_text", prompt_text)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	npc.add_child(col)

	# Visual marker — a colored sprite placeholder
	var marker := Sprite2D.new()
	marker.texture = PlaceholderTexture2D.new()
	(marker.texture as PlaceholderTexture2D).size = Vector2(12, 12)
	match station_name:
		"Shop":      marker.modulate = Color(1.0, 0.85, 0.1)  # Gold
		"Vault":     marker.modulate = Color(0.3, 0.6, 1.0)   # Blue
		"Lore":      marker.modulate = Color(0.6, 0.9, 0.5)   # Green
		"Departure": marker.modulate = Color(1.0, 0.3, 0.3)   # Red
	npc.add_child(marker)

	# Label above NPC
	var lbl := Label.new()
	lbl.text = station_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-20, -18)
	lbl.add_theme_font_size_override("font_size", 7)
	npc.add_child(lbl)

	add_child(npc)
	stations.append({"node": npc, "type": station_name, "prompt": prompt_text})


# -------------------------------------------------------
# Named NPCs (Hades-style characters)
# -------------------------------------------------------
var named_npcs: Array[Dictionary] = []

var NPC_POSITIONS := {
	0: Vector2i(10, 8),   # ROADIE_RICK — Center-left, by the stage
	1: Vector2i(7, 4),    # MELODY — Near the merch table
	2: Vector2i(8, 12),   # DJ_SCRATCH — Near the mixing desk
	3: Vector2i(15, 3),   # MAMA_KRILL — Center top, backstage catering
	4: Vector2i(26, 14),  # THE_PRODUCER — Far corner, mysterious
}

func _create_named_npcs() -> void:
	for npc_id in NPC_POSITIONS:
		if not DialogueManager.is_npc_available(npc_id):
			continue
		var pos: Vector2i = NPC_POSITIONS[npc_id]
		var npc_name: String = DialogueManager.NPC_NAMES.get(npc_id, "???")
		var npc_color: Color = DialogueManager.NPC_COLORS.get(npc_id, Color.WHITE)

		var node := Area2D.new()
		node.name = "NPC_%s" % npc_name.replace(" ", "_")
		node.global_position = Vector2(pos) * TILE_SIZE
		node.add_to_group("hub_npc")
		node.set_meta("npc_id", npc_id)
		node.set_meta("npc_name", npc_name)

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 16.0
		col.shape = shape
		node.add_child(col)

		# Visual — slightly larger than station markers, unique color
		var marker := Sprite2D.new()
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(14, 14)
		marker.texture = tex
		marker.modulate = npc_color
		node.add_child(marker)

		# Name label above
		var lbl := Label.new()
		lbl.text = npc_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(-28, -20)
		lbl.add_theme_font_size_override("font_size", 6)
		lbl.add_theme_color_override("font_color", npc_color)
		node.add_child(lbl)

		# Affinity indicator (small dots showing relationship level)
		var affinity_lbl := Label.new()
		affinity_lbl.name = "AffinityLabel"
		var aff: int = DialogueManager.affinity.get(npc_id, 0)
		var hearts := ""
		if aff >= 20: hearts += "o"
		if aff >= 40: hearts += "o"
		if aff >= 60: hearts += "o"
		if aff >= 80: hearts += "o"
		affinity_lbl.text = hearts
		affinity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		affinity_lbl.position = Vector2(-20, -28)
		affinity_lbl.add_theme_font_size_override("font_size", 5)
		affinity_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.7))
		node.add_child(affinity_lbl)

		add_child(node)
		named_npcs.append({"node": node, "npc_id": npc_id, "name": npc_name})


const NPC_INTERACT_RANGE := 26.0

func _check_npc_proximity() -> void:
	if not local_player:
		return
	var closest: Node2D = null
	var closest_dist := NPC_INTERACT_RANGE
	for npc in named_npcs:
		var node: Node2D = npc["node"]
		var dist := local_player.global_position.distance_to(node.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = node
	if closest != nearby_npc:
		nearby_npc = closest
		# Only update prompt if no station is nearby (stations take priority for prompt text)
		if nearby_npc and not nearby_station:
			var npc_name: String = nearby_npc.get_meta("npc_name", "???")
			interact_label.text = "[E] Talk to %s" % npc_name
			interact_label.show()
		elif not nearby_station:
			interact_label.hide()


func _talk_to_npc() -> void:
	if not nearby_npc or _hub_dialogue_active:
		return
	shop_panel.hide()
	vault_panel.hide()
	var npc_id: int = nearby_npc.get_meta("npc_id", -1)
	if npc_id < 0:
		return
	# Get dialogue from DialogueManager
	var result := DialogueManager.get_dialogue(npc_id)
	var speaker: String = result.get("speaker", "???")
	var text: String = result.get("text", "...")
	var color: Color = DialogueManager.NPC_COLORS.get(npc_id, Color.WHITE)

	# Show via hub dialogue popup
	_get_or_create_hub_dialogue()
	show_dialogue(speaker, text, color)

	# Check for gifts after dialogue
	var gift := DialogueManager.check_gift(npc_id)
	if not gift.is_empty():
		gift["npc_id"] = npc_id
		_gift_queue.append(gift)

	# Update affinity indicator
	_refresh_npc_affinity(npc_id)

	# Persist dialogue state and emit signal
	UnlockManager.save_data()
	DialogueManager.dialogue_started.emit(npc_id, text, speaker)



func _apply_gift(gift: Dictionary) -> void:
	match gift.get("type", ""):
		"buff":
			DialogueManager.add_run_buff({
				"buff_type": gift.get("buff_type", ""),
				"value": gift.get("value", 0),
			})
		"item":
			var item_data: Dictionary = gift.get("item_data", {})
			if not item_data.is_empty() and local_player:
				local_player.pick_up_item(item_data.duplicate(true))
		"unlock":
			var key: String = gift.get("unlock_key", "")
			if key != "" and UnlockManager.unlocks.has(key):
				UnlockManager.unlocks[key] = true
				UnlockManager.save_data()
		"consumable":
			# Add as a consumable item to player inventory
			if local_player:
				var consumable := {
					"display_name": gift.get("name", "Consumable"),
					"item_type": ItemDatabase.ItemType.POTION,
					"effect": "heal",
					"power": 50,
					"rarity": 2,
					"desc": gift.get("desc", ""),
				}
				local_player.pick_up_item(consumable)


func _refresh_npc_affinity(npc_id: int) -> void:
	for npc in named_npcs:
		if npc["npc_id"] == npc_id:
			var node: Node2D = npc["node"]
			var aff_label := node.get_node_or_null("AffinityLabel")
			if aff_label:
				var aff: int = DialogueManager.affinity.get(npc_id, 0)
				var hearts := ""
				if aff >= 20: hearts += "o"
				if aff >= 40: hearts += "o"
				if aff >= 60: hearts += "o"
				if aff >= 80: hearts += "o"
				(aff_label as Label).text = hearts
			break


var _hub_dialogue_panel: PanelContainer = null
var _hub_dialogue_speaker: Label = null
var _hub_dialogue_text: Label = null
var _hub_dialogue_active: bool = false

func _get_or_create_hub_dialogue() -> void:
	if _hub_dialogue_panel:
		return
	# Build a simple dialogue popup for the hub
	_hub_dialogue_panel = PanelContainer.new()
	_hub_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hub_dialogue_panel.offset_left = -140
	_hub_dialogue_panel.offset_right = 140
	_hub_dialogue_panel.offset_top = -80
	_hub_dialogue_panel.offset_bottom = -10

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	sb.border_color = Color(0.3, 0.4, 0.5, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	_hub_dialogue_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	_hub_dialogue_speaker = Label.new()
	_hub_dialogue_speaker.add_theme_font_size_override("font_size", 8)
	vbox.add_child(_hub_dialogue_speaker)

	_hub_dialogue_text = Label.new()
	_hub_dialogue_text.add_theme_font_size_override("font_size", 7)
	_hub_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_hub_dialogue_text)

	var continue_lbl := Label.new()
	continue_lbl.text = "[Any key to continue]"
	continue_lbl.add_theme_font_size_override("font_size", 5)
	continue_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	continue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(continue_lbl)

	_hub_dialogue_panel.add_child(vbox)
	_hub_dialogue_panel.visible = false
	hud_layer.add_child(_hub_dialogue_panel)


func show_dialogue(speaker: String, text: String, color: Color = Color.WHITE) -> void:
	if not _hub_dialogue_panel:
		_get_or_create_hub_dialogue()
	_hub_dialogue_speaker.text = speaker
	_hub_dialogue_speaker.add_theme_color_override("font_color", color)
	_hub_dialogue_text.text = text
	_hub_dialogue_panel.show()
	_hub_dialogue_active = true


func _dismiss_hub_dialogue() -> void:
	if _hub_dialogue_panel:
		_hub_dialogue_panel.hide()
	_hub_dialogue_active = false
	# Show queued gift dialogues
	if not _gift_queue.is_empty():
		var gift: Dictionary = _gift_queue.pop_front()
		var npc_id: int = gift.get("npc_id", 0)
		var speaker: String = DialogueManager.NPC_NAMES.get(npc_id, "???")
		var color: Color = DialogueManager.NPC_COLORS.get(npc_id, Color.WHITE)
		var gift_text: String = gift.get("dialogue", "Here, take this.")
		gift_text += "\n\n[Received: %s]" % gift.get("name", "???")
		show_dialogue(speaker, gift_text, color)
		_apply_gift(gift)


# -------------------------------------------------------
# Station proximity & interaction
# -------------------------------------------------------
const STATION_INTERACT_RANGE := 28.0

func _check_station_proximity() -> void:
	if not local_player:
		return
	var closest: Node2D = null
	var closest_dist := STATION_INTERACT_RANGE
	for station in stations:
		var node: Node2D = station["node"]
		var dist := local_player.global_position.distance_to(node.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = node
	if closest != nearby_station:
		nearby_station = closest
		if nearby_station:
			interact_label.text = "[E] " + nearby_station.get_meta("prompt_text", "Interact")
			interact_label.show()
		elif not nearby_npc:
			interact_label.hide()


func _unhandled_input(event: InputEvent) -> void:
	# ESC / ui_cancel closes any open panel
	if event.is_action_pressed("ui_cancel"):
		if _hub_dialogue_active:
			_dismiss_hub_dialogue()
			get_viewport().set_input_as_handled()
			return
		if shop_panel.visible:
			shop_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if vault_panel.visible:
			vault_panel.hide()
			get_viewport().set_input_as_handled()
			return
		if inventory_ui and inventory_ui.visible:
			inventory_ui.hide()
			get_viewport().set_input_as_handled()
			return
	# Dismiss hub dialogue on any key
	if _hub_dialogue_active and (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_dismiss_hub_dialogue()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		if nearby_station:
			var station_type: String = nearby_station.get_meta("station_type", "")
			match station_type:
				"Shop":      _open_shop()
				"Vault":     _open_vault()
				"Lore":      _open_lore()
				"Departure": _depart_for_dungeon()
		elif nearby_npc:
			_talk_to_npc()
	if event.is_action_pressed("inventory_open") and local_player and inventory_ui:
		inventory_ui.toggle(local_player)


# -------------------------------------------------------
# Shop UI
# -------------------------------------------------------
func _open_shop() -> void:
	if shop_panel.visible:
		shop_panel.hide()
		return
	vault_panel.hide()
	shop_panel.show()
	_populate_shop_ui()


func _populate_shop_ui() -> void:
	var list := shop_panel.get_node_or_null("ItemList")
	if not list:
		return
	for child in list.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "Tide Tokens: %d" % UnlockManager.tide_tokens
	header.add_theme_font_size_override("font_size", 9)
	list.add_child(header)

	for entry in UnlockManager.SHOP:
		if UnlockManager.is_unlocked(entry["key"]):
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %d" % [entry["label"], entry["cost"]]
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.text = "Buy"
		btn.add_theme_font_size_override("font_size", 7)
		btn.custom_minimum_size = Vector2(30, 12)
		btn.disabled = not UnlockManager.can_purchase(entry["key"])
		var key: String = entry["key"]
		btn.pressed.connect(func():
			UnlockManager.purchase(key)
			_populate_shop_ui()
		)
		row.add_child(lbl)
		row.add_child(btn)
		list.add_child(row)


# -------------------------------------------------------
# Vault UI
# -------------------------------------------------------
func _open_vault() -> void:
	if vault_panel.visible:
		vault_panel.hide()
		return
	shop_panel.hide()
	vault_panel.show()
	_populate_vault_ui()


func _populate_vault_ui() -> void:
	var list := vault_panel.get_node_or_null("ItemList")
	if not list:
		return
	for child in list.get_children():
		child.queue_free()

	var saved: Array = UnlockManager.get_saved_items()
	if saved.is_empty():
		var lbl := Label.new()
		lbl.text = "No saved items yet.\nComplete a run to save one item!"
		lbl.add_theme_font_size_override("font_size", 7)
		list.add_child(lbl)
		return

	for item in saved:
		var lbl := Label.new()
		var display: String = item.get("display_name", "Unknown Item")
		var rarity: int = item.get("rarity", 0)
		lbl.text = display
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(rarity))
		list.add_child(lbl)


# -------------------------------------------------------
# Lore
# -------------------------------------------------------
func _open_lore() -> void:
	shop_panel.hide()
	vault_panel.hide()
	var lore_entries: Array[String] = []
	if UnlockManager.is_unlocked("lore_zone1"):
		lore_entries.append("The colony built a cage in the deep.")
	if UnlockManager.is_unlocked("lore_zone2"):
		lore_entries.append("The Pact was sealed in willing blood.")
	if UnlockManager.is_unlocked("lore_zone3"):
		lore_entries.append("Your parents knew. They always knew.")
	if UnlockManager.is_unlocked("lore_sanctum"):
		lore_entries.append("Something was counting the days.")
	if lore_entries.is_empty():
		lore_entries.append("No lore discovered yet.\nExplore deeper.")
	_get_or_create_hub_dialogue()
	show_dialogue("Lore Keeper", "\n".join(lore_entries), Color(0.6, 0.9, 0.5))


# -------------------------------------------------------
# Departure — start dungeon run
# -------------------------------------------------------
func _depart_for_dungeon() -> void:
	shop_panel.hide()
	vault_panel.hide()
	if multiplayer.is_server():
		# Gather class choices from NetworkManager players
		var selected: Array[int] = []
		for pid in NetworkManager.players:
			var info: Dictionary = NetworkManager.players[pid]
			selected.append(info.get("chosen_class", 0))
		GameManager.enter_dungeon(selected)
	else:
		_request_departure.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_departure() -> void:
	if multiplayer.is_server():
		_depart_for_dungeon()


# -------------------------------------------------------
# Player spawning
# -------------------------------------------------------
func _spawn_players() -> void:
	var spawn_pos := Vector2(15, 8) * TILE_SIZE  # Center of hub
	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		var chosen_class: int = info.get("chosen_class", 0)
		var player := PlayerScene.instantiate()
		player.set_multiplayer_authority(peer_id)
		player.set_script(PlayerScripts[chosen_class])
		# Pre-build sprite frames before entering tree to avoid "no animation" warning
		var anim: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
		anim.sprite_frames = SpriteFramesBuilder.build_frames_for_class(chosen_class)
		player.global_position = spawn_pos + Vector2(randi_range(-16, 16), randi_range(-16, 16))
		player.name = "Player_%d" % peer_id
		players_node.add_child(player, true)

		if peer_id == multiplayer.get_unique_id():
			local_player = player

	# If no players registered (single player dev), spawn a default
	if NetworkManager.players.is_empty():
		var player := PlayerScene.instantiate()
		player.set_multiplayer_authority(1)
		player.set_script(PlayerScripts[ItemDatabase.PlayerClass.EMPEROR])
		var anim: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
		anim.sprite_frames = SpriteFramesBuilder.build_frames_for_class(ItemDatabase.PlayerClass.EMPEROR)
		player.global_position = spawn_pos
		player.name = "Player_1"
		players_node.add_child(player, true)
		local_player = player
