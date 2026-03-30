extends CharacterBody2D
# Base player class — all four siblings inherit from this.
const SpriteFramesBuilder = preload("res://scenes/player/SpriteFramesBuilder.gd")


# Base player class — all four siblings inherit from this.
# Networked: each player is authoritative over their own movement;
# server is authoritative over combat/damage.

const TILE_SIZE := 16
const MOVE_SPEED := 80.0

# Class definitions loaded by each subclass
var player_class: int = 0  # ItemDatabase.PlayerClass enum
var peer_id: int = 0
var is_local_player: bool = false

# -------------------------------------------------------
# Stats
# -------------------------------------------------------
var max_hp: int = 100
var current_hp: int = 100
var max_mana: int = 50
var current_mana: int = 50
var strength: int = 10
var dexterity: int = 10
var intelligence: int = 10
var speed_multiplier: float = 1.0
var defense: int = 0
var crit_chance: float = 0.05   # 5% base
var crit_multiplier: float = 1.5
var dodge_chance: float = 0.0
var lifesteal: float = 0.0
var xp_bonus: float = 0.0
var gold_find: float = 0.0
var thorns_damage: int = 0

# -------------------------------------------------------
# Inventory & equipment
# -------------------------------------------------------
const INVENTORY_SIZE := 16
var inventory: Array = []         # Array of ItemData
var equipped_weapon = null
var equipped_armor: Dictionary = {}   # slot -> ItemData
var relics: Array = []            # passive relic items

# -------------------------------------------------------
# State
# -------------------------------------------------------
var is_dead: bool = false
var is_invincible: bool = false
var invincibility_timer: float = 0.0
const INVINCIBILITY_DURATION := 0.5

# Heal-over-time state
var hot_amount: int = 0
var hot_ticks_left: int = 0
var hot_tick_timer: float = 0.0
const HOT_TICK_INTERVAL := 1.0

# Damage boost state
var damage_boost_multiplier: float = 1.0
var damage_boost_timer: float = 0.0

# Mana regen
var mana_regen_rate: float = 2.0  # mana per second
var mana_regen_timer: float = 0.0

# HP regen (from regen affix)
var hp_regen_rate: float = 0.0
var hp_regen_timer: float = 0.0

# Attack cooldown
var attack_cooldown: float = 0.0
var attack_cooldown_max: float = 0.4

# Crit tracking for visual feedback
var _last_hit_was_crit: bool = false

# -------------------------------------------------------
# Leveling
# -------------------------------------------------------
var level: int = 1
var current_xp: int = 0
var xp_to_next: int = 100

# XP thresholds scale: floor(100 * 1.35^(level-1))
# Stat gains per level (base values, subclasses can override)
var hp_per_level: int     = 8
var mana_per_level: int   = 4
var str_per_level: int    = 1
var dex_per_level: int    = 1
var int_per_level: int    = 1

# -------------------------------------------------------
# Signals
# -------------------------------------------------------
signal hp_changed(new_hp: int, max_hp: int)
signal mana_changed(new_mana: int, max_mana: int)
signal xp_changed(current: int, needed: int)
signal leveled_up(new_level: int)
signal died(peer_id: int)
signal item_picked_up(item: Dictionary)
signal damage_taken(amount: int)

# -------------------------------------------------------
# Nodes
# -------------------------------------------------------
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox
@onready var pickup_area: Area2D = $PickupArea
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	peer_id = get_multiplayer_authority()
	is_local_player = (peer_id == multiplayer.get_unique_id())

	# Build sprite frames for all players (local and remote)
	sprite.sprite_frames = SpriteFramesBuilder.build_frames_for_class(player_class)
	sprite.play("idle")

	if not is_local_player:
		# Non-local players: disable local input processing
		set_physics_process(false)
		return

	pickup_area.area_entered.connect(_on_pickup_area_entered)
	pickup_area.area_exited.connect(_on_pickup_area_exited)
	hitbox.area_entered.connect(_on_hitbox_entered)

	# Give a starting weapon if none equipped
	if equipped_weapon == null:
		_equip_starting_weapon()

	# Equip saved items from vault at run start
	if GameManager.current_state == GameManager.State.IN_GAME:
		for saved_item in UnlockManager.get_saved_items():
			var item_copy: Dictionary = saved_item.duplicate(true)
			pick_up_item(item_copy)
		# Apply NPC run buffs from DialogueManager
		_apply_npc_run_buffs()


func _physics_process(delta: float) -> void:
	if not is_local_player or is_dead:
		return

	_handle_invincibility(delta)
	_handle_hot(delta)
	_handle_damage_boost(delta)
	_handle_mana_regen(delta)
	_handle_hp_regen(delta)
	if attack_cooldown > 0:
		attack_cooldown -= delta
	_handle_movement()
	_handle_ability_input()


