extends Control
# Main Menu for TUX

@onready var play_button: Button      = $UI/Buttons/PlayButton
@onready var settings_button: Button  = $UI/Buttons/SettingsButton
@onready var quit_button: Button      = $UI/Buttons/QuitButton
@onready var title_label: Label       = $UI/TitleLabel
@onready var background: ColorRect    = $Background
@onready var settings_panel: PanelContainer = $UI/SettingsPanel

# Beach penguin data: {sprite, base_pos, anim_type, anim_timer, anim_phase}
var _beach_penguins: Array = []
var _beach_props: Array = []  # {node, type, timer}
var _placed_positions: Array[Vector2] = []  # shared spacing tracker

func _ready() -> void:
	# Show intro cutscene on first launch
	if not UnlockManager.is_unlocked("intro_seen"):
		get_tree().change_scene_to_file("res://scenes/intro/Intro.tscn")
		return

	title_label.text = "TUX"

	play_button.pressed.connect(_on_play)
	settings_button.pressed.connect(_on_settings)
	quit_button.pressed.connect(func(): get_tree().quit())

	_setup_beach_background()
	_spawn_beach_props()
	_spawn_beach_penguins()

	GameManager.change_state(GameManager.State.MAIN_MENU)
	MusicManager.play_zone("menu")


func _process(delta: float) -> void:
	_animate_beach_penguins(delta)
	_animate_beach_props(delta)


