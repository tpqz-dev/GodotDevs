extends Node3D

const CHARACTER_SCENE: PackedScene = preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const PROJECTILE_SCRIPT = preload("res://scripts/projectile.gd")
const CHARACTER_STEPS = preload("res://scripts/character_steps.gd")
const HEALTH_PICKUPS = preload("res://scripts/health_pickups.gd")
const HEALTH_VISUALS = preload("res://scripts/health_visuals.gd")
const WALK_SPEED := 3.0
const RUN_SPEED := 5.5
const JUMP_VELOCITY := 7.2
const GRAVITY := 18.0
const PLAYER_RADIUS := CHARACTER_STEPS.PLAYER_RADIUS
const CAMERA_INITIAL_OFFSET := Vector3(0.0, 2.6, 6.2)
const CAMERA_MIN_DISTANCE := 2.0
const CAMERA_ZOOM_STEP := 0.6

var player: CharacterBody3D
var character_model: Node3D
var animation_player: AnimationPlayer
var camera_pivot: Node3D
var camera: Camera3D
var camera_yaw := 0.0
var camera_pitch := -0.18
var current_animation := ""
var jump_was_pressed := false
var shot_requested := false
var shooting := false
var health := 3
var dying := false
var health_bar: ProgressBar
var health_label: Label

@onready var arena: CSGBox3D = $Arena
@onready var target_cube: RigidBody3D = $targetCubeRg

func _ready() -> void:
	_build_world()
	_build_player()
	_build_camera()
	_build_hud()
	var pickups := HEALTH_PICKUPS.new()
	pickups.setup(self, false)
	add_child(pickups)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		camera.position = CAMERA_INITIAL_OFFSET
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not dying:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			shot_requested = true
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.003
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.002, -0.65, 0.25)
		camera_pivot.rotation.y = camera_yaw
		camera.rotation.x = camera_pitch

func _zoom_camera(change: float) -> void:
	var distance := clampf(camera.position.length() + change, CAMERA_MIN_DISTANCE, CAMERA_INITIAL_OFFSET.length())
	camera.position = CAMERA_INITIAL_OFFSET.normalized() * distance

func _physics_process(delta: float) -> void:
	if dying:
		return
	if shot_requested:
		shot_requested = false
		_shoot()

	var jump_pressed := Input.is_action_pressed("jump")
	var jump_requested := jump_pressed and not jump_was_pressed and player.is_on_floor() and not shooting
	jump_was_pressed = jump_pressed

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera_pivot.global_basis.z
	var right := camera_pivot.global_basis.x
	var move_direction := (right * input_vector.x - forward * input_vector.y)	
	move_direction.y = 0.0
	move_direction = move_direction.normalized()
	if shooting:
		move_direction = Vector3.ZERO

	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif jump_requested:
		player.velocity.y = JUMP_VELOCITY
		_play_animation("Jump")

	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target_velocity := move_direction * speed
	if shooting:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	else:
		player.velocity.x = move_toward(player.velocity.x, target_velocity.x, 22.0 * delta)
		player.velocity.z = move_toward(player.velocity.z, target_velocity.z, 22.0 * delta)
	var was_on_floor := player.is_on_floor()
	var start_position := player.global_position
	player.move_and_slide()
	if was_on_floor and not jump_requested and move_direction.length_squared() > 0.001:
		var intended_motion := Vector3(target_velocity.x, 0.0, target_velocity.z) * delta
		var traveled := player.global_position - start_position
		traveled.y = 0.0
		CHARACTER_STEPS.try_step_up(player, intended_motion - traveled)

	if not shooting and move_direction.length_squared() > 0.001:
		var target_angle := atan2(move_direction.x, move_direction.z)
		character_model.rotation.y = lerp_angle(character_model.rotation.y, target_angle, minf(12.0 * delta, 1.0))

	if player.is_on_floor():
		if move_direction.length_squared() > 0.001:
			_play_animation("Sprint" if Input.is_action_pressed("sprint") else "Walk")
		else:
			_play_animation("Idle")

func _shoot() -> void:
	var direction := -camera_pivot.global_basis.z.normalized()
	character_model.rotation.y = atan2(direction.x, direction.z)
	if animation_player != null:
		shooting = true
		current_animation = "Pistol_Shoot"
		animation_player.stop()
		animation_player.play(current_animation, 0.1)
	var projectile := PROJECTILE_SCRIPT.new()
	projectile.direction = direction
	projectile.shooter = player
	projectile.target = target_cube if is_instance_valid(target_cube) else null
	add_child(projectile)
	projectile.global_position = player.global_position + Vector3.UP

func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"Pistol_Shoot":
		shooting = false
		current_animation = ""
		if not player.is_on_floor():
			_play_animation("Jump")

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9bc4db")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment_node.environment = environment
	add_child(environment_node)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = _arena_center()
	add_child(player)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	player.add_child(collision)

	character_model = CHARACTER_SCENE.instantiate() as Node3D
	character_model.name = "CharacterModel"
	character_model.rotation.y = PI
	player.add_child(character_model)
	animation_player = character_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_error("Le personnage GLB ne contient pas d'AnimationPlayer.")
	else:
		animation_player.animation_finished.connect(_on_animation_finished)
		_play_animation("Idle")

func _arena_center() -> Vector3:
	return to_local(arena.to_global(Vector3(0.0, arena.size.y * 0.5, 0.0)))

func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, 1.25, 0.0)
	player.add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "ThirdPersonCamera"
	camera.position = CAMERA_INITIAL_OFFSET
	camera.rotation.x = camera_pitch
	camera_pivot.add_child(camera)
	camera.current = true

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var hint := Label.new()
	hint.text = "ZQSD / WASD ou fleches : bouger   |   Maj : courir   |   Espace : sauter   |   Souris : camera\nClic gauche : tirer   |   Molette : zoom   |   R : zoom initial   |   Echap : liberer la souris"
	hint.position = Vector2(18.0, 18.0)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("17212b"))
	layer.add_child(hint)
	health_label = Label.new()
	health_label.position = Vector2(18, 68)
	layer.add_child(health_label)
	health_bar = HEALTH_VISUALS.make_bar(layer, Vector2(18, 90))
	_update_health_hud()

func _update_health_hud() -> void:
	health_bar.value = health
	health_label.text = "Vie : %d / 3%s" % [health, " — éliminé" if dying else ""]

func heal_one() -> bool:
	if dying or health >= 3:
		return false
	health += 1
	_update_health_hud()
	return true

func take_damage() -> void:
	if dying or health <= 0:
		return
	health -= 1
	if health == 0:
		dying = true
		shooting = false
		player.velocity = Vector3.ZERO
		player.collision_layer = 0
		player.collision_mask = 0
		camera_pivot.reparent(self, true)
		camera.current = true
		if animation_player != null and animation_player.has_animation("Death01"):
			animation_player.play("Death01", 0.1)
		else:
			push_error("L'animation de mort Death01 est absente.")
		get_tree().create_timer(3.0).timeout.connect(_finish_death)
	_update_health_hud()

func _finish_death() -> void:
	if is_instance_valid(player):
		HEALTH_VISUALS.explode(self, player.global_position)
		player.queue_free()

func _play_animation(animation_name: String) -> void:
	if not shooting and animation_player != null and current_animation != animation_name and animation_player.has_animation(animation_name):
		current_animation = animation_name
		animation_player.play(animation_name, 0.15)
