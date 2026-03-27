extends Node2D
# Main Game scene for TUX
# Orchestrates: dungeon generation, player spawning, enemy spawning,
# loot drops, floor transitions, and the four ending paths.

const BSPGenerator  = preload("res://scripts/utils/BSPGenerator.gd")
const ItemGenerator = preload("res://scenes/items/ItemGenerator.gd")
const EnemyScript   = preload("res://scenes/enemies/Enemy.gd")

const PlayerScripts := {
	ItemDatabase.PlayerClass.EMPEROR:    preload("res://scenes/player/classes/Emperor.gd"),
	ItemDatabase.PlayerClass.GENTOO:     preload("res://scenes/player/classes/Gentoo.gd"),
	ItemDatabase.PlayerClass.LITTLE_BLUE: preload("res://scenes/player/classes/LittleBlue.gd"),
	ItemDatabase.PlayerClass.MACARONI:   preload("res://scenes/player/classes/Macaroni.gd"),
}

const PlayerScene    := preload("res://scenes/player/Player.tscn")
const EnemyScene     := preload("res://scenes/enemies/Enemy.tscn")
const ItemScene      := preload("res://scenes/items/Item.tscn")

@onready var tilemap: TileMapLayer = $DungeonTileMap
@onready var players_node: Node2D  = $Players
@onready var enemies_node: Node2D  = $Enemies
@onready var items_node: Node2D    = $Items
@onready var hud: Control          = $HUD
@onready var camera: Camera2D      = $Camera2D

const TILE_SIZE := 16
const ProjectileScene := preload("res://scenes/game/Projectile.tscn")

var dungeon_data: BSPGenerator.DungeonData = null
var local_player: Node2D = null

# Ending dilemma tracking
var ending_active: bool = false

# Stair transition guard
var _stairs_triggered: bool = false


func _ready() -> void:
	add_to_group("game_scene")
	_setup_tileset()

	if multiplayer.is_server():
		_generate_floor()
		_spawn_all_players()
	else:
		# Clients wait for server to send dungeon seed + spawn info
		pass

	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.run_ended.connect(_on_run_ended)


# -------------------------------------------------------
# TileSet setup (programmatic — no editor config needed)
# Tileset layout (96×80, 6 cols × 5 rows of 16×16 tiles):
#  Row 0: Zone1 wall(0,0), Zone1 floor(1,0), Zone2 wall(2,0),
#          Zone2 floor(3,0), Zone3 wall(4,0), Zone3 floor(5,0)
#  Row 1: Zone4 wall(0,1), Zone4 floor(1,1), stairs_down(2,1),
#          stairs_up(3,1), chest(4,1), spawn(5,1)
# -------------------------------------------------------
func _setup_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Physics layer so walls block movement (layer 1 = default body layer)
	ts.add_physics_layer(0)
	ts.set_physics_layer_collision_layer(0, 1)
	ts.set_physics_layer_collision_mask(0, 1)

	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/sprites/tiles/tileset.png") as Texture2D
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Register all 12 used tiles
	for row in 2:
		for col in 6:
			source.create_tile(Vector2i(col, row))

	# Add source to tileset first so tile data can see physics layers
	ts.add_source(source, 0)
	tilemap.tile_set = ts

	# Add full-tile collision polygon to wall tiles (after tileset is assigned)
	var half := TILE_SIZE / 2.0
	var wall_polygon := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half),   Vector2(-half, half),
	])
	var wall_coords := [
		Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0), Vector2i(0, 1),
	]
	for coord in wall_coords:
		var td := source.get_tile_data(coord, 0)
		if td:
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, wall_polygon)


func _process(_delta: float) -> void:
	# Camera follows the local player
	if local_player and is_instance_valid(local_player):
		camera.global_position = local_player.global_position

	# Server checks if a player has reached the stairs
	if multiplayer.is_server() and dungeon_data and not _stairs_triggered:
		_check_stair_proximity()


