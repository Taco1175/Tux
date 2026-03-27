extends Node2D
# Hub World for TUX — Hades-style base between dungeon runs.
# Players walk around, interact with NPCs (shop, vault, lore, departure).

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

var local_player: CharacterBody2D = null
var nearby_station: Node2D = null


func _ready() -> void:
	GameManager.change_state(GameManager.State.HUB)
	_build_hub_tilemap()
	_create_stations()
	_spawn_players()
	shop_panel.hide()
	vault_panel.hide()
	interact_label.hide()


func _process(_delta: float) -> void:
	if local_player and is_instance_valid(local_player):
		camera.global_position = local_player.global_position
		_check_station_proximity()


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

	# Wall collision
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

	ts.add_source(source, 0)
	tilemap.tile_set = ts

	# Paint the hub: a cozy room with walls around the edges
	var wall_atlas := Vector2i(0, 0)  # Zone 1 wall (Flooded Ruins)
	var floor_atlas := Vector2i(1, 0) # Zone 1 floor
	for y in HUB_HEIGHT:
		for x in HUB_WIDTH:
			if x == 0 or x == HUB_WIDTH - 1 or y == 0 or y == HUB_HEIGHT - 1:
				tilemap.set_cell(Vector2i(x, y), 0, wall_atlas)
			else:
				tilemap.set_cell(Vector2i(x, y), 0, floor_atlas)


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
		else:
			interact_label.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and nearby_station:
		var station_type: String = nearby_station.get_meta("station_type", "")
		match station_type:
			"Shop":      _open_shop()
			"Vault":     _open_vault()
			"Lore":      _open_lore()
			"Departure": _depart_for_dungeon()


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
		lore_entries.append("Zone 1: The colony built a cage in the deep.")
	if UnlockManager.is_unlocked("lore_zone2"):
		lore_entries.append("Zone 2: The Pact was sealed in willing blood.")
	if UnlockManager.is_unlocked("lore_zone3"):
		lore_entries.append("Zone 3: Your parents knew. They always knew.")
	if UnlockManager.is_unlocked("lore_sanctum"):
		lore_entries.append("Sanctum: Something was counting the days.")
	if lore_entries.is_empty():
		lore_entries.append("No lore discovered yet. Explore deeper.")
	# Show as simple message via interact_label
	interact_label.text = "\n".join(lore_entries)
	interact_label.show()
	await get_tree().create_timer(5.0).timeout
	if nearby_station == null or nearby_station.get_meta("station_type", "") != "Lore":
		interact_label.hide()


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
		player.global_position = spawn_pos
		player.name = "Player_1"
		players_node.add_child(player, true)
		local_player = player
