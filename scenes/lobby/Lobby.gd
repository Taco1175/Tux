extends Control

# Lobby — Two-phase flow:
# Phase 1: Solo or Multiplayer
# Phase 2: Character select (all 4 visible, fighting-game roster style)

const CLASS_NAMES := ["Emperor", "Gentoo", "Little Blue", "Macaroni"]
const CLASS_ROLES := ["Lead Guitar", "Drums", "Vocals", "Bass"]
const CLASS_DESCS := [
	"The oldest sibling. Overprotective.\nWields a battle axe guitar like a\nweapon of mass distortion.\nSlow but absolutely unstoppable.",
	"The chaotic middle sibling.\nDual-wields drumsticks like daggers.\nFastest tempo, hardest crits.\nOne glass jaw away from glory.",
	"The peacekeeper of the band.\nMic stand doubles as a bo staff.\nHeals allies with power ballads.\nSnaps into death metal when cornered.",
	"The youngest. Unnerving calm.\nBass guitar channels raw sonic\ndevastation. Glass cannon.\nGets louder the closer to death.",
]

const CLASS_STATS := [
	# Emperor
	{"hp": 140, "mana": 25, "str": 14, "dex": 7, "int": 5, "spd": "0.85x", "def": 4, "crit": "4%"},
	# Gentoo
	{"hp": 80, "mana": 45, "str": 8, "dex": 15, "int": 7, "spd": "1.35x", "def": 1, "crit": "18%"},
	# Little Blue
	{"hp": 100, "mana": 70, "str": 10, "dex": 11, "int": 11, "spd": "1.10x", "def": 2, "crit": "8%"},
	# Macaroni
	{"hp": 60, "mana": 110, "str": 5, "dex": 7, "int": 16, "spd": "0.92x", "def": 0, "crit": "10%"},
]

const CLASS_WEAPONS := ["Axe Guitar", "Dual Drumsticks", "Mic Stand", "Bass Guitar"]

const CLASS_PRIMARY := [
	"Heavy Axe Swing\nSlow, devastating melee",
	"Drumstick Combo\n3rd hit = Drum Fill (2x AoE)",
	"Mic Stand Strike\nBalanced melee swing",
	"Sound Wave\nRanged sonic bolt (5 mana)",
]

const CLASS_SECONDARY := [
	"Power Chord\nAoE knockback blast (4s CD)",
	"Paradiddle Dash\nInvincible dash (3s CD)",
	"Power Ballad / Death Metal\nAoE heal OR rage mode (<20% HP)",
	"Bass Drop\nAoE explosion at cursor (2.5s CD)",
]

const CLASS_PASSIVE := [
	"Stage Presence: 15% block chance",
	"Tempo: 18% crit, 2.5x crit damage",
	"Dual Nature: Heal or rage, never both",
	"Low End Theory: Less HP = more damage",
]
const CLASS_COLORS := [
	Color(0.3, 0.5, 0.9),   # Emperor — blue
	Color(1.0, 0.5, 0.2),   # Gentoo — orange
	Color(0.4, 0.9, 0.5),   # Little Blue — green
	Color(0.9, 0.3, 0.9),   # Macaroni — purple
]
const CLASS_SHEET_PATHS := [
	"res://assets/sprites/players/emperor_sheet.png",
	"res://assets/sprites/players/gentoo_sheet.png",
	"res://assets/sprites/players/little_blue_sheet.png",
	"res://assets/sprites/players/macaroni_sheet.png",
]

var selected_class: int = 0
var is_solo: bool = false

# Phase containers
var _mode_panel: Control
var _char_panel: Control
var _roster_panels: Array[PanelContainer] = []

# Multiplayer widgets (stored for host/join flow)
var _mp_address: LineEdit
var _mp_port: LineEdit
var _mp_status: Label
var _mp_start_btn: Button
var _mp_room_code: LineEdit
var _mp_room_display: Label


func _ready() -> void:
	_build_bg()
	_build_mode_select()
	_build_char_select()
	_char_panel.hide()

	NetworkManager.player_connected.connect(func(_id, _info): _refresh_mp_status())
	NetworkManager.player_disconnected.connect(func(_id): _refresh_mp_status())
	NetworkManager.server_disconnected.connect(func():
		_char_panel.hide()
		_mode_panel.show()
	)
	NetworkManager.room_created.connect(func(code):
		if _mp_room_display:
			_mp_room_display.text = "Room: %s" % code
			_mp_room_display.show()
		_refresh_mp_status()
	)
	NetworkManager.room_joined.connect(func(_n): _refresh_mp_status())


# -------------------------------------------------------
# Background
# -------------------------------------------------------
func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)


