extends Control

# Lobby scene — handles host/join (LAN + Online), class selection, ready-up
# Supports 1–4 players

const CLASS_NAMES := ["Emperor", "Gentoo", "Little Blue", "Macaroni"]
const CLASS_DESCS := [
	"Lead Guitar. The oldest sibling.\nWields a battle axe guitar.\nHeavy riffs, heavy armor. Slow but unstoppable.",
	"Drums. The chaotic middle sibling.\nDual-wields drumsticks like daggers.\nFastest tempo, hardest crits. Glass jaw.",
	"Vocals. The peacekeeper.\nMic stand as weapon, voice as power.\nHeals with ballads. Snaps into death metal once.",
	"Bass. The youngest. Unnerving calm.\nBass guitar channels sonic devastation.\nGlass cannon. Accidentally the loudest.",
]

@onready var host_button: Button           = $Panel/Margin/UI/LANRow/HostButton
@onready var join_button: Button           = $Panel/Margin/UI/LANRow/JoinButton
@onready var host_online_button: Button    = $Panel/Margin/UI/OnlineRow/HostOnlineButton
@onready var join_online_button: Button    = $Panel/Margin/UI/OnlineRow/JoinOnlineButton
@onready var address_input: LineEdit       = $Panel/Margin/UI/LANRow/AddressInput
@onready var port_input: LineEdit          = $Panel/Margin/UI/LANRow/PortInput
@onready var room_code_input: LineEdit     = $Panel/Margin/UI/OnlineRow/RoomCodeInput
@onready var room_code_display: Label      = $Panel/Margin/UI/RoomCodeDisplay
@onready var status_label: Label           = $Panel/Margin/UI/StatusLabel
@onready var player_list: VBoxContainer    = $Panel/Margin/UI/PlayerList
@onready var class_selector: HBoxContainer = $Panel/Margin/UI/ClassRow/ClassInfo/ClassSelector
@onready var class_desc_label: Label       = $Panel/Margin/UI/ClassRow/ClassInfo/ClassDescLabel
@onready var class_portrait: TextureRect   = $Panel/Margin/UI/ClassRow/ClassPortrait
@onready var ready_button: Button          = $Panel/Margin/UI/BottomRow/ReadyButton
@onready var start_button: Button          = $Panel/Margin/UI/BottomRow/StartButton
@onready var token_label: Label            = $Panel/Margin/UI/BottomRow/TokenLabel

var selected_class: int = 0
var is_ready: bool = false


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	host_online_button.pressed.connect(_on_host_online_pressed)
	join_online_button.pressed.connect(_on_join_online_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)

	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.relay_error.connect(_on_relay_error)

	start_button.visible = false
	ready_button.disabled = true
	room_code_display.visible = false
	token_label.text = "Tide Tokens: %d" % UnlockManager.tide_tokens

	_build_class_selector()
	_update_class_preview(selected_class)
	_add_solo_button()


const CLASS_ROLES := ["Lead Guitar", "Drums", "Vocals", "Bass"]
const CLASS_COLORS := [
	Color(0.3, 0.5, 0.9),   # Emperor — blue
	Color(1.0, 0.5, 0.2),   # Gentoo — orange
	Color(0.4, 0.9, 0.5),   # Little Blue — green
	Color(0.9, 0.3, 0.9),   # Macaroni — purple
]
var _roster_panels: Array[PanelContainer] = []

