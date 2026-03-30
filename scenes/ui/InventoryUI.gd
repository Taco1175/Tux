extends Control
# Drag-and-drop inventory — equipment slots on the left, bag grid on the right.
# Drag items between bag slots, onto equip slots, or to the trash area.
# Click consumables to use them (with animation).

const SLOT_SIZE := Vector2(28, 28)
const GRID_COLS := 4
const FONT_SIZE := 6

const EQUIP_SLOTS := ["Weapon", "Helmet", "Chest", "Boots", "Shield"]

var player_ref: Node = null
var selected_item: Dictionary = {}

# UI nodes (built dynamically)
var equip_slot_panels: Dictionary = {}  # slot_name -> PanelContainer
var bag_slots: Array = []               # Array of PanelContainer
var bag_grid: GridContainer = null
var desc_label: Label = null
var equip_button: Button = null
var use_button: Button = null
var drop_button: Button = null
var title_label: Label = null

# Drag state
var _dragging: bool = false
var _drag_item: Dictionary = {}
var _drag_source: String = ""       # "bag_3" or "equip_Weapon"
var _drag_ghost: Control = null     # Visual that follows mouse


func _ready() -> void:
	hide()


func toggle(player: Node) -> void:
	player_ref = player
	if visible:
		hide()
		_cancel_drag()
	else:
		show()
		selected_item = {}
		_build_ui()


func _process(_delta: float) -> void:
	if _dragging and _drag_ghost:
		_drag_ghost.global_position = get_global_mouse_position() - SLOT_SIZE * 0.5


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()
	equip_slot_panels.clear()
	bag_slots.clear()

	# Dark background panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -190
	panel.offset_top = -110
	panel.offset_right = 190
	panel.offset_bottom = 110
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_hbox)

	# ---- Left side: Equipment slots ----
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 3)
	left_vbox.custom_minimum_size = Vector2(80, 0)
	main_hbox.add_child(left_vbox)

	var equip_title := Label.new()
	equip_title.text = "Equipment"
	equip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_title.add_theme_font_size_override("font_size", 8)
	equip_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	left_vbox.add_child(equip_title)

	for slot_name in EQUIP_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		left_vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = slot_name[0]
		lbl.add_theme_font_size_override("font_size", 5)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		lbl.custom_minimum_size = Vector2(8, 0)
		row.add_child(lbl)

		var slot_panel := _make_equip_slot(slot_name)
		row.add_child(slot_panel)
		equip_slot_panels[slot_name] = slot_panel

	_refresh_equip_slots()

	# ---- Separator ----
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	main_hbox.add_child(sep)

	# ---- Right side: Bag + details ----
	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 3)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(right_vbox)

	var bag_title := Label.new()
	bag_title.text = "Bag (%d/%d)" % [player_ref.inventory.size(), player_ref.INVENTORY_SIZE]
	bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_title.add_theme_font_size_override("font_size", 8)
	bag_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	right_vbox.add_child(bag_title)
	title_label = bag_title

	# Scrollable bag grid
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	bag_grid = GridContainer.new()
	bag_grid.columns = GRID_COLS
	bag_grid.add_theme_constant_override("h_separation", 3)
	bag_grid.add_theme_constant_override("v_separation", 3)
	bag_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bag_grid)

	_refresh_bag()

	# Item description area
	var desc_sep := HSeparator.new()
	right_vbox.add_child(desc_sep)

	desc_label = Label.new()
	desc_label.text = "Drag items to rearrange. Click to inspect."
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 6)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc_label.custom_minimum_size = Vector2(0, 36)
	right_vbox.add_child(desc_label)

	# Action buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_child(btn_row)

	equip_button = Button.new()
	equip_button.text = "Equip"
	equip_button.add_theme_font_size_override("font_size", 7)
	equip_button.custom_minimum_size = Vector2(40, 14)
	equip_button.disabled = true
	equip_button.pressed.connect(_on_equip_pressed)
	btn_row.add_child(equip_button)

	use_button = Button.new()
	use_button.text = "Use"
	use_button.add_theme_font_size_override("font_size", 7)
	use_button.custom_minimum_size = Vector2(40, 14)
	use_button.disabled = true
	use_button.pressed.connect(_on_use_pressed)
	btn_row.add_child(use_button)

	drop_button = Button.new()
	drop_button.text = "Drop"
	drop_button.add_theme_font_size_override("font_size", 7)
	drop_button.custom_minimum_size = Vector2(40, 14)
	drop_button.disabled = true
	drop_button.pressed.connect(_on_drop_pressed)
	btn_row.add_child(drop_button)