# -------------------------------------------------------
# Phase 1: Mode Select
# -------------------------------------------------------
func _build_mode_select() -> void:
	_mode_panel = Control.new()
	_mode_panel.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_mode_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	vbox.offset_left = -100
	vbox.offset_right = 100
	vbox.offset_top = -60
	vbox.offset_bottom = 60
	vbox.add_theme_constant_override("separation", 8)
	_mode_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "TUX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose your mode"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 7)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(subtitle)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var solo_btn := Button.new()
	solo_btn.text = "Solo"
	solo_btn.custom_minimum_size = Vector2(70, 20)
	solo_btn.add_theme_font_size_override("font_size", 9)
	solo_btn.pressed.connect(_on_solo_selected)
	btn_row.add_child(solo_btn)

	var mp_btn := Button.new()
	mp_btn.text = "Multiplayer"
	mp_btn.custom_minimum_size = Vector2(70, 20)
	mp_btn.add_theme_font_size_override("font_size", 9)
	mp_btn.pressed.connect(_on_multiplayer_selected)
	btn_row.add_child(mp_btn)

	# Token count
	var token_lbl := Label.new()
	token_lbl.text = "Tide Tokens: %d" % UnlockManager.tide_tokens
	token_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	token_lbl.add_theme_font_size_override("font_size", 6)
	token_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(token_lbl)


func _on_solo_selected() -> void:
	is_solo = true
	# Set up offline peer
	var peer := OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	NetworkManager.local_peer_id = 1
	_mode_panel.hide()
	_char_panel.show()
	_highlight_class(selected_class)


func _on_multiplayer_selected() -> void:
	is_solo = false
	_mode_panel.hide()
	_char_panel.show()
	_highlight_class(selected_class)


# -------------------------------------------------------
# Phase 2: Character Select
# -------------------------------------------------------
func _build_char_select() -> void:
	_char_panel = Control.new()
	_char_panel.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_char_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(PRESET_FULL_RECT)
	main_vbox.offset_left = 8
	main_vbox.offset_right = -8
	main_vbox.offset_top = 4
	main_vbox.offset_bottom = -4
	main_vbox.add_theme_constant_override("separation", 4)
	_char_panel.add_child(main_vbox)

	# Header
	var header := Label.new()
	header.text = "SELECT YOUR CHARACTER"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 8)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(header)

	# Roster: 4 character cards in a row
	var roster := HBoxContainer.new()
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster.alignment = BoxContainer.ALIGNMENT_CENTER
	roster.add_theme_constant_override("separation", 6)
	main_vbox.add_child(roster)

	for i in 4:
		var card := _build_char_card(i)
		roster.add_child(card)
		_roster_panels.append(card)

	# Bottom bar: multiplayer controls + play button
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 6)
	main_vbox.add_child(bottom)

	# MP controls (hidden in solo mode)
	_mp_status = Label.new()
	_mp_status.add_theme_font_size_override("font_size", 5)
	_mp_status.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	bottom.add_child(_mp_status)

	_mp_room_display = Label.new()
	_mp_room_display.add_theme_font_size_override("font_size", 5)
	_mp_room_display.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_mp_room_display.visible = false
	bottom.add_child(_mp_room_display)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 7)
	back_btn.pressed.connect(func():
		_char_panel.hide()
		_mode_panel.show()
	)
	bottom.add_child(back_btn)

	# Play button
	var play_btn := Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(60, 16)
	play_btn.add_theme_font_size_override("font_size", 8)
	play_btn.pressed.connect(_on_play_pressed)
	_mp_start_btn = play_btn
	bottom.add_child(play_btn)


