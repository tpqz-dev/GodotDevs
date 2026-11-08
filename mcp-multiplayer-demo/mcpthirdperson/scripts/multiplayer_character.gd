extends CharacterBody3D

const CHARACTER_SCENE: PackedScene = preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const STEPS = preload("res://scripts/character_steps.gd")
const INPUT_TIMEOUT_MSEC := 500
const INPUT_INTERVAL_MSEC := 12
const SHOT_COOLDOWN_MSEC := 650
const SHOT_DURATION := 0.633333
const INTERPOLATION_DELAY_MSEC := 100
const HISTORY_LIMIT := 128
const CORRECTION_SPEED := 10.0
const TELEPORT_DISTANCE := 2.0

var peer_id := 1
var player_name := ""
var player_color := Color.WHITE
var net_position := Vector3.ZERO
var net_velocity := Vector3.ZERO
var net_angle := PI
var net_animation := "Idle"
var net_ack := 0
var input_direction := Vector3.ZERO
var input_sprint := false
var input_jump := false
var jump_was_pressed := false
var last_input_msec := 0
var last_rpc_msec := 0
var send_timer := 0.0
var pending_jump := false
var last_shot_msec := -SHOT_COOLDOWN_MSEC
var shooting_time := 0.0
var model: Node3D
var animator: AnimationPlayer
var current_animation := ""
var local_camera: Camera3D
var camera_pivot: Node3D
var camera_pitch := -0.18
var camera_yaw := 0.0
var camera_offset := Vector3(0, 2.6, 6.2)
var input_sequence := 0
var last_received_sequence := 0
var last_ack := 0
var pending_sequence := 0
var prediction_history: Dictionary = {}
var correction := Vector3.ZERO
var snapshots: Array[Dictionary] = []
var jump_animation_active := false
var predicted_animation := "Idle"
var health := 3
var dying := false

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = STEPS.PLAYER_RADIUS
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	collision.disabled = not multiplayer.is_server() and peer_id != multiplayer.get_unique_id()
	if not multiplayer.is_server():
		collision_layer = 0
	add_child(collision)
	if not multiplayer.is_server():
		$Synchronizer.synchronized.connect(_on_snapshot)
	model = CHARACTER_SCENE.instantiate() as Node3D
	model.rotation.y = PI
	add_child(model)
	animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animator == null:
		push_error("Le modèle multijoueur ne contient pas d'AnimationPlayer.")
	var label := Label3D.new()
	label.text = player_name
	label.modulate = player_color
	label.position.y = 2.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	if peer_id == multiplayer.get_unique_id():
		camera_pivot = Node3D.new()
		camera_pivot.position.y = 1.25
		add_child(camera_pivot)
		local_camera = Camera3D.new()
		local_camera.position = camera_offset
		local_camera.rotation.x = camera_pitch
		camera_pivot.add_child(local_camera)
		local_camera.current = true
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if local_camera == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		local_camera.position = camera_offset
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not dying:
		var change := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change = -0.6
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change = 0.6
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var direction := -camera_pivot.global_basis.z.normalized()
			if multiplayer.is_server():
				_fire(direction)
			else:
				_request_shot.rpc_id(1, direction)
		if change != 0.0:
			var distance := clampf(local_camera.position.length() + change, 2.0, camera_offset.length())
			local_camera.position = camera_offset.normalized() * distance
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.003
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.002, -0.65, 0.25)
		camera_pivot.rotation.y = camera_yaw
		local_camera.rotation.x = camera_pitch

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if dying or health <= 0:
		return
	var send_input := false
	if local_camera != null:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := camera_pivot.global_basis.x * input.x + camera_pivot.global_basis.z * input.y
		direction.y = 0.0
		direction = direction.limit_length(1.0)
		var sprint := Input.is_action_pressed("sprint")
		var jump := Input.is_action_pressed("jump")
		if multiplayer.is_server():
			_set_input(direction, sprint, jump)
		else:
			if Input.is_action_just_pressed("jump"):
				pending_jump = true
			_set_input(direction, sprint, jump or pending_jump)
			send_timer -= delta
			if send_timer <= 0.0:
				send_timer = 0.05
				input_sequence += 1
				pending_sequence = input_sequence
				_receive_input.rpc_id(1, input_sequence, direction, sprint, jump or pending_jump)
				pending_jump = false
				send_input = true
	if not multiplayer.is_server() and local_camera == null:
		return
	if multiplayer.is_server():
		shooting_time = maxf(shooting_time - delta, 0.0)
	if multiplayer.is_server() and peer_id != 1 and Time.get_ticks_msec() - last_input_msec > INPUT_TIMEOUT_MSEC:
		input_direction = Vector3.ZERO
		input_sprint = false
		input_jump = false
	var shooting := shooting_time > 0.0 if multiplayer.is_server() else net_animation == "Pistol_Shoot"
	var jumped := _simulate_motion(delta, shooting)
	if jumped:
		jump_animation_active = true
	elif is_on_floor():
		jump_animation_active = false
	var movement_animation := "Jump" if jump_animation_active else ("Sprint" if input_sprint else "Walk") if input_direction.length_squared() > 0.001 else "Idle"
	if multiplayer.is_server():
		if not shooting and input_direction.length_squared() > 0.001:
			net_angle = lerp_angle(net_angle, atan2(input_direction.x, input_direction.z), minf(12.0 * delta, 1.0))
		net_animation = "Pistol_Shoot" if shooting else movement_animation
		net_position = position
		net_velocity = velocity
		net_ack = last_received_sequence
	else:
		predicted_animation = movement_animation
		_apply_correction(delta)
		if send_input:
			prediction_history[pending_sequence] = position
			while prediction_history.size() > HISTORY_LIMIT:
				prediction_history.erase(prediction_history.keys()[0])

