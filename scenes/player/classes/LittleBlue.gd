extends "../Player.gd"
# Little Blue Penguin — The Third Sibling
# Support/Balanced archetype. The peacekeeper.
# Balanced stats, heals allies, buffs party. Snaps exactly once.
# When they snap: berserker mode, doubled damage, frightening.

const CLASS_INDEX := ItemDatabase.PlayerClass.LITTLE_BLUE

var heal_pulse_cooldown: float = 0.0
const HEAL_PULSE_COOLDOWN_MAX := 8.0
const HEAL_PULSE_AMOUNT := 25
const HEAL_PULSE_RADIUS := 80.0

var has_snapped: bool = false
var snap_timer: float = 0.0
const SNAP_DURATION := 6.0
const SNAP_DAMAGE_MULT := 2.2


func _ready() -> void:
	player_class = CLASS_INDEX
	max_hp = 100
	current_hp = 100
	max_mana = 70
	current_mana = 70
	strength = 10
	dexterity = 11
	intelligence = 11
	speed_multiplier = 1.1
	defense = 2
	crit_chance = 0.08

	# Little Blue is balanced — grows evenly, never peaks, never falls behind
	hp_per_level   = 8
	mana_per_level = 6
	str_per_level  = 1
	dex_per_level  = 1
	int_per_level  = 1

	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if heal_pulse_cooldown > 0:
		heal_pulse_cooldown -= delta
	if snap_timer > 0:
		snap_timer -= delta
		if snap_timer <= 0:
			_end_snap()


# Override: Primary = attack (or snap attack if snapped)
func _use_primary_ability() -> void:
	attack()


# Override: Secondary = Heal Pulse — AoE heal to nearby allies
# But if HP < 20%, triggers "The Snap" instead
func _use_secondary_ability() -> void:
	if current_hp < int(max_hp * 0.2) and not has_snapped:
		_trigger_snap()
		return

	if heal_pulse_cooldown > 0:
		return
	heal_pulse_cooldown = HEAL_PULSE_COOLDOWN_MAX
	_request_heal_pulse.rpc_id(1, global_position)


@rpc("any_peer", "reliable")
func _request_heal_pulse(origin: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for player in get_tree().get_nodes_in_group("players"):
		if origin.distance_to((player as Node2D).global_position) <= HEAL_PULSE_RADIUS:
			# heal() uses call_local so rpc() runs on server and all clients
			player.heal.rpc(HEAL_PULSE_AMOUNT)
	_broadcast_heal_pulse.rpc(origin, HEAL_PULSE_AMOUNT)


@rpc("authority", "call_local", "reliable")
func _broadcast_heal_pulse(_origin: Vector2, _amount: int) -> void:
	# Visual: green pulse ring
	sprite.modulate = Color(0.4, 1.0, 0.5)
	await get_tree().create_timer(0.3).timeout
	if sprite:
		sprite.modulate = Color.WHITE


# "The Snap" — triggered when near death
# Little Blue stops being nice. Just for a moment.
func _trigger_snap() -> void:
	has_snapped = true
	snap_timer = SNAP_DURATION
	sprite.modulate = Color(0.7, 0.0, 0.0)
	# Temporary stat override
	crit_chance = 0.40
	crit_multiplier = 3.0
	speed_multiplier *= 1.3
	_announce_snap.rpc()


@rpc("authority", "call_local")
func _announce_snap() -> void:
	# Find HUD and show message (only local player sees their own HUD)
	if not is_local_player:
		return
	var game := get_tree().get_first_node_in_group("game_scene")
	if game:
		var hud = game.get_node_or_null("HUD")
		if hud and hud.has_method("show_message"):
			hud.show_message("...", 2.0)


func _end_snap() -> void:
	sprite.modulate = Color.WHITE
	# Restore stats (reset to base — in a full implementation, recalculate from equipment)
	crit_chance = 0.08
	crit_multiplier = 1.5
	speed_multiplier = 1.1


func _calculate_attack_damage() -> int:
	var base := super._calculate_attack_damage()
	if snap_timer > 0:
		return int(base * SNAP_DAMAGE_MULT)
	return base


func get_loot_class_bias() -> int:
	return CLASS_INDEX
