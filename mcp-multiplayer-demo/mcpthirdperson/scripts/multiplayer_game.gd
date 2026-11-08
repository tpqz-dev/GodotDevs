extends Node3D

const CHARACTER = preload("res://scripts/multiplayer_character.gd")
const PROJECTILE = preload("res://scripts/multiplayer_projectile.gd")
const HEALTH_PICKUPS = preload("res://scripts/health_pickups.gd")
const HEALTH_VISUALS = preload("res://scripts/health_visuals.gd")
const SPAWN_OFFSETS := [Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 2), Vector3(1.5, 0, 2)]

var network: Node
var players_node: Node3D
var spawner: MultiplayerSpawner
var projectile_spawner: MultiplayerSpawner
var target_cube: RigidBody3D
var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY
var spawned := false
var loading_deadline := 0
var match_started_msec := 0
var target_destroyed := false
var hud_layer: CanvasLayer
var finish_button: Button
var waiting_for_despawn := false
var health_pickups: Node3D
var health_bar: ProgressBar
var health_label: Label
var death_deadlines: Dictionary = {}
var saw_local_player := false

func _ready() -> void:
	if network == null:
		network = get_node("/root/NetworkManager")
	if not network.connected or not network.in_game:
		push_error("La scène multijoueur nécessite une session active.")
		return
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9bc4db")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	world.environment = environment
	add_child(world)
	target_cube = $targetCubeRg
	target_cube.freeze = not multiplayer.is_server()
	if not multiplayer.is_server():
		target_cube.collision_layer = 0
		target_cube.collision_mask = 0
	target_position = target_cube.position
	target_rotation = target_cube.quaternion
	var world_sync := MultiplayerSynchronizer.new()
	world_sync.name = "WorldSynchronizer"
	world_sync.root_path = NodePath("..")
	world_sync.replication_interval = 0.05
	var world_config := SceneReplicationConfig.new()
	for path in [NodePath(".:target_position"), NodePath(".:target_rotation")]:
		world_config.add_property(path)
		world_config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	world_sync.replication_config = world_config
	add_child(world_sync, true)
	players_node = Node3D.new()
	players_node.name = "Players"
	add_child(players_node, true)
	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player
	add_child(spawner, true)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	add_child(projectiles, true)
	projectile_spawner = MultiplayerSpawner.new()
	projectile_spawner.name = "ProjectileSpawner"
	projectile_spawner.spawn_path = NodePath("../Projectiles")
	projectile_spawner.spawn_function = _spawn_projectile
	add_child(projectile_spawner, true)
	health_pickups = HEALTH_PICKUPS.new()
	health_pickups.setup(self, true)
	add_child(health_pickups, true)
	network.game_peer_ready.connect(_on_peer_ready)
	network.player_left.connect(_on_player_left)
	network.session_closed.connect(_on_session_closed)
	network.game_finished.connect(_show_results)
	network.lobby_returned.connect(_on_lobby_returned)
	network.lobby_return_preparing.connect(_prepare_lobby_return)
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		loading_deadline = Time.get_ticks_msec() + 15000
	network.notify_game_ready()
	_check_ready()

func _physics_process(delta: float) -> void:
	if not network.connected or not multiplayer.has_multiplayer_peer() or not is_instance_valid(target_cube):
		return
	if multiplayer.is_server():
		target_position = target_cube.position
		target_rotation = target_cube.quaternion
	else:
		target_cube.position = target_cube.position.lerp(target_position, minf(delta * 12.0, 1.0))
		target_cube.quaternion = target_cube.quaternion.slerp(target_rotation, minf(delta * 12.0, 1.0))

