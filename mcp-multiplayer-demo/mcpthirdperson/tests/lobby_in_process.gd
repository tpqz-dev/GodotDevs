extends SceneTree

const MANAGER = preload("res://scripts/network_manager.gd")
const INCOMPATIBLE_MANAGER = preload("res://tests/incompatible_network_manager.gd")
var managers: Array[Node] = []
var apis: Array[SceneMultiplayer] = []
var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func _process(_delta: float) -> bool:
	for api in apis:
		api.poll()
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
		await create_timer(0.02).timeout
	return predicate.call()

func _make_peer(index: int, incompatible: bool = false) -> Node:
	var container := Node.new()
	container.name = "Peer%d" % index
	root.add_child(container)
	var api := SceneMultiplayer.new()
	api.root_path = container.get_path()
	set_multiplayer(api, container.get_path())
	apis.append(api)
	var manager := INCOMPATIBLE_MANAGER.new() if incompatible else MANAGER.new()
	manager.name = "NetworkManager"
	container.add_child(manager)
	managers.append(manager)
	return manager

func _test() -> void:
	var host := _make_peer(0)
	var result: String = host.host_game(24891, "Hôte", Color.RED)
	_check(result.is_empty(), "Host: " + result)
	_check(not host.update_profile("", Color.WHITE, false).is_empty(), "Empty name accepted.")
	var old_client := _make_peer(1, true)
	var old_message := [""]
	old_client.session_closed.connect(func(message: String) -> void: old_message[0] = message)
	old_client.join_game("127.0.0.1", 24891, "Ancien", Color.WHITE)
	var rejected := await _wait_until(func() -> bool: return not old_message[0].is_empty(), 3.0)
	_check(rejected and old_message[0] == "Version incompatible." and host.players.size() == 1, "Incompatible version was not rejected.")
	for i in range(1, 4):
		var client := _make_peer(i + 1)
		result = client.join_game("127.0.0.1", 24891, "Joueur%d" % i, Color.GREEN)
		_check(result.is_empty(), "Join: " + result)
	var joined := await _wait_until(func() -> bool:
		if host.players.size() != 4:
			return false
		for i in range(2, 5):
			if not managers[i].connected or managers[i].players.size() != 4:
				return false
		return true, 4.0)
	_check(joined, "Four-player lobby did not synchronize.")
	if joined:
		for i in range(2, 5):
			managers[i].update_profile("Joueur%d" % i, Color.BLUE, true)
		var ready := await _wait_until(func() -> bool:
			for i in range(2, 5):
				var id: int = managers[i].multiplayer.get_unique_id()
				if not host.players[id].ready or host.players[id].color != Color.BLUE:
					return false
			return true, 2.0)
		_check(ready, "Ready state and color were not synchronized.")
		var extra := _make_peer(5)
		var full_message := [""]
		extra.session_closed.connect(func(message: String) -> void: full_message[0] = message)
		extra.join_game("127.0.0.1", 24891, "Extra", Color.WHITE)
		var full := await _wait_until(func() -> bool: return not full_message[0].is_empty(), 10.0)
		_check(full and not extra.connected and host.players.size() == 4, "Fifth player was not rejected.")
		managers[4].close_session()
		var removed := await _wait_until(func() -> bool: return host.players.size() == 3 and managers[2].players.size() == 3, 3.0)
		_check(removed, "Disconnected player was not removed.")
		host.close_session()
		var disconnected := await _wait_until(func() -> bool: return not managers[2].connected and not managers[3].connected, 3.0)
		_check(disconnected, "Clients did not detect the host disconnect.")
	for manager in managers:
		manager.close_session()
	print("In-process lobby checks: %d failures" % failures)
	quit(1 if failures else 0)
