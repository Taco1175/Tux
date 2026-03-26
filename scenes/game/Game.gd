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

const TILE_SIZE := 16

var dungeon_data: BSPGenerator.DungeonData = null
var local_player: Node2D = null

# Ending dilemma tracking
var ending_active: bool = false


func _ready() -> void:
	if multiplayer.is_server():
		_generate_floor()
		_spawn_all_players()
	else:
		# Clients wait for server to send dungeon seed + spawn info
		pass

	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	GameManager.run_ended.connect(_on_run_ended)


# -------------------------------------------------------
# Floor generation (server)
# -------------------------------------------------------
func _generate_floor() -> void:
	var run := GameManager.current_run
	dungeon_data = BSPGenerator.generate(run.floor_number, run.seed)
	_broadcast_floor.rpc(run.floor_number, run.seed)
	_build_tilemap()
	_spawn_enemies()
	_spawn_floor_items()


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
	# Maps tile type + zone theme to atlas coordinates in your tileset
	# These coordinates correspond to your 8-bit tileset sprite sheet
	# Adjust once you have actual art assets
	match tile_type:
		BSPGenerator.TileType.WALL:
			match theme:
				BSPGenerator.ZoneTheme.FLOODED_RUINS:  return Vector2i(0, 0)
				BSPGenerator.ZoneTheme.CORAL_CRYPTS:   return Vector2i(1, 0)
				BSPGenerator.ZoneTheme.ABYSSAL_TRENCH: return Vector2i(2, 0)
				BSPGenerator.ZoneTheme.GODS_SANCTUM:   return Vector2i(3, 0)
		BSPGenerator.TileType.FLOOR:
			match theme:
				BSPGenerator.ZoneTheme.FLOODED_RUINS:  return Vector2i(0, 1)
				BSPGenerator.ZoneTheme.CORAL_CRYPTS:   return Vector2i(1, 1)
				BSPGenerator.ZoneTheme.ABYSSAL_TRENCH: return Vector2i(2, 1)
				BSPGenerator.ZoneTheme.GODS_SANCTUM:   return Vector2i(3, 1)
		BSPGenerator.TileType.STAIRS_DOWN: return Vector2i(4, 0)
		BSPGenerator.TileType.STAIRS_UP:   return Vector2i(4, 1)
		BSPGenerator.TileType.CHEST:       return Vector2i(5, 0)
		BSPGenerator.TileType.SECRET_WALL: return Vector2i(0, 0)  # Looks like a wall
		BSPGenerator.TileType.SPAWN:       return Vector2i(0, 1)  # Looks like floor
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
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