# -------------------------------------------------------
# Floor generation (server)
# -------------------------------------------------------
func _generate_floor() -> void:
	_stairs_triggered = false
	# Clear previous floor entities
	for child in enemies_node.get_children():
		child.queue_free()
	for child in items_node.get_children():
		child.queue_free()

	var run := GameManager.current_run
	dungeon_data = BSPGenerator.generate(run.floor_number, run.run_seed)
	_broadcast_floor.rpc(run.floor_number, run.run_seed)
	_build_tilemap()
	_spawn_enemies()
	_spawn_floor_items()
	_spawn_chests()
	_spawn_zone_boss()
	_place_mural_marker()


@rpc("authority", "reliable")
func _broadcast_floor(floor_number: int, seed: int) -> void:
	if multiplayer.is_server():
		return
	dungeon_data = BSPGenerator.generate(floor_number, seed)
	_build_tilemap()


func _build_tilemap() -> void:
	tilemap.clear()
	for y in BSPGenerator.MAP_HEIGHT:
		for x in BSPGenerator.MAP_WIDTH:
			var tile_type: int = dungeon_data.tiles[y][x]
			var source_id := 0
			var atlas_coords := _tile_type_to_atlas(tile_type, dungeon_data.theme)
			if atlas_coords != Vector2i(-1, -1):
				tilemap.set_cell(Vector2i(x, y), source_id, atlas_coords)


func _tile_type_to_atlas(tile_type: int, theme: int) -> Vector2i:
	# Tileset columns: wall and floor alternate per zone (col 0-5, rows 0-1)
	match tile_type:
		BSPGenerator.TileType.WALL:
			match theme:
				BSPGenerator.ZoneTheme.FLOODED_RUINS:  return Vector2i(0, 0)
				BSPGenerator.ZoneTheme.CORAL_CRYPTS:   return Vector2i(2, 0)
				BSPGenerator.ZoneTheme.ABYSSAL_TRENCH: return Vector2i(4, 0)
				BSPGenerator.ZoneTheme.GODS_SANCTUM:   return Vector2i(0, 1)
		BSPGenerator.TileType.FLOOR:
			match theme:
				BSPGenerator.ZoneTheme.FLOODED_RUINS:  return Vector2i(1, 0)
				BSPGenerator.ZoneTheme.CORAL_CRYPTS:   return Vector2i(3, 0)
				BSPGenerator.ZoneTheme.ABYSSAL_TRENCH: return Vector2i(5, 0)
				BSPGenerator.ZoneTheme.GODS_SANCTUM:   return Vector2i(1, 1)
		BSPGenerator.TileType.STAIRS_DOWN: return Vector2i(2, 1)
		BSPGenerator.TileType.STAIRS_UP:   return Vector2i(3, 1)
		BSPGenerator.TileType.CHEST:       return Vector2i(4, 1)
		BSPGenerator.TileType.SPAWN:       return Vector2i(5, 1)
		BSPGenerator.TileType.SECRET_WALL: return Vector2i(0, 0)  # Looks like a wall
		BSPGenerator.TileType.DOOR:        return Vector2i(1, 0)  # Looks like floor
	return Vector2i(-1, -1)


# -------------------------------------------------------
# Player spawning
# -------------------------------------------------------
func _spawn_all_players() -> void:
	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		var chosen_class: int = info.get("chosen_class", 0)
		_spawn_player(peer_id, chosen_class)


func _spawn_player(peer_id: int, chosen_class: int) -> void:
	var player := PlayerScene.instantiate()
	player.set_multiplayer_authority(peer_id)
	player.set_script(PlayerScripts[chosen_class])
	var spawn_world_pos := Vector2(dungeon_data.spawn_position) * TILE_SIZE
	player.global_position = spawn_world_pos + Vector2(randi_range(-8, 8), randi_range(-8, 8))
	player.name = "Player_%d" % peer_id
	players_node.add_child(player, true)

	player.died.connect(_on_player_died)

	if peer_id == multiplayer.get_unique_id():
		local_player = player
		hud.set_player(player)

	if GameManager.current_run:
		GameManager.current_run.players_alive.append(peer_id)


