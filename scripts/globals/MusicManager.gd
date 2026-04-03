extends Node
# MusicManager — Adaptive stem-based music system for TUX.
# Loads layered .wav stems per zone, mixes based on combat intensity.
# Falls back to LegacyMusicPlayer if stems are missing.

# -------------------------------------------------------
# Constants
# -------------------------------------------------------
const STEM_NAMES := ["atmosphere", "melody", "bass", "drums", "combat"]
# Alternate file names to check when a stem isn't found by its primary name
const STEM_ALIASES := {
	"atmosphere": ["pad"],
}
const MUSIC_BASE_PATH := "res://assets/music/"
const FADE_SPEED: float = 2.0  # volume lerp per second
const CROSSFADE_DURATION: float = 2.0
const INTENSITY_DECAY: float = 0.08  # per second when idle

# Stem intensity thresholds: [fade_in_at, full_at]
const STEM_THRESHOLDS := {
	"atmosphere": [0.0, 0.0],
	"melody":     [0.0, 0.3],
	"bass":       [0.2, 0.5],
	"drums":      [0.4, 0.7],
	"combat":     [0.6, 0.9],
}

# Per-stem max volume (0.0-1.0) to balance FluidSynth rendering levels
const STEM_MIX := {
	"atmosphere": 0.55,
	"melody":     0.70,
	"bass":       0.65,
	"drums":      0.60,
	"combat":     0.50,
}

# -------------------------------------------------------
# State
# -------------------------------------------------------
var current_zone: String = ""
var intensity: float = 0.0
var target_intensity: float = 0.0
var base_intensity: float = 0.0  # minimum intensity floor per zone
var music_volume: float = 0.7

var _stem_players: Dictionary = {}  # stem_name -> AudioStreamPlayer
var _stem_target_volumes: Dictionary = {}  # stem_name -> float
var _stinger_player: AudioStreamPlayer
var _active: bool = false
var _using_fallback: bool = false

# Fallback legacy player reference (set if stems missing)
var _legacy_player: Node = null
var _loop_timer: float = 0.0       # tracks playback position within the loop
var _loop_duration: float = 0.0    # duration of the longest stem


func _ready() -> void:
	# Ensure audio buses exist
	_ensure_bus("Music")
	_ensure_bus("SFX")

	# Create stem players
	for stem_name in STEM_NAMES:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = -80.0  # start silent
		add_child(player)
		_stem_players[stem_name] = player
		_stem_target_volumes[stem_name] = 0.0

	# Stinger player for one-shot beat-reactive sounds
	_stinger_player = AudioStreamPlayer.new()
	_stinger_player.bus = "Master"
	_stinger_player.volume_db = linear_to_db(0.6)
	add_child(_stinger_player)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func debug_test_audio() -> void:
	## Call from _ready to test if audio works at all
	var test_path := "res://assets/music/menu/melody.wav"
	print("[MusicManager] DEBUG: Testing audio...")
	print("[MusicManager] DEBUG: File exists: %s" % ResourceLoader.exists(test_path))
	if ResourceLoader.exists(test_path):
		var stream = load(test_path)
		print("[MusicManager] DEBUG: Stream type: %s" % stream.get_class())
		print("[MusicManager] DEBUG: Stream length: %s" % stream.get_length())
		var test_player := AudioStreamPlayer.new()
		test_player.stream = stream
		test_player.volume_db = 0.0
		test_player.bus = "Master"  # bypass Music bus, go straight to Master
		add_child(test_player)
		test_player.play()
		print("[MusicManager] DEBUG: Playing on Master bus at 0 dB")
	else:
		print("[MusicManager] DEBUG: File not found!")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		regenerate_music()


func _process(delta: float) -> void:
	if not _active:
		return

	# Decay intensity toward base level when no combat input
	intensity = move_toward(intensity, target_intensity, INTENSITY_DECAY * delta)
	target_intensity = move_toward(target_intensity, base_intensity, INTENSITY_DECAY * delta)

	# Update stem volumes based on intensity
	_update_stem_volumes(delta)

	# Timer-based loop restart — all stems restart together
	if _loop_duration > 0.0 and not _using_fallback:
		_loop_timer += delta
		if _loop_timer >= _loop_duration:
			_loop_timer = 0.0
			_restart_all_stems()


