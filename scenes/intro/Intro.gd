extends Control
# Intro cutscene for TUX — establishes the metal band backstory.
# Scrolling dialogue with placeholder character portraits.
# Skip with any key after first beat, or let it play through.

const BEATS := [
	{
		"speaker": "",
		"text": "Antarctica. The coldest place on Earth.\nBut underneath the ice... the music never stopped.",
		"color": Color(0.6, 0.7, 0.9),
		"portrait": "none",
		"duration": 4.5,
	},
	{
		"speaker": "",
		"text": "For generations, penguin bands have descended into\nthe deep venues beneath the glaciers.\nPlaying for something ancient. Something hungry.",
		"color": Color(0.6, 0.7, 0.9),
		"portrait": "none",
		"duration": 5.0,
	},
	{
		"speaker": "",
		"text": "The last band to go down was the best.\nTwo parents. One tour. No return.",
		"color": Color(0.8, 0.4, 0.4),
		"portrait": "none",
		"duration": 4.0,
	},
	{
		"speaker": "",
		"text": "They left behind four kids.\nFour siblings. Four instruments.\nOne band name.",
		"color": Color(1.0, 0.85, 0.2),
		"portrait": "none",
		"duration": 4.0,
	},
	{
		"speaker": "EMPEROR",
		"text": "The oldest. Lead guitar.\nWields a battle axe guitar heavier than he is.\nOverprotective. Secretly terrified.",
		"color": Color(0.3, 0.5, 0.9),
		"portrait": "emperor",
		"duration": 4.5,
	},
	{
		"speaker": "GENTOO",
		"text": "The middle child. Drums.\nDual-wields drumsticks like a maniac.\nFastest flippers in the colony. Worst attitude.",
		"color": Color(1.0, 0.5, 0.2),
		"portrait": "gentoo",
		"duration": 4.5,
	},
	{
		"speaker": "LITTLE BLUE",
		"text": "The peacekeeper. Vocals.\nSwings a mic stand. Heals with power ballads.\nDon't make them angry.\nYou won't like the death metal.",
		"color": Color(0.4, 0.9, 0.5),
		"portrait": "little_blue",
		"duration": 5.0,
	},
	{
		"speaker": "MACARONI",
		"text": "The youngest. Bass.\nChannels sonic devastation through four strings.\nUnnerving calm. Accidentally the loudest.",
		"color": Color(0.9, 0.3, 0.9),
		"portrait": "macaroni",
		"duration": 4.5,
	},
	{
		"speaker": "",
		"text": "Together they are...",
		"color": Color(0.7, 0.7, 0.7),
		"portrait": "none",
		"duration": 2.0,
	},
	{
		"speaker": "",
		"text": "T   U   X",
		"color": Color(1.0, 0.2, 0.2),
		"portrait": "band",
		"duration": 3.0,
		"big_title": true,
	},
	{
		"speaker": "",
		"text": "The Lobster Warlord rules the deep venues.\nHe silenced every band that came before.\nHe took your parents.\n\nNow it's your turn to play.",
		"color": Color(0.8, 0.3, 0.3),
		"portrait": "none",
		"duration": 5.5,
	},
	{
		"speaker": "ROADIE RICK",
		"text": "\"Listen up, kids. The deep venues aren't a concert.\nThey're a war. Your instruments are weapons now.\nPlay hard. Play loud. Come back alive.\"",
		"color": Color(0.7, 0.5, 0.3),
		"portrait": "rick",
		"duration": 5.5,
	},
]

var current_beat: int = -1
var beat_timer: float = 0.0
var can_skip: bool = false
var transitioning: bool = false

# UI nodes
var bg: ColorRect
var portrait_rect: TextureRect
var speaker_label: Label
var text_label: Label
var skip_label: Label
var title_label: Label  # For the big TUX reveal

# Waddling penguins
var _penguins: Array = []  # {node, sprite, base_y, timer, speed}


