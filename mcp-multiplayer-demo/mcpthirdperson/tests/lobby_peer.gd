extends SceneTree

var failed := false
var manager: Node
var coordination_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if manager != null and manager.multiplayer.has_multiplayer_peer():
		manager.multiplayer.poll()
	return false

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return predicate.call()

func _run() -> void:
	manager = root.get_node("NetworkManager")
	manager.status_changed.connect(func(message: String) -> void: print("status: ", message))
	manager.session_closed.connect(func(message: String) -> void: print("closed: ", message))
	manager.player_joined.connect(func(id: int, info: Dictionary) -> void: print("joined: ", id, " ", info))
	manager.multiplayer.peer_connected.connect(func(id: int) -> void: print("peer connected: ", id))
	var args := OS.get_cmdline_user_args()
	var role := args[0]
	var port := args[1].to_int()
	coordination_dir = args[2]
	if role == "host":
		await _run_host(port)
	elif role == "full":
		await _run_full_client(port)
	else:
		await _run_client(role, port)
	manager.close_session()
	print("%s: %s" % [role, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

func _run_host(port: int) -> void:
	_check(manager.host_game(port, "Hôte", Color.RED).is_empty(), "Host failed to start.")
	var all_ready := await _wait_until(func() -> bool:
		if manager.players.size() != 4:
			return false
		for id in manager.players:
			if id != 1 and not manager.players[id].ready:
				return false
		return true, 10.0)
	_check(all_ready, "Four players did not register and become ready.")
	_check(manager.players.size() <= 4, "Player limit exceeded.")
	if not all_ready:
		return
	_write_marker("host_ready")
	var full_checked := await _wait_until(func() -> bool:
		return FileAccess.file_exists(coordination_dir.path_join("full_done")), 15.0)
	_check(full_checked and manager.players.size() == 4, "Full-server test did not complete with four players present.")
	_write_marker("host_saw_full")
	var client_left := await _wait_until(func() -> bool: return manager.players.size() == 3, 6.0)
	_check(client_left, "Disconnected client was not removed.")
	await create_timer(2.0).timeout

func _run_client(role: String, port: int) -> void:
	var started := Time.get_ticks_msec()
	_check(manager.join_game("127.0.0.1", port, role, Color.GREEN).is_empty(), "Client could not start.")
	var joined := await _wait_until(func() -> bool: return manager.connected, 4.0)
	if not joined and manager.multiplayer.has_multiplayer_peer():
		print("client peer status: ", manager.multiplayer.multiplayer_peer.get_connection_status())
	_check(joined, "Client did not connect.")
	if not joined:
		return
	_check(Time.get_ticks_msec() - started < 3000, "Connection took more than three seconds.")
	_check(manager.update_profile(role, Color.BLUE, true).is_empty(), "Profile update failed.")
	var replicated := await _wait_until(func() -> bool:
		var id := manager.multiplayer.get_unique_id()
		return manager.players.has(id) and manager.players[id].ready and manager.players[id].color == Color.BLUE, 3.0)
	_check(replicated, "Profile was not synchronized.")
	if role == "client3":
		var full_checked := await _wait_until(func() -> bool:
			return FileAccess.file_exists(coordination_dir.path_join("host_saw_full")), 16.0)
		_check(full_checked, "Full-server test did not finish.")
		return
	var closed := await _wait_until(func() -> bool: return not manager.connected, 24.0)
	_check(closed, "Host disconnect was not detected.")

func _run_full_client(port: int) -> void:
	var closed_message := [""]
	manager.session_closed.connect(func(message: String) -> void: closed_message[0] = message)
	_check(manager.join_game("127.0.0.1", port, "Extra", Color.WHITE).is_empty(), "Extra connection could not start.")
	var closed := await _wait_until(func() -> bool: return not closed_message[0].is_empty(), 10.0)
	_check(closed and not manager.connected, "A fifth player was not rejected.")
	_check(closed_message[0].contains("complet"), "Full-server error was not shown.")
	_write_marker("full_done")

func _write_marker(marker: String) -> void:
	var file := FileAccess.open(coordination_dir.path_join(marker), FileAccess.WRITE)
	_check(file != null, "Could not write test coordination marker: " + marker)
	if file != null:
		file.store_string("done")