# -------------------------------------------------------
# Enemy spawning (server)
# -------------------------------------------------------
func _spawn_enemies() -> void:
	if not multiplayer.is_server():
		return
	for spawn_data in dungeon_data.enemy_spawns:
		var enemy := EnemyScene.instantiate()
		enemy.enemy_type = _pick_enemy_type(spawn_data)
		enemy.global_position = Vector2(spawn_data["position"]) * TILE_SIZE
		enemies_node.add_child(enemy, true)
		enemy.died.connect(_on_enemy_died)


func _pick_enemy_type(spawn_data: Dictionary) -> int:
	var theme: int = spawn_data.get("theme", BSPGenerator.ZoneTheme.FLOODED_RUINS)
	match theme:
		BSPGenerator.ZoneTheme.FLOODED_RUINS:
			return [
				EnemyScript.EnemyType.CRAB_GRUNT,
				EnemyScript.EnemyType.CRAB_GRUNT,
				EnemyScript.EnemyType.EEL_SCOUT,
			][randi() % 3]
		BSPGenerator.ZoneTheme.CORAL_CRYPTS:
			return [
				EnemyScript.EnemyType.CRAB_KNIGHT,
				EnemyScript.EnemyType.JELLYFISH_DRIFTER,
				EnemyScript.EnemyType.URCHIN_ROLLER,
			][randi() % 3]
		BSPGenerator.ZoneTheme.ABYSSAL_TRENCH:
			return [
				EnemyScript.EnemyType.SHARK_BRUTE,
				EnemyScript.EnemyType.ANGLERFISH,
				EnemyScript.EnemyType.ANEMONE_TRAP,
			][randi() % 3]
		_:
			return EnemyScript.EnemyType.CRAB_GRUNT


# -------------------------------------------------------
# Loot drops (server)
# -------------------------------------------------------
func _on_enemy_died(enemy: Node, pos: Vector2) -> void:
	if not multiplayer.is_server():
		return

	# Award XP to all living players
	var xp: int = enemy.xp_reward
	_broadcast_xp.rpc(xp)

	# Drop loot
	var run := GameManager.current_run
	var drop_roll := randf()
	if drop_roll < 0.6:  # 60% chance to drop something
		var bias := _get_nearest_player_class(pos)
		var item_data := ItemGenerator.generate_for_class(
			run.floor_number if run else 0, bias
		)
		_spawn_item_drop(pos, item_data)

	# Tide Tokens (run currency)
	var tokens := randi_range(1, 3 + (run.floor_number if run else 0))
	_award_tokens.rpc(tokens)


func _spawn_floor_items() -> void:
	for spawn_data in dungeon_data.item_spawns:
		var item_data := ItemGenerator.generate(GameManager.current_run.floor_number if GameManager.current_run else 0)
		_spawn_item_drop(Vector2(spawn_data["position"]) * TILE_SIZE, item_data)


func _spawn_chests() -> void:
	var floor_num := GameManager.current_run.floor_number if GameManager.current_run else 0
	for pos in dungeon_data.chest_positions:
		# Chests guarantee better loot — pass floor+2 to shift rarity weights up
		var item_data := ItemGenerator.generate(floor_num + 2)
		_spawn_item_drop(Vector2(pos) * TILE_SIZE, item_data)


