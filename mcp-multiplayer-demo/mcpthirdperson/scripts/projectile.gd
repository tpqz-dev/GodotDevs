extends Node3D

const SPEED := 18.0
const LIFETIME := 3.0

var direction: Vector3
var shooter: CharacterBody3D
var target: RigidBody3D
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
	var travel := direction * SPEED * minf(delta, time_left)
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + travel, shooter.collision_mask, [shooter.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		if is_instance_valid(target) and hit.collider == target:
			target.queue_free()
		queue_free()
		return
	global_position += travel
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
