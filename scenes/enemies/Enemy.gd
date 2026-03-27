

extends CharacterBody2D
# Enemy base class for TUX — all sea creature enemies inherit from this.
# Server-authoritative: AI runs only on server, position synced to clients.

const EnemySpriteBuilder = preload("res://scenes/enemies/EnemySpriteBuilder.gd")

enum EnemyType {
	# Crustacean Knights
	CRAB_GRUNT,
	CRAB_KNIGHT,
	LOBSTER_WARLORD,   # Mini-boss
	# Deep Sea Predators
	EEL_SCOUT,
	ANGLERFISH,
	SHARK_BRUTE,
	# Stinging Swarms
	JELLYFISH_DRIFTER,
	URCHIN_ROLLER,
	ANEMONE_TRAP,      # Stationary
	# Bosses
	CRAB_WARLORD,      # Zone 2 boss
	THE_LEVIATHAN,     # Zone 3 boss
	THE_DROWNED_GOD,   # Final boss
}

enum AIState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	FLEEING,
	DEAD,
}

# -------------------------------------------------------
# Stats
# -------------------------------------------------------
var enemy_type: int = EnemyType.CRAB_GRUNT
var max_hp: int = 30
var current_hp: int = 30
var damage: int = 8
var move_speed: float = 50.0
var aggro_range: float = 96.0
var attack_range: float = 20.0
var attack_cooldown_max: float = 1.2
var attack_cooldown: float = 0.0
var defense: int = 0
var loot_table_weight: int = 1   # higher = more/better loot
var xp_reward: int = 10

# Boss phase tracking
var boss_phase: int = 1
var is_boss: bool = false
var enrage_speed_mult: float = 1.0

# -------------------------------------------------------
# AI state
# -------------------------------------------------------
var ai_state: AIState = AIState.PATROL
var target: Node2D = null
var patrol_target: Vector2 = Vector2.ZERO
var patrol_timer: float = 0.0

# -------------------------------------------------------
# Signals
# -------------------------------------------------------
signal died(enemy_node: Node, position: Vector2)

# -------------------------------------------------------
# Nodes
# -------------------------------------------------------
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	_configure_stats()
	current_hp = max_hp
	sprite.sprite_frames = EnemySpriteBuilder.build_frames(enemy_type)
	sprite.play("idle")
	if multiplayer.is_server():
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)
		set_physics_process(true)
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if ai_state == AIState.DEAD:
		return

	attack_cooldown -= delta
	_run_ai(delta)
	_sync_state.rpc(global_position, int(ai_state), sprite.flip_h)


# -------------------------------------------------------
# AI state machine (server only)
# -------------------------------------------------------
func _run_ai(delta: float) -> void:
	match ai_state:
		AIState.IDLE:    _ai_idle(delta)
		AIState.PATROL:  _ai_patrol(delta)
		AIState.CHASE:   _ai_chase(delta)
		AIState.ATTACK:  _ai_attack(delta)
		AIState.FLEEING: _ai_flee(delta)


func _ai_idle(delta: float) -> void:
	patrol_timer -= delta
	if patrol_timer <= 0:
		ai_state = AIState.PATROL
		_pick_patrol_point()


func _ai_patrol(_delta: float) -> void:
	if target:
		ai_state = AIState.CHASE
		return
	var dir := (patrol_target - global_position)
	if dir.length() < 4.0:
		ai_state = AIState.IDLE
		patrol_timer = randf_range(1.5, 3.5)
		velocity = Vector2.ZERO
	else:
		velocity = dir.normalized() * move_speed * 0.6
	move_and_slide()


func _ai_chase(_delta: float) -> void:
	if not target or not is_instance_valid(target):
		ai_state = AIState.PATROL
		target = null
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > aggro_range * 1.5:
		target = null
		ai_state = AIState.PATROL
		return
	if dist <= attack_range:
		ai_state = AIState.ATTACK
		return
	velocity = (target.global_position - global_position).normalized() * move_speed
	sprite.flip_h = target.global_position.x < global_position.x
	move_and_slide()


func _ai_attack(_delta: float) -> void:
	if not target or not is_instance_valid(target):
		ai_state = AIState.PATROL
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range * 1.2:
		ai_state = AIState.CHASE
		return
	if attack_cooldown <= 0:
		_do_attack()


func _ai_flee(delta: float) -> void:
	# Used by certain low-HP enemies (e.g. Jellyfish Drifter)
	patrol_timer -= delta
	if patrol_timer <= 0 or current_hp > max_hp * 0.3:
		ai_state = AIState.PATROL
		return
	if target:
		velocity = (global_position - target.global_position).normalized() * move_speed * 1.2
		move_and_slide()


