extends Control
# Run-end screen: player picks 1 item to save permanently.
# Shows all items collected during the run in a grid.

@onready var title_label: Label = $Panel/VBox/Title
@onready var stats_label: Label = $Panel/VBox/Stats
@onready var item_grid: GridContainer = $Panel/VBox/ScrollContainer/ItemGrid
@onready var save_button: Button = $Panel/VBox/SaveButton
@onready var skip_button: Button = $Panel/VBox/SkipButton
@onready var desc_label: Label = $Panel/VBox/DescLabel

var selected_item: Dictionary = {}
var selected_button: Button = null
var run_items: Array = []


func _ready() -> void:
	save_button.disabled = true
	save_button.pressed.connect(_on_save)
	skip_button.pressed.connect(_on_skip)

	_show_run_stats()
	_populate_items()


func _show_run_stats() -> void:
	var run := GameManager.current_run
	if run:
		var floors := run.floor_number
		var tokens := run.run_currency
		title_label.text = "Expedition Complete"
		stats_label.text = "Floors: %d  |  Tokens earned: %d" % [floors, tokens]
	else:
		title_label.text = "Expedition Complete"
		stats_label.text = ""


func _populate_items() -> void:
	# Gather items from all local players (in practice, just the local one)
	for player in get_tree().get_nodes_in_group("players"):
		if player.get("is_local_player") and player.is_local_player:
			run_items = player.inventory.duplicate()
			break

	# If no items found (e.g. player died early), show message
	if run_items.is_empty():
		desc_label.text = "No items to save. Better luck next time."
		save_button.hide()
		return

	for item in run_items:
		var btn := Button.new()
		var display: String = item.get("display_name", "???")
		var rarity: int = item.get("rarity", 0)
		btn.text = display
		btn.add_theme_font_size_override("font_size", 7)
		btn.custom_minimum_size = Vector2(90, 16)
		btn.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(rarity))
		btn.pressed.connect(func(): _select_item(item, btn))
		item_grid.add_child(btn)


func _select_item(item: Dictionary, btn: Button) -> void:
	# Deselect previous
	if selected_button:
		selected_button.modulate = Color.WHITE
	selected_item = item
	selected_button = btn
	btn.modulate = Color(1.0, 1.0, 0.5)
	save_button.disabled = false

	# Show item details
	var lines: Array[String] = []
	lines.append(item.get("display_name", "???"))
	lines.append(ItemDatabase.get_rarity_name(item.get("rarity", 0)))
	if item.has("desc"):
		lines.append(item["desc"])
	for affix in item.get("affixes", []):
		lines.append("  " + affix.get("label", ""))
	desc_label.text = "\n".join(lines)


func _on_save() -> void:
	if selected_item.is_empty():
		return
	UnlockManager.save_item(selected_item)
	_return_to_hub()


func _on_skip() -> void:
	_return_to_hub()


func _return_to_hub() -> void:
	GameManager.return_to_hub()