func _handle_movement() -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_up"):    dir.y -= 1

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		velocity = dir * MOVE_SPEED * speed_multiplier
		_update_facing(dir)
		sprite.play("walk")
	else:
		velocity = Vector2.ZERO
		sprite.play("idle")

	move_and_slide()
	_sync_position.rpc(global_position)


func _handle_ability_input() -> void:
	if Input.is_action_just_pressed("ability_primary"):
		_use_primary_ability()
	if Input.is_action_just_pressed("ability_secondary"):
		_use_secondary_ability()
	if Input.is_action_just_pressed("interact"):
		try_pickup_nearest_item()
		_try_interact()


func _update_facing(dir: Vector2) -> void:
	if dir.x < 0:
		sprite.flip_h = true
	elif dir.x > 0:
		sprite.flip_h = false


func _handle_invincibility(delta: float) -> void:
	if is_invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0:
			is_invincible = false
			sprite.modulate = Color.WHITE


# -------------------------------------------------------
# Position sync (client -> all peers)
# -------------------------------------------------------
@rpc("any_peer", "unreliable")
func _sync_position(pos: Vector2) -> void:
	if not is_local_player:
		global_position = global_position.lerp(pos, 0.3)


# -------------------------------------------------------
# Combat (server authoritative)
# -------------------------------------------------------
@rpc("authority", "reliable")
func take_damage(amount: int, attacker: Node2D = null) -> void:
	if is_dead or is_invincible:
		return

	# Dodge check
	if dodge_chance > 0.0 and randf() < dodge_chance:
		_spawn_dodge_text()
		# Brief flash to show dodge
		sprite.modulate = Color(0.7, 0.7, 1.0, 0.5)
		is_invincible = true
		invincibility_timer = 0.2
		return

	# Apply defense reduction
	var final_damage: int = maxi(1, amount - _get_total_defense())
	current_hp -= final_damage
	damage_taken.emit(final_damage)
	hp_changed.emit(current_hp, max_hp)

	# Floating damage number
	_spawn_damage_number(final_damage, Color(1.0, 0.3, 0.3))
	AudioManager.play_sfx("hit_taken")

	# Screen shake
	_screen_shake(3.0, 0.15)

	# Thorns: reflect damage to attacker
	if thorns_damage > 0 and attacker and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		attacker.take_damage(thorns_damage)

	is_invincible = true
	invincibility_timer = INVINCIBILITY_DURATION
	sprite.modulate = Color(1.0, 0.4, 0.4)

	if current_hp <= 0:
		_die()


@rpc("authority", "call_local", "reliable")
func heal(amount: int) -> void:
	current_hp = min(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)
	_spawn_damage_number(amount, Color(0.3, 1.0, 0.3))


func _spawn_damage_number(value: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = str(value)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-8, -20)
	lbl.z_index = 10
	add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 16, 0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)


func _spawn_dodge_text() -> void:
	var lbl := Label.new()
	lbl.text = "DODGE"
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-12, -20)
	lbl.z_index = 10
	add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 14, 0.5)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)