func _build_char_card(index: int) -> PanelContainer:
	var available := _is_class_available(index)
	var accent: Color = CLASS_COLORS[index]

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.10, 0.95)
	sb.border_color = accent * 0.3
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", sb)

	# ScrollContainer so content fits even on small viewports
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Portrait
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(28, 28)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sheet := load(CLASS_SHEET_PATHS[index]) as Texture2D
	if sheet and available:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, 16, 16)
		portrait.texture = atlas
	else:
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(24, 24)
		portrait.texture = tex
		portrait.modulate = Color(0.3, 0.3, 0.3) if not available else accent
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(portrait)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = CLASS_NAMES[index]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color", accent if available else Color(0.4, 0.4, 0.4))
	vbox.add_child(name_lbl)

	# Role + Weapon
	var role_lbl := Label.new()
	role_lbl.text = CLASS_ROLES[index] + " — " + CLASS_WEAPONS[index]
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.add_theme_font_size_override("font_size", 4)
	role_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(role_lbl)

	if not available:
		var lock_lbl := Label.new()
		lock_lbl.text = "LOCKED\nEarn Tide Tokens to unlock."
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 5)
		lock_lbl.add_theme_color_override("font_color", Color(0.35, 0.2, 0.2))
		lock_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(lock_lbl)
		scroll.add_child(vbox)
		panel.add_child(scroll)
		panel.gui_input.connect(_on_card_clicked.bind(index))
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		return panel

	# --- Stats bar ---
	var stats: Dictionary = CLASS_STATS[index]
	var stat_line := Label.new()
	stat_line.text = "HP %d  MP %d  DEF %d" % [stats["hp"], stats["mana"], stats["def"]]
	stat_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_line.add_theme_font_size_override("font_size", 4)
	stat_line.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(stat_line)

	var stat_line2 := Label.new()
	stat_line2.text = "STR %d  DEX %d  INT %d" % [stats["str"], stats["dex"], stats["int"]]
	stat_line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_line2.add_theme_font_size_override("font_size", 4)
	stat_line2.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(stat_line2)

	var stat_line3 := Label.new()
	stat_line3.text = "SPD %s  CRIT %s" % [stats["spd"], stats["crit"]]
	stat_line3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_line3.add_theme_font_size_override("font_size", 4)
	stat_line3.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(stat_line3)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Passive
	var passive_lbl := Label.new()
	passive_lbl.text = CLASS_PASSIVE[index]
	passive_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	passive_lbl.add_theme_font_size_override("font_size", 4)
	passive_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(passive_lbl)

	# Primary ability
	var pri_header := Label.new()
	pri_header.text = "[Primary]"
	pri_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pri_header.add_theme_font_size_override("font_size", 4)
	pri_header.add_theme_color_override("font_color", accent)
	vbox.add_child(pri_header)

	var pri_desc := Label.new()
	pri_desc.text = CLASS_PRIMARY[index]
	pri_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pri_desc.add_theme_font_size_override("font_size", 4)
	pri_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(pri_desc)

	# Secondary ability
	var sec_header := Label.new()
	sec_header.text = "[Secondary]"
	sec_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_header.add_theme_font_size_override("font_size", 4)
	sec_header.add_theme_color_override("font_color", accent)
	vbox.add_child(sec_header)

	var sec_desc := Label.new()
	sec_desc.text = CLASS_SECONDARY[index]
	sec_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_desc.add_theme_font_size_override("font_size", 4)
	sec_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	vbox.add_child(sec_desc)

	# Flavor description
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var desc := Label.new()
	desc.text = CLASS_DESCS[index]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 4)
	desc.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	vbox.add_child(desc)

	scroll.add_child(vbox)
	panel.add_child(scroll)

	# Click handler
	panel.gui_input.connect(_on_card_clicked.bind(index))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	return panel


func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_class_available(index):
			selected_class = index
			_highlight_class(index)


func _highlight_class(index: int) -> void:
	for i in _roster_panels.size():
		var panel: PanelContainer = _roster_panels[i]
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if i == index:
			sb.border_color = CLASS_COLORS[i]
			sb.set_border_width_all(2)
			sb.bg_color = Color(0.08, 0.08, 0.14, 0.95)
			panel.modulate = Color.WHITE
		else:
			sb.border_color = CLASS_COLORS[i] * 0.3
			sb.set_border_width_all(1)
			sb.bg_color = Color(0.06, 0.06, 0.10, 0.95)
			panel.modulate = Color(0.65, 0.65, 0.65)


func _is_class_available(class_index: int) -> bool:
	match class_index:
		0: return UnlockManager.is_unlocked("class_emperor")
		1: return UnlockManager.is_unlocked("class_gentoo")
		2: return UnlockManager.is_unlocked("class_little_blue")
		3: return UnlockManager.is_unlocked("class_macaroni")
	return false


# -------------------------------------------------------
# Play / Start
# -------------------------------------------------------
func _on_play_pressed() -> void:
	if is_solo:
		_start_solo()
	else:
		_start_multiplayer()


func _start_solo() -> void:
	NetworkManager.players[1] = {
		"peer_id": 1,
		"name": "Penguin",
		"chosen_class": selected_class,
		"ready": true,
	}
	GameManager.change_state(GameManager.State.HUB)
	get_tree().change_scene_to_file("res://scenes/hub/Hub.tscn")


func _start_multiplayer() -> void:
	if multiplayer.is_server():
		NetworkManager.server_start_game()
	else:
		_mp_status.text = "Waiting for host to start..."


func _refresh_mp_status() -> void:
	if _mp_status:
		_mp_status.text = "Players: %d/%d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]


# -------------------------------------------------------
# ESC to go back
# -------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _char_panel.visible:
			_char_panel.hide()
			_mode_panel.show()
		else:
			get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
