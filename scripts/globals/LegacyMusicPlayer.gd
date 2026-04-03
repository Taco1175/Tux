extends Node
# LegacyMusicPlayer — Preserved procedural 8-bit metal music from AudioManager.
# Used as fallback when .ogg stems are not yet generated.
# MusicManager holds a reference and delegates to this when needed.

var _music_player: AudioStreamPlayer
var _music_gen: AudioStreamGenerator
var _music_playback: AudioStreamGeneratorPlayback
var _music_phase: float = 0.0
var _music_beat: float = 0.0
var _music_tempo: float = 140.0
var _music_playing: bool = false
var _current_track: String = ""

var _riff_index: int = 0
var _drum_index: int = 0
var _current_riff: Array = []
var _current_drums: Array = []
var _note_timer: float = 0.0
var _sample_rate: float = 22050.0

const NOTE_FREQS := {
	"C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61,
	"G3": 196.00, "A3": 220.00, "B3": 246.94,
	"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
	"G4": 392.00, "A4": 440.00, "B4": 493.88,
	"C5": 523.25, "D5": 587.33, "E5": 659.26,
}

const RIFFS := {
	"hub": ["E3", "E3", "G3", "A3", "E3", "E3", "B3", "A3",
			"D3", "D3", "F3", "G3", "D3", "D3", "A3", "G3"],
	"dungeon": ["E3", "E3", "E3", "F3", "E3", "D3", "E3", "E3",
				"G3", "G3", "A3", "G3", "F3", "E3", "D3", "E3"],
	"boss": ["E3", "F3", "E3", "F3", "G3", "A3", "G3", "F3",
			 "E3", "E3", "B3", "A3", "G3", "F3", "E3", "E3"],
	"menu": ["A3", "C4", "E4", "A3", "C4", "E4", "G3", "B3",
			 "D4", "G3", "B3", "D4", "A3", "C4", "E4", "A4"],
}

const DRUM_PATTERNS := {
	"metal": [1, 3, 2, 3, 1, 3, 2, 3, 1, 3, 2, 3, 1, 1, 2, 3],
	"fast":  [1, 3, 1, 3, 2, 3, 1, 3, 1, 3, 1, 3, 2, 3, 2, 3],
	"boss":  [1, 1, 2, 3, 1, 1, 2, 3, 1, 1, 2, 1, 2, 1, 2, 3],
}


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_gen = AudioStreamGenerator.new()
	_music_gen.mix_rate = _sample_rate
	_music_gen.buffer_length = 0.2
	_music_player.stream = _music_gen
	_music_player.volume_db = linear_to_db(0.7 * 0.4)
	add_child(_music_player)

	# Register with MusicManager as fallback
	if MusicManager:
		MusicManager.set_legacy_player(self)


func _process(_delta: float) -> void:
	if _music_playing and _music_playback:
		_fill_music_buffer()


func play_track(track_name: String) -> void:
	if _current_track == track_name and _music_playing:
		return
	_current_track = track_name
	_current_riff = RIFFS.get(track_name, RIFFS["hub"])
	match track_name:
		"boss": _current_drums = DRUM_PATTERNS["boss"]
		"dungeon": _current_drums = DRUM_PATTERNS["fast"]
		_: _current_drums = DRUM_PATTERNS["metal"]
	_riff_index = 0
	_drum_index = 0
	_music_phase = 0.0
	_music_beat = 0.0
	_music_playing = true
	_music_player.play()
	_music_playback = _music_player.get_stream_playback()


func stop_music() -> void:
	_music_playing = false
	_music_player.stop()
	_current_track = ""


func _fill_music_buffer() -> void:
	var frames_available: int = _music_playback.get_frames_available()
	if frames_available <= 0:
		return
	var beat_duration: float = 60.0 / _music_tempo / 4.0
	var note_freq: float = NOTE_FREQS.get(_current_riff[_riff_index], 130.81)
	for i in frames_available:
		var t: float = _music_phase / _sample_rate
		var riff_sample: float = _square_wave(t, note_freq) * 0.3
		var fifth_freq: float = note_freq * 1.5
		riff_sample += _square_wave(t, fifth_freq) * 0.15
		var bass_sample: float = _triangle_wave(t, note_freq * 0.5) * 0.25
		var drum_sample: float = _get_drum_sample(t)
		var mixed: float = riff_sample + bass_sample + drum_sample
		mixed = clampf(mixed, -0.8, 0.8)
		_music_playback.push_frame(Vector2(mixed, mixed))
		_music_phase += 1.0
		_music_beat += 1.0 / _sample_rate
		if _music_beat >= beat_duration:
			_music_beat -= beat_duration
			_riff_index = (_riff_index + 1) % _current_riff.size()
			_drum_index = (_drum_index + 1) % _current_drums.size()


func _get_drum_sample(t: float) -> float:
	var beat_pos: float = fmod(_music_beat, 60.0 / _music_tempo / 4.0)
	var attack: float = beat_pos * _sample_rate
	if attack > 800:
		return 0.0
	var drum_type: int = _current_drums[_drum_index]
	var envelope: float = maxf(0.0, 1.0 - attack / 800.0)
	match drum_type:
		1: return _square_wave(t, 60.0 + attack * 0.02) * envelope * 0.4
		2: return (randf() * 2.0 - 1.0) * envelope * 0.3
		3:
			var hh_env: float = maxf(0.0, 1.0 - attack / 200.0)
			return (randf() * 2.0 - 1.0) * hh_env * 0.15
	return 0.0


func _square_wave(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0

func _triangle_wave(t: float, freq: float) -> float:
	var phase: float = fmod(t * freq, 1.0)
	return 4.0 * absf(phase - 0.5) - 1.0
