extends Node
# BSP Dungeon Generator for TUX
# Produces a grid of TileType values for each dungeon floor.
# Deterministic: same seed always produces same dungeon.

enum TileType {
	WALL,
	FLOOR,
	DOOR,
	STAIRS_DOWN,
	STAIRS_UP,
	SECRET_WALL,   # Looks like WALL, breakable to reveal hidden room
	CHEST,
	SPAWN,
}

# Zone themes affect tile palette and enemy spawns
enum ZoneTheme {
	FLOODED_RUINS,   # Zone 1 — crabs, basic enemies
	CORAL_CRYPTS,    # Zone 2 — stinging swarms, boss: Crab Warlord
	ABYSSAL_TRENCH,  # Zone 3 — predators, all types
	GODS_SANCTUM,    # Zone 4 — final zone, Drowned God
}

const MAP_WIDTH  := 80
const MAP_HEIGHT := 60
const MIN_ROOM_SIZE := 6   # minimum room dimension
const MAX_SPLIT_DEPTH := 5

# Lore mural rooms — placed once per zone when colony secret is in progress
const MURAL_ROOM_TAG := "mural"

class Room:
	var x: int
	var y: int
	var w: int
	var h: int

	func _init(rx: int, ry: int, rw: int, rh: int) -> void:
		x = rx; y = ry; w = rw; h = rh

	func center() -> Vector2i:
		return Vector2i(x + w / 2, y + h / 2)

	func random_point(rng: RandomNumberGenerator) -> Vector2i:
		return Vector2i(
			rng.randi_range(x + 1, x + w - 2),
			rng.randi_range(y + 1, y + h - 2)
		)

	func intersects(other: Room, margin: int = 1) -> bool:
		return not (x + w + margin <= other.x or other.x + other.w + margin <= x or
					y + h + margin <= other.y or other.y + other.h + margin <= y)


class DungeonData:
	var tiles: Array = []           # 2D array [y][x] of TileType
	var rooms: Array = []           # Array of Room
	var spawn_position: Vector2i = Vector2i.ZERO
	var stairs_down: Vector2i = Vector2i.ZERO
	var stairs_up: Vector2i = Vector2i.ZERO
	var enemy_spawns: Array = []    # Array of { position, type_hint }
	var item_spawns: Array = []     # Array of { position }
	var chest_positions: Array = []
	var mural_position: Vector2i = Vector2i(-1, -1)
	var theme: int = ZoneTheme.FLOODED_RUINS
	var floor_number: int = 0


# -------------------------------------------------------
# Main entry point
# -------------------------------------------------------
static func generate(floor_number: int, run_seed: int) -> DungeonData:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed + floor_number * 9973  # each floor gets a unique but deterministic seed

	var data := DungeonData.new()
	data.floor_number = floor_number
	data.theme = _floor_to_theme(floor_number)
	data.tiles = _blank_map()

	var root_rect := Room.new(0, 0, MAP_WIDTH, MAP_HEIGHT)
	var leaves: Array = []
	_bsp_split(root_rect, 0, leaves, rng)

	# Carve rooms from leaves
	for leaf in leaves:
		var room := _carve_room(leaf, rng)
		data.rooms.append(room)
		_paint_room(data.tiles, room)

	# Connect rooms with corridors
	for i in range(data.rooms.size() - 1):
		_carve_corridor(data.tiles, data.rooms[i], data.rooms[i + 1], rng)

	# Place spawn in first room, stairs down in last room
	var spawn_room: Room = data.rooms[0]
	var stairs_room: Room = data.rooms[data.rooms.size() - 1]

	data.spawn_position = spawn_room.center()
	data.tiles[data.spawn_position.y][data.spawn_position.x] = TileType.SPAWN

	data.stairs_down = stairs_room.center()
	data.tiles[data.stairs_down.y][data.stairs_down.x] = TileType.STAIRS_DOWN

	if floor_number > 0:
		data.stairs_up = spawn_room.random_point(rng)
		data.tiles[data.stairs_up.y][data.stairs_up.x] = TileType.STAIRS_UP

	# Populate: enemies, items, chests
	_populate_enemies(data, rng)
	_populate_items(data, rng)
	_place_chests(data, rng)

	# Secret rooms (hidden behind breakable walls)
	_place_secret_rooms(data, rng)

	# Lore mural room (zone 2+, once per zone)
	if floor_number >= 3:
		_place_mural_room(data, rng)

	return data


# -------------------------------------------------------
# BSP splitting
# -------------------------------------------------------
static func _bsp_split(rect: Room, depth: int, leaves: Array, rng: RandomNumberGenerator) -> void:
	if depth >= MAX_SPLIT_DEPTH or (rect.w < MIN_ROOM_SIZE * 2 and rect.h < MIN_ROOM_SIZE * 2):
		leaves.append(rect)
		return

	var split_horizontal := rng.randi() % 2 == 0
	if rect.w < MIN_ROOM_SIZE * 2:
		split_horizontal = true
	elif rect.h < MIN_ROOM_SIZE * 2:
		split_horizontal = false

	if split_horizontal:
		var split := rng.randi_range(int(rect.h * 0.4), int(rect.h * 0.6))
		_bsp_split(Room.new(rect.x, rect.y, rect.w, split), depth + 1, leaves, rng)
		_bsp_split(Room.new(rect.x, rect.y + split, rect.w, rect.h - split), depth + 1, leaves, rng)
	else:
		var split := rng.randi_range(int(rect.w * 0.4), int(rect.w * 0.6))
		_bsp_split(Room.new(rect.x, rect.y, split, rect.h), depth + 1, leaves, rng)
		_bsp_split(Room.new(rect.x + split, rect.y, rect.w - split, rect.h), depth + 1, leaves, rng)


