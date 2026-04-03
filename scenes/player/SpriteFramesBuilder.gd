extends Node
# Run this as an EditorScript (Tools > Execute Script) once to build SpriteFrames .tres files.
# Or call build_frames_for_class() at runtime to attach frames dynamically.

# Sheet layout: 64×80, 4 cols × 5 rows of 16×16 frames
# Row 0 = idle (4), Row 1 = walk (4), Row 2 = attack (4), Row 3 = death (4), Row 4 = secondary (4)
const FRAME_W := 16
const FRAME_H := 16
const COLS    := 4

const SHEET_PATHS := {
	ItemDatabase.PlayerClass.EMPEROR:    "res://assets/sprites/players/emperor_sheet.png",
	ItemDatabase.PlayerClass.GENTOO:     "res://assets/sprites/players/gentoo_sheet.png",
	ItemDatabase.PlayerClass.LITTLE_BLUE:"res://assets/sprites/players/little_blue_sheet.png",
	ItemDatabase.PlayerClass.MACARONI:   "res://assets/sprites/players/macaroni_sheet.png",
}

# Per-class animation speed overrides (attack speed, walk speed, etc.)
const CLASS_ANIM_SPEED := {
	ItemDatabase.PlayerClass.EMPEROR:     {"walk": 6.0, "attack": 8.0,  "secondary": 8.0},
	ItemDatabase.PlayerClass.GENTOO:      {"walk": 12.0, "attack": 16.0, "secondary": 14.0},
	ItemDatabase.PlayerClass.LITTLE_BLUE: {"walk": 8.0, "attack": 12.0, "secondary": 10.0},
	ItemDatabase.PlayerClass.MACARONI:    {"walk": 7.0, "attack": 10.0, "secondary": 6.0},
}

# Per-class visual scale (applied to the AnimatedSprite2D)
const CLASS_SCALE := {
	ItemDatabase.PlayerClass.EMPEROR:     Vector2(1.25, 1.25),
	ItemDatabase.PlayerClass.GENTOO:      Vector2(0.9, 0.9),
	ItemDatabase.PlayerClass.LITTLE_BLUE: Vector2(1.0, 1.0),
	ItemDatabase.PlayerClass.MACARONI:    Vector2(1.1, 1.15),
}

const ANIM_ROWS := {
	"idle":      { "row": 0, "frames": 2, "speed": 4.0,  "loop": true  },
	"walk":      { "row": 1, "frames": 4, "speed": 8.0,  "loop": true  },
	"attack":    { "row": 2, "frames": 2, "speed": 12.0, "loop": false },
	"death":     { "row": 3, "frames": 2, "speed": 5.0,  "loop": false },
	"secondary": { "row": 4, "frames": 2, "speed": 10.0, "loop": false },
}

static func build_frames_for_class(player_class: int) -> SpriteFrames:
	var sheet_path: String = SHEET_PATHS.get(player_class, SHEET_PATHS[ItemDatabase.PlayerClass.EMPEROR])
	var texture := load(sheet_path) as Texture2D
	if not texture:
		push_error("SpriteFramesBuilder: could not load %s" % sheet_path)
		return SpriteFrames.new()

	var speed_overrides: Dictionary = CLASS_ANIM_SPEED.get(player_class, {})

	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name in ANIM_ROWS:
		var info: Dictionary = ANIM_ROWS[anim_name]
		frames.add_animation(anim_name)
		var speed: float = speed_overrides.get(anim_name, info["speed"])
		frames.set_animation_speed(anim_name, speed)
		frames.set_animation_loop(anim_name, info["loop"])
		for f in info["frames"]:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				f * FRAME_W,
				info["row"] * FRAME_H,
				FRAME_W,
				FRAME_H
			)
			frames.add_frame(anim_name, atlas)

	return frames

static func get_class_scale(player_class: int) -> Vector2:
	return CLASS_SCALE.get(player_class, Vector2.ONE)
