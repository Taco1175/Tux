extends "../Player.gd"
# Macaroni Penguin — Bassist
# The youngest sibling. Unnerving calm. Treated like a baby.
# Bass guitar channels sonic devastation. Glass cannon.
# Primary: Sound Wave bolt. Secondary: Bass Drop AoE.
# Passive: "Low End Theory" — lower HP = more damage.

const CLASS_INDEX := ItemDatabase.PlayerClass.MACARONI

var bass_drop_cooldown: float = 0.0
const BASS_DROP_COOLDOWN_MAX := 2.5
const BASS_DROP_MANA_COST := 20
const BASS_DROP_BASE_DAMAGE := 35
const BASS_DROP_RADIUS := 40.0

# Passive: spell affixes trigger 50% more often (applied in ItemGenerator)
const SPELL_AFFIX_BONUS := 0.5

# "Low End Theory" passive: the lower HP, the higher the damage
var calm_multiplier: float = 1.0


func _ready() -> void:
	player_class = CLASS_INDEX
	max_hp = 60
	current_hp = 60
	max_mana = 110
	current_mana = 110
	strength = 5
	dexterity = 7
	intelligence = 16
	speed_multiplier = 0.92
	defense = 0
	crit_chance = 0.10

	# Macaroni's INT scaling makes them exponentially powerful late
	hp_per_level   = 4
	mana_per_level = 12
	str_per_level  = 0
	dex_per_level  = 0
	int_per_level  = 3

	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if bass_drop_cooldown > 0:
		bass_drop_cooldown -= delta
	_update_calm_multiplier()


func _update_calm_multiplier() -> void:
	# "Low End Theory" — lower HP = higher damage. Macaroni doesn't flinch.
	var hp_ratio := float(current_hp) / float(max_hp)
	calm_multiplier = lerp(2.5, 1.0, hp_ratio)


# Primary: Sound Wave — ranged sonic bolt from the bass guitar
func _use_primary_ability() -> void:
	if current_mana >= 5:
		current_mana -= 5
		mana_changed.emit(current_mana, max_mana)
		var aim_dir := _get_aim_direction()
		if multiplayer.is_server():
			_request_sound_wave(global_position, aim_dir)
		else:
			_request_sound_wave.rpc_id(1, global_position, aim_dir)
	else:
		attack()  # Fallback to melee — swinging the bass like a bat


@rpc("any_peer", "reliable")
func _request_sound_wave(origin: Vector2, direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var damage := int((intelligence + randi_range(8, 15)) * calm_multiplier)
	_broadcast_sound_wave.rpc(origin, direction.normalized(), damage)


@rpc("authority", "call_local", "reliable")
func _broadcast_sound_wave(origin: Vector2, direction: Vector2, damage: int) -> void:
	var game := get_tree().get_first_node_in_group("game_scene")
	if game:
		game.spawn_projectile(origin, direction, 200.0, damage, 160.0, 0.0)


# Secondary: Bass Drop — AoE sonic explosion at target location
func _use_secondary_ability() -> void:
	if bass_drop_cooldown > 0 or current_mana < BASS_DROP_MANA_COST:
		return
	bass_drop_cooldown = BASS_DROP_COOLDOWN_MAX
	AudioManager.play_sfx("bass_drop")
	current_mana -= BASS_DROP_MANA_COST
	mana_changed.emit(current_mana, max_mana)

	var mouse_pos := get_global_mouse_position() if is_local_player else global_position
	if multiplayer.is_server():
		_request_bass_drop(global_position, mouse_pos)
	else:
		_request_bass_drop.rpc_id(1, global_position, mouse_pos)


@rpc("any_peer", "reliable")
func _request_bass_drop(origin: Vector2, target: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var damage := int((BASS_DROP_BASE_DAMAGE + intelligence) * calm_multiplier)
	_broadcast_bass_drop.rpc(origin, target, damage, BASS_DROP_RADIUS)


@rpc("authority", "call_local", "reliable")
func _broadcast_bass_drop(origin: Vector2, target: Vector2, damage: int, radius: float) -> void:
	var game := get_tree().get_first_node_in_group("game_scene")
	if game:
		game.spawn_fireball(origin, target, damage, radius)


func get_loot_class_bias() -> int:
	return CLASS_INDEX
