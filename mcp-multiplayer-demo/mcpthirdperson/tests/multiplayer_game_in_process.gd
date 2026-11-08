extends SceneTree

const MANAGER = preload("res://scripts/network_manager.gd")
const GAME = preload("res://MultiplayerGame.tscn")
var managers: Array[Node] = []
var apis: Array[SceneMultiplayer] = []
var roots: Array[Node] = []
var games: Array[Node] = []
var failures := 0
var pause_host_poll := false

func _initialize() -> void:
	multiplayer_poll = false
	call_deferred("_test")

func _process(_delta: float) -> bool:
	for i in range(apis.size()):
		if i != 0 or not pause_host_poll:
			apis[i].poll()
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.03).timeout
	return predicate.call()

func _make_peer(index: int) -> Node:
	var container := Node.new()
	container.name = "Peer%d" % index
	root.add_child(container)
	roots.append(container)
	var api := SceneMultiplayer.new()
	api.root_path = container.get_path()
	set_multiplayer(api, container.get_path())
	apis.append(api)
	var manager := MANAGER.new()
	manager.name = "NetworkManager"
	container.add_child(manager)
	managers.append(manager)
	return manager

func _load_game(index: int) -> void:
	var game := GAME.instantiate()
	game.network = managers[index]
	roots[index].add_child(game)
	games.append(game)

func _test() -> void:
	var host := _make_peer(0)
	var client := _make_peer(1)
	var client2 := _make_peer(2)
	var client3 := _make_peer(3)
	_check(host.host_game(24893, "Hôte", Color.RED).is_empty(), "Host failed.")
	_check(client.join_game("127.0.0.1", 24893, "Invité", Color.BLUE).is_empty(), "Join failed.")
	_check(client2.join_game("127.0.0.1", 24893, "Invité2", Color.GREEN).is_empty(), "Join failed.")
	_check(client3.join_game("127.0.0.1", 24893, "Invité3", Color.WHITE).is_empty(), "Join failed.")
	var joined := await _wait_until(func() -> bool: return client.connected and client2.connected and client3.connected and host.players.size() == 4, 4)
	_check(joined, "Client did not connect.")
	if joined:
		_check(not host.start_game().is_empty(), "Game started before players were ready.")
		host.update_profile("Hôte", Color.RED, true)
		client.update_profile("Invité", Color.BLUE, true)
		client2.update_profile("Invité2", Color.GREEN, true)
		client3.update_profile("Invité3", Color.WHITE, true)
		var ready := await _wait_until(func() -> bool: return host.can_start_game(), 3)
		_check(ready, "Ready state was not received.")
		host.start_game()
		var started := await _wait_until(func() -> bool: return client.in_game and client2.in_game and client3.in_game, 3)
		_check(started, "Game start was not received.")
		if started:
			_load_game(1)
			_load_game(2)
			_load_game(3)
			_load_game(0)
			var spawned := await _wait_until(func() -> bool:
				for game in games:
					if game.players_node.get_child_count() != 4:
						return false
				return true, 5)
			_check(spawned, "Characters did not spawn on both peers.")
			if spawned:
				var id: int = client.multiplayer.get_unique_id()
				var server_character: CharacterBody3D = games[3].players_node.get_node("Player%d" % id)
				var replica: CharacterBody3D = games[0].players_node.get_node("Player%d" % id)
				replica.add_collision_exception_with(server_character)
				var start: Vector3 = server_character.position
				Input.action_press("move_forward")
				var moved := await _wait_until(func() -> bool: return server_character.position.distance_to(start) > 0.6, 3)
				Input.action_release("move_forward")
				_check(moved, "Server did not move client character.")
				var replicated := await _wait_until(func() -> bool: return replica.position.distance_to(start) > 0.4, 3)
				_check(replicated, "Client character movement was not replicated.")
				_check(replica.position.distance_to(server_character.position) < 1.0, "Replica diverged from server.")
				var observer = games[1].players_node.get_node("Player%d" % id)
				_check(observer.snapshots.size() >= 2, "Remote interpolation snapshots were not received.")
				await _check_prediction(server_character, replica)
				await _check_stair_animation(server_character, replica, observer, false)
				await _check_stair_animation(server_character, replica, observer, true)
				await create_timer(0.4).timeout
				var floor_y := server_character.global_position.y
				Input.action_press("jump")
				var jumped := await _wait_until(func() -> bool: return server_character.global_position.y > floor_y + 0.3, 2)
				var jump_animated := await _wait_until(func() -> bool:
					return server_character.net_animation == "Jump" and replica.current_animation == "Jump" and observer.current_animation == "Jump", 1)
				Input.action_release("jump")
				_check(jumped, "Network character did not jump.")
				_check(jump_animated, "A real jump did not animate on all peers.")
				await _check_combat(server_character, replica)
				await _check_results()
				await _check_health()
				client.session_closed.disconnect(games[0]._on_session_closed)
				client.close_session()
				var removed := await _wait_until(func() -> bool:
					return games[3].players_node.get_node_or_null("Player%d" % id) == null and games[1].players_node.get_node_or_null("Player%d" % id) == null, 3)
				_check(removed, "Disconnected player was not removed.")
				games[3]._finish_match()
				var second_finished := await _wait_until(func() -> bool: return client2.match_finished and client3.match_finished, 3)
				_check(second_finished and not games[3].target_destroyed, "Undestroyed-target results were not sent.")
				for game in games:
					if game.network.session_closed.is_connected(game._on_session_closed):
						game.network.session_closed.disconnect(game._on_session_closed)
				host.close_session()
				var closed := await _wait_until(func() -> bool: return not client2.connected and not client3.connected, 3)
				_check(closed, "Remaining players did not detect the host disconnect.")
	for game in games:
		if is_instance_valid(game):
			if game.network.session_closed.is_connected(game._on_session_closed):
				game.network.session_closed.disconnect(game._on_session_closed)
	for manager in managers:
		manager.close_session()
	print("Multiplayer game checks: %d failures" % failures)
	quit(1 if failures else 0)