func _simulate_motion(delta: float, shooting: bool) -> bool:
	var jump_requested := input_jump and not jump_was_pressed and is_on_floor() and not shooting
	jump_was_pressed = input_jump
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif jump_requested:
		velocity.y = 7.2
	var speed := 5.5 if input_sprint else 3.0
	var target := input_direction * speed if not shooting else Vector3.ZERO
	if shooting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity.x = move_toward(velocity.x, target.x, 22.0 * delta)
		velocity.z = move_toward(velocity.z, target.z, 22.0 * delta)
	var on_floor := is_on_floor()
	var before := global_position
	move_and_slide()
	if on_floor and not jump_requested and target.length_squared() > 0.001:
		var traveled := global_position - before
		traveled.y = 0.0
		STEPS.try_step_up(self, target * delta - traveled)
	return jump_requested
func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if dying or health <= 0:
		if not dying:
			return
		if animator != null and current_animation != "Death01" and animator.has_animation("Death01"):
			current_animation = "Death01"
			animator.play("Death01", 0.1)
		return
	if not multiplayer.is_server() and local_camera == null:
		_interpolate_remote()
	elif not multiplayer.is_server() and local_camera != null and net_animation != "Pistol_Shoot" and input_direction.length_squared() > 0.001:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(input_direction.x, input_direction.z), minf(12.0 * delta, 1.0))
	else:
		model.rotation.y = net_angle
	var animation := net_animation
	if not multiplayer.is_server() and local_camera != null and net_animation != "Pistol_Shoot":
		animation = predicted_animation
	if animator != null and current_animation != animation and animator.has_animation(animation):
		current_animation = animation
		animator.play(animation, 0.15)

func _set_input(direction: Vector3, sprint: bool, jump: bool) -> void:
	input_direction = direction
	input_sprint = sprint
	input_jump = jump
	last_input_msec = Time.get_ticks_msec()