func _unhandled_input(event: InputEvent) -> void:
	if not network.connected or not saw_local_player:
		return
	var local_player := players_node.get_node_or_null("Player%d" % multiplayer.get_unique_id())
	if (local_player == null or local_player.dying) and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	if health_bar != null and network.connected:
		var local_player := players_node.get_node_or_null("Player%d" % multiplayer.get_unique_id())
		if local_player != null:
			saw_local_player = true
		var hp: int = local_player.health if local_player != null and not local_player.dying else (0 if saw_local_player else 3)
		health_bar.value = hp
		health_label.text = "Vie : %d / 3%s" % [hp, " — spectateur" if hp == 0 and saw_local_player else ""]
	if network.hosting and not network.returning_to_lobby:
		for id in death_deadlines.keys():
			if Time.get_ticks_msec() >= death_deadlines[id]:
				death_deadlines.erase(id)
				var character := players_node.get_node_or_null("Player%d" % id)
				if character != null:
					_explode_player.rpc(character.global_position)
					character.queue_free()
	if waiting_for_despawn and players_node.get_child_count() == 0 and $Projectiles.get_child_count() == 0 and health_pickups.items.get_child_count() == 0:
		waiting_for_despawn = false
		network.notify_lobby_return_ready()
	if network.connected and network.hosting and not spawned and loading_deadline > 0 and Time.get_ticks_msec() >= loading_deadline:
		network.close_session("Un joueur n'a pas chargé la partie à temps.")

func _on_peer_ready(_id: int) -> void:
	_check_ready()

func _check_ready() -> void:
	if not network.hosting or not network.connected or not multiplayer.has_multiplayer_peer() or spawned:
		return
	for id in network.players:
		if not network.game_ready_ids.has(id):
			return
	if network.players.size() < 2:
		network.close_session("Pas assez de joueurs pour commencer.")
		return
	spawned = true
	match_started_msec = Time.get_ticks_msec()
	if finish_button != null and network.hosting:
		finish_button.disabled = false
	var arena: CSGBox3D = $Arena
	var center := arena.to_global(Vector3(0, arena.size.y * 0.5, 0))
	var ids: Array = network.players.keys()
	ids.sort()
	for i in range(ids.size()):
		var id: int = ids[i]
		spawner.spawn({"id": id, "info": network.players[id], "position": to_local(center) + SPAWN_OFFSETS[i]})

func _spawn_player(data: Variant) -> Node:
	var character := CHARACTER.new()
	character.name = "Player%d" % data.id
	character.peer_id = data.id
	character.player_name = data.info.name
	character.player_color = data.info.color
	character.position = data.position
	character.net_position = data.position
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Synchronizer"
	sync.root_path = NodePath("..")
	sync.replication_interval = 0.05
	sync.delta_interval = 0.05
	var config := SceneReplicationConfig.new()
	for path in [NodePath(".:net_position"), NodePath(".:net_velocity"), NodePath(".:net_angle"), NodePath(".:net_animation"), NodePath(".:net_ack"), NodePath(".:health")]:
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	character.add_child(sync, true)
	return character

func spawn_projectile(shooter_id: int, origin: Vector3, direction: Vector3) -> void:
	if not network.hosting or not network.connected or not spawned or network.match_finished:
		return
	projectile_spawner.spawn({"shooter": shooter_id, "position": to_local(origin), "direction": direction})

func _spawn_projectile(data: Variant) -> Node:
	var projectile := PROJECTILE.new()
	projectile.shooter_id = data.shooter
	projectile.position = data.position
	projectile.direction = data.direction
	return projectile

func destroy_target() -> void:
	if not network.hosting or not network.connected or network.match_finished or not is_instance_valid(target_cube):
		return
	target_destroyed = true
	_remove_target.rpc()

func begin_death(id: int) -> void:
	if not network.hosting or not network.connected or network.match_finished or death_deadlines.has(id):
		return
	death_deadlines[id] = Time.get_ticks_msec() + 3000
	_start_death.rpc(id)

@rpc("authority", "call_local", "reliable")
func _start_death(id: int) -> void:
	var character := players_node.get_node_or_null("Player%d" % id)
	if character != null:
		character.start_death()

@rpc("authority", "call_local", "reliable")
func _explode_player(point: Vector3) -> void:
	HEALTH_VISUALS.explode(self, point)

