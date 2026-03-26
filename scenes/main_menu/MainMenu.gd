extends Control
# Main Menu for TUX

@onready var play_button: Button   = $UI/Buttons/PlayButton
@onready var shop_button: Button   = $UI/Buttons/ShopButton
@onready var quit_button: Button   = $UI/Buttons/QuitButton
@onready var token_label: Label    = $UI/TokenLabel
@onready var title_label: Label    = $UI/TitleLabel
@onready var shop_panel: Control   = $UI/ShopPanel

func _ready() -> void:
	title_label.text = "TUX"
	token_label.text = "Tide Tokens: %d" % UnlockManager.tide_tokens
	UnlockManager.tokens_changed.connect(func(t): token_label.text = "Tide Tokens: %d" % t)

	play_button.pressed.connect(_on_play)
	shop_button.pressed.connect(_on_shop)
	quit_button.pressed.connect(func(): get_tree().quit())
	shop_panel.hide()

	GameManager.change_state(GameManager.State.MAIN_MENU)


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")


func _on_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		_populate_shop()


func _populate_shop() -> void:
	var list := shop_panel.get_node_or_null("ItemList")
	if not list:
		return
	for child in list.get_children():
		child.queue_free()

	for entry in UnlockManager.SHOP:
		if UnlockManager.is_unlocked(entry["key"]):
			continue
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %d Tokens" % [entry["label"], entry["cost"]]
		lbl.tooltip_text = entry["desc"]
		var btn := Button.new()
		btn.text = "Unlock"
		btn.disabled = not UnlockManager.can_purchase(entry["key"])
		btn.pressed.connect(func(): _purchase(entry["key"]))
		row.add_child(lbl)
		row.add_child(btn)
		list.add_child(row)


func _purchase(key: String) -> void:
	UnlockManager.purchase(key)
	_populate_shop()