func _check_stair_animation(server_character, replica, observer, sprint: bool) -> void:
	var stairs: CSGPolygon3D = games[3].get_node("Stairs")
	server_character.global_position = stairs.global_position + Vector3(-1, 0.02, -1)
	server_character.velocity = Vector3.ZERO
	await create_timer(0.8).timeout
	if sprint:
		Input.action_press("sprint")
	Input.action_press("move_right")
	var deadline := Time.get_ticks_msec() + 4000
	var false_jumps := 0
	var samples := 0
	var correct_animation := [0, 0, 0]
	var expected := "Sprint" if sprint else "Walk"
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var offset: float = server_character.global_position.x - stairs.global_position.x
		if offset > 0.0 and offset < 2.7:
			samples += 1
			if server_character.net_animation == "Jump" or replica.current_animation == "Jump" or observer.current_animation == "Jump":
				false_jumps += 1
			if server_character.current_animation == expected:
				correct_animation[0] += 1
			if replica.current_animation == expected:
				correct_animation[1] += 1
			if observer.current_animation == expected:
				correct_animation[2] += 1
		if offset > 2.5 and server_character.global_position.y > stairs.global_position.y + 1.7:
			break
	Input.action_release("move_right")
	Input.action_release("sprint")
	_check(samples > 0 and server_character.global_position.x > stairs.global_position.x + 2.5 and server_character.global_position.y > stairs.global_position.y + 1.7, "Network character did not climb the staircase.")
	_check(false_jumps == 0, "Staircase caused jump animations while %s (%d frames)." % ["sprinting" if sprint else "walking", false_jumps])
	_check(correct_animation[0] > 0 and correct_animation[1] > 0 and correct_animation[2] > 0, "%s animation was not displayed on all peers." % expected)
	await create_timer(0.4).timeout

