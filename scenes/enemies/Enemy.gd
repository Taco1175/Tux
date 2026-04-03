

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

var hp_bar: ProgressBar = null


func _ready() -> void:
	_configure_stats()
	current_hp = max_hp
	sprite.sprite_frames = EnemySpriteBuilder.build_frames(enemy_type)
	sprite.play("idle")
	_create_hp_bar()
	if multiplayer.is_server():
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)
		set_physics_process(true)
	else:
		set_physics_process(false)


func _create_hp_bar() -> void:
	hp_bar = ProgressBar.new()
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(20, 3)
	hp_bar.size = Vector2(20, 3)
	hp_bar.position = Vector2(-10, -14)
	hp_bar.add_theme_stylebox_override("fill", _make_hp_fill())
	hp_bar.add_theme_stylebox_override("background", _make_hp_bg())
	add_child(hp_bar)


func _make_hp_fill() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.15, 0.15)
	sb.corner_radius_top_left = 1
	sb.corner_radius_top_right = 1
	sb.corner_radius_bottom_left = 1
	sb.corner_radius_bottom_right = 1
	return sb


func _make_hp_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	sb.corner_radius_top_left = 1
	sb.corner_radius_top_right = 1
	sb.corner_radius_bottom_left = 1
	sb.corner_radius_bottom_right = 1
	return sb


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
	# Stationary enemies don't patrol
	if move_speed <= 0.0:
		ai_state = AIState.IDLE
		patrol_timer = randf_range(2.0, 4.0)
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
	# Stationary enemies (Anemone) don't chase, just wait for targets in range
	if move_speed <= 0.0:
		return
	velocity = (target.global_position - global_position).normalized() * move_speed * enrage_speed_mult
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
			max_hp = 45; damage = 12; move_speed = 0.0; aggro_range = 48.0; attack_range = 40.0; xp_reward = 14
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
	# Play attack animation
	_play_attack_anim()
	# Deal damage to target — re-check distance to prevent phantom hits
	if target and is_instance_valid(target):
		var dist := global_position.distance_to((target as Node2D).global_position)
		if dist <= attack_range * 1.5 and target.has_method("take_damage"):
			target.take_damage(damage, self)


func _play_attack_anim() -> void:
	sprite.play("attack")
	sprite.modulate = Color(1.0, 0.5, 0.3)
	var tween := create_tween()
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		if sprite:
			sprite.modulate = Color.WHITE
	)



func take_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if ai_state == AIState.DEAD:
		return
	current_hp -= amount
	if hp_bar:
		hp_bar.value = current_hp
	_sync_hp.rpc(current_hp)
	var is_big_hit := amount > max_hp * 0.15  # Show big hits differently
	_broadcast_damage_number.rpc(amount, is_big_hit)

	# Aggro: start chasing whoever hit us
	if ai_state == AIState.IDLE or ai_state == AIState.PATROL:
		ai_state = AIState.CHASE

	# Jellyfish flees when low HP
	if enemy_type == EnemyType.JELLYFISH_DRIFTER and float(current_hp) / float(max_hp) < 0.3:
		ai_state = AIState.FLEEING
		patrol_timer = 4.0

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
		MusicManager.set_intensity(0.85)
		_broadcast_boss_phase.rpc(2)
	elif boss_phase == 2 and hp_ratio <= 0.25:
		boss_phase = 3
		# Phase 3: enrage — much faster, more damage
		attack_cooldown_max *= 0.6
		damage = int(damage * 1.4)
		move_speed *= 1.3
		enrage_speed_mult = 1.5
		MusicManager.set_intensity(1.0)
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
	MusicManager.add_intensity(0.1 if not is_boss else 0.25)
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
	if hp_bar:
		hp_bar.value = current_hp
	# Flash red on hit, then restore to phase tint (not always white)
	var restore_color := Color.WHITE
	if is_boss:
		match boss_phase:
			2: restore_color = Color(1.0, 0.7, 0.3)
			3: restore_color = Color(1.0, 0.2, 0.2)
	sprite.modulate = Color(1.0, 0.3, 0.3)
	await get_tree().create_timer(0.15).timeout
	if sprite:
		sprite.modulate = restore_color


@rpc("authority", "reliable")
func _sync_death() -> void:
	ai_state = AIState.DEAD
	sprite.play("death")
	_spawn_death_particles()


func _spawn_death_particles() -> void:
	# Burst of small colored squares on death
	for i in 6:
		var particle := ColorRect.new()
		particle.size = Vector2(2, 2)
		particle.color = Color(0.8, 0.2 + randf() * 0.3, 0.1, 1.0)
		particle.position = Vector2(randf_range(-4, 4), randf_range(-4, 4))
		particle.z_index = 8
		add_child(particle)
		var tween := create_tween()
		var target_pos := particle.position + Vector2(randf_range(-12, 12), randf_range(-14, -4))
		tween.set_parallel(true)
		tween.tween_property(particle, "position", target_pos, 0.4)
		tween.tween_property(particle, "modulate:a", 0.0, 0.4).set_delay(0.15)
		tween.set_parallel(false)
		tween.tween_callback(particle.queue_free)


@rpc("authority", "call_local", "reliable")
func _broadcast_damage_number(amount: int, is_big_hit: bool = false) -> void:
	var lbl := Label.new()
	if is_big_hit:
		lbl.text = str(amount) + "!"
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	else:
		lbl.text = str(amount)
		lbl.add_theme_font_size_override("font_size", 7)
		lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-6 + randf_range(-4, 4), -18)
	lbl.z_index = 10
	add_child(lbl)
	var tween := create_tween()
	var float_dist := -18.0 if is_big_hit else -14.0
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y + float_dist, 0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.25)
	if is_big_hit:
		tween.tween_property(lbl, "scale", Vector2(1.3, 1.3), 0.1)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)


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