# -------------------------------------------------------
# Room carving
# -------------------------------------------------------
static func _carve_room(leaf: Room, rng: RandomNumberGenerator) -> Room:
	var padding := 1
	var max_w := leaf.w - padding * 2
	var max_h := leaf.h - padding * 2
	var rw := rng.randi_range(MIN_ROOM_SIZE, max(MIN_ROOM_SIZE, max_w))
	var rh := rng.randi_range(MIN_ROOM_SIZE, max(MIN_ROOM_SIZE, max_h))
	var rx := leaf.x + padding + rng.randi_range(0, max(0, max_w - rw))
	var ry := leaf.y + padding + rng.randi_range(0, max(0, max_h - rh))
	return Room.new(rx, ry, rw, rh)


static func _paint_room(tiles: Array, room: Room) -> void:
	for y in range(room.y, room.y + room.h):
		for x in range(room.x, room.x + room.w):
			if _in_bounds(x, y):
				tiles[y][x] = TileType.FLOOR


# -------------------------------------------------------
# Corridor carving (L-shaped)
# -------------------------------------------------------
static func _carve_corridor(tiles: Array, a: Room, b: Room, rng: RandomNumberGenerator) -> void:
	var pa := a.random_point(rng)
	var pb := b.random_point(rng)

	# Randomly choose horizontal-first or vertical-first
	if rng.randi() % 2 == 0:
		_carve_h_corridor(tiles, pa.x, pb.x, pa.y)
		_carve_v_corridor(tiles, pa.y, pb.y, pb.x)
	else:
		_carve_v_corridor(tiles, pa.y, pb.y, pa.x)
		_carve_h_corridor(tiles, pa.x, pb.x, pb.y)


static func _carve_h_corridor(tiles: Array, x1: int, x2: int, y: int) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if _in_bounds(x, y):
			tiles[y][x] = TileType.FLOOR


static func _carve_v_corridor(tiles: Array, y1: int, y2: int, x: int) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if _in_bounds(x, y):
			tiles[y][x] = TileType.FLOOR


# -------------------------------------------------------
# Population
# -------------------------------------------------------
static func _populate_enemies(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# Skip spawn room and stairs room
	for i in range(1, data.rooms.size() - 1):
		var room: Room = data.rooms[i]
		var count := rng.randi_range(1, 3 + data.floor_number / 2)
		for _j in count:
			data.enemy_spawns.append({
				"position": room.random_point(rng),
				"floor": data.floor_number,
				"theme": data.theme,
			})


static func _populate_items(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# ~40% of non-spawn rooms get a floor item
	for i in range(1, data.rooms.size()):
		if rng.randf() < 0.4:
			data.item_spawns.append({
				"position": data.rooms[i].random_point(rng),
			})


static func _place_chests(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# 1–2 chests per floor, in random rooms (not spawn, not stairs)
	var eligible := data.rooms.slice(1, data.rooms.size() - 1)
	var count := rng.randi_range(1, min(2, eligible.size()))
	for _i in count:
		var room: Room = eligible[rng.randi() % eligible.size()]
		var pos := room.random_point(rng)
		data.chest_positions.append(pos)
		data.tiles[pos.y][pos.x] = TileType.CHEST


# -------------------------------------------------------
# Secrets & Lore
# -------------------------------------------------------
static func _place_secret_rooms(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# 0–2 secret rooms: a wall tile adjacent to a floor room is marked SECRET_WALL
	var secret_count := rng.randi_range(0, 2)
	for _i in secret_count:
		if data.rooms.size() < 2:
			return
		var room: Room = data.rooms[rng.randi() % data.rooms.size()]
		# Pick a wall adjacent to the room
		var candidates := []
		for x in range(room.x - 1, room.x + room.w + 1):
			if _in_bounds(x, room.y - 1) and data.tiles[room.y - 1][x] == TileType.WALL:
				candidates.append(Vector2i(x, room.y - 1))
			if _in_bounds(x, room.y + room.h) and data.tiles[room.y + room.h][x] == TileType.WALL:
				candidates.append(Vector2i(x, room.y + room.h))
		if not candidates.is_empty():
			var wall_pos: Vector2i = candidates[rng.randi() % candidates.size()]
			data.tiles[wall_pos.y][wall_pos.x] = TileType.SECRET_WALL


static func _place_mural_room(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# A dedicated room with a lore mural — reveals part of the colony's sin
	if data.rooms.size() < 3:
		return
	var room: Room = data.rooms[rng.randi_range(1, data.rooms.size() - 2)]
	data.mural_position = room.center()


# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
static func _blank_map() -> Array:
	var tiles := []
	for _y in MAP_HEIGHT:
		var row := []
		row.resize(MAP_WIDTH)
		row.fill(TileType.WALL)
		tiles.append(row)
	return tiles


static func _in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < MAP_WIDTH and y >= 0 and y < MAP_HEIGHT


static func _floor_to_theme(floor_number: int) -> int:
	if floor_number < 3:    return ZoneTheme.FLOODED_RUINS
	elif floor_number < 6:  return ZoneTheme.CORAL_CRYPTS
	elif floor_number < 9:  return ZoneTheme.ABYSSAL_TRENCH
	else:                   return ZoneTheme.GODS_SANCTUM
