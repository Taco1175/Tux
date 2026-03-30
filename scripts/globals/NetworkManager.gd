extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS  := 4

# Default relay server — replace with your VPS IP/domain after deploying relay_server.py
const DEFAULT_RELAY_URL := "ws://localhost:9999"

# Peer ID -> player info
var players: Dictionary = {}
var local_peer_id: int = 1

# Online relay state
var _relay_ws: WebSocketPeer = null
var _relay_url: String = DEFAULT_RELAY_URL
var _room_code: String = ""
var _is_host: bool = false
var _relay_active: bool = false

signal player_connected(peer_id: int, info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected()
signal all_players_ready()
signal room_created(code: String)
signal room_joined(peer_count: int)
signal relay_error(message: String)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if _relay_active and _relay_ws:
		_relay_ws.poll()
		_drain_relay_messages()


# -------------------------------------------------------
# LAN Host / Join  (unchanged)
# -------------------------------------------------------
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("NetworkManager: Failed to create server on port %d" % port)
		return err
	multiplayer.multiplayer_peer = peer
	local_peer_id = 1
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


# -------------------------------------------------------
# Online Host  (WebSocket relay)
# -------------------------------------------------------
func host_online(relay_url: String = DEFAULT_RELAY_URL) -> void:
	_relay_url = relay_url
	_is_host = true
	_relay_ws = WebSocketPeer.new()
	var err := _relay_ws.connect_to_url(relay_url)
	if err != OK:
		relay_error.emit("Could not connect to relay server.")
		return
	_relay_active = true
	# Wait for socket to open, then send host request
	if not await _wait_for_relay_open():
		return
	_relay_send({"action": "host"})


func join_online(code: String, relay_url: String = DEFAULT_RELAY_URL) -> void:
	_relay_url = relay_url
	_is_host = false
	_room_code = code.to_upper().strip_edges()
	_relay_ws = WebSocketPeer.new()
	var err := _relay_ws.connect_to_url(relay_url)
	if err != OK:
		relay_error.emit("Could not connect to relay server.")
		return
	_relay_active = true
	if not await _wait_for_relay_open():
		return
	_relay_send({"action": "join", "code": _room_code})


func get_room_code() -> String:
	return _room_code


# -------------------------------------------------------
# Relay internals
# -------------------------------------------------------
func _wait_for_relay_open() -> bool:
	var timeout := 5.0  # seconds
	var elapsed := 0.0
	while _relay_ws and _relay_ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_relay_ws.poll()
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed >= timeout:
			_relay_active = false
			_relay_ws = null
			relay_error.emit("Relay connection timed out.")
			return false
	if not _relay_ws or _relay_ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_relay_active = false
		_relay_ws = null
		relay_error.emit("Could not reach relay server.")
		return false
	return true


func _relay_send(msg: Dictionary) -> void:
	if not _relay_ws:
		return
	var json_str := JSON.stringify(msg)
	_relay_ws.send_text(json_str)


func _drain_relay_messages() -> void:
	if not _relay_ws:
		return
	while _relay_ws.get_available_packet_count() > 0:
		var raw := _relay_ws.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			_handle_relay_message(parsed)


func _handle_relay_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"hosted":
			_room_code = msg.get("code", "")
			# Now start the actual ENet server locally
			host_game()
			room_created.emit(_room_code)

		"joined":
			var peer_id: int = msg.get("peer_id", 2)
			local_peer_id = peer_id
			# Connect to host via relay-proxied ENet
			# For relay play we use WebSocket multiplayer directly
			_start_websocket_client(peer_id)
			room_joined.emit(msg.get("peer_count", 1))

		"peer_joined":
			var peer_id: int = msg.get("peer_id", 0)
			players[peer_id] = _default_player_info()
			player_connected.emit(peer_id, players[peer_id])

		"peer_left":
			var peer_id: int = msg.get("peer_id", 0)
			players.erase(peer_id)
			player_disconnected.emit(peer_id)

		"relay":
			# Raw game data relayed from another peer (for WebSocketMultiplayerPeer)
			pass  # Handled by WebSocketMultiplayerPeer internally

		"error":
			relay_error.emit(msg.get("message", "Relay error."))

		"pong":
			pass


func _start_websocket_client(peer_id: int) -> void:
	# Once joined, switch multiplayer peer to WebSocket for actual game data
	var ws_peer := WebSocketMultiplayerPeer.new()
	var err := ws_peer.create_client(_relay_url.replace("ws://", "ws://") + "/game")
	if err != OK:
		relay_error.emit("WebSocket game connection failed.")
		return
	multiplayer.multiplayer_peer = ws_peer
	local_peer_id = peer_id


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	if _relay_ws:
		_relay_ws.close()
		_relay_ws = null
	_relay_active = false
	_room_code = ""
	players.clear()


# -------------------------------------------------------
# Player info sync
# -------------------------------------------------------
func register_player(info: Dictionary) -> void:
	_register_player.rpc(info)


@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
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
@rpc("authority", "call_local", "reliable")
func start_game_rpc(_run_seed: int, class_assignments: Dictionary) -> void:
	var selected: Array[int] = []
	for pid in class_assignments:
		selected.append(class_assignments[pid])
	# Store class selections but don't start a run yet — go to hub first
	GameManager.change_state(GameManager.State.HUB)
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


func server_start_game() -> void:
	if not multiplayer.is_server():
		return
	var assignments: Dictionary = {}
	var class_index := 0
	for pid in players:
		assignments[pid] = players[pid].get("chosen_class", class_index)
		class_index += 1
	start_game_rpc.rpc(GameManager.current_run.run_seed if GameManager.current_run else randi(), assignments)


# -------------------------------------------------------
# Callbacks
# -------------------------------------------------------
func _on_peer_connected(_peer_id: int) -> void:
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
