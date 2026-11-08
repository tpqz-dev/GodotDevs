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


func _s_key(app: Node, pressed: bool, ctrl: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_S
	key.pressed = pressed
	key.ctrl_pressed = ctrl
	if pressed:
		app._unhandled_input(key)
	else:
		app._input(key)


func _motion(app: Node, position: Vector2, delta: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.relative = delta
	app._handle_mouse_motion(motion)


func _run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var center := root.get_visible_rect().size / 2.0
	var vertices: PackedVector3Array = app.model.vertices.duplicate()
	_s_key(app, true, true)
	_check(not app.resizing_brush, "Ctrl+S does not start size adjustment")
	_s_key(app, true)
	_motion(app, center, Vector2(50, 0))
	_check(is_equal_approx(app.radius, 0.4) and is_equal_approx(app.radius_slider.value, 0.4), "S and right movement increases size and updates slider")
	_check(app.cursor.visible, "brush cursor remains visible over model")
	var ring_vertices: PackedVector3Array = app.cursor.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(is_equal_approx(ring_vertices[0].distance_to(ring_vertices[32]), 0.8), "brush cursor displays adjusted diameter")
	_motion(app, center, Vector2(-100, 0))
	_check(is_equal_approx(app.radius, 0.2), "left movement decreases size")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = center
	app._handle_mouse_button(click)
	_check(not app.sculpting and app.model.vertices == vertices and app.undo_history.is_empty(), "resizing does not sculpt or add history")
	_motion(app, center, Vector2(10000, 0))
	_check(is_equal_approx(app.radius, app.radius_slider.max_value), "size clamps at maximum")
	_motion(app, center, Vector2(-10000, 0))
	_check(is_equal_approx(app.radius, app.radius_slider.min_value), "size clamps at minimum")
	_s_key(app, false)
	var stopped_size: float = app.radius
	_motion(app, center, Vector2(30, 0))
	_check(is_equal_approx(app.radius, stopped_size), "releasing S ends adjustment")
	_s_key(app, true)
	for i in range(5):
		_motion(app, center, Vector2(1, 0))
	_check(is_equal_approx(app.radius, stopped_size + 0.01), "small movements accumulate across slider steps")
	_s_key(app, false)
	app.radius_slider.value = 0.3
	_check(is_equal_approx(app.radius, 0.3), "slider still changes brush size")
	app._handle_mouse_button(click)
	_check(app.sculpting and app.model.vertices != vertices, "normal sculpting resumes")
	_s_key(app, true)
	_check(not app.sculpting and app.undo_history.size() == 1, "starting adjustment commits active stroke")
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not app.resizing_brush, "focus loss ends adjustment")
	app.free()
	print("Brush size tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
