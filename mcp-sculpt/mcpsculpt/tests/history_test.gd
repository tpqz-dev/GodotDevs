extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)


func _key(app: Node, code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.shift_pressed = shift
	event.keycode = code
	app._unhandled_input(event)


func _press(app: Node, position: Vector2, shift: bool = false, alt: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	event.shift_pressed = shift
	event.alt_pressed = alt
	app._handle_mouse_button(event)


func _release(app: Node) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	app._input(event)


func _run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var center := root.get_visible_rect().size / 2.0
	var original: PackedVector3Array = app.model.vertices.duplicate()
	_check(app.undo_button.disabled and app.redo_button.disabled, "empty history buttons disabled")
	_press(app, center)
	var motion := InputEventMouseMotion.new()
	motion.position = center + Vector2(30, 0)
	app._handle_mouse_motion(motion)
	_release(app)
	var first: PackedVector3Array = app.model.vertices.duplicate()
	_check(first != original and app.undo_history.size() == 1, "multi-sample stroke is one action")
	_check(not app.undo_button.disabled and app.redo_button.disabled, "button state after stroke")
	app.wire_instance.visible = true
	app._refresh_mesh()
	_key(app, KEY_Z)
	_check(app.model.vertices == original and not app.modified, "Ctrl+Z restores original geometry and state")
	_check(app.wire_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original, "undo refreshes wireframe")
	_check(app.undo_button.disabled and not app.redo_button.disabled, "button state after undo")
	var hit: Dictionary = app._pick(center)
	_check(not hit.is_empty() and absf(hit.position.z - 1.0) < 0.01, "undo restores raycast bounds")
	_key(app, KEY_Y)
	_check(app.model.vertices == first and app.modified, "Ctrl+Y redoes stroke")
	_press(app, center, true)
	_release(app)
	var second: PackedVector3Array = app.model.vertices.duplicate()
	_check(second != first and app.undo_history.size() == 2, "smoothing stroke is recorded")
	app.undo_button.pressed.emit()
	_check(app.model.vertices == first, "undo button restores first stroke")
	_key(app, KEY_Z)
	_check(app.model.vertices == original, "multiple undo actions")
	_key(app, KEY_Z, true)
	_check(app.model.vertices == first, "Ctrl+Shift+Z redoes stroke")
	app.redo_button.pressed.emit()
	_check(app.model.vertices == second, "redo button restores smoothing")
	_key(app, KEY_Z)
	_press(app, center, false, true)
	_release(app)
	_check(app.redo_history.is_empty() and app.redo_button.disabled, "new stroke clears redo branch")
	var branch: PackedVector3Array = app.model.vertices.duplicate()
	_key(app, KEY_Y)
	_check(app.model.vertices == branch, "redo cannot restore discarded branch")
	_press(app, Vector2(-100, -100))
	_release(app)
	_check(app.model.vertices == branch, "stroke outside mesh is a no-op")
	_key(app, KEY_Z)
	_check(app.model.vertices == first, "no-op stroke does not create history")
	_press(app, center)
	_key(app, KEY_Z)
	_check(not app.sculpting and app.model.vertices == first, "undo during stroke commits then undoes it")
	_press(app, center)
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not app.sculpting and not app.undo_history.is_empty(), "focus loss commits active stroke")
	app._reset_sphere()
	_check(app.undo_history.is_empty() and app.redo_history.is_empty() and app.history_bytes == 0, "new sphere clears history")
	_check(app.model.vertices == original and not app.modified, "new sphere restores original state")
	app.history_limit_bytes = 1
	_press(app, center)
	_release(app)
	_check(app.undo_history.is_empty() and app.history_bytes == 0, "oversized stroke respects memory limit")
	_check(app.modified and app.history_status.text.begins_with("Trait trop volumineux"), "oversized stroke warns and keeps geometry")
	app._reset_sphere()
	app.history_limit_bytes = original.size() * 12 * 2 + 1
	_press(app, center)
	_release(app)
	var first_limited: PackedVector3Array = app.model.vertices.duplicate()
	_press(app, center)
	_release(app)
	_check(app.undo_history.size() == 1 and app.history_bytes <= app.history_limit_bytes, "oldest action trimmed within memory limit")
	_key(app, KEY_Z)
	_check(app.model.vertices == first_limited, "newest action remains undoable after trimming")
	app.free()
	print("History tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
