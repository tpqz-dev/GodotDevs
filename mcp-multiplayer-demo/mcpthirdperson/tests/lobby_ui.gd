extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_test")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _test() -> void:
	var lobby = load("res://Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	lobby.port_field.text = "0"
	lobby.host_button.pressed.emit()
	_check("port" in lobby.status_label.text.to_lower(), "Invalid port was not reported.")
	lobby.port_field.text = "24892"
	lobby.host_button.pressed.emit()
	_check(lobby.lobby_panel.visible and lobby.player_list.get_child_count() == 1, "Host lobby did not appear.")
	lobby.ready_button.pressed.emit()
	_check(lobby.ready_button.text == "Annuler prêt", "Host ready state was not displayed.")
	lobby._leave()
	_check(lobby.menu_panel.visible and not lobby.lobby_panel.visible, "Menu did not return after leaving.")
	lobby._play_solo()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "Main" and current_scene.get_node_or_null("Player") != null, "Solo game did not start.")
	print("Lobby UI checks: %d failures" % failures)
	quit(1 if failures else 0)