# -------------------------------------------------------
# Equipment slot panels
# -------------------------------------------------------
func _make_equip_slot(slot_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("slot_name", slot_name)
	_style_empty_panel(panel)

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = "--"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.clip_text = true
	panel.add_child(lbl)

	panel.gui_input.connect(_on_equip_slot_input.bind(slot_name))
	return panel


# -------------------------------------------------------
# Bag item slots (draggable)
# -------------------------------------------------------
func _make_bag_slot(index: int, item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_meta("bag_index", index)
	panel.set_meta("item", item)

	var rarity: int = item.get("rarity", 0)
	var rarity_color: Color = ItemDatabase.get_rarity_color(rarity)
	_style_item_panel(panel, rarity_color)

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", rarity_color)
	lbl.clip_text = true

	var item_type: int = item.get("item_type", 0)
	match item_type:
		ItemDatabase.ItemType.WEAPON:    lbl.text = "Wp"
		ItemDatabase.ItemType.ARMOR:     lbl.text = "Ar"
		ItemDatabase.ItemType.POTION:    lbl.text = "Pt"
		ItemDatabase.ItemType.THROWABLE: lbl.text = "Tb"
		_: lbl.text = "??"
	panel.add_child(lbl)

	panel.gui_input.connect(_on_bag_slot_input.bind(index, item))
	panel.tooltip_text = item.get("display_name", "???")
	return panel


func _make_empty_slot() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.12, 0.6)
	bg.border_color = Color(0.15, 0.15, 0.2)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(1)
	panel.add_theme_stylebox_override("panel", bg)

	# Accept drops on empty slots
	panel.gui_input.connect(_on_empty_slot_input.bind(panel))
	return panel


# -------------------------------------------------------
# Drag and drop input handling
# -------------------------------------------------------
func _on_bag_slot_input(event: InputEvent, index: int, item: Dictionary) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(item, "bag_%d" % index)
			elif _dragging:
				_finish_drag_at_mouse()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click = quick action (equip gear, use consumable)
			_quick_use(item)


func _on_equip_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _dragging:
			# Start dragging equipped item out
			var equipped := _get_equipped_item(slot_name)
			if not equipped.is_empty():
				_start_drag(equipped, "equip_%s" % slot_name)
		elif not event.pressed and _dragging:
			# Drop onto equip slot
			_drop_on_equip_slot(slot_name)


func _on_empty_slot_input(event: InputEvent, panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _dragging:
			# Drop onto empty bag slot — just rearrange
			_finish_drag_to_bag()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# ESC or ui_cancel closes inventory
	if event.is_action_pressed("ui_cancel"):
		_cancel_drag()
		hide()
		get_viewport().set_input_as_handled()
		return
	# Cancel drag on right-click
	if _dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_drag()
	# Click outside any slot = select nothing
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _dragging:
		selected_item = {}
		_update_buttons()
		if desc_label:
			desc_label.text = "Drag items to rearrange. Click to inspect."


# -------------------------------------------------------
# Drag logic
# -------------------------------------------------------
func _start_drag(item: Dictionary, source: String) -> void:
	_dragging = true
	_drag_item = item
	_drag_source = source
	# Select it too
	selected_item = item
	_show_item_details(item)
	_update_buttons()
	# Create ghost visual
	_drag_ghost = PanelContainer.new()
	_drag_ghost.custom_minimum_size = SLOT_SIZE
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_drag_ghost.z_index = 100

	var rarity: int = item.get("rarity", 0)
	var rc: Color = ItemDatabase.get_rarity_color(rarity)
	_style_item_panel(_drag_ghost, rc)

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", rc)
	var item_type: int = item.get("item_type", 0)
	match item_type:
		ItemDatabase.ItemType.WEAPON:    lbl.text = "Wp"
		ItemDatabase.ItemType.ARMOR:     lbl.text = "Ar"
		ItemDatabase.ItemType.POTION:    lbl.text = "Pt"
		ItemDatabase.ItemType.THROWABLE: lbl.text = "Tb"
		_: lbl.text = "??"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.add_child(lbl)
	add_child(_drag_ghost)


func _cancel_drag() -> void:
	_dragging = false
	_drag_item = {}
	_drag_source = ""
	if _drag_ghost:
		_drag_ghost.queue_free()
		_drag_ghost = null


func _finish_drag_at_mouse() -> void:
	# Generic drop — check if mouse is over an equip slot
	# If not, just put it back
	_finish_drag_to_bag()


func _finish_drag_to_bag() -> void:
	if _drag_source.begins_with("equip_"):
		# Moving from equip to bag = unequip
		var slot_name: String = _drag_source.substr(6)
		_unequip_to_bag(slot_name)
	# If from bag to bag, it's already in bag, just refresh order
	_cancel_drag()
	_refresh_equip_slots()
	_refresh_bag()


func _drop_on_equip_slot(slot_name: String) -> void:
	if _drag_item.is_empty():
		_cancel_drag()
		return
	var item_type: int = _drag_item.get("item_type", -1)

	# Can only equip matching slot types
	var can_equip := false
	if slot_name == "Weapon" and item_type == ItemDatabase.ItemType.WEAPON:
		can_equip = true
	elif slot_name != "Weapon" and item_type == ItemDatabase.ItemType.ARMOR:
		var armor_map := {
			"Helmet": ItemDatabase.ArmorType.HELMET,
			"Chest": ItemDatabase.ArmorType.CHESTPLATE,
			"Boots": ItemDatabase.ArmorType.BOOTS,
			"Shield": ItemDatabase.ArmorType.SHIELD,
		}
		var needed: int = armor_map.get(slot_name, -1)
		var item_armor: int = _drag_item.get("armor_type", -2)
		if needed == item_armor:
			can_equip = true

	if can_equip:
		# Remove from bag if it was in bag
		if _drag_source.begins_with("bag_"):
			player_ref.inventory.erase(_drag_item)
		elif _drag_source.begins_with("equip_"):
			# Unequip from old slot first
			var old_slot: String = _drag_source.substr(6)
			_clear_equip_slot(old_slot)
		player_ref.equip_item(_drag_item)

	_cancel_drag()
	_refresh_equip_slots()
	_refresh_bag()


func _unequip_to_bag(slot_name: String) -> void:
	if not player_ref:
		return
	if slot_name == "Weapon":
		if player_ref.equipped_weapon != null:
			var item: Dictionary = player_ref.equipped_weapon as Dictionary
			player_ref._unapply_affixes(item)
			player_ref.equipped_weapon = null
			if player_ref.inventory.size() < player_ref.INVENTORY_SIZE:
				player_ref.inventory.append(item)
	else:
		var armor_map := {
			"Helmet": ItemDatabase.ArmorType.HELMET,
			"Chest": ItemDatabase.ArmorType.CHESTPLATE,
			"Boots": ItemDatabase.ArmorType.BOOTS,
			"Shield": ItemDatabase.ArmorType.SHIELD,
		}
		var armor_type: int = armor_map.get(slot_name, -1)
		if player_ref.equipped_armor.has(armor_type):
			var item: Dictionary = player_ref.equipped_armor[armor_type]
			player_ref._unapply_affixes(item)
			player_ref.equipped_armor.erase(armor_type)
			if player_ref.inventory.size() < player_ref.INVENTORY_SIZE:
				player_ref.inventory.append(item)


func _clear_equip_slot(slot_name: String) -> void:
	if slot_name == "Weapon":
		if player_ref.equipped_weapon != null:
			player_ref._unapply_affixes(player_ref.equipped_weapon as Dictionary)
			player_ref.equipped_weapon = null
	else:
		var armor_map := {
			"Helmet": ItemDatabase.ArmorType.HELMET,
			"Chest": ItemDatabase.ArmorType.CHESTPLATE,
			"Boots": ItemDatabase.ArmorType.BOOTS,
			"Shield": ItemDatabase.ArmorType.SHIELD,
		}
		var armor_type: int = armor_map.get(slot_name, -1)
		if player_ref.equipped_armor.has(armor_type):
			player_ref._unapply_affixes(player_ref.equipped_armor[armor_type])
			player_ref.equipped_armor.erase(armor_type)


func _get_equipped_item(slot_name: String) -> Dictionary:
	if not player_ref:
		return {}
	if slot_name == "Weapon":
		if player_ref.equipped_weapon != null:
			return player_ref.equipped_weapon as Dictionary
	else:
		var armor_map := {
			"Helmet": ItemDatabase.ArmorType.HELMET,
			"Chest": ItemDatabase.ArmorType.CHESTPLATE,
			"Boots": ItemDatabase.ArmorType.BOOTS,
			"Shield": ItemDatabase.ArmorType.SHIELD,
		}
		var armor_type: int = armor_map.get(slot_name, -1)
		if player_ref.equipped_armor.has(armor_type):
			return player_ref.equipped_armor[armor_type]
	return {}


# -------------------------------------------------------
# Quick-use (right-click)
# -------------------------------------------------------
func _quick_use(item: Dictionary) -> void:
	var item_type: int = item.get("item_type", -1)
	if item_type == ItemDatabase.ItemType.WEAPON or item_type == ItemDatabase.ItemType.ARMOR:
		player_ref.inventory.erase(item)
		player_ref.equip_item(item)
	elif item_type == ItemDatabase.ItemType.POTION or item_type == ItemDatabase.ItemType.THROWABLE:
		player_ref.use_consumable(item)
	_refresh_equip_slots()
	_refresh_bag()
	selected_item = {}
	_update_buttons()
	if desc_label:
		desc_label.text = "Drag items to rearrange. Click to inspect."


# -------------------------------------------------------
# Refresh displays
# -------------------------------------------------------
func _refresh_equip_slots() -> void:
	# Weapon slot
	var weapon_panel: PanelContainer = equip_slot_panels.get("Weapon")
	if weapon_panel:
		var lbl: Label = weapon_panel.get_node_or_null("Label")
		if player_ref.equipped_weapon != null:
			var w: Dictionary = player_ref.equipped_weapon as Dictionary
			if lbl: lbl.text = w.get("display_name", "?").substr(0, 8)
			var rc: Color = ItemDatabase.get_rarity_color(w.get("rarity", 0))
			if lbl: lbl.add_theme_color_override("font_color", rc)
			_style_item_panel(weapon_panel, rc)
		else:
			if lbl: lbl.text = "--"
			if lbl: lbl.remove_theme_color_override("font_color")
			_style_empty_panel(weapon_panel)

	# Armor slots
	var armor_map := {
		"Helmet": ItemDatabase.ArmorType.HELMET,
		"Chest": ItemDatabase.ArmorType.CHESTPLATE,
		"Boots": ItemDatabase.ArmorType.BOOTS,
		"Shield": ItemDatabase.ArmorType.SHIELD,
	}
	for slot_name in armor_map:
		var panel: PanelContainer = equip_slot_panels.get(slot_name)
		if not panel:
			continue
		var lbl: Label = panel.get_node_or_null("Label")
		var armor_type: int = armor_map[slot_name]
		if player_ref.equipped_armor.has(armor_type):
			var a: Dictionary = player_ref.equipped_armor[armor_type]
			if lbl: lbl.text = a.get("display_name", "?").substr(0, 8)
			var rc: Color = ItemDatabase.get_rarity_color(a.get("rarity", 0))
			if lbl: lbl.add_theme_color_override("font_color", rc)
			_style_item_panel(panel, rc)
		else:
			if lbl: lbl.text = "--"
			if lbl: lbl.remove_theme_color_override("font_color")
			_style_empty_panel(panel)


func _refresh_bag() -> void:
	if not bag_grid:
		return
	for child in bag_grid.get_children():
		child.queue_free()
	bag_slots.clear()
	for i in player_ref.inventory.size():
		var slot := _make_bag_slot(i, player_ref.inventory[i])
		bag_grid.add_child(slot)
		bag_slots.append(slot)
	# Fill remaining with empties
	var remaining: int = player_ref.INVENTORY_SIZE - player_ref.inventory.size()
	for i in remaining:
		var empty := _make_empty_slot()
		bag_grid.add_child(empty)

	if title_label:
		title_label.text = "Bag (%d/%d)" % [player_ref.inventory.size(), player_ref.INVENTORY_SIZE]


# -------------------------------------------------------
# Styling helpers
# -------------------------------------------------------
func _style_item_panel(panel: PanelContainer, rarity_color: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(rarity_color.r * 0.25, rarity_color.g * 0.25, rarity_color.b * 0.25, 0.9)
	bg.border_color = rarity_color
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", bg)


func _style_empty_panel(panel: PanelContainer) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.18)
	bg.border_color = Color(0.25, 0.25, 0.35)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(1)
	panel.add_theme_stylebox_override("panel", bg)


# -------------------------------------------------------
# Button actions
# -------------------------------------------------------
func _update_buttons() -> void:
	if not equip_button:
		return
	if selected_item.is_empty():
		equip_button.disabled = true
		use_button.disabled = true
		drop_button.disabled = true
		return
	var item_type: int = selected_item.get("item_type", -1)
	equip_button.disabled = not (item_type == ItemDatabase.ItemType.WEAPON or item_type == ItemDatabase.ItemType.ARMOR)
	use_button.disabled = not (item_type == ItemDatabase.ItemType.POTION or item_type == ItemDatabase.ItemType.THROWABLE)
	drop_button.disabled = false


func _on_equip_pressed() -> void:
	if selected_item.is_empty() or not player_ref:
		return
	player_ref.inventory.erase(selected_item)
	player_ref.equip_item(selected_item)
	selected_item = {}
	_update_buttons()
	if desc_label:
		desc_label.text = "Drag items to rearrange. Click to inspect."
	_refresh_equip_slots()
	_refresh_bag()


func _on_use_pressed() -> void:
	if selected_item.is_empty() or not player_ref:
		return
	player_ref.use_consumable(selected_item)
	selected_item = {}
	_update_buttons()
	if desc_label:
		desc_label.text = "Drag items to rearrange. Click to inspect."
	_refresh_equip_slots()
	_refresh_bag()


func _on_drop_pressed() -> void:
	if selected_item.is_empty() or not player_ref:
		return
	player_ref.inventory.erase(selected_item)
	selected_item = {}
	_update_buttons()
	if desc_label:
		desc_label.text = "Drag items to rearrange. Click to inspect."
	_refresh_bag()


func _show_item_details(item: Dictionary) -> void:
	if not desc_label:
		return
	var lines: Array[String] = []
	var rarity_name: String = ItemDatabase.get_rarity_name(item.get("rarity", 0))
	lines.append("[%s] %s" % [rarity_name, item.get("display_name", "?")])
	if item.has("damage_min"):
		lines.append("Dmg: %d-%d" % [item["damage_min"], item["damage_max"]])
	if item.has("defense"):
		lines.append("Def: +%d" % item["defense"])
	if item.has("desc"):
		lines.append(item["desc"])
	for affix in item.get("affixes", []):
		lines.append("  + %s" % affix.get("label", ""))
	var item_type: int = item.get("item_type", -1)
	if item_type == ItemDatabase.ItemType.POTION:
		lines.append("\n[Right-click to use]")
	elif item_type == ItemDatabase.ItemType.THROWABLE:
		lines.append("\n[Right-click to throw]")
	desc_label.text = "\n".join(lines)