func _check_results() -> void:
	var host = managers[0]
	var client = managers[1]
	var summary := [{}]
	client.game_finished.connect(func(results: Dictionary) -> void: summary[0] = results)
	_check(not client.finish_game({}).is_empty(), "Client was able to finish the game.")
	games[3]._finish_match()
	var finished := await _wait_until(func() -> bool:
		for manager in managers:
			if not manager.match_finished:
				return false
		return true, 3)
	_check(finished, "Results were not received by all players.")
	_check(summary[0].get("target_destroyed", false), "Results did not report the destroyed target.")
	_check(summary[0].get("players", []).size() == 4, "Results did not report all players.")
	_check(summary[0].get("duration_seconds", -1) >= 0, "Results duration is missing.")
	for game in games:
		_check(game.get_node_or_null("Results") != null, "Results screen is missing.")
		_check(game.players_node.process_mode == Node.PROCESS_MODE_DISABLED, "Players remain active after the match.")
		game.network.lobby_returned.disconnect(game._on_lobby_returned)
	var server_character = games[3].players_node.get_node("Player%d" % client.multiplayer.get_unique_id())
	var client_character = games[0].players_node.get_node("Player%d" % client.multiplayer.get_unique_id())
	client_character._request_shot.rpc_id(1, Vector3.FORWARD)
	await create_timer(0.2).timeout
	_check(games[3].get_node("Projectiles").get_child_count() == 0, "A shot was accepted after the game ended.")
	_check(server_character.process_mode == Node.PROCESS_MODE_INHERIT, "Unexpected character process configuration.")
	_check(not client.return_to_lobby().is_empty(), "Client was able to force a lobby return.")
	_check(host.return_to_lobby().is_empty(), "Host could not return to lobby.")
	var returned := await _wait_until(func() -> bool:
		for manager in managers:
			if manager.in_game or manager.match_finished:
				return false
			for info in manager.players.values():
				if info.ready:
					return false
		return true, 3)
	_check(returned, "Players did not return to the lobby with ready states reset.")
	for game in games:
		game.queue_free()
	games.clear()
	await process_frame
	for manager in managers:
		var id: int = manager.multiplayer.get_unique_id()
		var info: Dictionary = manager.players[id]
		manager.update_profile(info.name, info.color, true)
	var ready := await _wait_until(func() -> bool: return host.can_start_game(), 3)
	_check(ready, "Players could not ready for a rematch.")
	if not ready:
		return
	_check(host.start_game().is_empty(), "Host could not start a rematch.")
	var restarted := await _wait_until(func() -> bool:
		for manager in managers:
			if not manager.in_game:
				return false
		return true, 3)
	_check(restarted, "Rematch did not start for all players.")
	if not restarted:
		return
	_load_game(1)
	_load_game(2)
	_load_game(3)
	_load_game(0)
	var respawned := await _wait_until(func() -> bool:
		for game in games:
			if game.players_node.get_child_count() != 4 or not is_instance_valid(game.target_cube):
				return false
		return true, 5)
	_check(respawned, "Rematch did not respawn all players and the target.")

