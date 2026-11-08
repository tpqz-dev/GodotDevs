extends Node3D

const SPEED := 18.0
const LIFETIME := 3.0

var direction := Vector3.ZERO
var shooter_id := 1
var time_left := LIFETIME

func _ready() -> void:
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	visual.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffc44d")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	add_child(visual)

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var travel := direction * SPEED * minf(delta, maxf(time_left, 0.0))
	if multiplayer.is_server():
		var game := get_parent().get_parent()
		var shooter := game.players_node.get_node_or_null("Player%d" % shooter_id) as CharacterBody3D
		var excluded: Array[RID] = []
		if shooter != null:
			excluded.append(shooter.get_rid())
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + travel, 1, excluded)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			if is_instance_valid(game.target_cube) and hit.collider == game.target_cube:
				game.destroy_target()
			elif hit.collider is CharacterBody3D and hit.collider.get_parent() == game.players_node:
				hit.collider.take_damage()
			queue_free()
			return
	position += travel
	time_left -= delta
	if time_left <= 0.0 and multiplayer.is_server():
		queue_free()
