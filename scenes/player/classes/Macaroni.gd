extends "../Player.gd"
# Macaroni Penguin — The Youngest Sibling
# Mage archetype. Treated like a baby. Unnerving calm.
# Glass cannon — devastating AoE, dies in two hits.
# Accidentally the most powerful one there.

const CLASS_INDEX := ItemDatabase.PlayerClass.MACARONI

var fireball_cooldown: float = 0.0
const FIREBALL_COOLDOWN_MAX := 2.5
const FIREBALL_MANA_COST := 20
const FIREBALL_BASE_DAMAGE := 35
const FIREBALL_RADIUS := 40.0

# Passive: spell affixes trigger 50% more often (applied in ItemGenerator)
const SPELL_AFFIX_BONUS := 0.5

# The "Unnerving Calm" passive: the lower HP, the higher spell damage
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
	if fireball_cooldown > 0:
		fireball_cooldown -= delta
	_update_calm_multiplier()


func _update_calm_multiplier() -> void:
	# "Unnerving calm" — lower HP = higher damage. Macaroni doesn't flinch.
	var hp_ratio := float(current_hp) / float(max_hp)
	# At full HP: 1.0x. At 10% HP: 2.5x. Linear.
	calm_multiplier = lerp(2.5, 1.0, hp_ratio)


# Override: Primary = Ice Staff melee / basic spell bolt
func _use_primary_ability() -> void:
	if current_mana >= 5:
		current_mana -= 5
		mana_changed.emit(current_mana, max_mana)
		_request_spell_bolt.rpc_id(1, global_position, sprite.flip_h)
	else:
		attack()  # Fallback to melee, deeply embarrassing for everyone


@rpc("any_peer", "reliable")
func _request_spell_bolt(origin: Vector2, facing_left: bool) -> void:
	if not multiplayer.is_server():
		return
	var damage := int((intelligence + randi_range(8, 15)) * calm_multiplier)
	var direction := Vector2.LEFT if facing_left else Vector2.RIGHT
	_broadcast_spell_bolt.rpc(origin, direction, damage)


@rpc("authority", "reliable")
func _broadcast_spell_bolt(_origin: Vector2, _direction: Vector2, _damage: int) -> void:
	pass  # Game scene spawns projectile


# Override: Secondary = Fireball — AoE ice/fire explosion
func _use_secondary_ability() -> void:
	if fireball_cooldown > 0 or current_mana < FIREBALL_MANA_COST:
		return
	fireball_cooldown = FIREBALL_COOLDOWN_MAX
	current_mana -= FIREBALL_MANA_COST
	mana_changed.emit(current_mana, max_mana)

	var mouse_pos := get_global_mouse_position() if is_local_player else global_position
	_request_fireball.rpc_id(1, global_position, mouse_pos)


@rpc("any_peer", "reliable")
func _request_fireball(origin: Vector2, target: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var damage := int((FIREBALL_BASE_DAMAGE + intelligence) * calm_multiplier)
	_broadcast_fireball.rpc(origin, target, damage, FIREBALL_RADIUS)


@rpc("authority", "reliable")
func _broadcast_fireball(_origin: Vector2, _target: Vector2, _damage: int, _radius: float) -> void:
	pass  # Game scene spawns AoE explosion


func get_loot_class_bias() -> int:
	return CLASS_INDEX
