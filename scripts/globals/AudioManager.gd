extends Node
# AudioManager — SFX system for TUX.
# Music is handled by MusicManager. This handles procedural sound effects only.

# -------------------------------------------------------
# Audio buses
# -------------------------------------------------------
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var sfx_volume: float = 0.8

# SFX pool — multiple simultaneous SFX
var _sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 8

var _sample_rate: float = 22050.0


func _ready() -> void:
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


# -------------------------------------------------------
# Legacy compatibility — redirect music calls to MusicManager
# -------------------------------------------------------
func play_track(track_name: String) -> void:
	MusicManager.play_zone(track_name)

func stop_music() -> void:
	MusicManager.stop_all()

func set_music_volume(vol: float) -> void:
	MusicManager.set_music_volume(vol)


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	for p in _sfx_players:
		p.volume_db = linear_to_db(sfx_volume)


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
	return _sfx_players[0]


func _generate_sfx(sfx_name: String) -> Array[float]:
	var samples: Array[float] = []
	var duration: float = 0.1

	match sfx_name:
		"guitar_hit":
			duration = 0.12
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _square_wave(t, 196.0) * 0.3 + _square_wave(t, 294.0) * 0.2
				s = clampf(s * 3.0, -1.0, 1.0) * env * 0.6
				samples.append(s)
		"drum_hit":
			duration = 0.08
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _square_wave(t, 80.0) * 0.3 + _noise() * 0.4
				samples.append(s * env * 0.5)
		"vocal_hit":
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var vibrato: float = sin(t * 30.0) * 20.0
				var s: float = _saw_wave(t, 523.0 + vibrato) * 0.3
				samples.append(s * env * 0.5)
		"bass_hit":
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _triangle_wave(t, 82.0) * 0.4 + _square_wave(t, 82.0) * 0.2
				samples.append(s * env * 0.6)
		"pickup":
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
			duration = 0.08
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _noise() * 0.5 + _square_wave(t, 100.0) * 0.3
				samples.append(s * env * 0.4)
		"death":
			duration = 0.4
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var f: float = 400.0 - t * 600.0
				var s: float = _saw_wave(t, maxf(f, 50.0)) * 0.3
				samples.append(s * env * 0.5)
		"power_chord":
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
			duration = 0.15
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var rapid: float = fmod(t * 25.0, 1.0)
				var s: float = _noise() * 0.3 + _square_wave(t, 200.0 * rapid) * 0.2
				samples.append(s * env * 0.5)
		"power_ballad":
			duration = 0.25
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration) * (0.5 + 0.5 * sin(t * 8.0))
				var s: float = _triangle_wave(t, 392.0) * 0.2
				s += _triangle_wave(t, 494.0) * 0.15
				s += _triangle_wave(t, 587.0) * 0.1
				samples.append(s * env * 0.5)
		"bass_drop":
			duration = 0.25
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var f: float = 50.0 + (1.0 - t / duration) * 80.0
				var s: float = _triangle_wave(t, f) * 0.5 + _square_wave(t, f) * 0.2
				s += _noise() * 0.1 * env
				samples.append(s * env * 0.6)
		"death_metal":
			duration = 0.3
			for i in int(_sample_rate * duration):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / duration)
				var s: float = _saw_wave(t, 200.0 + _noise() * 50.0) * 0.3
				s = clampf(s * 4.0, -1.0, 1.0) * env * 0.4
				samples.append(s)
		_:
			for i in int(_sample_rate * 0.05):
				var t: float = float(i) / _sample_rate
				var env: float = maxf(0.0, 1.0 - t / 0.05)
				samples.append(_square_wave(t, 440.0) * env * 0.3)

	return samples


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