# -------------------------------------------------------
# Animated beach background
# -------------------------------------------------------
func _setup_beach_background() -> void:
	if not background:
		return
	var shader := load("res://scenes/main_menu/beach_background.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		background.material = mat


func _spawn_beach_penguins() -> void:
	# Randomize penguin count (4-7) and positions in the sand area
	var anims := ["lounge", "sit", "waddle", "sit", "lounge", "sit", "waddle"]
	var count: int = randi_range(4, 6)
	var penguin_configs := []
	for i in count:
		var pos: Vector2 = _try_place(30, 450, 210, 248, 45.0)
		penguin_configs.append({
			pos = pos,
			anim = anims[i % anims.size()],
			flip = randf() > 0.5,
		})

	for config in penguin_configs:
		var penguin_node := Node2D.new()
		penguin_node.position = config.pos
		penguin_node.z_index = 2

		# Build pixel penguin sprite (drawn procedurally, scaled up)
		var img := _generate_penguin_image(config.anim)
		var tex := ImageTexture.create_from_image(img)
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(3.0, 3.0)  # 3x scale for chunky pixel look
		spr.flip_h = config.flip
		penguin_node.add_child(spr)

		# Towel/umbrella for lounging penguins
		if config.anim == "lounge":
			var towel := _create_towel(config.pos)
			add_child(towel)

		add_child(penguin_node)
		_beach_penguins.append({
			node = penguin_node,
			sprite = spr,
			base_pos = config.pos,
			anim = config.anim,
			timer = randf() * 6.28,  # random start phase
			frame = 0,
		})


func _generate_penguin_image(anim_type: String) -> Image:
	# 8x10 pixel penguin sprite
	var w := 8
	var h := 10
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var black := Color(0.1, 0.1, 0.15, 1.0)
	var white := Color(0.9, 0.92, 0.95, 1.0)
	var orange := Color(0.95, 0.6, 0.15, 1.0)
	var eye := Color(0.2, 0.2, 0.25, 1.0)

	match anim_type:
		"sit", "waddle":
			# Standing/sitting penguin (front view)
			# Head (rows 0-3)
			for x in range(2, 6): img.set_pixel(x, 0, black)
			for x in range(1, 7): img.set_pixel(x, 1, black)
			img.set_pixel(2, 1, white)  # eye left
			img.set_pixel(5, 1, white)  # eye right
			for x in range(1, 7): img.set_pixel(x, 2, black)
			img.set_pixel(3, 2, orange)  # beak
			img.set_pixel(4, 2, orange)
			for x in range(2, 6): img.set_pixel(x, 3, black)
			# Body (rows 4-7)
			for y in range(4, 8):
				for x in range(1, 7):
					if x >= 3 and x <= 4:
						img.set_pixel(x, y, white)  # belly
					else:
						img.set_pixel(x, y, black)  # sides
			# Feet (row 8-9)
			img.set_pixel(2, 8, orange)
			img.set_pixel(3, 8, orange)
			img.set_pixel(4, 8, orange)
			img.set_pixel(5, 8, orange)
			img.set_pixel(2, 9, orange)
			img.set_pixel(5, 9, orange)

		"lounge":
			# Lying down penguin (side view, horizontal)
			# More horizontal layout
			for x in range(1, 3): img.set_pixel(x, 4, black)  # head
			img.set_pixel(1, 3, black)
			img.set_pixel(2, 3, black)
			img.set_pixel(2, 3, white)  # eye
			img.set_pixel(0, 4, orange)  # beak
			for x in range(2, 8): img.set_pixel(x, 5, black)  # body top
			for x in range(2, 8): img.set_pixel(x, 6, white)  # belly
			for x in range(3, 7): img.set_pixel(x, 7, black)  # body bottom
			img.set_pixel(7, 7, orange)  # feet

	return img


func _create_towel(pos: Vector2) -> ColorRect:
	var towel := ColorRect.new()
	towel.size = Vector2(36, 8)
	towel.position = pos + Vector2(-18, 8)
	towel.z_index = 1
	# Random towel color
	var colors := [
		Color(0.8, 0.2, 0.2),  # red
		Color(0.2, 0.6, 0.8),  # blue
		Color(0.9, 0.7, 0.1),  # yellow
		Color(0.3, 0.8, 0.3),  # green
	]
	towel.color = colors[randi() % colors.size()]
	return towel


func _spawn_beach_props() -> void:
	# Fire pit + flames
	var fire_pos: Vector2 = _try_place(80, 400, 225, 240, 50.0)
	_add_pixel_prop(fire_pos, _generate_fire_pit_image(), 2)
	var flame_node := Node2D.new()
	flame_node.position = fire_pos + Vector2(0, -7)
	flame_node.z_index = 3
	var flame_spr := Sprite2D.new()
	flame_spr.texture = ImageTexture.create_from_image(_generate_flame_image(0))
	flame_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flame_spr.scale = Vector2(3.0, 3.0)
	flame_node.add_child(flame_spr)
	add_child(flame_node)
	_beach_props.append({node = flame_node, sprite = flame_spr, type = "flame", timer = 0.0, frame = 0})

	# Beach ball
	var ball_pos: Vector2 = _try_place(40, 440, 220, 248, 40.0)
	var ball_node := _add_pixel_prop(ball_pos, _generate_beach_ball_image(), 3)
	_beach_props.append({node = ball_node, type = "ball", timer = 0.0, base_pos = ball_pos})

	# Surfboard (leaning in sand)
	var surf_pos: Vector2 = _try_place(40, 440, 215, 240, 45.0)
	_add_pixel_prop(surf_pos, _generate_surfboard_image(), 1)

	# Sandcastle
	var castle_pos: Vector2 = _try_place(60, 420, 225, 248, 45.0)
	_add_pixel_prop(castle_pos, _generate_sandcastle_image(), 2)

	# Driftwood log
	var drift_pos: Vector2 = _try_place(40, 440, 218, 238, 45.0)
	_add_pixel_prop(drift_pos, _generate_driftwood_image(), 1)

	# Cooler box (random chance)
	if randf() > 0.3:
		var cooler_pos: Vector2 = _try_place(50, 430, 222, 245, 40.0)
		_add_pixel_prop(cooler_pos, _generate_cooler_image(), 2)


func _try_place(min_x: float, max_x: float, min_y: float, max_y: float, min_dist: float) -> Vector2:
	for attempt in 25:
		var pos := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		var too_close := false
		for other in _placed_positions:
			if pos.distance_to(other) < min_dist:
				too_close = true
				break
		if not too_close:
			_placed_positions.append(pos)
			return pos
	var pos := Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
	_placed_positions.append(pos)
	return pos


func _add_pixel_prop(pos: Vector2, img: Image, z: int) -> Node2D:
	var node := Node2D.new()
	node.position = pos
	node.z_index = z
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(3.0, 3.0)
	node.add_child(spr)
	add_child(node)
	return node


func _generate_surfboard_image() -> Image:
	# 4x14 pixel surfboard leaning at angle
	var w := 6
	var h := 14
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var board_colors := [
		[Color(0.2, 0.7, 0.85), Color(0.95, 0.95, 0.9)],  # teal/white
		[Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2)],     # red/yellow
		[Color(0.3, 0.8, 0.4), Color(0.9, 0.9, 0.85)],     # green/white
	]
	var bc: Array = board_colors[randi() % board_colors.size()]
	var top: Color = bc[0]
	var bot: Color = bc[1]
	# Surfboard shape (narrow top, wider middle, pointed bottom)
	# Offset to lean slightly
	img.set_pixel(3, 0, top)
	for x in [2, 3]: img.set_pixel(x, 1, top)
	for y in range(2, 5):
		for x in [2, 3, 4]: img.set_pixel(x, y, top)
	for y in range(5, 10):
		for x in [1, 2, 3, 4]: img.set_pixel(x, y, _color_mix(top, bot, float(y - 5) / 5.0))
	for y in range(10, 12):
		for x in [2, 3, 4]: img.set_pixel(x, y, bot)
	for x in [2, 3]: img.set_pixel(x, 12, bot)
	img.set_pixel(3, 13, bot)
	# Stripe
	for x in [2, 3, 4]: img.set_pixel(x, 6, Color(0.95, 0.95, 0.9, 1.0))
	return img

