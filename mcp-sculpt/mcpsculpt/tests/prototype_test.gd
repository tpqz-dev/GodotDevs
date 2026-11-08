extends SceneTree

const SculptMesh = preload("res://sculpt_mesh.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)


func _brute_force_hit(model, origin: Vector3, direction: Vector3) -> Variant:
	var nearest: Variant = null
	var closest := INF
	for i in range(0, model.indices.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(
			origin, origin + direction.normalized() * 10000.0,
			model.vertices[model.indices[i]], model.vertices[model.indices[i + 1]],
			model.vertices[model.indices[i + 2]]
		)
		if hit != null and origin.distance_squared_to(hit) < closest:
			closest = origin.distance_squared_to(hit)
			nearest = hit
	return nearest


func _test_symmetry() -> void:
	var model = SculptMesh.new()
	model.create_sphere(64, 32)
	var original: PackedVector3Array = model.vertices.duplicate()
	var right_index := 1 + 15 * 64 + 10
	var left_index := 1 + 15 * 64 + 22
	var center: Vector3 = original[right_index]
	var normal := center.normalized()
	model.apply_standard(center, normal, 0.25, 0.05, true)
	var right: Vector3 = model.vertices[right_index] - original[right_index]
	var left: Vector3 = model.vertices[left_index] - original[left_index]
	_check(right.length() > 0.04 and left.length() > 0.04, "X symmetry applies brush on both sides")
	_check(Vector3(-right.x, right.y, right.z).distance_to(left) < 0.00001, "X symmetry mirrors displacement")
	var mirrored_hit: Dictionary = model.intersect_ray(original[left_index] * 4.0, -original[left_index])
	_check(not mirrored_hit.is_empty() and mirrored_hit.position.length() > 1.02, "raycast reaches mirrored deformation")
	model.create_sphere(64, 32)
	model.apply_standard(center, normal, 0.25, -0.05, true)
	_check(model.vertices[right_index].length() < 0.99 and model.vertices[left_index].length() < 0.99, "X symmetry also carves both sides")
	model.create_sphere(64, 32)
	model.apply_standard(center, normal, 0.25, 0.05, false)
	_check(model.vertices[left_index].distance_to(original[left_index]) < 0.00001, "disabled symmetry leaves opposite side unchanged")
	model.create_sphere(64, 32)
	var seam_index := 1 + 15 * 64 + 16
	model.apply_standard(original[seam_index], Vector3.BACK, 0.25, 0.05, true)
	_check(absf(model.vertices[seam_index].z - original[seam_index].z - 0.05) < 0.00001, "seam brush strength is not doubled")
	model.create_sphere(64, 32)
	model.apply_standard(Vector3(0.08, 0.0, 0.98), Vector3(0.2, 0.0, 0.98).normalized(), 0.3, 0.05, true)
	_check(absf(model.vertices[seam_index].x - original[seam_index].x) < 0.00001, "overlap does not pull seam sideways")
	var mirror_consistent := true
	for ring in range(31):
		for segment in range(64):
			var a := 1 + ring * 64 + segment
			var b := 1 + ring * 64 + (32 - segment + 64) % 64
			var reflected := Vector3(-model.vertices[a].x, model.vertices[a].y, model.vertices[a].z)
			if reflected.distance_to(model.vertices[b]) > 0.00001:
				mirror_consistent = false
				break
	_check(mirror_consistent, "overlapping brush preserves mirrored geometry")


func _test_smoothing() -> void:
	var model = SculptMesh.new()
	model.create_sphere(64, 32)
	var right_index := 1 + 15 * 64 + 10
	var left_index := 1 + 15 * 64 + 22
	var right: Vector3 = model.vertices[right_index]
	var left: Vector3 = model.vertices[left_index]
	model.apply_standard(right, right.normalized(), 0.1, 0.15, true)
	var raised_right: Vector3 = model.vertices[right_index]
	var raised_left: Vector3 = model.vertices[left_index]
	var untouched: Vector3 = model.vertices[0]
	_check(model.apply_smooth(raised_right, 0.2, 0.5, true), "smooth modifies surface")
	_check(model.vertices[right_index].length() < raised_right.length() and model.vertices[left_index].length() < raised_left.length(), "smooth reduces mirrored bumps")
	_check(model.vertices[0] == untouched, "smooth leaves vertices outside brush untouched")
	var mirrored: Vector3 = model.vertices[right_index]
	mirrored.x = -mirrored.x
	_check(mirrored.distance_to(model.vertices[left_index]) < 0.00001, "smooth preserves X symmetry")
	var fast_hit: Dictionary = model.intersect_ray(right * 4.0, -right)
	var brute_hit: Variant = _brute_force_hit(model, right * 4.0, -right)
	_check(not fast_hit.is_empty() and brute_hit != null and fast_hit.position.distance_to(brute_hit) < 0.00001, "raycast remains correct after smoothing")
	var before: PackedVector3Array = model.vertices.duplicate()
	_check(not model.apply_smooth(raised_right, 0.2, 0.0, true) and model.vertices == before, "zero-intensity smoothing is a no-op")
	model.apply_smooth(raised_right, 0.2, 0.2, false)
	var weak_displacement: float = model.vertices[right_index].distance_to(before[right_index])
	model.vertices = before.duplicate()
	model.apply_smooth(raised_right, 0.2, 0.8, false)
	var strong_displacement: float = model.vertices[right_index].distance_to(before[right_index])
	_check(strong_displacement > weak_displacement, "smooth responds to intensity")
	model.create_sphere(64, 32)
	model.apply_standard(right, right.normalized(), 0.1, 0.15, true)
	var left_before: Vector3 = model.vertices[left_index]
	model.apply_smooth(model.vertices[right_index], 0.2, 0.5, false)
	_check(model.vertices[left_index] == left_before, "smoothing without symmetry leaves opposite side alone")
	var seam := Vector3(0, 0, 1)
	var source: PackedVector3Array = model.vertices.duplicate()
	model.apply_smooth(seam, 0.3, 0.5, false)
	var single_dab: PackedVector3Array = model.vertices.duplicate()
	model.vertices = source.duplicate()
	model.apply_smooth(seam, 0.3, 0.5, true)
	_check(model.vertices == single_dab, "seam smoothing is not doubled by symmetry")


func _run() -> void:
	_test_symmetry()
	_test_smoothing()
	var model = SculptMesh.new()
	model.create_sphere(64, 32)
	_check(model.vertices.size() == 1986, "sphere vertex count")
	_check(model.indices.size() / 3 == 3968, "sphere triangle count")
	_check(model.normals[0].dot(Vector3.UP) > 0.99, "outward normals")
	var correct_winding := true
	var correct_vertex_normals := true
	for i in range(0, model.indices.size(), 3):
		var a: Vector3 = model.vertices[model.indices[i]]
		var b: Vector3 = model.vertices[model.indices[i + 1]]
		var c: Vector3 = model.vertices[model.indices[i + 2]]
		if (b - a).cross(c - a).dot(a + b + c) >= 0.0:
			correct_winding = false
			break
	for i in range(model.vertices.size()):
		if model.normals[i].dot(model.vertices[i]) <= 0.0:
			correct_vertex_normals = false
			break
	_check(correct_winding, "every triangle faces outward with Godot clockwise winding")
	_check(correct_vertex_normals, "every vertex normal points outward")
	var edges := {}
	for i in range(0, model.indices.size(), 3):
		for j in range(3):
			var a: int = model.indices[i + j]
			var b: int = model.indices[i + (j + 1) % 3]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edges[edge] = edges.get(edge, 0) + 1
	var closed := true
	for count in edges.values():
		if count != 2:
			closed = false
			break
	_check(closed, "sphere has no boundary or non-manifold edges")
	var hit: Dictionary = model.intersect_ray(Vector3(0, 0, 4), Vector3.FORWARD)
	_check(not hit.is_empty(), "front ray hits sphere")
	if not hit.is_empty():
		_check(hit.normal.dot(Vector3.BACK) > 0.9, "front face normal")
		var before: Vector3 = model.vertices[1 + 15 * 64 + 16]
		_check(model.apply_standard(hit.position, hit.normal, 0.3, 0.05), "standard brush changes geometry")
		var after: Vector3 = model.vertices[1 + 15 * 64 + 16]
		_check(after.z > before.z, "standard brush adds volume")
		_check(model.apply_standard(hit.position, hit.normal, 0.3, -0.05), "inverted brush changes geometry")
		_check(model.vertices[1 + 15 * 64 + 16].z < after.z, "inverted brush removes volume")
		model.create_sphere(64, 32)
		var baseline: PackedVector3Array = model.vertices.duplicate()
		model.apply_standard(hit.position, hit.normal, 0.15, 0.01)
		var small := 0
		for i in range(model.vertices.size()):
			if model.vertices[i] != baseline[i]:
				small += 1
		var weak_displacement: float = model.vertices[1 + 15 * 64 + 16].distance_to(baseline[1 + 15 * 64 + 16])
		model.create_sphere(64, 32)
		model.apply_standard(hit.position, hit.normal, 0.3, 0.05)
		var large := 0
		for i in range(model.vertices.size()):
			if model.vertices[i] != baseline[i]:
				large += 1
		var strong_displacement: float = model.vertices[1 + 15 * 64 + 16].distance_to(baseline[1 + 15 * 64 + 16])
		_check(large > small, "larger brush affects more vertices")
		_check(strong_displacement > weak_displacement, "greater intensity increases displacement")
	_check(model.intersect_ray(Vector3(0, 0, 4), Vector3.UP).is_empty(), "missed ray")
	var cardinal_ray_normals_outward := true
	for direction in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var axis_hit: Dictionary = model.intersect_ray(direction * 4.0, -direction)
		if axis_hit.is_empty() or axis_hit.normal.dot(direction) < 0.95:
			cardinal_ray_normals_outward = false
	_check(cardinal_ray_normals_outward, "brush hit normals point outward from all sides")
	var displaced_hit: Dictionary = model.intersect_ray(Vector3(0, 0, 4), Vector3.FORWARD)
	if not displaced_hit.is_empty():
		for i in range(3):
			model.apply_standard(displaced_hit.position, displaced_hit.normal, 0.5, 0.4)
	var ray_results_match := true
	for i in range(40):
		var angle := TAU * float(i) / 40.0
		var origin := Vector3(cos(angle) * 4.0, sin(angle * 3.0) * 2.0, sin(angle) * 4.0)
		var direction := (-origin + Vector3(0.3 * sin(angle * 5.0), 0.1, 0.0)).normalized()
		var fast_hit: Dictionary = model.intersect_ray(origin, direction)
		var brute_hit: Variant = _brute_force_hit(model, origin, direction)
		if (brute_hit == null) != fast_hit.is_empty():
			ray_results_match = false
		elif brute_hit != null and fast_hit.position.distance_to(brute_hit) > 0.0001:
			ray_results_match = false
	_check(ray_results_match, "accelerated raycasts match brute force after deformation")

	var scene := load("res://main.tscn") as PackedScene
	var app = scene.instantiate()
	root.add_child(app)
	await process_frame
	_check(app.mesh_instance.mesh != null, "scene builds visible mesh")
	var toggles := app.find_children("*", "CheckBox", true, false)
	_check(toggles.size() == 1 and not app.symmetry_x, "X symmetry is available and disabled by default")
	if toggles.size() == 1:
		var toggle: CheckBox = toggles[0]
		toggle.button_pressed = true
		_check(app.symmetry_x, "X symmetry control enables symmetry")
		var right_screen: Vector2 = app.camera.unproject_position(Vector3(0.4, 0.0, 0.9165))
		var left_screen: Vector2 = app.camera.unproject_position(Vector3(-0.4, 0.0, 0.9165))
		var before_right: Dictionary = app._pick(right_screen)
		var before_left: Dictionary = app._pick(left_screen)
		if not before_right.is_empty() and not before_left.is_empty():
			app._apply_at(right_screen, false)
			var after_right: Dictionary = app._pick(right_screen)
			var after_left: Dictionary = app._pick(left_screen)
			_check(not after_right.is_empty() and not after_left.is_empty() and after_right.position.z > before_right.position.z and after_left.position.z > before_left.position.z, "enabled symmetry mirrors viewport strokes")
			app._reset_sphere()
		else:
			_check(false, "symmetry test rays hit both sides")
		toggle.button_pressed = false
		_check(not app.symmetry_x, "X symmetry control disables symmetry")
	_check(app.model.indices.size() / 3 == 30000, "startup sphere has 30000 triangles")
	_check(not app.wire_instance.visible, "wireframe initially hidden")
	var shift_f := InputEventKey.new()
	shift_f.keycode = KEY_F
	shift_f.pressed = true
	shift_f.shift_pressed = true
	var initial_target: Vector3 = app.target
	app._unhandled_input(shift_f)
	_check(app.wire_instance.visible, "shift+F shows wireframe")
	_check(app.target == initial_target, "shift+F does not frame model")
	_check(app.wire_instance.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES, "wireframe draws edges")
	_check(app.wire_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 180000, "wireframe includes triangle edges")
	app._unhandled_input(shift_f)
	_check(not app.wire_instance.visible, "shift+F hides wireframe")
	var frame_key := InputEventKey.new()
	frame_key.keycode = KEY_F
	frame_key.pressed = true
	app.target = Vector3(1, 0, 0)
	app._unhandled_input(frame_key)
	_check(app.target.length() < 0.001 and not app.wire_instance.visible, "F frames without toggling wireframe")
	var center := root.get_visible_rect().size / 2.0
	var pick_start := Time.get_ticks_usec()
	var app_hit: Dictionary = app._pick(center)
	print("High-resolution ray pick: %.2f ms" % ((Time.get_ticks_usec() - pick_start) / 1000.0))
	if app_hit.is_empty():
		print("Viewport: ", root.get_visible_rect(), " camera origin: ", app.camera.project_ray_origin(center), " ray: ", app.camera.project_ray_normal(center))
	_check(not app_hit.is_empty(), "camera picks sphere at viewport center")
	if not app_hit.is_empty():
		var original: PackedVector3Array = app.model.vertices.duplicate()
		var click := InputEventMouseButton.new()
		click.position = center
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.alt_pressed = true
		app._handle_mouse_button(click)
		var carved: Dictionary = app._pick(center)
		_check(carved.position.z < app_hit.position.z, "alt+click removes volume")
		app._reset_sphere()
		click.alt_pressed = false
		click.shift_pressed = true
		app._apply_at(center, false)
		var before_smooth: Dictionary = app._pick(center)
		app._handle_mouse_button(click)
		var smoothed: Dictionary = app._pick(center)
		_check(smoothed.position.z < before_smooth.position.z, "shift+click smooths a raised area")
		var smooth_snapshot: PackedVector3Array = app.model.vertices.duplicate()
		var smooth_motion := InputEventMouseMotion.new()
		smooth_motion.position = center + Vector2(20, 0)
		smooth_motion.shift_pressed = true
		app._handle_mouse_motion(smooth_motion)
		_check(app.model.vertices != smooth_snapshot, "shift+drag continues smoothing")
		var before_release: PackedVector3Array = app.model.vertices.duplicate()
		smooth_motion.position = center + Vector2(40, 0)
		smooth_motion.shift_pressed = false
		app._handle_mouse_motion(smooth_motion)
		var resumed_standard := false
		for i in range(app.model.vertices.size()):
			if app.model.vertices[i].z > before_release[i].z + 0.000001:
				resumed_standard = true
				break
		_check(resumed_standard, "releasing shift resumes standard brush mid-stroke")
		app._reset_sphere()
		app._apply_at(center, false)
		click.alt_pressed = true
		app._handle_mouse_button(click)
		var smooth_alt: Dictionary = app._pick(center)
		_check(smooth_alt.position.z < before_smooth.position.z, "shift+alt uses smoothing")
		app._reset_sphere()
		click.shift_pressed = false
		click.alt_pressed = true
		app._handle_mouse_button(click)
		var motion_before: PackedVector3Array = app.model.vertices.duplicate()
		var sculpt_motion := InputEventMouseMotion.new()
		sculpt_motion.position = center + Vector2(20, 0)
		sculpt_motion.alt_pressed = true
		app._handle_mouse_motion(sculpt_motion)
		var removed_during_motion := false
		for i in range(app.model.vertices.size()):
			if app.model.vertices[i].z < motion_before[i].z - 0.000001:
				removed_during_motion = true
				break
		_check(removed_during_motion, "alt+drag removes volume during motion")
		app.sculpting = false
		app._reset_sphere()
		var brush_start := Time.get_ticks_usec()
		app._apply_at(center, false)
		print("High-resolution brush sample: %.2f ms" % ((Time.get_ticks_usec() - brush_start) / 1000.0))
		_check(app.model.vertices != original, "viewport stroke deforms mesh")
		_check(app.modified, "sculpt marks model modified")
		app._unhandled_input(shift_f)
		_check(app.wire_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == app.model.vertices, "wireframe matches deformed geometry")
		app._apply_at(center, false)
		_check(app.wire_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == app.model.vertices, "visible wireframe updates during sculpt")
		app._reset_sphere()
		_check(app.wire_instance.visible and app.wire_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == app.model.vertices, "visible wireframe updates on reset")
		app._unhandled_input(shift_f)
		app._reset_sphere()
		_check(app.model.vertices == original, "reset restores sphere")
		_check(app.model.indices.size() / 3 == 30000, "reset sphere has 30000 triangles")
		_check(not app.modified, "reset clears modified state")
		app.target = Vector3(3, 2, 1)
		app._update_camera()
		app._frame_model()
		_check(app.target.length() < 0.001, "frame recenters model")
		var yaw_before: float = app.yaw
		app.rotating = true
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, 10)
		app._handle_mouse_motion(motion)
		_check(app.yaw != yaw_before, "middle-drag orbit changes camera")
		app.rotating = false
		var target_before: Vector3 = app.target
		app.panning = true
		app._handle_mouse_motion(motion)
		_check(app.target != target_before, "middle-drag pan changes target")
		app.panning = false
		var wheel := InputEventMouseButton.new()
		wheel.pressed = true
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		var distance_before: float = app.distance
		app._handle_mouse_button(wheel)
		_check(app.distance < distance_before, "wheel zooms camera")
		app._frame_model()
		var stroke_start := root.get_visible_rect().size / 2.0
		app.last_sample = stroke_start
		app.sample_remainder = 0.0
		app._sample_stroke(stroke_start + Vector2(20, 0), false)
		var single_motion: PackedVector3Array = app.model.vertices.duplicate()
		app._reset_sphere()
		app.last_sample = stroke_start
		app.sample_remainder = 0.0
		app._sample_stroke(stroke_start + Vector2(10, 0), false)
		app._sample_stroke(stroke_start + Vector2(20, 0), false)
		_check(app.model.vertices == single_motion, "stroke sampling is independent of motion event count")
	app.free()
	print("Prototype tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
