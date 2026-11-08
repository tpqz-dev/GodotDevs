extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_test")

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

func _test() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var populated := await _wait_until(func() -> bool: return game.get_node("HealthPickups/Items").get_child_count() == 5, 5)
	_check(populated, "Solo pickups did not spawn.")
	_check(game.health == 3 and game.health_bar.value == 3, "Solo health did not start at three.")
	_check(not game.heal_one(), "Health exceeded its maximum.")
	_check(game.animation_player.has_animation("Death01"), "Solo death animation is unavailable.")
	game.take_damage()
	_check(game.health == 2 and game.health_bar.value == 2, "Solo damage did not update health.")
	if populated:
		var pickup = game.get_node("HealthPickups/Items").get_child(0)
		pickup.global_position = game.player.global_position + Vector3.UP * 0.5
		var healed := await _wait_until(func() -> bool: return game.health == 3, 2)
		_check(healed, "Solo pickup did not restore health.")
	game.take_damage()
	game.take_damage()
	game.take_damage()
	_check(game.dying and game.health == 0 and game.animation_player.current_animation == &"Death01", "Solo death animation did not start.")
	await create_timer(1.0).timeout
	_check(is_instance_valid(game.player), "Solo player disappeared too early.")
	var disappeared := await _wait_until(func() -> bool: return not is_instance_valid(game.player), 3)
	_check(disappeared and game.camera.current, "Solo player or spectator camera state is incorrect.")
	print("Solo health checks: %d failures" % failures)
	quit(1 if failures else 0)