func _color_mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, t)

func _generate_sandcastle_image() -> Image:
	# 10x8 pixel sandcastle
	var w := 10
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var sand := Color(0.82, 0.7, 0.45, 1.0)
	var dark := Color(0.65, 0.52, 0.32, 1.0)
	var flag := Color(0.85, 0.2, 0.2, 1.0)
	# Center tower
	img.set_pixel(5, 0, flag)  # flag
	img.set_pixel(5, 1, dark)  # flag pole
	for x in [4, 5, 6]: img.set_pixel(x, 2, sand)  # tower top (crenellations)
	for y in [3, 4]:
		for x in range(4, 7): img.set_pixel(x, y, sand)
	# Base / walls
	for x in range(2, 8): img.set_pixel(x, 5, sand)
	for x in range(1, 9): img.set_pixel(x, 6, sand)
	for x in range(0, 10): img.set_pixel(x, 7, dark)
	# Side turrets
	img.set_pixel(2, 4, sand)
	img.set_pixel(7, 4, sand)
	img.set_pixel(2, 3, dark)
	img.set_pixel(7, 3, dark)
	return img

func _generate_driftwood_image() -> Image:
	# 12x3 pixel driftwood log
	var w := 12
	var h := 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wood1 := Color(0.5, 0.38, 0.25, 1.0)
	var wood2 := Color(0.6, 0.48, 0.32, 1.0)
	var wood3 := Color(0.45, 0.34, 0.22, 1.0)
	for x in range(1, 11): img.set_pixel(x, 0, wood2)
	for x in range(0, 12): img.set_pixel(x, 1, wood1 if (x % 3 != 0) else wood3)
	for x in range(1, 11): img.set_pixel(x, 2, wood3)
	# Knot
	img.set_pixel(4, 1, wood3)
	img.set_pixel(8, 0, wood3)
	return img

