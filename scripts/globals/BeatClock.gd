extends Node
# BeatClock — Central metronome for the adaptive music system.
# Tracks beat position synced to MusicManager playback.
# Provides is_on_beat() for combat timing checks.

signal beat_hit(beat_number: int)
signal measure_hit(measure_number: int)

# Tempo
var bpm: float = 140.0
var beats_per_measure: int = 4

# Beat state
var beat_number: int = 0
var measure_number: int = 0
var beat_progress: float = 0.0  # 0.0–1.0 within current beat

# Timing
var _beat_duration: float = 60.0 / 140.0  # seconds per beat
var _accumulated_time: float = 0.0
var _active: bool = false

# Tolerance windows (in milliseconds)
const PERFECT_MS: float = 40.0
const GOOD_MS: float = 80.0
const OK_MS: float = 120.0


func _ready() -> void:
	_update_beat_duration()


func _process(delta: float) -> void:
	if not _active:
		return

	# Sync to MusicManager's playback position if available
	var synced := false
	if MusicManager and MusicManager._active and not MusicManager._using_fallback:
		for stem_name in MusicManager.STEM_NAMES:
			var player: AudioStreamPlayer = MusicManager._stem_players.get(stem_name)
			if player and player.stream and player.playing:
				_accumulated_time = player.get_playback_position()
				synced = true
				break

	if not synced:
		_accumulated_time += delta

	beat_progress = fmod(_accumulated_time, _beat_duration) / _beat_duration

	# Check if we crossed a beat boundary
	var current_beat := int(_accumulated_time / _beat_duration)
	if current_beat != beat_number:
		beat_number = current_beat
		beat_hit.emit(beat_number)

		# Check measure boundary
		var current_measure := beat_number / beats_per_measure
		if current_measure != measure_number:
			measure_number = current_measure
			measure_hit.emit(measure_number)


# -------------------------------------------------------
# Public API
# -------------------------------------------------------
func start(new_bpm: float = 0.0) -> void:
	if new_bpm > 0.0:
		set_bpm(new_bpm)
	_accumulated_time = 0.0
	beat_number = 0
	measure_number = 0
	beat_progress = 0.0
	_active = true


func stop() -> void:
	_active = false


func set_bpm(new_bpm: float) -> void:
	bpm = new_bpm
	_update_beat_duration()


func is_on_beat(tolerance_ms: float = OK_MS) -> Dictionary:
	## Returns {on_beat: bool, offset_ms: float, accuracy: float, rating: String}
	## accuracy: 1.0 = perfect center, decays to 0.0 at tolerance edge
	## rating: "perfect", "great", "good", or "miss"
	if not _active:
		return {on_beat = false, offset_ms = 999.0, accuracy = 0.0, rating = "miss"}

	# Distance to nearest beat edge (could be before or after)
	var pos_in_beat: float = fmod(_accumulated_time, _beat_duration)
	var dist_to_prev: float = pos_in_beat
	var dist_to_next: float = _beat_duration - pos_in_beat
	var offset_sec: float = minf(dist_to_prev, dist_to_next)
	var offset_ms: float = offset_sec * 1000.0

	if offset_ms > tolerance_ms:
		return {on_beat = false, offset_ms = offset_ms, accuracy = 0.0, rating = "miss"}

	# Calculate accuracy (1.0 at center, 0.0 at edge)
	var accuracy: float = 1.0 - (offset_ms / tolerance_ms)

	# Determine rating
	var rating: String = "miss"
	if offset_ms <= PERFECT_MS:
		rating = "perfect"
	elif offset_ms <= GOOD_MS:
		rating = "great"
	elif offset_ms <= OK_MS:
		rating = "good"

	return {on_beat = true, offset_ms = offset_ms, accuracy = accuracy, rating = rating}


func get_seconds_to_next_beat() -> float:
	## How many seconds until the next beat — useful for scheduling.
	if not _active:
		return 0.0
	var pos_in_beat: float = fmod(_accumulated_time, _beat_duration)
	return _beat_duration - pos_in_beat


# -------------------------------------------------------
# Internal
# -------------------------------------------------------
func _update_beat_duration() -> void:
	_beat_duration = 60.0 / bpm