func _fire(direction: Vector3) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if get_parent().get_parent().network.match_finished or dying or health <= 0:
		return
	if not direction.is_finite() or absf(direction.y) > 0.001 or absf(direction.length_squared() - 1.0) > 0.01:
		return
	var now := Time.get_ticks_msec()
	if now - last_shot_msec < SHOT_COOLDOWN_MSEC:
		return
	last_shot_msec = now
	shooting_time = SHOT_DURATION
	net_angle = atan2(direction.x, direction.z)
	net_animation = "Pistol_Shoot"
	get_parent().get_parent().spawn_projectile(peer_id, global_position + Vector3.UP, direction)

@rpc("any_peer", "call_remote", "reliable")
func _request_shot(direction: Vector3) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == peer_id:
		_fire(direction)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_input(sequence: int, direction: Vector3, sprint: bool, jump: bool) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if get_parent().get_parent().network.match_finished or dying or health <= 0:
		return
	var now := Time.get_ticks_msec()
	if now - last_rpc_msec < INPUT_INTERVAL_MSEC:
		return
	if sequence <= last_received_sequence:
		return
	if not direction.is_finite() or absf(direction.y) > 0.001 or direction.length_squared() > 1.01:
		return
	last_rpc_msec = now
	last_received_sequence = sequence
	_set_input(direction.limit_length(1.0), sprint, jump)

func heal_one() -> bool:
	if not multiplayer.is_server() or dying or health <= 0 or health >= 3:
		return false
	health += 1
	return true

func take_damage() -> void:
	if not multiplayer.is_server() or dying or health <= 0 or get_parent().get_parent().network.match_finished:
		return
	health -= 1
	if health == 0:
		get_parent().get_parent().begin_death(peer_id)

func start_death() -> void:
	if dying:
		return
	dying = true
	health = 0
	velocity = Vector3.ZERO
	input_direction = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if local_camera != null:
		camera_pivot.reparent(get_parent().get_parent(), true)
		local_camera.current = true

func _on_snapshot() -> void:
	if local_camera != null:
		if net_ack <= last_ack:
			return
		last_ack = net_ack
		if prediction_history.has(net_ack):
			var error: Vector3 = net_position - prediction_history[net_ack]
			correction = error
			if correction.length() > TELEPORT_DISTANCE:
				position += correction
				_shift_history(correction)
				correction = Vector3.ZERO
				velocity = net_velocity
		for sequence in prediction_history.keys():
			if sequence <= net_ack:
				prediction_history.erase(sequence)
	else:
		snapshots.append({"time": Time.get_ticks_msec(), "position": net_position, "angle": net_angle})
		while snapshots.size() > HISTORY_LIMIT:
			snapshots.pop_front()

func _shift_history(offset: Vector3) -> void:
	for sequence in prediction_history:
		prediction_history[sequence] += offset

func _apply_correction(delta: float) -> void:
	if correction.length_squared() < 0.000001:
		return
	var step := correction * minf(delta * CORRECTION_SPEED, 1.0)
	var collision := move_and_collide(step)
	var applied := step if collision == null else collision.get_travel()
	correction -= applied
	_shift_history(applied)

func _interpolate_remote() -> void:
	if snapshots.is_empty():
		return
	var render_time := Time.get_ticks_msec() - INTERPOLATION_DELAY_MSEC
	while snapshots.size() > 2 and int(snapshots[1].time) <= render_time:
		snapshots.pop_front()
	if snapshots.size() == 1 or render_time <= int(snapshots[0].time):
		position = snapshots[0].position
		model.rotation.y = snapshots[0].angle
		return
	var first := snapshots[0]
	var second := snapshots[1]
	var duration := int(second.time) - int(first.time)
	var weight := clampf(float(render_time - int(first.time)) / maxf(float(duration), 1.0), 0.0, 1.0)
	position = (first.position as Vector3).lerp(second.position, weight)
	model.rotation.y = lerp_angle(first.angle, second.angle, weight)