# -------------------------------------------------------
# Secret walls (server)
# -------------------------------------------------------
func try_break_secret_wall(player_pos: Vector2) -> void:
	if not multiplayer.is_server() or not dungeon_data:
		return
	var tile_pos := Vector2i(int(player_pos.x / TILE_SIZE), int(player_pos.y / TILE_SIZE))
	# Check the 4 adjacent tiles for SECRET_WALL
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for offset in offsets:
		var check: Vector2i = tile_pos + offset
		if check.x >= 0 and check.x < BSPGenerator.MAP_WIDTH and check.y >= 0 and check.y < BSPGenerator.MAP_HEIGHT:
			if dungeon_data.tiles[check.y][check.x] == BSPGenerator.TileType.SECRET_WALL:
				dungeon_data.tiles[check.y][check.x] = BSPGenerator.TileType.FLOOR
				_broadcast_secret_wall_break.rpc(check)
				return


@rpc("authority", "call_local", "reliable")
func _broadcast_secret_wall_break(tile: Vector2i) -> void:
	# Replace the wall tile with a floor tile on all clients
	var theme: int = dungeon_data.theme if dungeon_data else BSPGenerator.ZoneTheme.FLOODED_RUINS
	var floor_atlas := _tile_type_to_atlas(BSPGenerator.TileType.FLOOR, theme)
	tilemap.set_cell(tile, 0, floor_atlas)
	if hud:
		hud.show_message("A hidden passage!", 1.5)


# -------------------------------------------------------
# Lore murals
# -------------------------------------------------------
const LoreMuralScript = preload("res://scenes/game/LoreMural.gd")

func _place_mural_marker() -> void:
	if not multiplayer.is_server() or not dungeon_data:
		return
	if dungeon_data.mural_position == Vector2i(-1, -1):
		return
	var mural := Area2D.new()
	mural.name = "LoreMural"
	mural.set_script(LoreMuralScript)
	mural.global_position = Vector2(dungeon_data.mural_position) * TILE_SIZE
	mural.add_to_group("interactable")
	mural.mural_zone = dungeon_data.theme
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	mural.add_child(col)
	items_node.add_child(mural, true)


const MURAL_TEXTS := {
	BSPGenerator.ZoneTheme.FLOODED_RUINS:
		"The walls depict penguins building something deep underground.\nIt looks like... a cage.",
	BSPGenerator.ZoneTheme.CORAL_CRYPTS:
		"A mural shows the colony elders kneeling before something massive.\n\"The Pact was sealed in willing blood.\"",
	BSPGenerator.ZoneTheme.ABYSSAL_TRENCH:
		"The final mural. Your parents, younger, standing at this exact spot.\nThey knew. They always knew.",
	BSPGenerator.ZoneTheme.GODS_SANCTUM:
		"There is no mural here. Just claw marks on the wall.\nSomething was counting the days.",
}


func show_mural(zone: int) -> void:
	var text: String = MURAL_TEXTS.get(zone, "The wall is blank.")
	_broadcast_mural.rpc(text, zone)


@rpc("authority", "call_local", "reliable")
func _broadcast_mural(text: String, zone: int) -> void:
	if hud:
		hud.show_message(text, 4.0)
	# Mark lore as discovered
	var lore_key := ""
	match zone:
		BSPGenerator.ZoneTheme.FLOODED_RUINS:  lore_key = "lore_zone1"
		BSPGenerator.ZoneTheme.CORAL_CRYPTS:   lore_key = "lore_zone2"
		BSPGenerator.ZoneTheme.ABYSSAL_TRENCH: lore_key = "lore_zone3"
		BSPGenerator.ZoneTheme.GODS_SANCTUM:   lore_key = "lore_sanctum"
	if lore_key != "" and not UnlockManager.is_unlocked(lore_key):
		UnlockManager.unlocks[lore_key] = true
		UnlockManager.save_data()
	if GameManager.current_run and zone == BSPGenerator.ZoneTheme.CORAL_CRYPTS:
		GameManager.current_run.colony_secret_known = true


