extends Control
# HUD for TUX — health bars, mana, inventory hotbar, floor info,
# the sanctum ending choice UI, and ending cutscene display.

@onready var hp_bar: ProgressBar       = $TopLeft/HPBar
@onready var hp_label: Label           = $TopLeft/HPLabel
@onready var mana_bar: ProgressBar     = $TopLeft/ManaBar
@onready var mana_label: Label         = $TopLeft/ManaLabel
@onready var xp_bar: ProgressBar       = $TopLeft/XPBar
@onready var level_label: Label        = $TopLeft/LevelLabel
@onready var floor_label: Label        = $TopRight/FloorLabel
@onready var token_label: Label        = $TopRight/TokenLabel
@onready var hotbar: HBoxContainer     = $Bottom/Hotbar
@onready var message_box: PanelContainer    = $Center/MessageBox
@onready var message_label: Label           = $Center/MessageBox/MessageLabel
@onready var ending_panel: PanelContainer   = $Center/EndingPanel
@onready var ending_title: Label            = $Center/EndingPanel/VBox/Title
@onready var ending_desc: Label             = $Center/EndingPanel/VBox/Description
@onready var ending_buttons: VBoxContainer  = $Center/EndingPanel/VBox/Buttons
@onready var game_over_panel: PanelContainer = $Center/GameOverPanel
@onready var inventory_ui: Control = $InventoryUI
@onready var pause_panel: PanelContainer = $Center/PausePanel

var player_ref: Node = null

# Hotbar items (consumables bound to 1-4 keys / D-pad)
var hotbar_items: Array = [null, null, null, null]

# Ability cooldown display
var primary_cd_bar: ProgressBar = null
var secondary_cd_bar: ProgressBar = null

# Dialogue UI
var dialogue_panel: PanelContainer = null
var dialogue_speaker: Label = null
var dialogue_text: Label = null
var dialogue_continue: Label = null
var _dialogue_active: bool = false

# Status effect icons
var status_container: HBoxContainer = null

