extends Area2D
# Projectile — used for Macaroni's spell bolt and fireball.
# Server instance does damage; client instances are visual only.
# Both run the same movement logic so they stay visually in sync.

var damage: int = 0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 180.0
var max_range: float = 160.0
var aoe_radius: float = 0.0   # 0 = single-target, >0 = AoE explosion on arrival
var is_server_projectile: bool = false

var _traveled: float = 0.0
var _exploded: bool = false

@onready var sprite: Sprite2D = $Sprite2D


func setup(p_damage: int, p_direction: Vector2, p_speed: float,
		p_range: float, p_aoe: float, p_is_server: bool) -> void:
	damage = p_damage
	direction = p_direction.normalized()
	speed = p_speed
	max_range = p_range
	aoe_radius = p_aoe
	is_server_projectile = p_is_server
	# Give sprite a visible texture
	if sprite and not sprite.texture:
		var tex := PlaceholderTexture2D.new()
		tex.size = Vector2(8, 8) if aoe_radius <= 0.0 else Vector2(12, 12)
		sprite.texture = tex
	# Fireball tint vs spell bolt tint
	if sprite:
		sprite.modulate = Color(1.0, 0.5, 0.1) if aoe_radius > 0.0 else Color(0.3, 0.7, 1.0)


func _physics_process(delta: float) -> void:
	var move := direction * speed * delta
	global_position += move
	_traveled += move.length()

	if is_server_projectile:
		_check_enemy_hits()

	if _traveled >= max_range:
		if is_server_projectile and aoe_radius > 0.0:
			_explode()
		queue_free()


func _check_enemy_hits() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= 8.0:
			if aoe_radius > 0.0:
				_explode()
			else:
				(enemy as CharacterBody2D).take_damage(damage)
				queue_free()
			return


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to((enemy as Node2D).global_position) <= aoe_radius:
			(enemy as CharacterBody2D).take_damage(damage)
	queue_free()