# -------------------------------------------------------
# Public API
# -------------------------------------------------------
func play_zone(zone_name: String) -> void:
	print("[MusicManager] >>> play_zone('%s') called. current_zone='%s' active=%s" % [zone_name, current_zone, _active])
	if zone_name == current_zone and _active:
		print("[MusicManager] >>> Already playing this zone, skipping")
		return

	var zone_path: String = MUSIC_BASE_PATH + zone_name + "/"
	print("[MusicManager] >>> Zone path: %s" % zone_path)

	# Check if stems exist for this zone
	if not _zone_has_stems(zone_path):
		print("[MusicManager] >>> No stems found for '%s', using fallback" % zone_name)
		_start_fallback(zone_name)
		current_zone = zone_name
		return
	print("[MusicManager] >>> Stems found! Loading...")

	# Stop fallback if it was playing
	_stop_fallback()

	# Load and start all stems simultaneously
	_stop_all_stems()
	current_zone = zone_name
	_using_fallback = false

	_loop_duration = 0.0
	for stem_name in STEM_NAMES:
		var file_path: String = _find_stem_file(zone_path, stem_name)
		if file_path != "":
			var stream: AudioStream = load(file_path)
			var player: AudioStreamPlayer = _stem_players[stem_name]
			player.stream = stream
			player.bus = "Master"
			player.volume_db = 0.0
			player.play()
			# Track longest stem for loop timing
			if stream.get_length() > _loop_duration:
				_loop_duration = stream.get_length()
		else:
			_stem_players[stem_name].stream = null

	_loop_timer = 0.0
	_active = true
	BeatClock.start(140.0)

	# Set starting intensity so stems are audible
	# Menu/hub stay ambient; dungeon zones start at exploration level
	# base_intensity prevents decay from silencing everything
	match zone_name:
		"menu":
			base_intensity = 0.1
		"hub":
			base_intensity = 0.2
		_:
			base_intensity = 0.35
	intensity = base_intensity
	target_intensity = base_intensity


func stop_all() -> void:
	_active = false
	_stop_all_stems()
	_stop_fallback()
	BeatClock.stop()
	current_zone = ""


var _regenerating: bool = false

func regenerate_music() -> void:
	## Run generate_music.py in background, then reload current zone.
	if _regenerating:
		print("[MusicManager] Already regenerating...")
		return
	_regenerating = true
	print("[MusicManager] Regenerating music stems...")

	# Run the Python script in a thread so the game doesn't freeze
	var thread := Thread.new()
	thread.start(_regen_thread.bind(thread))


func _regen_thread(thread: Thread) -> void:
	var script_path: String = ProjectSettings.globalize_path("res://").path_join("../tools/generate_music.py")
	# Try to find generate_music.py relative to project
	var paths_to_try: Array[String] = [
		ProjectSettings.globalize_path("res://tools/generate_music.py"),
		ProjectSettings.globalize_path("res://").get_base_dir() + "/tools/generate_music.py",
	]
	# Use OS.execute for cross-platform
	var output: Array = []
	var exit_code: int = OS.execute("python", [ProjectSettings.globalize_path("res://").get_base_dir().path_join("tools/generate_music.py")], output, true)
	call_deferred("_regen_finished", exit_code, output, thread)


func _regen_finished(exit_code: int, output: Array, thread: Thread) -> void:
	thread.wait_to_finish()
	_regenerating = false
	if exit_code == 0:
		print("[MusicManager] Regen complete! Reloading zone...")
		# Force reload by clearing current_zone so play_zone doesn't skip
		var zone := current_zone
		current_zone = ""
		# Clear resource cache for music files so Godot reloads them
		for stem_name in STEM_NAMES:
			var file_path: String = _find_stem_file(MUSIC_BASE_PATH + zone + "/", stem_name)
			if file_path != "":
				ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		play_zone(zone)
	else:
		print("[MusicManager] Regen FAILED (exit %d)" % exit_code)
		if output.size() > 0:
			print(str(output[0]).substr(0, 500))