# Ending choice texts
const ENDING_DATA := {
	GameManager.EndingChoice.LET_PARENTS_GO: {
		"title": "Let Them Go",
		"desc": "Your parents look at you. All four of you. They don't look afraid.\n\n\"This isn't your fault,\" your mother says.\n\"Go home,\" your father says.\n\nYou do."
	},
	GameManager.EndingChoice.SIBLING_STAYS: {
		"title": "Someone Has To",
		"desc": "Nobody says it first. Nobody wants to be the one.\n\nThen one of you steps forward.\n\n\"I'll stay.\"\n\nThe other three don't move for a long moment."
	},
	GameManager.EndingChoice.EXPOSE_AND_REFUSE: {
		"title": "The Truth Belongs to Everyone",
		"desc": "\"No one is dying today.\"\n\nYou turn and start swimming up.\n\n\"The colony will know what it built this on. And then we fix it together.\"\n\nYour parents call after you. You don't stop."
	},
	GameManager.EndingChoice.REIMPRISION_THE_GOD: {
		"title": "...",
		"desc": "You rebuild the cage.\n\nIt's easier the second time. That's the worst part.\n\nYou swim up. You say nothing. You will never say anything.\n\nEveryone goes home."
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if message_box:
		message_box.hide()
	if ending_panel:
		ending_panel.hide()
	if game_over_panel:
		game_over_panel.hide()
	if pause_panel:
		pause_panel.hide()
	if inventory_ui:
		inventory_ui.hide()
	GameManager.run_started.connect(_on_run_started)
	_build_ability_cooldowns()
	_build_dialogue_ui()
	_build_status_bar()
	_build_hotbar_slots()


func _on_run_started(_r) -> void:
	_update_floor_label()


func _process(_delta: float) -> void:
	# Update token counter live
	if token_label and GameManager.current_run:
		token_label.text = "Tide Tokens: %d" % GameManager.current_run.run_currency
	# Update ability cooldown bars
	_update_cooldown_bars()


func _unhandled_input(event: InputEvent) -> void:
	# ESC closes open panels first, then pauses
	if event.is_action_pressed("ui_cancel"):
		if _dialogue_active:
			_dismiss_dialogue()
			get_viewport().set_input_as_handled()
			return
		if inventory_ui and inventory_ui.visible:
			inventory_ui.hide()
			get_viewport().set_input_as_handled()
			return
		_toggle_pause()
		return
	if _dialogue_active and event is InputEventKey and event.is_pressed():
		_dismiss_dialogue()
		return
	if _dialogue_active and event is InputEventJoypadButton and event.is_pressed():
		_dismiss_dialogue()
		return
	if event.is_action_pressed("inventory_open") and player_ref and inventory_ui:
		inventory_ui.toggle(player_ref)
	if event.is_action_pressed("pause"):
		_toggle_pause()
	# Hotbar 1-4 (number keys or D-pad)
	for i in 4:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_use_hotbar_slot(i)
			break


func set_player(player: Node) -> void:
	player_ref = player
	player.hp_changed.connect(_on_hp_changed)
	player.mana_changed.connect(_on_mana_changed)
	player.xp_changed.connect(_on_xp_changed)
	player.leveled_up.connect(_on_leveled_up)
	player.item_picked_up.connect(_refresh_hotbar)

	_on_hp_changed(player.current_hp, player.max_hp)
	_on_mana_changed(player.current_mana, player.max_mana)
	if xp_bar:
		_on_xp_changed(player.current_xp, player.xp_to_next)
	if level_label:
		level_label.text = "Lv.%d" % player.level


# -------------------------------------------------------
# Ability cooldown bars (bottom-left, next to HP)
# -------------------------------------------------------
func _build_ability_cooldowns() -> void:
	var cd_container := VBoxContainer.new()
	cd_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cd_container.offset_left = 4
	cd_container.offset_bottom = -4
	cd_container.offset_top = -22
	cd_container.offset_right = 50

	# Primary ability label + bar
	var p_row := HBoxContainer.new()
	var p_label := Label.new()
	p_label.text = "LMB"
	p_label.add_theme_font_size_override("font_size", 5)
	p_label.custom_minimum_size = Vector2(18, 0)
	primary_cd_bar = ProgressBar.new()
	primary_cd_bar.custom_minimum_size = Vector2(28, 4)
	primary_cd_bar.max_value = 1.0
	primary_cd_bar.value = 1.0
	primary_cd_bar.show_percentage = false
	primary_cd_bar.modulate = Color(1.0, 0.8, 0.3)
	p_row.add_child(p_label)
	p_row.add_child(primary_cd_bar)
	cd_container.add_child(p_row)

	# Secondary ability label + bar
	var s_row := HBoxContainer.new()
	var s_label := Label.new()
	s_label.text = "RMB"
	s_label.add_theme_font_size_override("font_size", 5)
	s_label.custom_minimum_size = Vector2(18, 0)
	secondary_cd_bar = ProgressBar.new()
	secondary_cd_bar.custom_minimum_size = Vector2(28, 4)
	secondary_cd_bar.max_value = 1.0
	secondary_cd_bar.value = 1.0
	secondary_cd_bar.show_percentage = false
	secondary_cd_bar.modulate = Color(0.3, 0.7, 1.0)
	s_row.add_child(s_label)
	s_row.add_child(secondary_cd_bar)
	cd_container.add_child(s_row)

	add_child(cd_container)


func _update_cooldown_bars() -> void:
	if not player_ref or not is_instance_valid(player_ref):
		return
	# Primary: base attack cooldown
	if primary_cd_bar:
		var cd: float = player_ref.attack_cooldown if player_ref.get("attack_cooldown") != null else 0.0
		var max_cd: float = player_ref.attack_cooldown_max if player_ref.get("attack_cooldown_max") != null else 0.4
		primary_cd_bar.value = 1.0 - (cd / maxf(max_cd, 0.01))
	# Secondary: class-specific cooldown
	if secondary_cd_bar:
		var cd := 0.0
		var max_cd := 1.0
		if player_ref.get("shield_bash_cooldown") != null:  # Emperor
			cd = player_ref.shield_bash_cooldown
			max_cd = 4.0
		elif player_ref.get("dash_cooldown") != null:  # Gentoo
			cd = player_ref.dash_cooldown
			max_cd = 3.0
		elif player_ref.get("heal_pulse_cooldown") != null:  # LittleBlue
			cd = player_ref.heal_pulse_cooldown
			max_cd = 8.0
		elif player_ref.get("fireball_cooldown") != null:  # Macaroni
			cd = player_ref.fireball_cooldown
			max_cd = 2.5
		secondary_cd_bar.value = 1.0 - (cd / maxf(max_cd, 0.01))


# -------------------------------------------------------
# Hotbar slots (bottom center, 4 consumable slots)
# -------------------------------------------------------
func _build_hotbar_slots() -> void:
	if not hotbar:
		return
	for child in hotbar.get_children():
		child.queue_free()
	for i in 4:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(20, 20)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.12, 0.15, 0.8)
		sb.border_color = Color(0.3, 0.3, 0.35)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("panel", sb)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon := Label.new()
		icon.name = "Icon"
		icon.text = ""
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.add_theme_font_size_override("font_size", 7)
		vbox.add_child(icon)

		var key := Label.new()
		key.text = str(i + 1)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 5)
		key.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(key)

		slot.add_child(vbox)
		hotbar.add_child(slot)