func _generate_cooler_image() -> Image:
	# 7x6 pixel cooler box
	var w := 7
	var h := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body := Color(0.2, 0.45, 0.75, 1.0)
	var lid := Color(0.25, 0.5, 0.8, 1.0)
	var white := Color(0.9, 0.9, 0.9, 1.0)
	var handle := Color(0.7, 0.7, 0.7, 1.0)
	# Handle
	for x in [2, 3, 4]: img.set_pixel(x, 0, handle)
	# Lid
	for x in range(0, 7): img.set_pixel(x, 1, lid)
	for x in range(0, 7): img.set_pixel(x, 2, white)  # white stripe
	# Body
	for y in [3, 4, 5]:
		for x in range(0, 7): img.set_pixel(x, y, body)
	return img


func _generate_beach_ball_image() -> Image:
	# 6x6 pixel beach ball
	var w := 6
	var h := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var red := Color(0.9, 0.2, 0.2, 1.0)
	var white := Color(0.95, 0.95, 0.95, 1.0)
	var blue := Color(0.2, 0.4, 0.9, 1.0)
	# Round ball shape with colored panels
	#   .RWWB.
	#   RRWWBB
	#   RRWWBB
	#   RRWWBB
	#   RRWWBB
	#   .RWWB.
	var rows := [
		[null, red, white, white, blue, null],
		[red, red, white, white, blue, blue],
		[red, red, white, white, blue, blue],
		[red, red, white, white, blue, blue],
		[red, red, white, white, blue, blue],
		[null, red, white, white, blue, null],
	]
	for y in rows.size():
		for x in rows[y].size():
			if rows[y][x] != null:
				img.set_pixel(x, y, rows[y][x])
	return img


func _generate_fire_pit_image() -> Image:
	# 8x4 pixel stone fire pit base
	var w := 8
	var h := 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stone1 := Color(0.35, 0.3, 0.28, 1.0)
	var stone2 := Color(0.45, 0.4, 0.35, 1.0)
	# Ring of stones
	for x in range(1, 7): img.set_pixel(x, 0, stone2)
	img.set_pixel(0, 1, stone1)
	img.set_pixel(7, 1, stone1)
	img.set_pixel(0, 2, stone2)
	img.set_pixel(7, 2, stone2)
	for x in range(1, 7): img.set_pixel(x, 3, stone1)
	# Dark inside
	var ash := Color(0.15, 0.12, 0.1, 1.0)
	for y in range(1, 3):
		for x in range(1, 7):
			img.set_pixel(x, y, ash)
	return img


func _generate_flame_image(frame: int) -> Image:
	# 6x7 pixel animated flame
	var w := 6
	var h := 7
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var yellow := Color(1.0, 0.85, 0.15, 1.0)
	var orange := Color(1.0, 0.5, 0.1, 1.0)
	var red := Color(0.9, 0.2, 0.1, 0.9)
	match frame % 3:
		0:
			img.set_pixel(3, 0, yellow)
			img.set_pixel(2, 1, yellow)
			img.set_pixel(3, 1, yellow)
			img.set_pixel(1, 2, orange)
			img.set_pixel(2, 2, yellow)
			img.set_pixel(3, 2, yellow)
			img.set_pixel(4, 2, orange)
			img.set_pixel(1, 3, orange)
			img.set_pixel(2, 3, orange)
			img.set_pixel(3, 3, yellow)
			img.set_pixel(4, 3, orange)
			for x in range(1, 5): img.set_pixel(x, 4, orange)
			for x in range(1, 5): img.set_pixel(x, 5, red)
			for x in range(2, 4): img.set_pixel(x, 6, red)
		1:
			img.set_pixel(2, 0, yellow)
			img.set_pixel(2, 1, yellow)
			img.set_pixel(3, 1, yellow)
			img.set_pixel(1, 2, orange)
			img.set_pixel(2, 2, yellow)
			img.set_pixel(3, 2, orange)
			img.set_pixel(4, 2, orange)
			img.set_pixel(1, 3, orange)
			img.set_pixel(2, 3, yellow)
			img.set_pixel(3, 3, orange)
			img.set_pixel(4, 3, red)
			for x in range(1, 5): img.set_pixel(x, 4, orange)
			for x in range(0, 5): img.set_pixel(x, 5, red)
			for x in range(1, 4): img.set_pixel(x, 6, red)
		2:
			img.set_pixel(3, 0, yellow)
			img.set_pixel(4, 0, yellow)
			img.set_pixel(3, 1, yellow)
			img.set_pixel(2, 1, orange)
			img.set_pixel(1, 2, orange)
			img.set_pixel(2, 2, yellow)
			img.set_pixel(3, 2, yellow)
			img.set_pixel(4, 2, orange)
			img.set_pixel(0, 3, red)
			img.set_pixel(1, 3, orange)
			img.set_pixel(2, 3, orange)
			img.set_pixel(3, 3, yellow)
			img.set_pixel(4, 3, orange)
			for x in range(1, 5): img.set_pixel(x, 4, orange)
			for x in range(1, 5): img.set_pixel(x, 5, red)
			for x in range(2, 5): img.set_pixel(x, 6, red)
	return img