func _configure_stats() -> void:
	match enemy_type:
		EnemyType.CRAB_GRUNT:
			max_hp = 30; damage = 6; move_speed = 45.0; xp_reward = 8
		EnemyType.CRAB_KNIGHT:
			max_hp = 55; damage = 10; move_speed = 38.0; defense = 4; xp_reward = 18
		EnemyType.LOBSTER_WARLORD:
			max_hp = 90; damage = 15; move_speed = 35.0; defense = 6; xp_reward = 35
			is_boss = true
		EnemyType.EEL_SCOUT:
			max_hp = 22; damage = 8; move_speed = 75.0; attack_range = 16.0; xp_reward = 10
		EnemyType.ANGLERFISH:
			max_hp = 60; damage = 18; move_speed = 30.0; aggro_range = 64.0; xp_reward = 25
		EnemyType.SHARK_BRUTE:
			max_hp = 80; damage = 22; move_speed = 60.0; attack_cooldown_max = 1.8; xp_reward = 30
		EnemyType.JELLYFISH_DRIFTER:
			max_hp = 18; damage = 5; move_speed = 35.0; xp_reward = 7
		EnemyType.URCHIN_ROLLER:
			max_hp = 35; damage = 9; move_speed = 55.0; xp_reward = 12
		EnemyType.ANEMONE_TRAP:
			max_hp = 45; damage = 12; move_speed = 0.0; aggro_range = 48.0; xp_reward = 14
		EnemyType.CRAB_WARLORD:   # Zone 2 boss
			max_hp = 320; damage = 25; move_speed = 42.0; defense = 8
			attack_cooldown_max = 0.8; loot_table_weight = 5; xp_reward = 150
			is_boss = true
		EnemyType.THE_LEVIATHAN:  # Zone 3 boss
			max_hp = 600; damage = 35; move_speed = 50.0; defense = 12
			attack_cooldown_max = 1.0; loot_table_weight = 8; xp_reward = 300
			is_boss = true
		EnemyType.THE_DROWNED_GOD: # Final boss
			max_hp = 1200; damage = 45; move_speed = 40.0; defense = 15
			attack_cooldown_max = 1.2; loot_table_weight = 10; xp_reward = 999
			is_boss = true


func _pick_patrol_point() -> void:
	patrol_target = global_position + Vector2(
		randf_range(-64, 64), randf_range(-64, 64)
	)


# -------------------------------------------------------
# Combat (server only)
# -------------------------------------------------------
func _do_attack() -> void:
	if not multiplayer.is_server():
		return
	attack_cooldown = attack_cooldown_max
	sprite.play("attack")
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage.rpc_id(target.get_multiplayer_authority(), damage)


func take_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if ai_state == AIState.DEAD:
		return
	current_hp -= amount
	_sync_hp.rpc(current_hp)

	# Aggro: start chasing whoever hit us
	if ai_state == AIState.IDLE or ai_state == AIState.PATROL:
		ai_state = AIState.CHASE

	# Boss phase transitions
	if is_boss:
		_check_boss_phase()

	if current_hp <= 0:
		_die()


func _check_boss_phase() -> void:
	var hp_ratio := float(current_hp) / float(max_hp)
	if boss_phase == 1 and hp_ratio <= 0.5:
		boss_phase = 2
		# Phase 2: faster attacks, increased damage
		attack_cooldown_max *= 0.7
		damage = int(damage * 1.3)
		move_speed *= 1.2
		_broadcast_boss_phase.rpc(2)
	elif boss_phase == 2 and hp_ratio <= 0.25:
		boss_phase = 3
		# Phase 3: enrage — much faster, more damage
		attack_cooldown_max *= 0.6
		damage = int(damage * 1.4)
		move_speed *= 1.3
		enrage_speed_mult = 1.5
		_broadcast_boss_phase.rpc(3)


@rpc("authority", "call_local", "reliable")
func _broadcast_boss_phase(phase: int) -> void:
	boss_phase = phase
	match phase:
		2:
			sprite.modulate = Color(1.0, 0.7, 0.3)  # Orange tint
		3:
			sprite.modulate = Color(1.0, 0.2, 0.2)  # Red enrage


func _die() -> void:
	ai_state = AIState.DEAD
	velocity = Vector2.ZERO
	_sync_death.rpc()
	died.emit(self, global_position)
	# Delay removal to let death animation play
	await get_tree().create_timer(0.8).timeout
	queue_free()


# -------------------------------------------------------
# Network sync (server -> clients)
# -------------------------------------------------------
@rpc("authority", "unreliable")
func _sync_state(pos: Vector2, state: int, flip: bool) -> void:
	if multiplayer.is_server():
		return
	global_position = global_position.lerp(pos, 0.25)
	sprite.flip_h = flip
	match state:
		AIState.IDLE, AIState.PATROL: sprite.play("walk" if velocity != Vector2.ZERO else "idle")
		AIState.CHASE:                sprite.play("walk")
		AIState.ATTACK:               pass  # handled by attack anim
		AIState.DEAD:                 sprite.play("death")


@rpc("authority", "reliable")
func _sync_hp(hp: int) -> void:
	current_hp = hp
	# Flash red on hit
	sprite.modulate = Color(1.0, 0.3, 0.3)
	await get_tree().create_timer(0.15).timeout
	if sprite:
		sprite.modulate = Color.WHITE


@rpc("authority", "reliable")
func _sync_death() -> void:
	ai_state = AIState.DEAD
	sprite.play("death")
	set_physics_process(false)


# -------------------------------------------------------
# Detection
# -------------------------------------------------------
func _on_body_entered_detection(body: Node) -> void:
	if body.is_in_group("players") and target == null:
		target = body
		if ai_state == AIState.IDLE or ai_state == AIState.PATROL:
			ai_state = AIState.CHASE


func _on_body_exited_detection(body: Node) -> void:
	if body == target:
		target = null
		ai_state = AIState.PATROL
