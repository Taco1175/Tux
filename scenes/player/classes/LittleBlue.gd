extends "../Player.gd"
# Little Blue Penguin — Lead Vocalist
# The peacekeeper. Mic stand as weapon, voice as power.
# Balanced stats, heals allies with Power Ballads, buffs party.
# When they snap: Death Metal mode — doubled damage, terrifying screams.

const CLASS_INDEX := ItemDatabase.PlayerClass.LITTLE_BLUE

var ballad_cooldown: float = 0.0
const BALLAD_COOLDOWN_MAX := 8.0
const BALLAD_HEAL_AMOUNT := 25
const BALLAD_RADIUS := 80.0

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
	if ballad_cooldown > 0:
		ballad_cooldown -= delta
	if snap_timer > 0:
		snap_timer -= delta
		if snap_timer <= 0:
			_end_snap()


# Primary: Mic stand swing
func _use_primary_ability() -> void:
	attack()


# Secondary: Power Ballad — AoE heal to nearby allies
# But if HP < 20%, triggers "Death Metal" instead
func _use_secondary_ability() -> void:
	if current_hp < int(max_hp * 0.2) and not has_snapped:
		_trigger_death_metal()
		return

	if ballad_cooldown > 0:
		return
	ballad_cooldown = BALLAD_COOLDOWN_MAX
	AudioManager.play_sfx("power_ballad")
	if multiplayer.is_server():
		_request_power_ballad(global_position)
	else:
		_request_power_ballad.rpc_id(1, global_position)


@rpc("any_peer", "reliable")
func _request_power_ballad(origin: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for player in get_tree().get_nodes_in_group("players"):
		if origin.distance_to((player as Node2D).global_position) <= BALLAD_RADIUS:
			player.heal.rpc(BALLAD_HEAL_AMOUNT)
	_broadcast_power_ballad.rpc(origin, BALLAD_HEAL_AMOUNT)


@rpc("authority", "call_local", "reliable")
func _broadcast_power_ballad(_origin: Vector2, _amount: int) -> void:
	# Visual: green healing pulse ring
	sprite.modulate = Color(0.4, 1.0, 0.5)
	await get_tree().create_timer(0.3).timeout
	if sprite:
		sprite.modulate = Color.WHITE


# "Death Metal" — triggered when near death
# Little Blue stops singing clean. Switches to screamo.
func _trigger_death_metal() -> void:
	has_snapped = true
	snap_timer = SNAP_DURATION
	AudioManager.play_sfx("death_metal")
	sprite.modulate = Color(0.7, 0.0, 0.0)
	# Temporary stat override — pure aggression
	crit_chance = 0.40
	crit_multiplier = 3.0
	speed_multiplier *= 1.3
	_announce_death_metal.rpc()


@rpc("authority", "call_local")
func _announce_death_metal() -> void:
	if not is_local_player:
		return
	var game := get_tree().get_first_node_in_group("game_scene")
	if game:
		var hud_node = game.get_node_or_null("HUDLayer/HUD")
		if hud_node and hud_node.has_method("show_message"):
			hud_node.show_message("DEATH METAL", 2.0)


func _end_snap() -> void:
	sprite.modulate = Color.WHITE
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
