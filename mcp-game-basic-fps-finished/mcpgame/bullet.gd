extends Node3D

const SPEED := 35.0
const LIFETIME := 3.0

var direction := Vector3.FORWARD
var shooter := RID()
var age := 0.0


func _physics_process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return

	var next_position := global_position + direction * SPEED * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, 3, [shooter])
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		var collider: Node = hit.collider
		if collider.is_in_group("trees"):
			collider.collect()
		queue_free()
		return
	global_position = next_position
