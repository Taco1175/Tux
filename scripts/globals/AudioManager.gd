extends Node
# AudioManager — Procedural 8-bit metal audio for TUX.
# Generates chiptune waveforms at runtime using AudioStreamGenerator.
# No external audio files needed.

# -------------------------------------------------------
# Audio buses
# -------------------------------------------------------
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var music_volume: float = 0.7
var sfx_volume: float = 0.8

# Music player
var _music_player: AudioStreamPlayer
var _music_gen: AudioStreamGenerator
var _music_playback: AudioStreamGeneratorPlayback
var _music_phase: float = 0.0
var _music_beat: float = 0.0
var _music_tempo: float = 140.0  # BPM — metal tempo
var _music_playing: bool = false
var _current_track: String = ""

# SFX pool — multiple simultaneous SFX
var _sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 8

# Note frequencies (A=440 tuning)
const NOTE_FREQS := {
	"C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61,
	"G3": 196.00, "A3": 220.00, "B3": 246.94,
	"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
	"G4": 392.00, "A4": 440.00, "B4": 493.88,
	"C5": 523.25, "D5": 587.33, "E5": 659.26,
}

# Metal riff patterns (note sequences for different tracks)
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

# Drum pattern (1 = kick, 2 = snare, 3 = hi-hat, 0 = rest)
const DRUM_PATTERNS := {
	"metal": [1, 3, 2, 3, 1, 3, 2, 3, 1, 3, 2, 3, 1, 1, 2, 3],
	"fast":  [1, 3, 1, 3, 2, 3, 1, 3, 1, 3, 1, 3, 2, 3, 2, 3],
	"boss":  [1, 1, 2, 3, 1, 1, 2, 3, 1, 1, 2, 1, 2, 1, 2, 3],
}

var _riff_index: int = 0
var _drum_index: int = 0
var _current_riff: Array = []
var _current_drums: Array = []
var _note_timer: float = 0.0
var _sample_rate: float = 22050.0


func _ready() -> void:
	# Create music player with generator stream
	_music_player = AudioStreamPlayer.new()
	_music_gen = AudioStreamGenerator.new()
	_music_gen.mix_rate = _sample_rate
	_music_gen.buffer_length = 0.2
	_music_player.stream = _music_gen
	_music_player.volume_db = linear_to_db(music_volume * 0.4)
	add_child(_music_player)

	# Create SFX player pool
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = _sample_rate
		gen.buffer_length = 0.15
		player.stream = gen
		player.volume_db = linear_to_db(sfx_volume)
		add_child(player)
		_sfx_players.append(player)


func _process(delta: float) -> void:
	if _music_playing and _music_playback:
		_fill_music_buffer()


# -------------------------------------------------------
# Music control
# -------------------------------------------------------
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


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(music_volume * 0.4)


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	for p in _sfx_players:
		p.volume_db = linear_to_db(sfx_volume)


# -------------------------------------------------------
# Music generation — fills the buffer with 8-bit metal
# -------------------------------------------------------
func _fill_music_buffer() -> void:
	var frames_available: int = _music_playback.get_frames_available()
	if frames_available <= 0:
		return

	var beat_duration: float = 60.0 / _music_tempo / 4.0  # 16th notes
	var note_freq: float = NOTE_FREQS.get(_current_riff[_riff_index], 130.81)

	for i in frames_available:
		var t: float = _music_phase / _sample_rate

		# Main riff: square wave (classic 8-bit)
		var riff_sample: float = _square_wave(t, note_freq) * 0.3

		# Power chord: add fifth
		var fifth_freq: float = note_freq * 1.5
		riff_sample += _square_wave(t, fifth_freq) * 0.15

		# Bass: one octave down, triangle wave
		var bass_sample: float = _triangle_wave(t, note_freq * 0.5) * 0.25

		# Drums
		var drum_sample: float = _get_drum_sample(t)

		var mixed: float = riff_sample + bass_sample + drum_sample
		mixed = clampf(mixed, -0.8, 0.8)

		_music_playback.push_frame(Vector2(mixed, mixed))
		_music_phase += 1.0

		# Advance beat
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
		1:  # Kick — low freq noise burst
			return _square_wave(t, 60.0 + attack * 0.02) * envelope * 0.4
		2:  # Snare — mid noise burst
			return (randf() * 2.0 - 1.0) * envelope * 0.3
		3:  # Hi-hat — high noise, short
			var hh_env: float = maxf(0.0, 1.0 - attack / 200.0)
			return (randf() * 2.0 - 1.0) * hh_env * 0.15
	return 0.0


# -------------------------------------------------------
# Waveform generators
# -------------------------------------------------------
func _square_wave(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0


func _triangle_wave(t: float, freq: float) -> float:
	var phase: float = fmod(t * freq, 1.0)
	return 4.0 * absf(phase - 0.5) - 1.0


func _saw_wave(t: float, freq: float) -> float:
	return 2.0 * fmod(t * freq, 1.0) - 1.0


func _noise() -> float:
	return randf() * 2.0 - 1.0


# -------------------------------------------------------
# SFX — class-specific attack sounds
# -------------------------------------------------------
func play_sfx(sfx_name: String) -> void:
	var player := _get_free_sfx_player()
	if not player:
		return
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if not playback:
		return
	var samples := _generate_sfx(sfx_name)
	for s in samples:
		if playback.can_push_buffer(1):
			playback.push_frame(Vector2(s, s))


func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]  # Reuse oldest if all busy


