extends CharacterBody2D

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

# -------------------------------------------------------
# Inventory & equipment
# -------------------------------------------------------
const INVENTORY_SIZE := 16
var inventory: Array = []         # Array of ItemData
var equipped_weapon: Resource = null
var equipped_armor: Dictionary = {}   # slot -> ItemData
var relics: Array = []            # passive relic items

# -------------------------------------------------------
# State
# -------------------------------------------------------
var is_dead: bool = false
var is_invincible: bool = false
var invincibility_timer: float = 0.0
const INVINCIBILITY_DURATION := 0.5

# -------------------------------------------------------
# Signals
# -------------------------------------------------------
signal hp_changed(new_hp: int, max_hp: int)
signal mana_changed(new_mana: int, max_mana: int)
signal died(peer_id: int)
signal item_picked_up(item: Resource)
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

	if not is_local_player:
		# Non-local players: disable local input processing
		set_physics_process(false)
		# Still process for animation sync
		return

	pickup_area.body_entered.connect(_on_pickup_area_entered)
	hitbox.area_entered.connect(_on_hitbox_entered)


func _physics_process(delta: float) -> void:
	if not is_local_player or is_dead:
		return

	_handle_invincibility(delta)
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
func take_damage(amount: int) -> void:
	if is_dead or is_invincible:
		return

	# Apply defense reduction
	var final_damage := max(1, amount - _get_total_defense())
	current_hp -= final_damage
	damage_taken.emit(final_damage)
	hp_changed.emit(current_hp, max_hp)

	is_invincible = true
	invincibility_timer = INVINCIBILITY_DURATION
	sprite.modulate = Color(1.0, 0.4, 0.4)

	if current_hp <= 0:
		_die()


@rpc("authority", "reliable")
func heal(amount: int) -> void:
	current_hp = min(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)


func _die() -> void:
	is_dead = true
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
func attack() -> void:
	if not is_local_player:
		return
	_request_attack.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_attack() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var damage := _calculate_attack_damage()
	# Server broadcasts the attack result to nearby enemies
	_broadcast_attack.rpc(global_position, damage, sender)


@rpc("authority", "reliable")
func _broadcast_attack(origin: Vector2, damage: int, attacker_peer: int) -> void:
	# Handled by the Game scene which coordinates enemy/player collision
	pass


func _calculate_attack_damage() -> int:
	var base := strength
	if equipped_weapon:
		var w: Dictionary = equipped_weapon
		base += randi_range(w.get("damage_min", 0), w.get("damage_max", 0))
		# Apply affixes
		for affix in w.get("affixes", []):
			base += _resolve_affix_damage(affix)

	# Crit check
	var total_crit := crit_chance
	if equipped_weapon:
		for affix in equipped_weapon.get("affixes", []):
			if affix["type"] == "crit_chance":
				total_crit += affix["value"]
	if randf() < total_crit:
		base = int(base * crit_multiplier)

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
func pick_up_item(item: Resource) -> bool:
	if inventory.size() >= INVENTORY_SIZE:
		return false
	inventory.append(item)
	item_picked_up.emit(item)
	return true


func equip_item(item: Dictionary) -> void:
	match item.get("item_type"):
		ItemDatabase.ItemType.WEAPON:
			equipped_weapon = item
		ItemDatabase.ItemType.ARMOR:
			var slot: int = item.get("armor_type", ItemDatabase.ArmorType.HELMET)
			equipped_armor[slot] = item


func use_consumable(item: Dictionary) -> void:
	match item.get("effect", ""):
		"heal":          heal(item.get("power", 20))
		"heal_over_time": _apply_hot(item.get("power", 10))
		"damage_boost":   _apply_damage_boost(item.get("power", 1.5), 10.0)
		"invincibility":  _apply_invincibility(item.get("power", 3.0))
		"random":         _apply_random_effect()
	inventory.erase(item)


func _apply_hot(_power: int) -> void:
	pass  # TODO: implement heal over time via tween/timer


func _apply_damage_boost(_multiplier: float, _duration: float) -> void:
	pass  # TODO: implement temporary damage buff


func _apply_invincibility(duration: float) -> void:
	is_invincible = true
	invincibility_timer = duration
	sprite.modulate = Color(0.8, 0.8, 1.0, 0.7)


func _apply_random_effect() -> void:
	var effects := ["heal", "damage_boost", "invincibility", "chaos"]
	var effect := effects[randi() % effects.size()]
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


# -------------------------------------------------------
# Interaction
# -------------------------------------------------------
func _try_interact() -> void:
	# Handled by child classes or via Area2D overlap with interactables
	pass


func _on_pickup_area_entered(body: Node) -> void:
	if body.is_in_group("items") and is_local_player:
		var item_node := body
		if item_node.has_method("get_item_data"):
			pick_up_item(item_node.get_item_data())
			item_node.queue_free()


func _on_hitbox_entered(_area: Area2D) -> void:
	pass  # Enemy projectile damage handled server-side


# -------------------------------------------------------
# Overrides in subclasses
# -------------------------------------------------------
func _use_primary_ability() -> void:
	attack()  # Default: basic attack


func _use_secondary_ability() -> void:
	pass  # Class-specific