func _ready() -> void:
	# Build the UI
	_build_ui()
	_spawn_waddling_penguins()
	# Start first beat after brief darkness
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_callback(_next_beat)


func _build_ui() -> void:
	# Full-screen black background
	bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	# Portrait (left side, placeholder colored rectangle)
	portrait_rect = TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(80, 80)
	portrait_rect.position = Vector2(30, 60)
	portrait_rect.visible = false
	add_child(portrait_rect)

	# Speaker name
	speaker_label = Label.new()
	speaker_label.position = Vector2(130, 65)
	speaker_label.add_theme_font_size_override("font_size", 10)
	add_child(speaker_label)

	# Main text
	text_label = Label.new()
	text_label.position = Vector2(130, 85)
	text_label.size = Vector2(320, 120)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.add_theme_font_size_override("font_size", 8)
	add_child(text_label)

	# Big title (hidden until the TUX reveal)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(PRESET_CENTER)
	title_label.position = Vector2(-100, -30)
	title_label.size = Vector2(200, 60)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	title_label.visible = false
	add_child(title_label)

	# Skip prompt
	skip_label = Label.new()
	skip_label.text = "[Any key to advance  |  Hold ESC to skip]"
	skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_label.position = Vector2(90, 250)
	skip_label.add_theme_font_size_override("font_size", 5)
	skip_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	add_child(skip_label)


func _process(delta: float) -> void:
	if transitioning:
		return

	beat_timer -= delta
	if beat_timer <= 0 and current_beat >= 0:
		_next_beat()

	_animate_penguins(delta)


func _unhandled_input(event: InputEvent) -> void:
	if transitioning:
		return

	# ESC held = skip entire intro
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish_intro()
		return

	# Any key/click = advance to next beat
	if event.is_pressed() and current_beat >= 0:
		if beat_timer > 0.5:  # Only skip if we've shown current for at least 0.5s
			_next_beat()


func _next_beat() -> void:
	current_beat += 1
	if current_beat >= BEATS.size():
		_finish_intro()
		return

	var beat: Dictionary = BEATS[current_beat]
	beat_timer = beat.get("duration", 4.0)

	# Fade in effect
	text_label.modulate = Color(1, 1, 1, 0)
	speaker_label.modulate = Color(1, 1, 1, 0)
	var fade := create_tween()
	fade.tween_property(text_label, "modulate", Color.WHITE, 0.5)
	fade.parallel().tween_property(speaker_label, "modulate", Color.WHITE, 0.5)

	# Update text
	var speaker: String = beat.get("speaker", "")
	speaker_label.text = speaker
	speaker_label.add_theme_color_override("font_color", beat.get("color", Color.WHITE))
	text_label.text = beat.get("text", "")
	text_label.add_theme_color_override("font_color", beat.get("color", Color.WHITE))

	# Big title mode
	if beat.get("big_title", false):
		title_label.text = beat["text"]
		title_label.visible = true
		text_label.visible = false
		# Pulse effect
		title_label.modulate = Color(1, 1, 1, 0)
		var title_tween := create_tween()
		title_tween.tween_property(title_label, "modulate", Color.WHITE, 0.8)
		title_tween.tween_property(title_label, "modulate", Color(1.0, 0.3, 0.3), 0.5)
		title_tween.tween_property(title_label, "modulate", Color.WHITE, 0.5)
	else:
		title_label.visible = false
		text_label.visible = true

	# Portrait — generate a colored placeholder for each character
	var portrait_key: String = beat.get("portrait", "none")
	if portrait_key != "none":
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(64, 64)
		portrait_rect.texture = tex
		portrait_rect.modulate = _get_portrait_color(portrait_key)
		portrait_rect.visible = true
	else:
		portrait_rect.visible = false