func _screen_shake(intensity: float, duration: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var tween := create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(cam, "offset", offset, duration / 4.0)
	tween.tween_property(cam, "offset", Vector2.ZERO, 0.05)


func _die() -> void:
	is_dead = true
	AudioManager.play_sfx("death")
	sprite.play("death")
	died.emit(peer_id)
	# Notify server
	_notify_death.rpc_id(1)


@rpc("any_peer", "reliable")
func _notify_death() -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		if GameManager.current_run:
			GameManager.current_run.players_alive.erase(sender)


# -------------------------------------------------------
# Attack — base melee swing
# -------------------------------------------------------
func _get_aim_direction() -> Vector2:
	# Right stick takes priority if pushed
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if stick.length() > 0.3:
		return stick.normalized()
	# Fall back to mouse position
	return (get_global_mouse_position() - global_position).normalized()


func attack() -> void:
	if not is_local_player or attack_cooldown > 0:
		return
	attack_cooldown = attack_cooldown_max
	AudioManager.play_attack_sfx(player_class)
	var attack_dir := _get_aim_direction()
	if multiplayer.is_server():
		_request_attack_directed(attack_dir)
	else:
		_request_attack_directed.rpc_id(1, attack_dir)


@rpc("any_peer", "reliable")
func _request_attack_directed(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var damage := _calculate_attack_damage()
	const MELEE_RANGE := 30.0
	const AIM_CONE := 0.7  # ~90 degree cone (dot product threshold)
	var hit_count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var enemy_node := enemy as Node2D
		var to_enemy := (enemy_node.global_position - global_position)
		var dist := to_enemy.length()
		if dist <= MELEE_RANGE:
			if dist < 5.0 or to_enemy.normalized().dot(dir) >= AIM_CONE:
				(enemy as CharacterBody2D).take_damage(damage)
				hit_count += 1
				_apply_on_hit_effects(enemy as CharacterBody2D, dir)
	# Lifesteal
	if hit_count > 0 and lifesteal > 0.0:
		var heal_amount := maxi(1, int(damage * lifesteal))
		heal(heal_amount)
	_broadcast_attack_directed.rpc(dir)


@rpc("authority", "call_local", "reliable")
func _broadcast_attack_directed(dir: Vector2) -> void:
	# Flip sprite to face attack direction
	if dir.x != 0:
		sprite.flip_h = dir.x < 0
	_spawn_slash_effect(dir)
	sprite.modulate = Color(1.0, 1.0, 0.6)
	await get_tree().create_timer(0.1).timeout
	if sprite:
		sprite.modulate = Color.WHITE


func _apply_on_hit_effects(enemy: CharacterBody2D, dir: Vector2) -> void:
	if equipped_weapon == null:
		return
	for affix in (equipped_weapon as Dictionary).get("affixes", []):
		match affix.get("type", ""):
			"knockback":
				enemy.velocity += dir * affix.get("value", 30.0)
			"poison":
				# Apply poison DoT: deal value damage per second for 3 seconds
				_apply_poison_to_enemy(enemy, int(affix.get("value", 3)), 3)
			"fire_damage":
				# 30% chance to inflict burn (extra tick of fire damage after 1s)
				if randf() < 0.3 and enemy.has_method("take_damage"):
					_apply_burn_to_enemy(enemy, int(affix.get("value", 5)))
			"ice_damage":
				# 25% chance to slow enemy for 2 seconds
				if randf() < 0.25:
					_apply_slow_to_enemy(enemy, 2.0)


func _apply_poison_to_enemy(enemy: CharacterBody2D, dmg_per_tick: int, ticks: int) -> void:
	for i in ticks:
		if not is_instance_valid(enemy):
			return
		await get_tree().create_timer(1.0).timeout
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(dmg_per_tick)


func _apply_burn_to_enemy(enemy: CharacterBody2D, burn_dmg: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		enemy.take_damage(burn_dmg)


func _apply_slow_to_enemy(enemy: CharacterBody2D, duration: float) -> void:
	var original_speed: float = enemy.move_speed
	enemy.move_speed *= 0.4
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(enemy):
		enemy.move_speed = original_speed


func _spawn_slash_effect(dir: Vector2) -> void:
	# Spawn 3 arc lines to simulate a weapon swing
	var base_angle := dir.angle()
	for i in 3:
		var arc_offset := (i - 1) * 0.3  # -0.3, 0.0, 0.3 radians spread
		var slash := Sprite2D.new()
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(12, 2)
		slash.texture = tex
		slash.modulate = Color(1.0, 1.0, 0.8, 0.8 - i * 0.15)
		var offset_dir := Vector2.from_angle(base_angle + arc_offset)
		slash.position = offset_dir * (12 + i * 3)
		slash.rotation = base_angle + arc_offset
		add_child(slash)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(slash, "modulate:a", 0.0, 0.2)
		tween.tween_property(slash, "scale", Vector2(1.3, 0.2), 0.2)
		tween.set_parallel(false)
		tween.tween_callback(slash.queue_free)


func _equip_starting_weapon() -> void:
	var weapon_type: int
	match player_class:
		ItemDatabase.PlayerClass.EMPEROR:
			weapon_type = ItemDatabase.WeaponType.AXE_GUITAR
		ItemDatabase.PlayerClass.GENTOO:
			weapon_type = ItemDatabase.WeaponType.DRUM_STICKS
		ItemDatabase.PlayerClass.LITTLE_BLUE:
			weapon_type = ItemDatabase.WeaponType.MIC_STAND
		ItemDatabase.PlayerClass.MACARONI:
			weapon_type = ItemDatabase.WeaponType.BASS_GUITAR
		_:
			weapon_type = ItemDatabase.WeaponType.AXE_GUITAR
	var template: Dictionary = ItemDatabase.WEAPON_TEMPLATES[weapon_type].duplicate(true)
	equipped_weapon = {
		"base_name": template["name"],
		"weapon_type": weapon_type,
		"damage_min": template["damage_min"],
		"damage_max": template["damage_max"],
		"speed": template["speed"],
		"affixes": [],
		"desc": template["desc"],
		"display_name": "Rusty " + template["name"],
		"item_type": ItemDatabase.ItemType.WEAPON,
		"rarity": ItemDatabase.Rarity.COMMON,
	}


func _calculate_attack_damage() -> int:
	var base := strength
	if equipped_weapon != null:
		var w: Dictionary = equipped_weapon as Dictionary
		base += randi_range(w.get("damage_min", 0), w.get("damage_max", 0))
		# Apply flat damage affixes
		for affix in w.get("affixes", []):
			base += _resolve_affix_damage(affix)
		# Apply percent damage affixes
		for affix in w.get("affixes", []):
			if affix.get("type") == "percent_damage":
				base = int(base * (1.0 + affix.get("value", 0.0)))

	# Crit check
	var total_crit := crit_chance
	if equipped_weapon != null:
		for affix in (equipped_weapon as Dictionary).get("affixes", []):
			if affix["type"] == "crit_chance":
				total_crit += affix["value"]
	var is_crit := randf() < total_crit
	if is_crit:
		base = int(base * crit_multiplier)

	# Apply temporary damage boost
	if damage_boost_multiplier > 1.0:
		base = int(base * damage_boost_multiplier)

	_last_hit_was_crit = is_crit
	return max(1, base)


func _resolve_affix_damage(affix: Dictionary) -> int:
	match affix.get("type", ""):
		"flat_damage":    return int(affix.get("value", 0))
		"fire_damage":    return int(affix.get("value", 0))
		"ice_damage":     return int(affix.get("value", 0))
		_:                return 0


func _get_total_defense() -> int:
	var total := defense
	for slot in equipped_armor:
		var armor: Dictionary = equipped_armor[slot]
		total += armor.get("defense", 0)
		for affix in armor.get("affixes", []):
			if affix["type"] == "flat_defense":
				total += int(affix["value"])
	return total


# -------------------------------------------------------
# Inventory
# -------------------------------------------------------
func pick_up_item(item: Dictionary) -> bool:
	if inventory.size() >= INVENTORY_SIZE:
		return false
	inventory.append(item)
	item_picked_up.emit(item)
	# Auto-equip weapons/armor if slot is empty
	var item_type: int = item.get("item_type", -1)
	if item_type == ItemDatabase.ItemType.WEAPON and equipped_weapon == null:
		equip_item(item)
	elif item_type == ItemDatabase.ItemType.ARMOR:
		var slot: int = item.get("armor_type", ItemDatabase.ArmorType.HELMET)
		if not equipped_armor.has(slot):
			equip_item(item)
	return true


func equip_item(item: Dictionary) -> void:
	# Unapply old item affixes
	match item.get("item_type"):
		ItemDatabase.ItemType.WEAPON:
			if equipped_weapon != null:
				_unapply_affixes(equipped_weapon as Dictionary)
			equipped_weapon = item
		ItemDatabase.ItemType.ARMOR:
			var slot: int = item.get("armor_type", ItemDatabase.ArmorType.HELMET)
			if equipped_armor.has(slot):
				_unapply_affixes(equipped_armor[slot])
			equipped_armor[slot] = item
	# Apply new item affixes
	_apply_affixes(item)


func _apply_affixes(item: Dictionary) -> void:
	for affix in item.get("affixes", []):
		_apply_single_affix(affix, 1)


func _unapply_affixes(item: Dictionary) -> void:
	for affix in item.get("affixes", []):
		_apply_single_affix(affix, -1)


func _apply_single_affix(affix: Dictionary, multiplier: int) -> void:
	var value: float = affix.get("value", 0.0)
	match affix.get("type", ""):
		"max_health":
			max_hp += int(value) * multiplier
			current_hp = mini(current_hp, max_hp)
			hp_changed.emit(current_hp, max_hp)
		"max_mana":
			max_mana += int(value) * multiplier
			current_mana = mini(current_mana, max_mana)
			mana_changed.emit(current_mana, max_mana)
		"flat_defense":
			defense += int(value) * multiplier
		"move_speed":
			speed_multiplier += value * multiplier
		"crit_chance":
			crit_chance += value * multiplier
		"dodge_chance":
			dodge_chance += value * multiplier
		"lifesteal":
			lifesteal += value * multiplier
		"thorns":
			thorns_damage += int(value) * multiplier
		"xp_bonus":
			xp_bonus += value * multiplier
		"gold_find":
			gold_find += value * multiplier
		"regen":
			hp_regen_rate += value * multiplier
		"attack_speed":
			# Reduce attack cooldown (value is like 0.1-0.3, treat as % reduction)
			attack_cooldown_max = maxf(0.1, attack_cooldown_max - value * 0.5 * multiplier)
		# Damage affixes (flat_damage, fire, ice, poison, knockback) resolved at attack time


func use_consumable(item: Dictionary) -> void:
	var effect: String = item.get("effect", "")
	var item_type: int = item.get("item_type", 0)

	if item_type == ItemDatabase.ItemType.THROWABLE:
		_throw_item(item)
		inventory.erase(item)
		return

	# Potions — play drink animation
	match effect:
		"heal":
			heal(item.get("power", 20))
			_spawn_consumable_vfx(Color(0.2, 1.0, 0.3), "heal")
		"heal_over_time":
			_apply_hot(item.get("power", 10))
			_spawn_consumable_vfx(Color(0.4, 1.0, 0.5), "regen")
		"damage_boost":
			_apply_damage_boost(item.get("power", 1.5), 10.0)
			_spawn_consumable_vfx(Color(1.0, 0.3, 0.1), "power")
		"invincibility":
			_apply_invincibility(item.get("power", 3.0))
			_spawn_consumable_vfx(Color(0.8, 0.8, 1.0), "shield")
		"random":
			_apply_random_effect()
			_spawn_consumable_vfx(Color(1.0, 0.0, 1.0), "chaos")
	inventory.erase(item)


func _spawn_consumable_vfx(color: Color, _type: String) -> void:
	# Rising sparkle effect when drinking a potion
	for i in 5:
		var particle := Sprite2D.new()
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(2, 2)
		particle.texture = tex
		particle.modulate = color
		particle.global_position = global_position + Vector2(randf_range(-6, 6), randf_range(-4, 4))
		particle.z_index = 10
		get_parent().add_child(particle)
		var tween := particle.create_tween()
		tween.tween_property(particle, "global_position:y", particle.global_position.y - randf_range(12, 20), 0.6)
		tween.parallel().tween_property(particle, "modulate:a", 0.0, 0.6)
		tween.tween_callback(particle.queue_free)


func _throw_item(item: Dictionary) -> void:
	var aim_dir := _get_aim_direction()
	var throw_target := global_position + aim_dir * 80.0
	var effect: String = item.get("effect", "")
	var power: float = item.get("power", 2.0)
	var item_name: String = item.get("display_name", item.get("name", "Throwable"))

	# Determine color based on throwable type
	var throw_color := Color.WHITE
	match effect:
		"freeze_aoe": throw_color = Color(0.3, 0.7, 1.0)
		"blind_aoe":  throw_color = Color(0.1, 0.1, 0.1)
		"slow_aoe":   throw_color = Color(0.6, 0.5, 0.3)
		"chaos_aoe":  throw_color = Color(1.0, 0.0, 1.0)

	# Spawn the thrown projectile
	var thrown := Node2D.new()
	thrown.global_position = global_position
	thrown.z_index = 10
	get_parent().add_child(thrown)

	# Visual: the thrown item
	var thrown_sprite := Sprite2D.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(6, 6)
	thrown_sprite.texture = tex
	thrown_sprite.modulate = throw_color
	thrown.add_child(thrown_sprite)

	# Arc animation: move to target with a parabolic Y offset
	var tween := thrown.create_tween()
	var mid_point := (global_position + throw_target) * 0.5
	mid_point.y -= 20.0  # Arc height

	# Phase 1: Throw arc (0.4s)
	tween.tween_method(func(t: float):
		var a: Vector2 = global_position.lerp(mid_point, t)
		var b: Vector2 = mid_point.lerp(throw_target, t)
		thrown.global_position = a.lerp(b, t)
		thrown_sprite.rotation += 0.3
	, 0.0, 1.0, 0.4)

	# Phase 2: Brief pause at landing (0.15s) — item on the ground
	tween.tween_callback(func():
		thrown_sprite.modulate = throw_color * 0.6
	)
	tween.tween_interval(0.15)

	# Phase 3: Explosion
	tween.tween_callback(func():
		_explode_throwable(thrown.global_position, effect, power, throw_color)
		thrown.queue_free()
	)


func _explode_throwable(pos: Vector2, effect: String, power: float, color: Color) -> void:
	var aoe_radius := 40.0

	# Visual explosion — expanding ring + particles
	var ring := Sprite2D.new()
	var ring_tex := PlaceholderTexture2D.new()
	ring_tex.size = Vector2(4, 4)
	ring.texture = ring_tex
	ring.modulate = Color(color.r, color.g, color.b, 0.8)
	ring.global_position = pos
	ring.z_index = 10
	get_parent().add_child(ring)

	var ring_tween := ring.create_tween()
	ring_tween.tween_property(ring, "scale", Vector2(16, 16), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	ring_tween.tween_callback(ring.queue_free)

	# Burst particles
	for i in 10:
		var p := Sprite2D.new()
		var p_tex := PlaceholderTexture2D.new()
		p_tex.size = Vector2(2, 2)
		p.texture = p_tex
		p.modulate = Color(color.r + randf_range(-0.1, 0.1), color.g + randf_range(-0.1, 0.1), color.b, 0.9)
		p.global_position = pos
		p.z_index = 11
		get_parent().add_child(p)
		var dir := Vector2.from_angle(randf() * TAU)
		var dist := randf_range(10, aoe_radius)
		var p_tween := p.create_tween()
		p_tween.tween_property(p, "global_position", pos + dir * dist, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		p_tween.parallel().tween_property(p, "modulate:a", 0.0, 0.4)
		p_tween.tween_callback(p.queue_free)

	# Apply AoE effects to enemies (server only)
	if not multiplayer.is_server():
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var enemy_node: Node2D = enemy as Node2D
		if pos.distance_to(enemy_node.global_position) > aoe_radius:
			continue
		match effect:
			"freeze_aoe":
				_apply_slow_to_enemy(enemy as CharacterBody2D, power)
				if enemy.has_method("take_damage"):
					enemy.take_damage(5)
			"blind_aoe":
				# Blind: enemies lose track of player temporarily
				if enemy.get("ai_state") != null:
					enemy.ai_state = 0  # IDLE
					enemy.patrol_timer = power
				if enemy.has_method("take_damage"):
					enemy.take_damage(3)
			"slow_aoe":
				_apply_slow_to_enemy(enemy as CharacterBody2D, power)
				if enemy.has_method("take_damage"):
					enemy.take_damage(8)
			"chaos_aoe":
				# Random: could heal, damage, or confuse
				var roll := randi() % 3
				if roll == 0 and enemy.has_method("take_damage"):
					enemy.take_damage(25)
				elif roll == 1:
					_apply_slow_to_enemy(enemy as CharacterBody2D, 3.0)
				else:
					if enemy.has_method("take_damage"):
						enemy.take_damage(10)
					_apply_burn_to_enemy(enemy as CharacterBody2D, 8)


func _apply_hot(power: int) -> void:
	hot_amount = power
	hot_ticks_left = 5
	hot_tick_timer = 0.0


func _handle_hot(delta: float) -> void:
	if hot_ticks_left <= 0:
		return
	hot_tick_timer += delta
	if hot_tick_timer >= HOT_TICK_INTERVAL:
		hot_tick_timer -= HOT_TICK_INTERVAL
		heal(hot_amount)
		hot_ticks_left -= 1


func _apply_damage_boost(multiplier: float, duration: float) -> void:
	damage_boost_multiplier = multiplier
	damage_boost_timer = duration


func _handle_damage_boost(delta: float) -> void:
	if damage_boost_timer <= 0:
		return
	damage_boost_timer -= delta
	if damage_boost_timer <= 0:
		damage_boost_multiplier = 1.0


func _handle_mana_regen(delta: float) -> void:
	if current_mana >= max_mana:
		return
	mana_regen_timer += delta
	if mana_regen_timer >= 1.0:
		mana_regen_timer -= 1.0
		current_mana = mini(current_mana + int(mana_regen_rate), max_mana)
		mana_changed.emit(current_mana, max_mana)


func _handle_hp_regen(delta: float) -> void:
	if hp_regen_rate <= 0.0 or current_hp >= max_hp:
		return
	hp_regen_timer += delta
	if hp_regen_timer >= 1.0:
		hp_regen_timer -= 1.0
		current_hp = mini(current_hp + int(hp_regen_rate), max_hp)
		hp_changed.emit(current_hp, max_hp)


func _apply_invincibility(duration: float) -> void:
	is_invincible = true
	invincibility_timer = duration
	sprite.modulate = Color(0.8, 0.8, 1.0, 0.7)


func _apply_random_effect() -> void:
	var effects := ["heal", "damage_boost", "invincibility", "chaos"]
	var effect: String = effects[randi() % effects.size()]
	match effect:
		"heal":         heal(randi_range(10, 50))
		"damage_boost": _apply_damage_boost(2.0, 5.0)
		"invincibility": _apply_invincibility(2.0)
		"chaos":
			# The "cursed mackerel" energy — something random happens
			var chaos_roll := randi() % 3
			if chaos_roll == 0:
				take_damage(10)
			elif chaos_roll == 1:
				heal(max_hp)  # Full heal, incredibly lucky
			else:
				current_mana = max_mana  # Full mana restore


func _apply_npc_run_buffs() -> void:
	var dm := get_node_or_null("/root/DialogueManager")
	if not dm:
		return
	for buff in dm.get_run_buffs():
		match buff.get("buff_type", ""):
			"damage":
				damage_boost_multiplier += buff.get("value", 0.0)
			"defense":
				defense += int(buff.get("value", 0))
			"max_hp":
				max_hp += int(buff.get("value", 0))
				current_hp += int(buff.get("value", 0))
				hp_changed.emit(current_hp, max_hp)
			"heal":
				heal(int(buff.get("value", 0)))
			"gold_find":
				gold_find += buff.get("value", 0.0)
			"xp_bonus":
				xp_bonus += buff.get("value", 0.0)
			"reveal":
				pass  # Handled by minimap system
			"damage_resist":
				defense += int(buff.get("value", 0.0) * 100.0)
	dm.clear_run_buffs()


# -------------------------------------------------------
# Interaction
# -------------------------------------------------------
func _try_interact() -> void:
	const INTERACT_RANGE := 24.0
	# Check for interactable nodes in range
	for node in get_tree().get_nodes_in_group("interactable"):
		if global_position.distance_to((node as Node2D).global_position) <= INTERACT_RANGE:
			if node.has_method("interact"):
				node.interact(self)
				return
	# Check for secret walls (server-side)
	if multiplayer.is_server():
		_try_break_secret_wall()
	else:
		_request_break_secret_wall.rpc_id(1, global_position)


@rpc("any_peer", "reliable")
func _request_break_secret_wall(pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_try_break_secret_wall_at(pos)


func _try_break_secret_wall() -> void:
	_try_break_secret_wall_at(global_position)


func _try_break_secret_wall_at(pos: Vector2) -> void:
	var game := get_tree().get_first_node_in_group("game_scene")
	if game and game.has_method("try_break_secret_wall"):
		game.try_break_secret_wall(pos)


# -------------------------------------------------------
# Leveling (server-authoritative, synced to client)
# -------------------------------------------------------
func add_xp(amount: int) -> void:
	if not is_local_player:
		return
	_server_add_xp.rpc_id(1, amount)


@rpc("any_peer", "reliable")
func _server_add_xp(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var bonus := int(amount * xp_bonus) if xp_bonus > 0.0 else 0
	current_xp += amount + bonus
	if current_xp >= xp_to_next:
		_level_up()
	_sync_xp.rpc(level, current_xp, xp_to_next)


@rpc("authority", "reliable")
func _sync_xp(lv: int, xp: int, needed: int) -> void:
	level = lv
	current_xp = xp
	xp_to_next = needed
	xp_changed.emit(current_xp, xp_to_next)


func _level_up() -> void:
	current_xp -= xp_to_next
	level += 1
	xp_to_next = int(100 * pow(1.35, level - 1))

	# Stat gains
	max_hp   += hp_per_level
	max_mana += mana_per_level
	strength    += str_per_level
	dexterity   += dex_per_level
	intelligence+= int_per_level

	# Restore a portion of HP/mana on level up (feels great)
	current_hp   = min(current_hp + hp_per_level * 2, max_hp)
	current_mana = min(current_mana + mana_per_level, max_mana)

	_sync_level_up.rpc(level, max_hp, current_hp, max_mana, current_mana,
		strength, dexterity, intelligence)
	_broadcast_level_up_effect.rpc(level)

	# Award a tide token bonus on level up
	if GameManager.current_run:
		GameManager.current_run.run_currency += level


@rpc("authority", "call_local", "reliable")
func _sync_level_up(lv: int, mhp: int, chp: int, mmana: int, cmana: int,
		str_: int, dex: int, int_: int) -> void:
	level       = lv
	max_hp      = mhp
	current_hp  = chp
	max_mana    = mmana
	current_mana= cmana
	strength    = str_
	dexterity   = dex
	intelligence= int_
	hp_changed.emit(current_hp, max_hp)
	mana_changed.emit(current_mana, max_mana)
	leveled_up.emit(level)


@rpc("authority", "call_local", "reliable")
func _broadcast_level_up_effect(new_level: int) -> void:
	# Golden flash + floating "LEVEL UP" text visible to all players
	sprite.modulate = Color(1.0, 0.85, 0.2)
	var lbl := Label.new()
	lbl.text = "LEVEL UP!"
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-20, -26)
	lbl.z_index = 10
	add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 20, 1.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.6)
	tween.set_parallel(false)
	tween.tween_callback(lbl.queue_free)


var nearby_items: Array[Area2D] = []
var _pickup_prompt: Label = null
var _loot_card: PanelContainer = null
var _loot_card_timer: float = 0.0

func _on_pickup_area_entered(area: Area2D) -> void:
	if area.is_in_group("items") and is_local_player:
		if not nearby_items.has(area):
			nearby_items.append(area)
		_update_pickup_prompt()

func _on_pickup_area_exited(area: Area2D) -> void:
	nearby_items.erase(area)
	_update_pickup_prompt()

func _update_pickup_prompt() -> void:
	# Clean dead refs
	nearby_items = nearby_items.filter(func(a): return is_instance_valid(a))
	if nearby_items.is_empty():
		if _pickup_prompt:
			_pickup_prompt.hide()
		return
	var closest: Area2D = nearby_items[0]
	if not _pickup_prompt:
		_pickup_prompt = Label.new()
		_pickup_prompt.add_theme_font_size_override("font_size", 5)
		_pickup_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pickup_prompt.z_index = 20
		add_child(_pickup_prompt)
	if closest.has_method("get_item_data"):
		var data: Dictionary = closest.get_item_data()
		var rarity: int = data.get("rarity", 0)
		var color: Color = ItemDatabase.get_rarity_color(rarity)
		_pickup_prompt.text = "[E] %s" % data.get("display_name", "Item")
		_pickup_prompt.add_theme_color_override("font_color", color)
	else:
		_pickup_prompt.text = "[E] Pick up"
	_pickup_prompt.position = Vector2(-30, -22)
	_pickup_prompt.show()

func try_pickup_nearest_item() -> void:
	nearby_items = nearby_items.filter(func(a): return is_instance_valid(a))
	if nearby_items.is_empty():
		return
	var area: Area2D = nearby_items[0]
	if area.has_method("get_item_data"):
		var data: Dictionary = area.get_item_data()
		if pick_up_item(data):
			AudioManager.play_sfx("pickup")
			_show_loot_card(data)
			area.queue_free()
			nearby_items.erase(area)
			_update_pickup_prompt()

func _show_loot_card(item: Dictionary) -> void:
	# Borderlands-style loot pickup card
	if _loot_card and is_instance_valid(_loot_card):
		_loot_card.queue_free()
	var rarity: int = item.get("rarity", 0)
	var color: Color = ItemDatabase.get_rarity_color(rarity)
	var rarity_name: String = ItemDatabase.get_rarity_name(rarity)
	var item_score: int = _calculate_item_score(item)

	# Build the card
	_loot_card = PanelContainer.new()
	_loot_card.z_index = 50

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(4)
	_loot_card.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)

	# Item name
	var name_lbl := Label.new()
	name_lbl.text = item.get("display_name", "???")
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.add_theme_color_override("font_color", color)
	vbox.add_child(name_lbl)

	# Rarity + Score
	var score_lbl := Label.new()
	score_lbl.text = "%s  |  Score: %d" % [rarity_name, item_score]
	score_lbl.add_theme_font_size_override("font_size", 5)
	score_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(score_lbl)

	# Stats line
	var stats_text := ""
	if item.has("damage_min"):
		stats_text += "DMG: %d-%d  " % [item["damage_min"], item["damage_max"]]
	if item.has("defense"):
		stats_text += "DEF: %d  " % item["defense"]
	if item.has("speed"):
		stats_text += "SPD: %.1f" % item["speed"]
	if stats_text != "":
		var stats_lbl := Label.new()
		stats_lbl.text = stats_text
		stats_lbl.add_theme_font_size_override("font_size", 5)
		stats_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		vbox.add_child(stats_lbl)

	# Affixes
	var affixes: Array = item.get("affixes", [])
	for affix in affixes:
		var aff_lbl := Label.new()
		aff_lbl.text = affix.get("label", "???")
		aff_lbl.add_theme_font_size_override("font_size", 5)
		aff_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		vbox.add_child(aff_lbl)

	# Comparison arrow (better/worse than equipped)
	var compare := _compare_to_equipped(item)
	if compare != "":
		var cmp_lbl := Label.new()
		cmp_lbl.text = compare
		cmp_lbl.add_theme_font_size_override("font_size", 5)
		vbox.add_child(cmp_lbl)

	_loot_card.add_child(vbox)
	_loot_card.position = Vector2(-50, -70)
	add_child(_loot_card)

	# Animate: slide in + fade out after 3 seconds
	_loot_card.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(_loot_card, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.5)
	tween.tween_property(_loot_card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if _loot_card and is_instance_valid(_loot_card):
			_loot_card.queue_free()
			_loot_card = null
	)

func _calculate_item_score(item: Dictionary) -> int:
	var score := 0
	var rarity: int = item.get("rarity", 0)
	score += rarity * 100
	score += item.get("damage_max", 0) * 5
	score += item.get("defense", 0) * 8
	for affix in item.get("affixes", []):
		score += 50
	return score

func _compare_to_equipped(item: Dictionary) -> String:
	var item_type: int = item.get("item_type", -1)
	if item_type == ItemDatabase.ItemType.WEAPON and equipped_weapon:
		var new_avg: float = (item.get("damage_min", 0) + item.get("damage_max", 0)) / 2.0
		var old_avg: float = (equipped_weapon.get("damage_min", 0) + equipped_weapon.get("damage_max", 0)) / 2.0
		var diff: int = int(new_avg - old_avg)
		if diff > 0:
			return "^ +%d avg damage (UPGRADE)" % diff
		elif diff < 0:
			return "v %d avg damage" % diff
	elif item_type == ItemDatabase.ItemType.ARMOR:
		var slot: int = item.get("armor_type", 0)
		if equipped_armor.has(slot):
			var diff: int = item.get("defense", 0) - equipped_armor[slot].get("defense", 0)
			if diff > 0:
				return "^ +%d defense (UPGRADE)" % diff
			elif diff < 0:
				return "v %d defense" % diff
	return ""


func _on_hitbox_entered(_area: Area2D) -> void:
	pass  # Enemy projectile damage handled server-side


# -------------------------------------------------------
# Overrides in subclasses
# -------------------------------------------------------
func _use_primary_ability() -> void:
	attack()  # Default: basic attack


func _use_secondary_ability() -> void:
	pass  # Class-specific