func _refresh_hotbar(_item: Dictionary = {}) -> void:
	if not player_ref:
		return
	hotbar_items = [null, null, null, null]
	var slot_idx := 0
	for item in player_ref.inventory:
		if slot_idx >= 4:
			break
		var item_dict := item as Dictionary
		if item_dict.get("item_type") in [ItemDatabase.ItemType.POTION, ItemDatabase.ItemType.THROWABLE]:
			hotbar_items[slot_idx] = item_dict
			slot_idx += 1
	# Update visual
	for i in 4:
		if i >= hotbar.get_child_count():
			break
		var slot := hotbar.get_child(i)
		var icon: Node = slot.get_node_or_null("VBoxContainer/Icon") if slot.get_child_count() > 0 else null
		if not icon:
			# Try finding the label directly
			var vbox: Node = slot.get_child(0) if slot.get_child_count() > 0 else null
			if vbox and vbox.get_child_count() > 0:
				icon = vbox.get_child(0)
		if icon and icon is Label:
			if hotbar_items[i]:
				icon.text = hotbar_items[i].get("display_name", "?")[0]
				icon.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(hotbar_items[i].get("rarity", 0)))
			else:
				icon.text = ""


func _use_hotbar_slot(index: int) -> void:
	if not player_ref or not hotbar_items[index]:
		return
	player_ref.use_consumable(hotbar_items[index])
	_refresh_hotbar()