func _check_health() -> void:
	var server = games[3]
	var shooter_id: int = managers[1].multiplayer.get_unique_id()
	var victim_id: int = managers[3].multiplayer.get_unique_id()
	var victim = server.players_node.get_node("Player%d" % victim_id)
	var victim_replica = games[2].players_node.get_node("Player%d" % victim_id)
	_check(victim.animator.has_animation("Death01"), "Death animation is unavailable.")
	var pickups_ready := await _wait_until(func() -> bool:
		for game in games:
			if game.health_pickups.items.get_child_count() != 5:
				return false
		return true, 5)
	_check(pickups_ready, "Initial pickups were not replicated.")
	if not pickups_ready:
		return
	var ground_y: float = server.get_node("Arena").global_position.y + 0.12
	for character in server.players_node.get_children():
		character.global_position = Vector3(100 + character.peer_id % 4 * 4, ground_y, 110)
		character.velocity = Vector3.ZERO
	victim.global_position = Vector3(100, ground_y, 100)
	await create_timer(0.3).timeout
	var pickup = server.health_pickups.items.get_child(0)
	pickup.global_position = victim.global_position + Vector3.UP * 0.5
	await create_timer(0.2).timeout
	_check(is_instance_valid(pickup) and victim.health == 3, "Full-health player consumed a pickup.")
	_check(not victim_replica.heal_one(), "A client could authoritatively heal itself.")
	server.spawn_projectile(shooter_id, victim.global_position + Vector3(0, 1, 3), Vector3.FORWARD)
	pickup.global_position = Vector3(150, ground_y + 0.5, 150)
	var hit := await _wait_until(func() -> bool: return victim.health == 2 and victim_replica.health == 2, 3)
	_check(hit, "Projectile damage was not replicated.")
	pickup.global_position = victim.global_position + Vector3.UP * 0.5
	var healed := await _wait_until(func() -> bool: return victim.health == 3 and victim_replica.health == 3, 3)
	_check(healed, "Pickup did not restore and replicate one health point.")
	var consumed := await _wait_until(func() -> bool:
		for game in games:
			if game.health_pickups.items.get_child_count() != 4:
				return false
		return true, 3)
	_check(consumed, "Consumed pickup did not despawn everywhere.")
	_check(server.health_pickups.timer > 19.0, "Pickup replacement was not scheduled after collection.")
	server.health_pickups.timer = 0.0
	var replenished := await _wait_until(func() -> bool:
		for game in games:
			if game.health_pickups.items.get_child_count() != 5:
				return false
		return true, 3)
	_check(replenished, "Pickup did not respawn everywhere.")
	var death_started := 0
	for i in range(3):
		server.spawn_projectile(shooter_id, victim.global_position + Vector3(0, 1, 3), Vector3.FORWARD)
		var damage := await _wait_until(func() -> bool: return victim.health == 2 - i, 2)
		_check(damage, "Shot %d did not inflict one point of damage." % (i + 1))
		if i == 2:
			death_started = Time.get_ticks_msec()
	_check(victim.dying, "Victim did not enter death state.")
	var dying_replica := await _wait_until(func() -> bool:
		return victim_replica.dying and victim_replica.current_animation == "Death01", 2)
	_check(dying_replica, "Death animation did not start on the victim's client.")
	_check(victim_replica.local_camera.current and victim_replica.camera_pivot.get_parent() == games[2], "Spectator camera was not preserved.")
	await create_timer(2.5).timeout
	_check(is_instance_valid(victim), "Victim disappeared before three seconds.")
	var removed := await _wait_until(func() -> bool:
		for game in games:
			if game.players_node.has_node("Player%d" % victim_id):
				return false
		return true, 4)
	_check(removed, "Eliminated player did not disappear on all peers.")
	_check(Time.get_ticks_msec() - death_started >= 2900, "Death duration was shorter than three seconds.")
	var explosion_visible := false
	for node in games[2].get_children():
		if node is CPUParticles3D:
			explosion_visible = true
	_check(explosion_visible, "Death particles were not created on the client.")
	_check("spectateur" in games[2].health_label.text, "Spectator status was not shown.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	games[2]._unhandled_input(escape)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Eliminated player cannot release the mouse.")
	var host_character = server.players_node.get_node("Player1")
	host_character.take_damage()
	host_character.take_damage()
	host_character.take_damage()
	var host_removed := await _wait_until(func() -> bool: return not server.players_node.has_node("Player1"), 4)
	_check(host_removed and server.finish_button != null and not server.finish_button.disabled, "Eliminated host cannot finish the game.")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	server._unhandled_input(escape)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Eliminated host cannot release the mouse.")
	_check(games[2].get_viewport().get_camera_3d() != null, "Spectator camera disappeared.")

func _check_prediction(server_character: CharacterBody3D, replica: CharacterBody3D) -> void:
	Input.action_release("move_forward")
	Input.action_release("move_right")
	server_character.global_position = Vector3(80, 2.2, 80)
	server_character.velocity = Vector3.ZERO
	await create_timer(1.0).timeout
	var initial: Vector3 = replica.global_position
	var server_initial: Vector3 = server_character.global_position
	pause_host_poll = true
	Input.action_press("move_forward")
	await create_timer(0.15).timeout
	_check(replica.global_position.distance_to(initial) > 0.1, "Local prediction did not move before server input arrived.")
	_check(server_character.global_position.distance_to(server_initial) < 0.1, "Server moved despite delayed input.")
	pause_host_poll = false
	await create_timer(0.5).timeout
	Input.action_release("move_forward")
	var converged := await _wait_until(func() -> bool:
		return replica.global_position.distance_to(server_character.global_position) < 0.2, 3)
	_check(converged, "Predicted position did not converge to server state.")
	Input.action_press("move_forward")
	var moving := await _wait_until(func() -> bool: return server_character.velocity.length() > 2.0, 2)
	_check(moving, "Server did not resume movement.")
	pause_host_poll = true
	Input.action_release("move_forward")
	await create_timer(0.9).timeout
	_check(Vector2(server_character.velocity.x, server_character.velocity.z).length() < 0.01, "Server did not stop after input packets stopped.")
	pause_host_poll = false
	await create_timer(0.3).timeout

