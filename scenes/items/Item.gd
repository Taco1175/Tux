extends Area2D
# Item drop node — sits on the ground until a player walks over it.
# Added to "items" group so Player.gd's pickup_area can detect it.

var item_data: Dictionary = {}

@onready var sprite: Sprite2D  = $Sprite2D
@onready var label: Label      = $Label
@onready var glow: PointLight2D = $Glow


func _ready() -> void:
	add_to_group("items")


func setup(data: Dictionary) -> void:
	item_data = data
	var rarity: int = data.get("rarity", ItemDatabase.Rarity.COMMON)
	var color: Color = ItemDatabase.get_rarity_color(rarity)

	if label:
		label.text = data.get("display_name", "?")
		label.add_theme_color_override("font_color", color)

	# Tint the sprite by rarity color (placeholder until real sprites exist)
	if sprite:
		sprite.modulate = color

	# Glow intensity scales with rarity
	if glow:
		glow.color = color
		glow.energy = 0.3 + rarity * 0.15
		glow.visible = rarity >= ItemDatabase.Rarity.RARE

	# Gentle bob animation
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position:y", position.y - 3.0, 0.8).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", position.y, 0.8).set_ease(Tween.EASE_IN_OUT)


func get_item_data() -> Dictionary:
	return item_data


func _on_body_entered(body: Node) -> void:
	# Handled by Player.gd's pickup_area — this just provides the data
	pass