# -------------------------------------------------------
# Dialogue popup (Hades-style NPC conversation)
# -------------------------------------------------------
func _build_dialogue_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dialogue_panel.offset_left = 8
	dialogue_panel.offset_bottom = -8
	dialogue_panel.offset_top = -75
	dialogue_panel.offset_right = 280
	dialogue_panel.visible = false
	dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.1, 0.92)
	sb.border_color = Color(0.3, 0.4, 0.5, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	dialogue_panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()

	dialogue_speaker = Label.new()
	dialogue_speaker.add_theme_font_size_override("font_size", 8)
	dialogue_speaker.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(dialogue_speaker)

	dialogue_text = Label.new()
	dialogue_text.add_theme_font_size_override("font_size", 7)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(dialogue_text)

	dialogue_continue = Label.new()
	dialogue_continue.text = "[Any key to continue]"
	dialogue_continue.add_theme_font_size_override("font_size", 5)
	dialogue_continue.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	dialogue_continue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(dialogue_continue)

	dialogue_panel.add_child(vbox)
	add_child(dialogue_panel)


func show_dialogue(speaker: String, text: String, color: Color = Color.WHITE) -> void:
	if not dialogue_panel:
		return
	dialogue_speaker.text = speaker
	dialogue_speaker.add_theme_color_override("font_color", color)
	dialogue_text.text = text
	dialogue_panel.show()
	_dialogue_active = true


func _dismiss_dialogue() -> void:
	if dialogue_panel:
		dialogue_panel.hide()
	_dialogue_active = false


func is_dialogue_active() -> bool:
	return _dialogue_active


# -------------------------------------------------------
# Status effect icons (under HP bars)
# -------------------------------------------------------
func _build_status_bar() -> void:
	status_container = HBoxContainer.new()
	status_container.position = Vector2(4, 56)
	status_container.add_theme_constant_override("separation", 2)
	add_child(status_container)


func update_status_effects(effects: Array[Dictionary]) -> void:
	if not status_container:
		return
	for child in status_container.get_children():
		child.queue_free()
	for effect in effects:
		var icon := Label.new()
		icon.text = effect.get("icon", "?")
		icon.add_theme_font_size_override("font_size", 6)
		icon.add_theme_color_override("font_color", effect.get("color", Color.WHITE))
		icon.tooltip_text = effect.get("name", "")
		status_container.add_child(icon)


# -------------------------------------------------------
# Stat updates
# -------------------------------------------------------
func _on_hp_changed(hp: int, max_hp: int) -> void:
	if not hp_bar:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [hp, max_hp]
	if float(hp) / float(max_hp) < 0.25:
		hp_bar.modulate = Color(1.0, 0.3, 0.3)
	else:
		hp_bar.modulate = Color.WHITE


func _on_mana_changed(mana: int, max_mana: int) -> void:
	if not mana_bar:
		return
	mana_bar.max_value = max_mana
	mana_bar.value = mana
	mana_label.text = "%d / %d" % [mana, max_mana]




func _update_floor_label() -> void:
	if GameManager.current_run and floor_label:
		floor_label.text = _floor_display_name(GameManager.current_run.floor_number)


func _on_xp_changed(current: int, needed: int) -> void:
	if xp_bar:
		xp_bar.max_value = needed
		xp_bar.value = current


func _on_leveled_up(new_level: int) -> void:
	if level_label:
		level_label.text = "Lv.%d" % new_level
	# Flash level label gold
	if level_label:
		level_label.modulate = Color(1.0, 0.85, 0.2)
		var tween := create_tween()
		tween.tween_property(level_label, "modulate", Color.WHITE, 1.0)
	# Brief "LEVEL UP!" message
	show_message("Level %d!" % new_level, 1.5)


func _floor_display_name(floor_num: int) -> String:
	if floor_num < 3:   return "Flooded Ruins — Floor %d" % (floor_num + 1)
	elif floor_num < 6: return "Coral Crypts — Floor %d" % (floor_num - 2)
	elif floor_num < 9: return "Abyssal Trench — Floor %d" % (floor_num - 5)
	else:               return "The God's Sanctum"


# -------------------------------------------------------
# Messages
# -------------------------------------------------------
func show_message(text: String, duration: float = 3.0) -> void:
	message_label.text = text
	message_box.show()
	await get_tree().create_timer(duration).timeout
	message_box.hide()


func show_sanctum_message() -> void:
	# Slow reveal — the siblings find their parents
	await show_message("You hear them before you see them.", 2.5)
	await show_message("They're alive.", 2.5)
	await show_message("They weren't taken.", 2.5)
	await show_message("They came here on purpose.", 3.0)
	await get_tree().create_timer(1.0).timeout
	_show_ending_choice()


func _show_ending_choice() -> void:
	ending_panel.show()
	ending_title.text = "What do you do?"
	ending_desc.text = "The ritual is almost complete.\nOne life, freely given, will free the God.\nYour parents are already kneeling."

	for child in ending_buttons.get_children():
		child.queue_free()

	_add_ending_button("Let them go.", GameManager.EndingChoice.LET_PARENTS_GO)
	_add_ending_button("Step forward.", GameManager.EndingChoice.SIBLING_STAYS)

	# Paths C and D only available if unlocked
	if UnlockManager.is_unlocked("ending_expose_unlocked"):
		_add_ending_button("\"Nobody dies today.\" (Turn back)", GameManager.EndingChoice.EXPOSE_AND_REFUSE)
	if UnlockManager.is_unlocked("ending_reimprision_unlocked"):
		_add_ending_button("Rebuild the cage. [Say nothing.]", GameManager.EndingChoice.REIMPRISION_THE_GOD)


func _add_ending_button(text: String, choice: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(func(): _on_ending_chosen(choice))
	ending_buttons.add_child(btn)


func _on_ending_chosen(choice: int) -> void:
	ending_panel.hide()
	# Tell the Game scene
	get_parent().trigger_ending(choice)


# -------------------------------------------------------
# Ending cutscene
# -------------------------------------------------------
func play_ending_cutscene(choice: int) -> void:
	var data: Dictionary = ENDING_DATA.get(choice, {})
	ending_panel.show()
	ending_title.text = data.get("title", "")
	ending_desc.text = data.get("desc", "")
	for child in ending_buttons.get_children():
		child.queue_free()


# -------------------------------------------------------
# Game over
# -------------------------------------------------------
func show_game_over() -> void:
	game_over_panel.show()
	var label := game_over_panel.get_node_or_null("Label")
	if label:
		var run := GameManager.current_run
		var floors: int = run.floor_number if run else 0
		var tokens: int = run.run_currency if run else 0
		var kills: int = run.enemies_killed if run else 0
		label.text = "The deep claims another.\n\nFloors reached: %d\nEnemies slain: %d\nTide Tokens earned: %d" % [floors, kills, tokens]


# -------------------------------------------------------
# Pause menu
# -------------------------------------------------------
func _toggle_pause() -> void:
	if GameManager.current_state == GameManager.State.PAUSED:
		_resume()
	elif GameManager.current_state == GameManager.State.IN_GAME:
		_pause()


func _pause() -> void:
	GameManager.pause_game()
	if pause_panel:
		pause_panel.show()
		_setup_pause_buttons()


func _resume() -> void:
	GameManager.resume_game()
	if pause_panel:
		pause_panel.hide()


func _setup_pause_buttons() -> void:
	var vbox := pause_panel.get_node_or_null("VBox")
	if not vbox:
		return
	for child in vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 10)
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.add_theme_font_size_override("font_size", 8)
	resume_btn.custom_minimum_size = Vector2(0, 16)
	resume_btn.pressed.connect(_resume)
	vbox.add_child(resume_btn)

	var controls_btn := Button.new()
	controls_btn.text = "Controls"
	controls_btn.add_theme_font_size_override("font_size", 8)
	controls_btn.custom_minimum_size = Vector2(0, 16)
	controls_btn.pressed.connect(_show_controls_menu)
	vbox.add_child(controls_btn)

	var hub_btn := Button.new()
	hub_btn.text = "Quit to Hub"
	hub_btn.add_theme_font_size_override("font_size", 8)
	hub_btn.custom_minimum_size = Vector2(0, 16)
	hub_btn.pressed.connect(func():
		_resume()  # Unpause first
		GameManager.end_run(GameManager.EndingChoice.NONE)
	)
	vbox.add_child(hub_btn)


# -------------------------------------------------------
# Controls / Key Rebinding menu
# -------------------------------------------------------
const REBINDABLE_ACTIONS := [
	["move_up",           "Move Up"],
	["move_down",         "Move Down"],
	["move_left",         "Move Left"],
	["move_right",        "Move Right"],
	["ability_primary",   "Primary Attack"],
	["ability_secondary", "Secondary Attack"],
	["interact",          "Interact / Pickup"],
	["inventory_open",    "Inventory"],
	["hotbar_1",          "Hotbar 1"],
	["hotbar_2",          "Hotbar 2"],
	["hotbar_3",          "Hotbar 3"],
	["hotbar_4",          "Hotbar 4"],
]

var _rebind_buttons: Dictionary = {}  # action_name -> Button
var _waiting_for_input: String = ""   # action currently being rebound


func _show_controls_menu() -> void:
	var vbox := pause_panel.get_node_or_null("VBox")
	if not vbox:
		return
	for child in vbox.get_children():
		child.queue_free()
	_rebind_buttons.clear()
	_waiting_for_input = ""

	var title := Label.new()
	title.text = "Controls"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 9)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Click a key to rebind"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 5)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	# Scrollable list of bindings
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for entry in REBINDABLE_ACTIONS:
		var action_name: String = entry[0]
		var display_name: String = entry[1]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		list.add_child(row)

		var lbl := Label.new()
		lbl.text = display_name
		lbl.add_theme_font_size_override("font_size", 5)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.custom_minimum_size = Vector2(70, 0)
		row.add_child(lbl)

		var btn := Button.new()
		btn.text = _get_key_name_for_action(action_name)
		btn.add_theme_font_size_override("font_size", 5)
		btn.custom_minimum_size = Vector2(60, 12)
		btn.pressed.connect(_start_rebind.bind(action_name))
		row.add_child(btn)
		_rebind_buttons[action_name] = btn

	# Back + Reset row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.add_theme_font_size_override("font_size", 6)
	reset_btn.custom_minimum_size = Vector2(0, 14)
	reset_btn.pressed.connect(_reset_default_bindings)
	btn_row.add_child(reset_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 6)
	back_btn.custom_minimum_size = Vector2(0, 14)
	back_btn.pressed.connect(_setup_pause_buttons)
	btn_row.add_child(back_btn)


