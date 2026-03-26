extends Node
# Builds SpriteFrames for each enemy type at runtime.
# Sheet format: 32×16 (2 frames: idle left, walk right), all 16×16.

const SHEET_MAP := {
	# EnemyType -> sprite sheet path
	0:  "res://assets/sprites/enemies/crab_grunt.png",    # CRAB_GRUNT
	1:  "res://assets/sprites/enemies/crab_knight.png",   # CRAB_KNIGHT
	2:  "res://assets/sprites/enemies/crab_warlord.png",  # LOBSTER_WARLORD (reuse)
	3:  "res://assets/sprites/enemies/eel_scout.png",     # EEL_SCOUT
	4:  "res://assets/sprites/enemies/anglerfish.png",    # ANGLERFISH
	5:  "res://assets/sprites/enemies/shark_brute.png",   # SHARK_BRUTE
	6:  "res://assets/sprites/enemies/jellyfish.png",     # JELLYFISH_DRIFTER
	7:  "res://assets/sprites/enemies/urchin.png",        # URCHIN_ROLLER
	8:  "res://assets/sprites/enemies/anemone.png",       # ANEMONE_TRAP
	9:  "res://assets/sprites/enemies/crab_warlord.png",  # CRAB_WARLORD (boss)
	10: "res://assets/sprites/enemies/leviathan.png",     # THE_LEVIATHAN
	11: "res://assets/sprites/enemies/drowned_god.png",   # THE_DROWNED_GOD
}

static func build_frames(enemy_type: int) -> SpriteFrames:
	var path: String = SHEET_MAP.get(enemy_type, SHEET_MAP[0])
	var texture := load(path) as Texture2D
	if not texture:
		push_error("EnemySpriteBuilder: could not load %s" % path)
		return SpriteFrames.new()

	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	# idle: frame 0
	_add_anim(frames, texture, "idle",   [0], 4.0,  true)
	# walk: frame 1
	_add_anim(frames, texture, "walk",   [1], 6.0,  true)
	# attack: flash between 0 and 1
	_add_anim(frames, texture, "attack", [0, 1], 10.0, false)
	# death: frame 0 (tinted red via modulate in code)
	_add_anim(frames, texture, "death",  [0], 4.0, false)

	return frames

static func _add_anim(frames: SpriteFrames, tex: Texture2D,
		name: String, frame_indices: Array,
		speed: float, loop: bool) -> void:
	frames.add_animation(name)
	frames.set_animation_speed(name, speed)
	frames.set_animation_loop(name, loop)
	for fi in frame_indices:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(fi * 16, 0, 16, 16)
		frames.add_frame(name, atlas)
