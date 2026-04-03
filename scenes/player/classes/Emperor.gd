extends "../Player.gd"
# Emperor Penguin — Lead Guitar
# The oldest sibling. Wields a battle axe guitar.
# Heavy riffs, heavy armor. Slow but unstoppable.
# Secondary: Power Chord — AoE sonic blast that knockbacks enemies.

const CLASS_INDEX := ItemDatabase.PlayerClass.EMPEROR

var power_chord_cooldown: float = 0.0
const POWER_CHORD_COOLDOWN_MAX := 4.0
const POWER_CHORD_RANGE := 48.0
const POWER_CHORD_DAMAGE := 20
const POWER_CHORD_KNOCKBACK := 150.0

# Passive: Stage Presence — chance to block incoming damage
const BLOCK_CHANCE_BASE := 0.15
var block_chance: float = BLOCK_CHANCE_BASE


func _ready() -> void:
	player_class = CLASS_INDEX
	# Emperor stats — the heaviest hitter, slowest tempo
	max_hp = 140
	current_hp = 140
	max_mana = 25
	current_mana = 25
	strength = 14
	dexterity = 7
	intelligence = 5
	speed_multiplier = 0.85
	defense = 4
	crit_chance = 0.04

	# Emperor grows into a tank — big HP, armor scaling
	hp_per_level   = 14
	mana_per_level = 2
	str_per_level  = 2
	dex_per_level  = 0
	int_per_level  = 0

	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if power_chord_cooldown > 0:
		power_chord_cooldown -= delta


# Primary: Heavy axe guitar swing
func _use_primary_ability() -> void:
	attack()


# Secondary: Power Chord — AoE sonic knockback in a frontal cone
func _use_secondary_ability() -> void:
	if power_chord_cooldown > 0:
		return
	power_chord_cooldown = POWER_CHORD_COOLDOWN_MAX
	AudioManager.play_sfx("power_chord")
	play_secondary_animation()
	var aim_dir := _get_aim_direction()
	if multiplayer.is_server():
		_request_power_chord(global_position, aim_dir)
	else:
		_request_power_chord.rpc_id(1, global_position, aim_dir)


@rpc("any_peer", "reliable")
func _request_power_chord(origin: Vector2, direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	# Sonic blast damages all enemies in a frontal arc
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = (enemy as Node2D).global_position - origin
		var dist: float = to_enemy.length()
		if dist <= POWER_CHORD_RANGE:
			if dist < 1.0 or to_enemy.normalized().dot(direction) > 0.2:
				(enemy as CharacterBody2D).take_damage(POWER_CHORD_DAMAGE)
				(enemy as CharacterBody2D).velocity += direction * POWER_CHORD_KNOCKBACK
	_execute_power_chord.rpc(origin, direction)


@rpc("authority", "call_local", "reliable")
func _execute_power_chord(_origin: Vector2, _direction: Vector2) -> void:
	# Visual: orange sonic blast flash
	sprite.modulate = Color(1.0, 0.6, 0.2)
	await get_tree().create_timer(0.2).timeout
	if sprite:
		sprite.modulate = Color.WHITE


# Passive: Stage Presence — chance to shrug off damage
func take_damage(amount: int, attacker: Node2D = null) -> void:
	if randf() < block_chance:
		sprite.modulate = Color(1.0, 0.6, 0.2)
		await get_tree().create_timer(0.2).timeout
		if sprite:
			sprite.modulate = Color.WHITE
		return
	super.take_damage(amount, attacker)


func get_loot_class_bias() -> int:
	return CLASS_INDEX
