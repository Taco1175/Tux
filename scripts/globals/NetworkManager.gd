extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

# Peer ID -> player info
var players: Dictionary = {}
var local_peer_id: int = 1

signal player_connected(peer_id: int, info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal all_players_ready()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# -------------------------------------------------------
# Host / Join
# -------------------------------------------------------
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to create server on port %d" % port)
		return err
	multiplayer.multiplayer_peer = peer
	local_peer_id = 1
	# Host registers themselves
	players[1] = _default_player_info()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("NetworkManager: Failed to connect to %s:%d" % [address, port])
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	players.clear()


# -------------------------------------------------------
# Player info sync
# -------------------------------------------------------
func register_player(info: Dictionary) -> void:
	# Called locally, then synced to all peers
	_register_player.rpc(info)


@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	players[sender_id] = info
	player_connected.emit(sender_id, info)
	_check_all_ready()


@rpc("any_peer", "reliable")
func set_player_ready(is_ready: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		players[sender_id]["ready"] = is_ready
	_check_all_ready()


func _check_all_ready() -> void:
	if not multiplayer.is_server():
		return
	if players.size() < 1:
		return
	for info in players.values():
		if not info.get("ready", false):
			return
	all_players_ready.emit()


# -------------------------------------------------------
# Game start sync (server -> all clients)
# -------------------------------------------------------
@rpc("authority", "reliable")
func start_game_rpc(run_seed: int, class_assignments: Dictionary) -> void:
	# class_assignments: peer_id -> PlayerClass enum value
	var selected: Array[int] = []
	for pid in class_assignments:
		selected.append(class_assignments[pid])
	GameManager.start_run(selected)
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")


func server_start_game() -> void:
	if not multiplayer.is_server():
		return
	var assignments: Dictionary = {}
	var class_index := 0
	for pid in players:
		assignments[pid] = players[pid].get("chosen_class", class_index)
		class_index += 1
	start_game_rpc.rpc(GameManager.current_run.seed if GameManager.current_run else randi(), assignments)


# -------------------------------------------------------
# Callbacks
# -------------------------------------------------------
func _on_peer_connected(peer_id: int) -> void:
	# New client connected to our server — they'll register themselves via RPC
	pass


func _on_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	player_disconnected.emit(peer_id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	register_player(_default_player_info())


func _on_connection_failed() -> void:
	push_error("NetworkManager: Connection failed")
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	players.clear()
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()


func _default_player_info() -> Dictionary:
	return {
		"peer_id": multiplayer.get_unique_id(),
		"name": "Penguin_%d" % multiplayer.get_unique_id(),
		"chosen_class": 0,
		"ready": false,
	}