func _build_class_selector() -> void:
	# Clear existing children in class_selector
	for child in class_selector.get_children():
		child.queue_free()

	# Build 4 character panels side by side (fighting game roster style)
	for i in CLASS_NAMES.size():
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(90, 120)

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.12, 0.9)
		sb.border_color = CLASS_COLORS[i] * 0.5
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(4)
		panel.add_theme_stylebox_override("panel", sb)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)

		# Character portrait (colored placeholder)
		var portrait := TextureRect.new()
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(32, 32)
		portrait.texture = tex
		portrait.custom_minimum_size = Vector2(32, 32)
		portrait.modulate = CLASS_COLORS[i] if _is_class_available(i) else Color(0.3, 0.3, 0.3)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		vbox.add_child(portrait)

		# Try to load actual sprite sheet
		var sheet := load(CLASS_SHEET_PATHS[i]) as Texture2D
		if sheet and _is_class_available(i):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(0, 0, 16, 16)
			portrait.texture = atlas
			portrait.modulate = Color.WHITE

		# Name
		var name_lbl := Label.new()
		name_lbl.text = CLASS_NAMES[i]
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.add_theme_color_override("font_color", CLASS_COLORS[i])
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(name_lbl)

		# Role
		var role_lbl := Label.new()
		role_lbl.text = CLASS_ROLES[i]
		role_lbl.add_theme_font_size_override("font_size", 5)
		role_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(role_lbl)

		# Description (compact)
		var desc_lbl := Label.new()
		desc_lbl.text = CLASS_DESCS[i]
		desc_lbl.add_theme_font_size_override("font_size", 4)
		desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.custom_minimum_size = Vector2(80, 0)
		vbox.add_child(desc_lbl)

		# Locked overlay
		if not _is_class_available(i):
			var lock_lbl := Label.new()
			lock_lbl.text = "LOCKED"
			lock_lbl.add_theme_font_size_override("font_size", 6)
			lock_lbl.add_theme_color_override("font_color", Color(0.6, 0.2, 0.2))
			lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vbox.add_child(lock_lbl)

		panel.add_child(vbox)

		# Click handler
		panel.gui_input.connect(_on_roster_panel_input.bind(i))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

		class_selector.add_child(panel)
		_roster_panels.append(panel)

	_highlight_class(selected_class)


func _on_roster_panel_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_class_available(index):
			_on_class_selected(index)


func _is_class_available(class_index: int) -> bool:
	match class_index:
		0: return UnlockManager.is_unlocked("class_emperor")
		1: return UnlockManager.is_unlocked("class_gentoo")
		2: return UnlockManager.is_unlocked("class_little_blue")
		3: return UnlockManager.is_unlocked("class_macaroni")
	return false


func _highlight_class(index: int) -> void:
	for i in _roster_panels.size():
		var panel: PanelContainer = _roster_panels[i]
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if i == index:
			sb.border_color = CLASS_COLORS[i]
			sb.set_border_width_all(2)
			panel.modulate = Color.WHITE
		else:
			sb.border_color = CLASS_COLORS[i] * 0.3
			sb.set_border_width_all(1)
			panel.modulate = Color(0.7, 0.7, 0.7)


const CLASS_SHEET_PATHS := [
	"res://assets/sprites/players/emperor_sheet.png",
	"res://assets/sprites/players/gentoo_sheet.png",
	"res://assets/sprites/players/little_blue_sheet.png",
	"res://assets/sprites/players/macaroni_sheet.png",
]

func _update_class_preview(index: int) -> void:
	class_desc_label.text = CLASS_DESCS[index]
	if not _is_class_available(index):
		class_portrait.texture = null
		class_desc_label.text = "LOCKED — earn Tide Tokens to unlock.\n" + CLASS_DESCS[index]
		return
	var sheet := load(CLASS_SHEET_PATHS[index]) as Texture2D
	if sheet:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, 16, 16)
		class_portrait.texture = atlas
	else:
		class_portrait.texture = null


# -------------------------------------------------------
# Connection — LAN
# -------------------------------------------------------
func _on_host_pressed() -> void:
	var port := int(port_input.text) if port_input.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err := NetworkManager.host_game(port)
	if err == OK:
		status_label.text = "Hosting on port %d. Share your IP with friends." % port
		_lock_connection_buttons()
		start_button.visible = true
		start_button.disabled = false  # Host can start anytime
		ready_button.disabled = false
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
		_lock_connection_buttons()
	else:
		status_label.text = "Failed to connect."