func _get_portrait_color(key: String) -> Color:
	match key:
		"emperor":    return Color(0.3, 0.5, 0.9)    # Blue — stoic tank
		"gentoo":     return Color(1.0, 0.5, 0.2)    # Orange — chaotic energy
		"little_blue": return Color(0.4, 0.9, 0.5)   # Green — healer/vocalist
		"macaroni":   return Color(0.9, 0.3, 0.9)    # Purple — mage bassist
		"band":       return Color(1.0, 0.2, 0.2)    # Red — TUX logo
		"rick":       return Color(0.7, 0.5, 0.3)    # Brown — roadie
	return Color.WHITE


func _spawn_waddling_penguins() -> void:
	# 4 penguins (the siblings) waddle across the bottom of the screen
	var penguin_colors := [
		Color(0.3, 0.5, 0.9),   # Emperor — blue tint
		Color(1.0, 0.5, 0.2),   # Gentoo — orange tint
		Color(0.4, 0.9, 0.5),   # Little Blue — green tint
		Color(0.9, 0.3, 0.9),   # Macaroni — purple tint
	]
	for i in 4:
		var penguin := Node2D.new()
		# Start off-screen left, spaced apart
		penguin.position = Vector2(-30.0 - i * 25.0, 240.0)
		penguin.z_index = 5

		var img := _make_penguin_sprite(penguin_colors[i])
		var tex := ImageTexture.create_from_image(img)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(2.5, 2.5)
		penguin.add_child(spr)
		add_child(penguin)

		_penguins.append({
			node = penguin,
			sprite = spr,
			base_y = 240.0,
			timer = randf() * 6.28,
			speed = 14.0 + i * 0.5,  # slightly different speeds for natural look
		})


func _make_penguin_sprite(tint: Color) -> Image:
	# 8x10 pixel penguin (side-facing, walking pose)
	var w := 8
	var h := 10
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var black := Color(0.1, 0.1, 0.15, 1.0)
	var white := Color(0.9, 0.92, 0.95, 1.0)
	var orange := Color(0.95, 0.6, 0.15, 1.0)
	# Subtle tint on the black
	var tinted := Color(
		black.r + tint.r * 0.15,
		black.g + tint.g * 0.15,
		black.b + tint.b * 0.15, 1.0)

	# Side-facing walking penguin
	# Head
	for x in range(3, 7): img.set_pixel(x, 0, tinted)
	for x in range(2, 7): img.set_pixel(x, 1, tinted)
	img.set_pixel(5, 1, white)  # eye
	for x in range(2, 7): img.set_pixel(x, 2, tinted)
	img.set_pixel(7, 2, orange)  # beak
	# Body
	for y in range(3, 7):
		for x in range(1, 6):
			img.set_pixel(x, y, tinted if x < 4 else white)
	# Wing (extended back)
	img.set_pixel(0, 4, tinted)
	img.set_pixel(0, 5, tinted)
	# Feet (walking pose — one forward, one back)
	img.set_pixel(2, 7, orange)
	img.set_pixel(3, 7, orange)
	img.set_pixel(5, 8, orange)
	img.set_pixel(4, 8, orange)

	return img


func _animate_penguins(delta: float) -> void:
	for p in _penguins:
		p.timer += delta
		# Walk to the right
		p.node.position.x += p.speed * delta
		# Waddle bob
		p.node.position.y = p.base_y + sin(p.timer * 6.0) * 1.5
		# Slight body tilt with waddle
		p.node.rotation = sin(p.timer * 6.0) * 0.12
		# Wrap around when off-screen right
		if p.node.position.x > 510:
			p.node.position.x = -20.0


func _finish_intro() -> void:
	transitioning = true
	# Mark intro as seen
	UnlockManager.unlocks["intro_seen"] = true
	UnlockManager.save_data()
	# Fade to black then go to main menu
	var fade := create_tween()
	fade.tween_property(self, "modulate", Color(1, 1, 1, 0), 1.0)
	fade.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn"))
