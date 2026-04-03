extends Area2D
# Item drop node — sits on the ground until a player walks over it.
# Added to "items" group so Player.gd's pickup_area can detect it.

var item_data: Dictionary = {}

# Item icon atlas: 4 icons × 16px in assets/sprites/items/item_icons.png
# Col 0 = weapon, 1 = armor, 2 = potion, 3 = throwable
const ICON_SHEET := "res://assets/sprites/items/item_icons.png"

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
		label.add_theme_font_size_override("font_size", 6)

	# Create a visible colored box sprite — guaranteed to render
	if sprite:
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		# Draw a filled box with a 1px darker border
		var border := color.darkened(0.4)
		for y in 10:
			for x in 10:
				if x == 0 or x == 9 or y == 0 or y == 9:
					img.set_pixel(x, y, border)
				else:
					img.set_pixel(x, y, color)
		sprite.texture = ImageTexture.create_from_image(img)

	# Glow intensity scales with rarity
	if glow:
		if not glow.texture:
			var grad_tex := GradientTexture2D.new()
			grad_tex.fill = GradientTexture2D.FILL_RADIAL
			var gradient := Gradient.new()
			gradient.set_color(0, Color.WHITE)
			gradient.set_color(1, Color(1, 1, 1, 0))
			grad_tex.gradient = gradient
			glow.texture = grad_tex
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
