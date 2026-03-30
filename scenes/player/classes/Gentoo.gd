extends "../Player.gd"
# Gentoo Penguin — Drummer
# The chaotic middle sibling. Dual-wields drumsticks like daggers.
# Fastest tempo, hardest crits. Glass jaw.
# Secondary: Paradiddle Dash — invincible dash through enemies.

const CLASS_INDEX := ItemDatabase.PlayerClass.GENTOO

var dash_cooldown: float = 0.0
const DASH_COOLDOWN_MAX := 3.0
const DASH_DISTANCE := 80.0
const DASH_INVINCIBLE_DURATION := 0.25

var combo_count: int = 0
var combo_timer: float = 0.0
const COMBO_WINDOW := 1.2  # seconds to chain hits — keep the beat going


func _ready() -> void:
	player_class = CLASS_INDEX
	# Gentoo stats — fastest BPM, glass cannon melee
	max_hp = 80
	current_hp = 80
	max_mana = 45
	current_mana = 45
	strength = 8
	dexterity = 15
	intelligence = 7
	speed_multiplier = 1.35
	defense = 1
	crit_chance = 0.18   # High base crit — every hit is a rimshot
	crit_multiplier = 2.5  # Crits hit HARD

	# Gentoo scales into burst damage — dex and crit compound fast
	hp_per_level   = 5
	mana_per_level = 4
	str_per_level  = 0
	dex_per_level  = 3
	int_per_level  = 0

	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dash_cooldown > 0:
		dash_cooldown -= delta
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo_count = 0


# Primary: Rapid drumstick combo — 3rd hit is a Drum Fill finisher
func _use_primary_ability() -> void:
	combo_count += 1
	combo_timer = COMBO_WINDOW
	if combo_count >= 3:
		if multiplayer.is_server():
			_request_drum_fill()
		else:
			_request_drum_fill.rpc_id(1)
		combo_count = 0
	else:
		attack()


@rpc("any_peer", "reliable")
func _request_drum_fill() -> void:
	if not multiplayer.is_server():
		return
	var damage := _calculate_attack_damage() * 2
	const FILL_HIT_RANGE := 32.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= FILL_HIT_RANGE:
			enemy.take_damage(damage)
	_broadcast_drum_fill.rpc(global_position, damage)


@rpc("authority", "call_local", "reliable")
func _broadcast_drum_fill(_origin: Vector2, _damage: int) -> void:
	# Visual: yellow burst for the drum fill finisher
	sprite.modulate = Color(1.0, 0.9, 0.2)
	await get_tree().create_timer(0.12).timeout
	if sprite:
		sprite.modulate = Color.WHITE


# Secondary: Paradiddle Dash — dash through enemies with brief invincibility
func _use_secondary_ability() -> void:
	if dash_cooldown > 0:
		return
	dash_cooldown = DASH_COOLDOWN_MAX
	AudioManager.play_sfx("drum_fill")
	var dir := _get_aim_direction()
	_execute_dash(dir)


func _execute_dash(direction: Vector2) -> void:
	is_invincible = true
	invincibility_timer = DASH_INVINCIBLE_DURATION
	sprite.modulate = Color(1.0, 1.0, 0.4, 0.7)
	var tween := create_tween()
	tween.tween_property(self, "global_position",
		global_position + direction * DASH_DISTANCE, 0.15)
	tween.tween_callback(func(): sprite.modulate = Color.WHITE)


func get_loot_class_bias() -> int:
	return CLASS_INDEX