# -------------------------------------------------------
# Zone bosses
# -------------------------------------------------------
func _spawn_zone_boss() -> void:
	if not multiplayer.is_server() or not dungeon_data:
		return
	var floor_num := dungeon_data.floor_number
	var boss_type := -1
	# Spawn boss on last floor of each zone
	match floor_num:
		2: boss_type = EnemyScript.EnemyType.LOBSTER_WARLORD
		5: boss_type = EnemyScript.EnemyType.CRAB_WARLORD
		8: boss_type = EnemyScript.EnemyType.THE_LEVIATHAN
	if floor_num >= 9:
		boss_type = EnemyScript.EnemyType.THE_DROWNED_GOD

	if boss_type < 0:
		return

	# Spawn boss in the stairs room (last room, guarding exit)
	var boss_room: BSPGenerator.Room = dungeon_data.rooms[dungeon_data.rooms.size() - 1]
	var enemy := EnemyScene.instantiate()
	enemy.enemy_type = boss_type
	enemy.global_position = Vector2(boss_room.center()) * TILE_SIZE
	enemies_node.add_child(enemy, true)
	enemy.died.connect(_on_enemy_died)


# -------------------------------------------------------
# Stair detection (server)
# -------------------------------------------------------
func _check_stair_proximity() -> void:
	var stairs_world := Vector2(dungeon_data.stairs_down) * TILE_SIZE
	for player in players_node.get_children():
		if player.is_dead:
			continue
		if player.global_position.distance_to(stairs_world) < TILE_SIZE * 1.5:
			_stairs_triggered = true
			_on_player_reached_stairs()
			return


# -------------------------------------------------------
# Projectile spawning (called by player ability RPCs)
# -------------------------------------------------------
func spawn_projectile(origin: Vector2, direction: Vector2, speed: float,
		damage: int, max_range: float, aoe_radius: float) -> void:
	var proj := ProjectileScene.instantiate()
	proj.global_position = origin
	proj.setup(damage, direction, speed, max_range, aoe_radius, multiplayer.is_server())
	items_node.add_child(proj)


func spawn_fireball(origin: Vector2, target_pos: Vector2,
		damage: int, aoe_radius: float) -> void:
	var direction := (target_pos - origin).normalized()
	var dist := origin.distance_to(target_pos)
	var proj := ProjectileScene.instantiate()
	proj.global_position = origin
	proj.setup(damage, direction, 150.0, dist, aoe_radius, multiplayer.is_server())
	items_node.add_child(proj)


func _spawn_item_drop(pos: Vector2, item_data: Dictionary) -> void:
	var item_node := ItemScene.instantiate()
	item_node.global_position = pos
	item_node.setup(item_data)
	items_node.add_child(item_node, true)