func _animate_beach_penguins(delta: float) -> void:
	for p in _beach_penguins:
		p.timer += delta

		match p.anim:
			"sit":
				# Gentle breathing bob
				p.node.position.y = p.base_pos.y + sin(p.timer * 1.5) * 0.5

			"lounge":
				# Very subtle movement — occasional shift
				p.node.position.y = p.base_pos.y + sin(p.timer * 0.8) * 0.3

			"waddle":
				# Walk back and forth along the shore
				var walk_range := 40.0
				var walk_speed := 12.0
				var offset_x := sin(p.timer * 0.3) * walk_range
				p.node.position.x = p.base_pos.x + offset_x
				p.node.position.y = p.base_pos.y + abs(sin(p.timer * 1.2)) * -1.0  # hop
				# Flip based on direction
				p.sprite.flip_h = cos(p.timer * 0.3) < 0


func _animate_beach_props(delta: float) -> void:
	for p in _beach_props:
		p.timer += delta
		match p.type:
			"ball":
				# Gentle bob and slow roll
				p.node.position.y = p.base_pos.y + sin(p.timer * 2.0) * 1.0
				p.node.rotation = sin(p.timer * 0.5) * 0.3
			"flame":
				# Swap flame frame every 0.2s
				var new_frame: int = int(p.timer / 0.2) % 3
				if new_frame != p.frame:
					p.frame = new_frame
					var img := _generate_flame_image(new_frame)
					var tex := ImageTexture.create_from_image(img)
					p.sprite.texture = tex


func _on_settings() -> void:
	if settings_panel.visible:
		settings_panel.hide()
		return
	# Build settings UI
	for child in settings_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	settings_panel.add_child(vbox)

	# Music Volume
	_add_slider(vbox, "Music", MusicManager.get_music_volume(),
		func(val: float): MusicManager.set_music_volume(val))

	# SFX Volume
	_add_slider(vbox, "SFX", AudioManager.sfx_volume,
		func(val: float): AudioManager.set_sfx_volume(val))

	# Master Volume
	var master_linear: float = db_to_linear(
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")))
	_add_slider(vbox, "Master", master_linear,
		func(val: float):
			AudioServer.set_bus_volume_db(
				AudioServer.get_bus_index("Master"),
				linear_to_db(maxf(val, 0.001))))

	settings_panel.show()


func _add_slider(parent: VBoxContainer, label_text: String, initial: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.custom_minimum_size = Vector2(36, 0)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.custom_minimum_size = Vector2(70, 10)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(initial * 100)
	val_lbl.add_theme_font_size_override("font_size", 6)
	val_lbl.custom_minimum_size = Vector2(24, 0)
	row.add_child(val_lbl)

	slider.value_changed.connect(func(val: float):
		callback.call(val)
		val_lbl.text = "%d%%" % int(val * 100)
	)


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")


