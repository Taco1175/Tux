extends Control

# Lobby scene — handles host/join, class selection, ready-up
# Supports 1–4 players

const CLASS_NAMES := ["Emperor", "Gentoo", "Little Blue", "Macaroni"]
const CLASS_DESCS := [
	"The oldest. Overprotective.\nHigh HP, heavy armor, shield bash.\nSlow but immovable.",
	"The chaotic middle sibling.\nFastest, crits hard, dies easy.\nGoggles and a bad attitude.",
	"The peacekeeper.\nBalanced stats, support skills.\nSnaps exactly once.",
	"The youngest. Unnerving calm.\nGlass cannon mage.\nAccidentally the most powerful.",
]

@onready var host_button: Button = $UI/ConnectionPanel/HostButton
@onready var join_button: Button = $UI/ConnectionPanel/JoinButton
@onready var address_input: LineEdit = $UI/ConnectionPanel/AddressInput
@onready var port_input: LineEdit = $UI/ConnectionPanel/PortInput
@onready var status_label: Label = $UI/StatusLabel
@onready var player_list: VBoxContainer = $UI/PlayerList
@onready var class_selector: HBoxContainer = $UI/ClassSelector
@onready var ready_button: Button = $UI/ReadyButton
@onready var start_button: Button = $UI/StartButton
@onready var token_label: Label = $UI/TokenLabel

var selected_class: int = 0
var is_ready: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.all_players_ready.connect(_on_all_players_ready)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	start_button.visible = false
	ready_button.disabled = true
	token_label.text = "Tide Tokens: %d" % UnlockManager.tide_tokens

	_build_class_selector()


func _build_class_selector() -> void:
	for i in CLASS_NAMES.size():
		var btn := Button.new()
		btn.text = CLASS_NAMES[i]
		btn.tooltip_text = CLASS_DESCS[i]
		btn.disabled = not _is_class_available(i)
		btn.pressed.connect(_on_class_selected.bind(i))
		class_selector.add_child(btn)
	_highlight_class(selected_class)


func _is_class_available(class_index: int) -> bool:
	match class_index:
		0: return UnlockManager.is_unlocked("class_emperor")
		1: return UnlockManager.is_unlocked("class_gentoo")
		2: return UnlockManager.is_unlocked("class_little_blue")
		3: return UnlockManager.is_unlocked("class_macaroni")
	return false


func _highlight_class(index: int) -> void:
	for i in class_selector.get_child_count():
		var btn := class_selector.get_child(i) as Button
		btn.modulate = Color.WHITE if i != index else Color(1.0, 0.85, 0.2)


# -------------------------------------------------------
# Connection
# -------------------------------------------------------
func _on_host_pressed() -> void:
	var port := int(port_input.text) if port_input.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err := NetworkManager.host_game(port)
	if err == OK:
		status_label.text = "Hosting on port %d — waiting for players…" % port
		host_button.disabled = true
		join_button.disabled = true
		ready_button.disabled = false
		start_button.visible = true
		start_button.disabled = true
		_refresh_player_list()
	else:
		status_label.text = "Failed to host. Check port."


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port := int(port_input.text) if port_input.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err := NetworkManager.join_game(address, port)
	if err == OK:
		status_label.text = "Connecting to %s:%d…" % [address, port]
		host_button.disabled = true
		join_button.disabled = true
	else:
		status_label.text = "Failed to connect."


# -------------------------------------------------------
# Class selection
# -------------------------------------------------------
func _on_class_selected(index: int) -> void:
	selected_class = index
	_highlight_class(index)
	var local_id := multiplayer.get_unique_id()
	if NetworkManager.players.has(local_id):
		NetworkManager.players[local_id]["chosen_class"] = index
	NetworkManager._register_player.rpc_id(1, NetworkManager.players.get(local_id, NetworkManager._default_player_info()))


# -------------------------------------------------------
# Ready / Start
# -------------------------------------------------------
func _on_ready_pressed() -> void:
	is_ready = not is_ready
	ready_button.text = "Unready" if is_ready else "Ready"
	NetworkManager.set_player_ready.rpc(is_ready)


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager.server_start_game()


func _on_all_players_ready() -> void:
	if multiplayer.is_server():
		start_button.disabled = false
		status_label.text = "All players ready — host can start!"


# -------------------------------------------------------
# Player list refresh
# -------------------------------------------------------
func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	status_label.text = "Player joined (%d/%d)" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	_refresh_player_list()
	if not multiplayer.is_server():
		ready_button.disabled = false


func _on_player_disconnected(peer_id: int) -> void:
	status_label.text = "Player left."
	_refresh_player_list()


func _on_server_disconnected() -> void:
	status_label.text = "Lost connection to host."
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()

	for peer_id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[peer_id]
		var label := Label.new()
		var class_name_str := CLASS_NAMES[info.get("chosen_class", 0)]
		var ready_str := "✓" if info.get("ready", false) else "…"
		label.text = "[%s] %s — %s" % [ready_str, info.get("name", "?"), class_name_str]
		player_list.add_child(label)
