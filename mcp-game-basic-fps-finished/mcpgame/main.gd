extends Node3D

const RESTART_DELAY := 10.0

var score := 0
var total_trees := 0

@onready var score_label: Label = $HUD/Score
@onready var victory_label: Label = $HUD/Victory


func _ready() -> void:
	var trees := get_tree().get_nodes_in_group("trees")
	total_trees = trees.size()
	for tree in trees:
		tree.collected.connect(_on_tree_collected)
	_update_score()


func _on_tree_collected() -> void:
	score += 1
	_update_score()
	if score == total_trees:
		victory_label.show()
		get_tree().create_timer(RESTART_DELAY).timeout.connect(_restart_game)


func _restart_game() -> void:
	var error := get_tree().reload_current_scene()
	if error != OK:
		push_error("Impossible de redémarrer la partie : %s" % error_string(error))


func _update_score() -> void:
	score_label.text = "Arbres touchés : %d / %d" % [score, total_trees]
