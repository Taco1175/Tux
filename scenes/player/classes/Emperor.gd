extends "../Player.gd"
# Emperor Penguin — The Oldest Sibling
# Warrior archetype. Overprotective. Secretly the most scared.
# High HP, heavy armor, shield bash. Slow but immovable.

const CLASS_INDEX := ItemDatabase.PlayerClass.EMPEROR

var shield_bash_cooldown: float = 0.0
const SHIELD_BASH_COOLDOWN_MAX := 4.0
const SHIELD_BASH_RANGE := 48.0
const SHIELD_BASH_DAMAGE := 20
const SHIELD_BASH_KNOCKBACK := 150.0

# Block: passive chance to reduce incoming damage
const BLOCK_CHANCE_BASE := 0.15
var block_chance: float = BLOCK_CHANCE_BASE


func _ready() -> void:
	player_class = CLASS_INDEX
	# Emperor stats
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
	if shield_bash_cooldown > 0:
		shield_bash_cooldown -= delta


# Override: Primary = melee attack with higher base damage
func _use_primary_ability() -> void:
	attack()


# Override: Secondary = Shield Bash — AoE knockback in front
func _use_secondary_ability() -> void:
	if shield_bash_cooldown > 0:
		return
	shield_bash_cooldown = SHIELD_BASH_COOLDOWN_MAX
	_request_shield_bash.rpc_id(1, global_position, sprite.flip_h)


@rpc("any_peer", "reliable")
func _request_shield_bash(origin: Vector2, facing_left: bool) -> void:
	if not multiplayer.is_server():
		return
	var direction := Vector2.LEFT if facing_left else Vector2.RIGHT
	# Damage all enemies in a frontal arc
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = (enemy as Node2D).global_position - origin
		var dist: float = to_enemy.length()
		if dist <= SHIELD_BASH_RANGE:
			# Must be roughly in the facing direction (dot > 0.2 gives ~78° cone)
			if dist < 1.0 or to_enemy.normalized().dot(direction) > 0.2:
				(enemy as CharacterBody2D).take_damage(SHIELD_BASH_DAMAGE)
				# Apply knockback by pushing enemy velocity
				(enemy as CharacterBody2D).velocity += direction * SHIELD_BASH_KNOCKBACK
	_execute_shield_bash.rpc(origin, direction)


@rpc("authority", "call_local", "reliable")
func _execute_shield_bash(_origin: Vector2, _direction: Vector2) -> void:
	# Visual flash on all clients
	sprite.modulate = Color(0.5, 0.8, 1.0)
	await get_tree().create_timer(0.2).timeout
	if sprite:
		sprite.modulate = Color.WHITE


# Passive: block chance reduces damage
func take_damage(amount: int) -> void:
	if randf() < block_chance:
		# Block — take 0 damage, brief flash
		sprite.modulate = Color(0.5, 0.8, 1.0)
		await get_tree().create_timer(0.2).timeout
		sprite.modulate = Color.WHITE
		return
	super.take_damage(amount)


# Emperor's loot affinity: strength scaling, defense affixes appear more often
func get_loot_class_bias() -> int:
	return CLASS_INDEX