func _get_nearest_player_class(pos: Vector2) -> int:
	var closest_class := -1
	var closest_dist := INF
	for player in players_node.get_children():
		var dist := pos.distance_to(player.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_class = player.player_class
	return closest_class


@rpc("authority", "reliable")
func _broadcast_xp(amount: int) -> void:
	if local_player and local_player.has_method("add_xp"):
		local_player.add_xp(amount)


@rpc("authority", "reliable")
func _award_tokens(amount: int) -> void:
	if GameManager.current_run:
		GameManager.current_run.run_currency += amount


# -------------------------------------------------------
# Floor transition
# -------------------------------------------------------
func _on_player_reached_stairs() -> void:
	if not multiplayer.is_server():
		return
	# All living players must be at stairs (or a timer expires)
	GameManager.current_run.floor_number += 1
	_check_for_sanctum()
	_generate_floor()
	_reposition_players()


func _check_for_sanctum() -> void:
	var floor_num := GameManager.current_run.floor_number
	if floor_num >= 9 and not GameManager.current_run.parents_found:
		# Trigger sanctum arrival — reveal the truth, initiate ending sequence
		_trigger_sanctum_arrival.rpc()


@rpc("authority", "reliable")
func _trigger_sanctum_arrival() -> void:
	GameManager.current_run.parents_found = true
	ending_active = true
	hud.show_sanctum_message()


func _reposition_players() -> void:
	var spawn_pos := Vector2(dungeon_data.spawn_position) * TILE_SIZE
	for player in players_node.get_children():
		player.global_position = spawn_pos


# -------------------------------------------------------
# The Four Endings (triggered from ending UI)
# -------------------------------------------------------
func trigger_ending(choice: int) -> void:
	if not multiplayer.is_server():
		_request_ending.rpc_id(1, choice)
		return
	_execute_ending(choice)


@rpc("any_peer", "reliable")
func _request_ending(choice: int) -> void:
	if multiplayer.is_server():
		_execute_ending(choice)


func _execute_ending(choice: int) -> void:
	match choice:
		GameManager.EndingChoice.LET_PARENTS_GO:
			_ending_let_parents_go.rpc()
		GameManager.EndingChoice.SIBLING_STAYS:
			_ending_sibling_stays.rpc()
		GameManager.EndingChoice.EXPOSE_AND_REFUSE:
			_ending_expose.rpc()
		GameManager.EndingChoice.REIMPRISION_THE_GOD:
			_ending_reimprision.rpc()


@rpc("authority", "call_local", "reliable")
func _ending_let_parents_go() -> void:
	# Path A — parents sacrifice. Siblings surface alone.
	# Unlock: "ending_expose_unlocked" for next run.
	hud.play_ending_cutscene(GameManager.EndingChoice.LET_PARENTS_GO)
	await get_tree().create_timer(3.0).timeout
	GameManager.end_run(GameManager.EndingChoice.LET_PARENTS_GO)


@rpc("authority", "call_local", "reliable")
func _ending_sibling_stays() -> void:
	# Path B — a sibling volunteers. In co-op: the player who triggers it stays.
	var sacrificed_peer := multiplayer.get_remote_sender_id()
	if sacrificed_peer == 0:
		sacrificed_peer = 1  # server/host triggered it
	if GameManager.current_run:
		GameManager.current_run.sibling_sacrificed_peer = sacrificed_peer
	hud.play_ending_cutscene(GameManager.EndingChoice.SIBLING_STAYS)
	# Remove the sacrificed player's character
	for player in players_node.get_children():
		if player.get_multiplayer_authority() == sacrificed_peer:
			player.queue_free()
	await get_tree().create_timer(3.0).timeout
	GameManager.end_run(GameManager.EndingChoice.SIBLING_STAYS)


@rpc("authority", "call_local", "reliable")
func _ending_expose() -> void:
	# Path C — refuse, surface, blow the whistle.
	# Only available after seeing Path A or B once.
	hud.play_ending_cutscene(GameManager.EndingChoice.EXPOSE_AND_REFUSE)
	await get_tree().create_timer(3.0).timeout
	GameManager.end_run(GameManager.EndingChoice.EXPOSE_AND_REFUSE)


@rpc("authority", "call_local", "reliable")
func _ending_reimprision() -> void:
	# Path D — put it back in the cage. Everyone goes home. You know what you did.
	hud.play_ending_cutscene(GameManager.EndingChoice.REIMPRISION_THE_GOD)
	await get_tree().create_timer(3.0).timeout
	GameManager.end_run(GameManager.EndingChoice.REIMPRISION_THE_GOD)


# -------------------------------------------------------
# Death & disconnects
# -------------------------------------------------------
func _on_player_died(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var run := GameManager.current_run
	if run and run.players_alive.is_empty():
		# All dead — game over
		_all_dead.rpc()


@rpc("authority", "reliable")
func _all_dead() -> void:
	hud.show_game_over()
	await get_tree().create_timer(2.5).timeout
	GameManager.end_run(GameManager.EndingChoice.NONE)


func _on_player_disconnected(peer_id: int) -> void:
	for player in players_node.get_children():
		if player.get_multiplayer_authority() == peer_id:
			player.queue_free()


func _on_run_ended(_choice: int) -> void:
	# Show item save screen, then return to hub
	get_tree().change_scene_to_file("res://scenes/ui/ItemSaveScreen.tscn")