func _get_key_name_for_action(action_name: String) -> String:
	var events := InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey:
			return event.as_text().get_slice(" (", 0)
		if event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:  return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "Mouse %d" % event.button_index
	return "---"


func _start_rebind(action_name: String) -> void:
	_waiting_for_input = action_name
	if _rebind_buttons.has(action_name):
		_rebind_buttons[action_name].text = "..."


func _input(event: InputEvent) -> void:
	if _waiting_for_input == "":
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and not event.pressed:
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	# Don't allow ESC as a rebind — it's reserved for pause
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_waiting_for_input = ""
		_refresh_rebind_buttons()
		return

	get_viewport().set_input_as_handled()

	var action := _waiting_for_input
	# Remove existing keyboard/mouse events, keep gamepad events
	var existing := InputMap.action_get_events(action)
	for ev in existing:
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)
	InputMap.action_add_event(action, event)

	_waiting_for_input = ""
	_refresh_rebind_buttons()
	_save_keybinds()


func _refresh_rebind_buttons() -> void:
	for action_name in _rebind_buttons:
		_rebind_buttons[action_name].text = _get_key_name_for_action(action_name)


func _reset_default_bindings() -> void:
	InputMap.load_from_project_settings()
	_refresh_rebind_buttons()
	_delete_keybinds_file()