@rpc("authority", "call_local", "reliable")
func _remove_target() -> void:
	if is_instance_valid(target_cube):
		target_cube.queue_free()

func _on_player_left(id: int) -> void:
	if not network.hosting or not multiplayer.has_multiplayer_peer() or players_node == null:
		return
	death_deadlines.erase(id)
	var character := players_node.get_node_or_null("Player%d" % id)
	if character != null:
		character.queue_free()
	if not spawned:
		_check_ready()

func _on_session_closed(_message: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_return_to_menu")

func _on_lobby_returned() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_return_to_menu")

func _prepare_lobby_return() -> void:
	waiting_for_despawn = true
	if network.hosting:
		death_deadlines.clear()
		for character in players_node.get_children():
			character.queue_free()
		for projectile in $Projectiles.get_children():
			projectile.queue_free()
		for pickup in health_pickups.items.get_children():
			pickup.queue_free()

func _return_to_menu() -> void:
	var error := get_tree().change_scene_to_file("res://Lobby.tscn")
	if error != OK:
		push_error("Impossible de retourner au menu : %d" % error)

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	var label := Label.new()
	label.text = "ZQSD / WASD : bouger | Maj : courir | Espace : sauter | Souris : camera\nClic gauche : tirer | Molette : zoom | R : zoom initial | Echap : liberer la souris"
	label.position = Vector2(18, 18)
	hud_layer.add_child(label)
	health_label = Label.new()
	health_label.position = Vector2(18, 68)
	health_label.text = "Vie : 3 / 3"
	hud_layer.add_child(health_label)
	health_bar = HEALTH_VISUALS.make_bar(hud_layer, Vector2(18, 90))
	var button := Button.new()
	finish_button = button
	button.text = "Terminer la partie" if network.hosting else "Quitter la partie"
	button.position = Vector2(18, 125)
	button.disabled = network.hosting and not spawned
	button.pressed.connect(_finish_match if network.hosting else _leave_game)
	hud_layer.add_child(button)

func _finish_match() -> void:
	if not spawned:
		push_warning("La partie ne peut pas être terminée avant l'arrivée des joueurs.")
		return
	var names: Array[String] = []
	for id in network.players:
		names.append(network.players[id].name)
	var results := {
		"duration_seconds": int((Time.get_ticks_msec() - match_started_msec) / 1000),
		"target_destroyed": target_destroyed,
		"players": names,
	}
	var error: String = network.finish_game(results)
	if not error.is_empty():
		push_error(error)

func _leave_game() -> void:
	network.close_session("Vous avez quitté la partie.")

func _show_results(results: Dictionary) -> void:
	players_node.process_mode = Node.PROCESS_MODE_DISABLED
	$Projectiles.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(target_cube):
		target_cube.freeze = true
	hud_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.name = "Results"
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.08, 0.12, 0.9)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(400, 0)
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)
	var title := Label.new()
	title.text = "Partie terminée"
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	var summary := Label.new()
	var seconds: int = results.duration_seconds
	summary.text = "Durée : %d min %02d s\nCube cible : %s\nJoueurs : %s" % [
		seconds / 60, seconds % 60,
		"détruit" if results.target_destroyed else "non détruit",
		", ".join(results.players),
	]
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary)
	if network.hosting:
		var lobby_button := Button.new()
		lobby_button.text = "Retourner au lobby"
		lobby_button.pressed.connect(_return_all_to_lobby)
		content.add_child(lobby_button)
	else:
		var waiting := Label.new()
		waiting.text = "En attente du retour au lobby par l'hôte."
		content.add_child(waiting)
	var menu_button := Button.new()
	menu_button.text = "Quitter vers le menu"
	menu_button.pressed.connect(_leave_game)
	content.add_child(menu_button)

func _return_all_to_lobby() -> void:
	var error: String = network.return_to_lobby()
	if not error.is_empty():
		push_error(error)
