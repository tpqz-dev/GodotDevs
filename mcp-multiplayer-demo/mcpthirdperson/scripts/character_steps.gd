extends RefCounted

const MAX_STEP_HEIGHT := 0.32
const PLAYER_RADIUS := 0.34

static func try_step_up(player: CharacterBody3D, motion: Vector3) -> void:
	if motion.length_squared() < 0.000001:
		return
	var probe_motion := motion.normalized() * (PLAYER_RADIUS + 0.015)
	var origin := player.global_transform
	var raised := origin.translated(Vector3.UP * MAX_STEP_HEIGHT)
	if player.test_move(origin, Vector3.UP * MAX_STEP_HEIGHT):
		return
	if player.test_move(raised, probe_motion):
		return
	var ray_start := raised.origin + probe_motion
	var ray_query := PhysicsRayQueryParameters3D.create(ray_start, ray_start + Vector3.DOWN * (MAX_STEP_HEIGHT + 0.05), player.collision_mask, [player.get_rid()])
	var ground := player.get_world_3d().direct_space_state.intersect_ray(ray_query)
	if ground.is_empty() or ground.normal.dot(Vector3.UP) < cos(player.floor_max_angle):
		return
	var down_result := KinematicCollision3D.new()
	if not player.test_move(raised.translated(probe_motion), Vector3.DOWN * (MAX_STEP_HEIGHT + 0.05), down_result):
		return
	var step_motion := Vector3.UP * MAX_STEP_HEIGHT + motion + down_result.get_travel()
	if step_motion.y <= 0.01 or step_motion.y > MAX_STEP_HEIGHT:
		return
	player.global_position += step_motion
	player.apply_floor_snap()
