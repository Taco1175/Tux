extends Control
# Inventory panel — toggled with inventory_open action.
# Shows equipped gear and all items in a grid. 480×270 viewport.

@onready var grid: GridContainer = $Panel/VBox/ScrollContainer/Grid
@onready var weapon_label: Label = $Panel/VBox/EquippedRow/WeaponLabel
@onready var armor_label: Label = $Panel/VBox/EquippedRow/ArmorLabel
@onready var desc_label: Label = $Panel/VBox/DescLabel

var player_ref: Node = null


func _ready() -> void:
	hide()


func toggle(player: Node) -> void:
	player_ref = player
	if visible:
		hide()
	else:
		show()
		_refresh()


func _refresh() -> void:
	if not player_ref:
		return
	_show_equipped()
	_show_inventory()


func _show_equipped() -> void:
	if player_ref.equipped_weapon != null:
		var w: Dictionary = player_ref.equipped_weapon as Dictionary
		weapon_label.text = "Wpn: %s" % w.get("display_name", "None")
		weapon_label.add_theme_color_override("font_color",
			ItemDatabase.get_rarity_color(w.get("rarity", 0)))
	else:
		weapon_label.text = "Wpn: None"
		weapon_label.remove_theme_color_override("font_color")

	var armor_parts: Array[String] = []
	for slot in player_ref.equipped_armor:
		var a: Dictionary = player_ref.equipped_armor[slot]
		armor_parts.append(a.get("display_name", "?"))
	armor_label.text = "Armor: %s" % (", ".join(armor_parts) if not armor_parts.is_empty() else "None")


func _show_inventory() -> void:
	for child in grid.get_children():
		child.queue_free()

	for item in player_ref.inventory:
		var btn := Button.new()
		var display: String = item.get("display_name", "?")
		var rarity: int = item.get("rarity", 0)
		btn.text = display
		btn.add_theme_font_size_override("font_size", 6)
		btn.custom_minimum_size = Vector2(70, 14)
		btn.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(rarity))
		btn.pressed.connect(func(): _on_item_clicked(item))
		grid.add_child(btn)


func _on_item_clicked(item: Dictionary) -> void:
	# Show details
	var lines: Array[String] = []
	lines.append(item.get("display_name", "?"))
	lines.append(ItemDatabase.get_rarity_name(item.get("rarity", 0)))
	if item.has("desc"):
		lines.append(item["desc"])
	for affix in item.get("affixes", []):
		lines.append("  " + affix.get("label", ""))
	desc_label.text = "\n".join(lines)

	# Equip/use on second click or via button
	var item_type: int = item.get("item_type", -1)
	if item_type == ItemDatabase.ItemType.WEAPON or item_type == ItemDatabase.ItemType.ARMOR:
		player_ref.equip_item(item)
		_refresh()
	elif item_type == ItemDatabase.ItemType.POTION or item_type == ItemDatabase.ItemType.THROWABLE:
		player_ref.use_consumable(item)
		_refresh()