func set_intensity(value: float) -> void:
	target_intensity = clampf(value, 0.0, 1.0)
	intensity = target_intensity


func add_intensity(amount: float) -> void:
	target_intensity = clampf(target_intensity + amount, 0.0, 1.0)
	intensity = clampf(intensity + amount * 0.5, 0.0, 1.0)  # partial immediate bump


func play_stinger(stinger_name: String) -> void:
	var path: String = MUSIC_BASE_PATH + "stingers/" + stinger_name + ".wav"
	if ResourceLoader.exists(path):
		_stinger_player.stream = load(path)
		_stinger_player.play()


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	# Update stinger volume too
	if _stinger_player:
		_stinger_player.volume_db = linear_to_db(clampf(music_volume * 0.8, 0.001, 1.0))


func get_music_volume() -> float:
	return music_volume


# -------------------------------------------------------
# Stem volume management
# -------------------------------------------------------
func _update_stem_volumes(delta: float) -> void:
	if _using_fallback:
		return

	for stem_name in STEM_NAMES:
		var player: AudioStreamPlayer = _stem_players[stem_name]
		if not player.stream:
			continue

		# Calculate target volume based on intensity thresholds
		var thresholds: Array = STEM_THRESHOLDS[stem_name]
		var fade_in: float = thresholds[0]
		var full_at: float = thresholds[1]

		var target_vol: float = 0.0
		if intensity >= full_at:
			target_vol = 1.0
		elif intensity >= fade_in:
			var range_size: float = full_at - fade_in
			if range_size > 0.001:
				target_vol = (intensity - fade_in) / range_size
			else:
				target_vol = 1.0

		target_vol *= music_volume * STEM_MIX.get(stem_name, 0.7)
		_stem_target_volumes[stem_name] = target_vol

		# Lerp current volume toward target
		var current_linear: float = db_to_linear(player.volume_db)
		var new_linear: float = move_toward(current_linear, target_vol, FADE_SPEED * delta)

		# Clamp to avoid -INF dB
		if new_linear < 0.001:
			player.volume_db = -80.0
		else:
			player.volume_db = linear_to_db(new_linear)


func _restart_all_stems() -> void:
	# Restart all stems from the beginning, perfectly synced
	for stem_name in STEM_NAMES:
		var player: AudioStreamPlayer = _stem_players[stem_name]
		if player.stream:
			player.stop()
			player.play()
			player.seek(0.0)


func _stop_all_stems() -> void:
	for stem_name in STEM_NAMES:
		var player: AudioStreamPlayer = _stem_players[stem_name]
		player.stop()
		player.stream = null
		player.volume_db = -80.0


# -------------------------------------------------------
# Zone detection
# -------------------------------------------------------
func _find_stem_file(zone_path: String, stem_name: String) -> String:
	# Check primary name
	var path: String = zone_path + stem_name + ".wav"
	if ResourceLoader.exists(path):
		return path
	# Check aliases
	if STEM_ALIASES.has(stem_name):
		for alias in STEM_ALIASES[stem_name]:
			var alias_path: String = zone_path + alias + ".wav"
			if ResourceLoader.exists(alias_path):
				return alias_path
	return ""


func _zone_has_stems(zone_path: String) -> bool:
	# Check if at least one stem file exists (including aliases)
	for stem_name in STEM_NAMES:
		if _find_stem_file(zone_path, stem_name) != "":
			return true
	return false


# -------------------------------------------------------
# Fallback to legacy procedural music
# -------------------------------------------------------
func _start_fallback(zone_name: String) -> void:
	_using_fallback = true
	_active = true
	_stop_all_stems()

	if _legacy_player and _legacy_player.has_method("play_track"):
		# Map zone names to legacy track names
		var track := "hub"
		match zone_name:
			"menu": track = "menu"
			"hub": track = "hub"
			"boss": track = "boss"
			_: track = "dungeon"
		_legacy_player.play_track(track)

	BeatClock.start(140.0)


func _stop_fallback() -> void:
	if _using_fallback and _legacy_player and _legacy_player.has_method("stop_music"):
		_legacy_player.stop_music()
	_using_fallback = false


