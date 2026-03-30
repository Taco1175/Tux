extends Area2D

var mural_zone: int = 0
var already_read: bool = false


func interact(_player: Node) -> void:
	if already_read:
		return
	already_read = true
	var game := get_tree().get_first_node_in_group("game_scene")
	if game and game.has_method("show_mural"):
		game.show_mural(mural_zone)