func _generate_sfx(sfx_name: String) -> Array[float]:
	var samples: Array[float] = []
	var duration: float = 0.1
	var freq: float = 440.0

	match sfx_name:
		"guitar_hit":
			# Distorted guitar power chord stab
			duration = 0.12
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _square_wave(t, 196.0) * 0.3 + _square_wave(t, 294.0) * 0.2
				s = clampf(s * 3.0, -1.0, 1.0) * env * 0.6  # Distortion
				samples.append(s)
		"drum_hit":
			# Rapid snare + kick combo
			duration = 0.08
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _square_wave(t, 80.0) * 0.3 + _noise() * 0.4
				samples.append(s * env * 0.5)
		"vocal_hit":
			# Vocal screech / note
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var vibrato: float = sin(t * 30.0) * 20.0
				var s: float = _saw_wave(t, 523.0 + vibrato) * 0.3
				samples.append(s * env * 0.5)
		"bass_hit":
			# Deep bass thump + buzz
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _triangle_wave(t, 82.0) * 0.4 + _square_wave(t, 82.0) * 0.2
				samples.append(s * env * 0.6)
		"pickup":
			# Item pickup jingle — ascending arpeggio
			duration = 0.2
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var note_idx: int = int(t / duration * 4.0)
				var freqs := [523.0, 659.0, 784.0, 1047.0]
				var f: float = freqs[mini(note_idx, 3)]
				var s: float = _square_wave(t, f) * 0.15 + _triangle_wave(t, f) * 0.15
				samples.append(s * env * 0.5)
		"hit_taken":
			# Damage received — harsh noise burst
			duration = 0.08
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _noise() * 0.5 + _square_wave(t, 100.0) * 0.3
				samples.append(s * env * 0.4)
		"death":
			# Descending wah — game over sting
			duration = 0.4
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var f: float = 400.0 - t * 600.0
				var s: float = _saw_wave(t, maxf(f, 50.0)) * 0.3
				samples.append(s * env * 0.5)
		"power_chord":
			# Emperor special — big distorted chord
			duration = 0.2
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _square_wave(t, 130.0) * 0.25
				s += _square_wave(t, 196.0) * 0.2
				s += _square_wave(t, 261.0) * 0.15
				s = clampf(s * 3.0, -1.0, 1.0) * env * 0.5
				samples.append(s)
		"drum_fill":
			# Gentoo special — rapid drum fill
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var rapid: float = fmod(t * 25.0, 1.0)
				var s: float = _noise() * 0.3 + _square_wave(t, 200.0 * rapid) * 0.2
				samples.append(s * env * 0.5)
		"power_ballad":
			# Little Blue special — warm healing chord
			duration = 0.25
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration) * (0.5 + 0.5 * sin(t * 8.0))
				var s: float = _triangle_wave(t, 392.0) * 0.2
				s += _triangle_wave(t, 494.0) * 0.15
				s += _triangle_wave(t, 587.0) * 0.1
				samples.append(s * env * 0.5)
		"bass_drop":
			# Macaroni special — deep sub-bass explosion
			duration = 0.25
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var f: float = 50.0 + (1.0 - t / duration) * 80.0
				var s: float = _triangle_wave(t, f) * 0.5 + _square_wave(t, f) * 0.2
				s += _noise() * 0.1 * env
				samples.append(s * env * 0.6)
		"death_metal":
			# Little Blue snap — harsh vocal screech
			duration = 0.3
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _saw_wave(t, 200.0 + _noise() * 50.0) * 0.3
				s = clampf(s * 4.0, -1.0, 1.0) * env * 0.4
				samples.append(s)
		_:
			# Generic blip
			for i in int(_sample_rate * 0.05):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / 0.05)
				samples.append(_square_wave(t, 440.0) * env * 0.3)

	return samples


# -------------------------------------------------------
# Convenience: play class-appropriate attack SFX
# -------------------------------------------------------
func play_attack_sfx(player_class: int) -> void:
	match player_class:
		ItemDatabase.PlayerClass.EMPEROR:  play_sfx("guitar_hit")
		ItemDatabase.PlayerClass.GENTOO:   play_sfx("drum_hit")
		ItemDatabase.PlayerClass.LITTLE_BLUE: play_sfx("vocal_hit")
		ItemDatabase.PlayerClass.MACARONI: play_sfx("bass_hit")
		_: play_sfx("guitar_hit")

func play_ability_sfx(player_class: int) -> void:
	match player_class:
		ItemDatabase.PlayerClass.EMPEROR:  play_sfx("power_chord")
		ItemDatabase.PlayerClass.GENTOO:   play_sfx("drum_fill")
		ItemDatabase.PlayerClass.LITTLE_BLUE: play_sfx("power_ballad")
		ItemDatabase.PlayerClass.MACARONI: play_sfx("bass_drop")
