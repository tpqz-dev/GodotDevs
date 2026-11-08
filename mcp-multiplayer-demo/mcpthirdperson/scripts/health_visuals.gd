extends RefCounted

static func make_bar(layer: CanvasLayer, position: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = position
	bar.custom_minimum_size = Vector2(180, 24)
	bar.max_value = 3
	bar.value = 3
	bar.show_percentage = false
	layer.add_child(bar)
	return bar

static func explode(parent: Node3D, point: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 45
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.0
	particles.gravity = Vector3(0, -6, 0)
	particles.scale_amount_min = 0.07
	particles.scale_amount_max = 0.18
	particles.color = Color("ff7137")
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	particles.mesh = mesh
	parent.add_child(particles)
	particles.global_position = point + Vector3.UP
	particles.emitting = true
	parent.get_tree().create_timer(1.5).timeout.connect(particles.queue_free)