func _check_combat(server_character: CharacterBody3D, replica: CharacterBody3D) -> void:
	var server = games[3]
	var ground_y: float = server.get_node("Arena").global_position.y + 0.12
	server_character.global_position = Vector3(80, ground_y, 80)
	server_character.velocity = Vector3.ZERO
	server.target_cube.global_position = Vector3(80, ground_y + 0.6, 74)
	server.target_cube.linear_velocity = Vector3.ZERO
	server.target_cube.angular_velocity = Vector3.ZERO
	await create_timer(0.5).timeout
	var moved_target := await _wait_until(func() -> bool:
		return games[1].target_cube.global_position.distance_to(server.target_cube.global_position) < 0.5, 3)
	_check(moved_target, "Target position was not replicated.")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.2)
	collision.shape = box
	wall.add_child(collision)
	server.add_child(wall)
	wall.global_position = server_character.global_position + Vector3(0, 1, -3)
	await create_timer(0.1).timeout
	var other_id: int = managers[2].multiplayer.get_unique_id()
	var other_replica = games[0].players_node.get_node("Player%d" % other_id)
	other_replica._request_shot.rpc_id(1, Vector3.FORWARD)
	await create_timer(0.1).timeout
	_check(server.get_node("Projectiles").get_child_count() == 0, "A client fired as another player.")
	replica._request_shot.rpc_id(1, Vector3.FORWARD)
	var fired := await _wait_until(func() -> bool: return server_character.shooting_time > 0.0, 2)
	_check(fired, "Client shot was not accepted by server.")
	_check(server.get_node("Projectiles").get_child_count() == 1, "Server projectile was not spawned.")
	var visible_projectile := await _wait_until(func() -> bool: return games[1].get_node("Projectiles").get_child_count() == 1, 0.15)
	_check(visible_projectile, "Projectile spawn was not replicated.")
	var stopped_at: Vector3 = server_character.global_position
	Input.action_press("move_forward")
	replica._request_shot.rpc_id(1, Vector3.FORWARD)
	replica._request_shot.rpc_id(1, Vector3(100, 0, 0))
	await create_timer(0.1).timeout
	Input.action_release("move_forward")
	_check(Vector2(server_character.global_position.x - stopped_at.x, server_character.global_position.z - stopped_at.z).length() < 0.02, "Player moved while shooting.")
	_check(server.get_node("Projectiles").get_child_count() == 1, "Invalid or rapid shot bypassed validation.")
	_check(server_character.net_animation == "Pistol_Shoot", "Shoot animation was not set.")
	var animated := await _wait_until(func() -> bool: return replica.net_animation == "Pistol_Shoot", 0.5)
	_check(animated, "Shoot animation was not replicated.")
	await create_timer(0.4).timeout
	_check(is_instance_valid(server.target_cube), "Target was destroyed through a wall.")
	_check(server.get_node("Projectiles").get_child_count() == 0, "Projectile did not stop at wall.")
	_check(games[1].get_node("Projectiles").get_child_count() == 0, "Projectile despawn was not replicated.")
	wall.queue_free()
	await create_timer(0.4).timeout
	replica._request_shot.rpc_id(1, Vector3.FORWARD)
	var destroyed := await _wait_until(func() -> bool:
		for game in games:
			if is_instance_valid(game.target_cube):
				return false
		return true, 3)
	_check(destroyed, "Target destruction was not replicated to all players.")
	_check(is_instance_valid(server.get_node_or_null("Box")), "A wall was removed.")
