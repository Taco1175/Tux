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
@onready var ending_title: Label            = $Center/EndingPanel/Title
@onready var ending_desc: Label             = $Center/EndingPanel/Description
@onready var ending_buttons: VBoxContainer  = $Center/EndingPanel/Buttons
@onready var game_over_panel: PanelContainer = $Center/GameOverPanel

var player_ref: Node = null

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
	message_box.hide()
	ending_panel.hide()
	game_over_panel.hide()

	if GameManager.current_run:
		floor_label.text = _floor_display_name(GameManager.current_run.floor_number)
		token_label.text = "Tide Tokens: %d" % GameManager.current_run.run_currency

	GameManager.run_started.connect(func(_r): _update_floor_label())


func set_player(player: Node) -> void:
	player_ref = player
	player.hp_changed.connect(_on_hp_changed)
	player.mana_changed.connect(_on_mana_changed)
	player.xp_changed.connect(_on_xp_changed)
	player.leveled_up.connect(_on_leveled_up)
	player.item_picked_up.connect(_refresh_hotbar)

	_on_hp_changed(player.current_hp, player.max_hp)
	_on_mana_changed(player.current_mana, player.max_mana)
	_on_xp_changed(player.current_xp, player.xp_to_next)
	level_label.text = "Lv.%d" % player.level


# -------------------------------------------------------
# Stat updates
# -------------------------------------------------------
func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "%d / %d" % [hp, max_hp]
	# Flash bar red when low
	if float(hp) / float(max_hp) < 0.25:
		hp_bar.modulate = Color(1.0, 0.3, 0.3)
	else:
		hp_bar.modulate = Color.WHITE


func _on_mana_changed(mana: int, max_mana: int) -> void:
	mana_bar.max_value = max_mana
	mana_bar.value = mana
	mana_label.text = "%d / %d" % [mana, max_mana]


func _refresh_hotbar(_item: Resource) -> void:
	if not player_ref:
		return
	for child in hotbar.get_children():
		child.queue_free()
	# Show first 5 consumables/throwables in inventory
	var shown := 0
	for item in player_ref.inventory:
		if shown >= 5:
			break
		var item_dict := item as Dictionary
		if item_dict.get("item_type") in [ItemDatabase.ItemType.POTION, ItemDatabase.ItemType.THROWABLE]:
			var slot := _make_hotbar_slot(item_dict)
			hotbar.add_child(slot)
			shown += 1


func _make_hotbar_slot(item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var label := Label.new()
	label.text = item.get("display_name", "?")[0]  # First letter as placeholder
	label.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(item.get("rarity", 0)))
	panel.add_child(label)
	panel.tooltip_text = "%s\n%s" % [item.get("display_name", "?"), item.get("desc", "")]
	return panel


func _update_floor_label() -> void:
	if GameManager.current_run:
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
		var floors := run.floor_number if run else 0
		var tokens := run.run_currency if run else 0
		label.text = "The deep claims another.\n\nFloors reached: %d\nTide Tokens earned: %d" % [floors, tokens]