func _save_keybinds() -> void:
	var data := {}
	for entry in REBINDABLE_ACTIONS:
		var action_name: String = entry[0]
		var events := InputMap.action_get_events(action_name)
		var saved_events := []
		for ev in events:
			if ev is InputEventKey:
				saved_events.append({"type": "key", "keycode": ev.keycode, "physical_keycode": ev.physical_keycode})
			elif ev is InputEventMouseButton:
				saved_events.append({"type": "mouse", "button_index": ev.button_index})
			elif ev is InputEventJoypadButton:
				saved_events.append({"type": "joypad_button", "button_index": ev.button_index})
			elif ev is InputEventJoypadMotion:
				saved_events.append({"type": "joypad_axis", "axis": ev.axis, "axis_value": ev.axis_value})
		data[action_name] = saved_events
	var file := FileAccess.open("user://keybinds.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func _delete_keybinds_file() -> void:
	if FileAccess.file_exists("user://keybinds.json"):
		DirAccess.remove_absolute("user://keybinds.json")


static func load_keybinds() -> void:
	if not FileAccess.file_exists("user://keybinds.json"):
		return
	var file := FileAccess.open("user://keybinds.json", FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	for action_name in data:
		if not InputMap.has_action(action_name):
			continue
		InputMap.action_erase_events(action_name)
		for ev_data in data[action_name]:
			var ev: InputEvent = null
			match ev_data.get("type", ""):
				"key":
					ev = InputEventKey.new()
					ev.keycode = ev_data.get("keycode", 0)
					ev.physical_keycode = ev_data.get("physical_keycode", 0)
				"mouse":
					ev = InputEventMouseButton.new()
					ev.button_index = ev_data.get("button_index", 1)
				"joypad_button":
					ev = InputEventJoypadButton.new()
					ev.button_index = ev_data.get("button_index", 0)
				"joypad_axis":
					ev = InputEventJoypadMotion.new()
					ev.axis = ev_data.get("axis", 0)
					ev.axis_value = ev_data.get("axis_value", 0.0)
			if ev:
				InputMap.action_add_event(action_name, ev)
