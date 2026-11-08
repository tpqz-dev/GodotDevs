extends Node3D

const CHARACTER_SCENE: PackedScene = preload("res://Godot/AnimationLibrary_Godot_Standard.glb")
const WALK_SPEED := 3.0
const RUN_SPEED := 5.5
const JUMP_VELOCITY := 7.2
const GRAVITY := 18.0

var player: CharacterBody3D
var character_model: Node3D
var animation_player: AnimationPlayer
var camera_pivot: Node3D
var camera: Camera3D
var camera_yaw := 0.0
var camera_pitch := -0.18
var current_animation := ""
var jump_was_pressed := false

func _ready() -> void:
	_build_world()
	_build_player()
	_build_camera()
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.003
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.002, -0.65, 0.25)
		camera_pivot.rotation.y = camera_yaw
		camera.rotation.x = camera_pitch

func _physics_process(delta: float) -> void:
	var jump_pressed := Input.is_action_pressed("jump")
	var jump_requested := jump_pressed and not jump_was_pressed and player.is_on_floor()
	jump_was_pressed = jump_pressed

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := -camera_pivot.global_basis.z
	var right := camera_pivot.global_basis.x
	var move_direction := (right * input_vector.x - forward * input_vector.y)	
	move_direction.y = 0.0
	move_direction = move_direction.normalized()

	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	elif jump_requested:
		player.velocity.y = JUMP_VELOCITY
		_play_animation("Jump")

	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target_velocity := move_direction * speed
	player.velocity.x = move_toward(player.velocity.x, target_velocity.x, 22.0 * delta)
	player.velocity.z = move_toward(player.velocity.z, target_velocity.z, 22.0 * delta)
	player.move_and_slide()

	if move_direction.length_squared() > 0.001:
		var target_angle := atan2(move_direction.x, move_direction.z)
		character_model.rotation.y = lerp_angle(character_model.rotation.y, target_angle, minf(12.0 * delta, 1.0))

	if player.is_on_floor():
		if move_direction.length_squared() > 0.001:
			_play_animation("Sprint" if Input.is_action_pressed("sprint") else "Walk")
		else:
			_play_animation("Idle")

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9bc4db")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6e5f0")
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "CheckeredGround"
	add_child(ground)
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(32.0, 0.2, 32.0)
	ground_collision.shape = ground_shape
	ground_collision.position.y = 0.0
	ground.add_child(ground_collision)

	var light_tile := _make_material(Color("e9edf0"))
	var dark_tile := _make_material(Color("26364f"))
	light_tile.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	dark_tile.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	for x in range(-8, 8):
		for z in range(-8, 8):
			var tile := MeshInstance3D.new()
			var tile_mesh := PlaneMesh.new()
			tile_mesh.size = Vector2(1.0, 1.0)
			tile.mesh = tile_mesh
			tile.material_override = light_tile if (x + z) % 2 == 0 else dark_tile
			tile.position = Vector3(float(x) + 0.5, 0.106, float(z) + 0.5)
			ground.add_child(tile)

	var platform := StaticBody3D.new()
	platform.name = "JumpCube"
	platform.position = Vector3(2.7, 0.7, 0.0)
	add_child(platform)
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(1.6, 1.2, 1.6)
	var cube_visual := MeshInstance3D.new()
	cube_visual.mesh = cube_mesh
	var cube_material := _make_material(Color("e58b48"))
	cube_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	cube_visual.material_override = cube_material
	platform.add_child(cube_visual)
	var cube_collision := CollisionShape3D.new()
	var cube_shape := BoxShape3D.new()
	cube_shape.size = cube_mesh.size
	cube_collision.shape = cube_shape
	platform.add_child(cube_collision)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position.y = 0.1
	add_child(player)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
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
		_play_animation("Idle")

func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0.0, 1.25, 0.0)
	player.add_child(camera_pivot)
	camera = Camera3D.new()
	camera.name = "ThirdPersonCamera"
	camera.position = Vector3(0.0, 2.6, 6.2)
	camera.rotation.x = camera_pitch
	camera_pivot.add_child(camera)
	camera.current = true

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var hint := Label.new()
	hint.text = "ZQSD / WASD ou fleches : bouger   |   Maj : courir   |   Espace : sauter   |   Souris : camera   |   Echap : liberer la souris"
	hint.position = Vector2(18.0, 18.0)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("17212b"))
	layer.add_child(hint)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material

func _play_animation(animation_name: String) -> void:
	if animation_player != null and current_animation != animation_name and animation_player.has_animation(animation_name):
		current_animation = animation_name
		animation_player.play(animation_name, 0.15)