# -------------------------------------------------------
# Connection — Online (relay)
# -------------------------------------------------------
func _on_host_online_pressed() -> void:
	status_label.text = "Connecting to relay server…"
	_lock_connection_buttons()
	NetworkManager.host_online()


func _on_join_online_pressed() -> void:
	var code := room_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code."
		return
	status_label.text = "Joining room %s…" % code
	_lock_connection_buttons()
	NetworkManager.join_online(code)


func _on_room_created(code: String) -> void:
	room_code_display.text = "Room Code: %s" % code
	room_code_display.visible = true
	status_label.text = "Room created. Share the code with friends."
	start_button.visible = true
	start_button.disabled = false
	ready_button.disabled = false
	_refresh_player_list()


func _on_room_joined(_peer_count: int) -> void:
	status_label.text = "Joined! Waiting for host to start…"
	ready_button.disabled = false


func _on_relay_error(message: String) -> void:
	status_label.text = "Relay error: %s" % message
	_unlock_connection_buttons()


func _lock_connection_buttons() -> void:
	host_button.disabled = true
	join_button.disabled = true
	host_online_button.disabled = true
	join_online_button.disabled = true


func _unlock_connection_buttons() -> void:
	host_button.disabled = false
	join_button.disabled = false
	host_online_button.disabled = false
	join_online_button.disabled = false


# -------------------------------------------------------
# Class selection
# -------------------------------------------------------
func _on_class_selected(index: int) -> void:
	selected_class = index
	_highlight_class(index)
	_update_class_preview(index)
	var local_id := multiplayer.get_unique_id()
	if NetworkManager.players.has(local_id):
		NetworkManager.players[local_id]["chosen_class"] = index
	var info: Dictionary = NetworkManager.players.get(local_id, NetworkManager._default_player_info())
	if multiplayer.is_server():
		NetworkManager._register_player(info)
	else:
		NetworkManager._register_player.rpc_id(1, info)


# -------------------------------------------------------
# Ready / Start
# -------------------------------------------------------
func _on_ready_pressed() -> void:
	is_ready = not is_ready
	ready_button.text = "Unready" if is_ready else "Ready"
	if not multiplayer.is_server():
		NetworkManager.set_player_ready.rpc_id(1, is_ready)


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager.server_start_game()


# -------------------------------------------------------
# Player list
# -------------------------------------------------------
func _on_player_connected(_peer_id: int, _info: Dictionary) -> void:
	status_label.text = "Players: %d/%d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	_refresh_player_list()
	if not multiplayer.is_server():
		ready_button.disabled = false


func _on_player_disconnected(_peer_id: int) -> void:
	status_label.text = "A player left."
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
		var class_name_str: String = CLASS_NAMES[info.get("chosen_class", 0)]
		var ready_str: String = "✓" if info.get("ready", false) else "…"
		label.text = "[%s] %s — %s" % [ready_str, info.get("name", "?"), class_name_str]
		label.add_theme_font_size_override("font_size", 13)
		player_list.add_child(label)


# -------------------------------------------------------
# Solo Play — skip networking, go straight to hub
# -------------------------------------------------------
func _add_solo_button() -> void:
	var solo_btn := Button.new()
	solo_btn.text = "Solo Play"
	solo_btn.custom_minimum_size = Vector2(120, 0)
	solo_btn.pressed.connect(_on_solo_pressed)
	# Insert above the ready/start row
	var bottom_row := ready_button.get_parent()
	bottom_row.add_child(solo_btn)
	bottom_row.move_child(solo_btn, 0)


func _on_solo_pressed() -> void:
	# Set up a local offline peer so multiplayer calls don't error
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	NetworkManager.local_peer_id = 1
	NetworkManager.players[1] = {
		"peer_id": 1,
		"name": "Penguin",
		"chosen_class": selected_class,
		"ready": true,
	}
	GameManager.change_state(GameManager.State.HUB)
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")