func set_legacy_player(player: Node) -> void:
	_legacy_player = player


# -------------------------------------------------------
# Soundtrack save/load system
# -------------------------------------------------------
const SAVED_MUSIC_PATH := "user://saved_soundtracks/"
const ZONE_NAMES := ["menu", "hub", "flooded_ruins", "coral_crypts",
	"abyssal_trench", "gods_sanctum", "boss"]

func save_current_soundtrack(save_name: String) -> bool:
	## Copy all current stems to a named save folder.
	var save_dir: String = SAVED_MUSIC_PATH + save_name + "/"
	DirAccess.make_dir_recursive_absolute(save_dir)

	var copied := 0
	for zone in ZONE_NAMES:
		var zone_src: String = MUSIC_BASE_PATH + zone + "/"
		var zone_dst: String = save_dir + zone + "/"
		DirAccess.make_dir_recursive_absolute(zone_dst)

		for stem_name in STEM_NAMES:
			var src_file: String = zone_src + stem_name + ".wav"
			if ResourceLoader.exists(src_file):
				# Read and write the file data
				var data := FileAccess.get_file_as_bytes(src_file)
				if data.size() > 0:
					var dst_file: String = zone_dst + stem_name + ".wav"
					var f := FileAccess.open(dst_file, FileAccess.WRITE)
					if f:
						f.store_buffer(data)
						f.close()
						copied += 1

	if copied > 0:
		# Save metadata
		var meta := FileAccess.open(save_dir + "info.txt", FileAccess.WRITE)
		if meta:
			meta.store_string("Saved: %s\nTracks: %d\n" % [save_name, copied])
			meta.close()
		return true
	return false


func get_saved_soundtracks() -> Array[String]:
	## Return list of saved soundtrack names.
	var saves: Array[String] = []
	var dir := DirAccess.open(SAVED_MUSIC_PATH)
	if not dir:
		return saves
	dir.list_dir_begin()
	var folder := dir.get_next()
	while folder != "":
		if dir.current_is_dir() and folder != "." and folder != "..":
			saves.append(folder)
		folder = dir.get_next()
	return saves


func load_saved_soundtrack(save_name: String) -> bool:
	## Load a previously saved soundtrack as the active music source.
	## Copies saved stems into the active music folder.
	var save_dir: String = SAVED_MUSIC_PATH + save_name + "/"
	var dir := DirAccess.open(save_dir)
	if not dir:
		return false

	# Copy stems from saved location back to active music folder
	var old_path: String = MUSIC_BASE_PATH
	# Can't change const, so we play zones from saved dir manually
	for zone in ZONE_NAMES:
		var zone_path: String = save_dir + zone + "/"
		# Check if this zone has stems in the save
		var zone_dir := DirAccess.open(zone_path)
		if not zone_dir:
			continue
		# Copy back to active music folder
		var dst_zone: String = MUSIC_BASE_PATH + zone + "/"
		for stem_name in STEM_NAMES:
			var src: String = zone_path + stem_name + ".wav"
			var dst: String = dst_zone + stem_name + ".wav"
			if FileAccess.file_exists(src):
				var data := FileAccess.get_file_as_bytes(src)
				if data.size() > 0:
					var f := FileAccess.open(dst, FileAccess.WRITE)
					if f:
						f.store_buffer(data)
						f.close()
	return true


func delete_saved_soundtrack(save_name: String) -> void:
	var save_dir: String = SAVED_MUSIC_PATH + save_name + "/"
	var dir := DirAccess.open(save_dir)
	if not dir:
		return
	# Delete all files in the save
	for zone in ZONE_NAMES:
		var zone_path: String = save_dir + zone + "/"
		var zone_dir := DirAccess.open(zone_path)
		if zone_dir:
			zone_dir.list_dir_begin()
			var fname := zone_dir.get_next()
			while fname != "":
				zone_dir.remove(fname)
				fname = zone_dir.get_next()
			DirAccess.remove_absolute(zone_path)
	# Remove info file and folder
	if FileAccess.file_exists(save_dir + "info.txt"):
		DirAccess.remove_absolute(save_dir + "info.txt")
	DirAccess.remove_absolute(save_dir)
