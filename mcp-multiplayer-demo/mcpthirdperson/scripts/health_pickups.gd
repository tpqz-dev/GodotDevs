extends Node3D

const MAX_PICKUPS := 5
const RESPAWN_INTERVAL := 20.0
const SPAWN_RADIUS := 25.0
const PICKUP_DISTANCE := 1.4
const MAX_SPAWN_ATTEMPTS := 40

var game: Node3D
var networked := false
var timer := 0.0
var spawner: MultiplayerSpawner
var items: Node3D
var initial_fill := true

func setup(owner_game: Node3D, is_networked: bool) -> void:
	game = owner_game
	networked = is_networked
	name = "HealthPickups"
	items = Node3D.new()
	items.name = "Items"
	add_child(items)
	if networked:
		spawner = MultiplayerSpawner.new()
		spawner.name = "Spawner"
		spawner.spawn_path = NodePath("../Items")
		spawner.spawn_function = _create_pickup
		add_child(spawner)

func _physics_process(delta: float) -> void:
	if networked and (not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or not game.spawned or game.network.match_finished or game.network.returning_to_lobby):
		return
	timer -= delta
	if timer <= 0.0 and items.get_child_count() < MAX_PICKUPS:
		if _spawn_pickup():
			if initial_fill and items.get_child_count() >= MAX_PICKUPS:
				initial_fill = false
			timer = 0.0 if initial_fill else RESPAWN_INTERVAL
		else:
			timer = 2.0
	for pickup in items.get_children():
		var characters: Array = game.players_node.get_children() if networked else [game.player]
		for character in characters:
			if not is_instance_valid(character):
				continue
			if character.global_position.distance_to(pickup.global_position) > PICKUP_DISTANCE:
				continue
			var healed: bool = character.heal_one() if networked else game.heal_one()
			if healed:
				pickup.queue_free()
				timer = RESPAWN_INTERVAL
				break

func _spawn_pickup() -> bool:
	var arena: CSGBox3D = game.get_node("Arena")
	var center := arena.to_global(Vector3(0, arena.size.y * 0.5, 0))
	for attempt in range(MAX_SPAWN_ATTEMPTS):
		var point := center + Vector3(randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), 0, randf_range(-SPAWN_RADIUS, SPAWN_RADIUS))
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 8.0, point - Vector3.UP * 2.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or absf(hit.position.y - center.y) > 0.2 or hit.normal.y < 0.9:
			continue
		var spawn_position: Vector3 = hit.position + Vector3.UP * 0.55
		var occupied := false
		for pickup in items.get_children():
			if pickup.global_position.distance_to(spawn_position) < 2.0:
				occupied = true
				break
		if occupied:
			continue
		if networked:
			spawner.spawn(to_local(spawn_position))
		else:
			items.add_child(_create_pickup(to_local(spawn_position)))
		return true
	push_warning("Impossible de placer une sphère de soin sur le sol.")
	return false

func _create_pickup(data: Variant) -> Node:
	var pickup := Node3D.new()
	pickup.position = data
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("e32929")
	material.emission_enabled = true
	material.emission = Color("c41616")
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	pickup.add_child(visual)
	return pickup
