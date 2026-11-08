extends SceneTree

const ObjIO = preload("res://obj_io.gd")
var failures := 0
var test_paths: Array[String] = []
var prefix := ""


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)


func _path(name: String) -> String:
	var result := prefix + name + ".obj"
	test_paths.append(result)
	return result


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(contents)
	file.close()


func _run() -> void:
	prefix = ProjectSettings.globalize_path("user://obj-test-%d-%d-" % [Time.get_ticks_usec(), randi()])
	var quad_path := _path("quad")
	_write(quad_path, "v -1 -1 0\nv 1 -1 0\nv 1 1 0\nv -1 1 0\nf -4/1/1 -3/2/1 -2/3/1 -1/4/1\n")
	var quad: Dictionary = ObjIO.read_obj(quad_path)
	_check(not quad.has("error"), "OBJ quad with negative indices imports")
	if not quad.has("error"):
		_check(quad.indices.size() == 6 and quad.vertices.size() == 4, "quad triangulates into two triangles")
		var tri: PackedInt32Array = quad.indices
		var verts: PackedVector3Array = quad.vertices
		var cross: Vector3 = (verts[tri[2]] - verts[tri[0]]).cross(verts[tri[1]] - verts[tri[0]])
		_check(cross.z > 0.0, "OBJ front orientation becomes Godot clockwise winding")
	var concave_path := _path("concave")
	_write(concave_path, "v 0 0 0\nv 2 0 0\nv 2 2 0\nv 1 1 0\nv 0 2 0\nf 1 2 3 4 5\n")
	var concave: Dictionary = ObjIO.read_obj(concave_path)
	_check(not concave.has("error") and concave.get("indices", PackedInt32Array()).size() == 9, "concave polygon triangulates")
	_write(concave_path, "v 0 0 0\nv 2 0 0\nv 2 2 0\nv 1 1 0\nv 0 2 0\nf 5 4 3 2 1\n")
	var reverse: Dictionary = ObjIO.read_obj(concave_path)
	_check(not reverse.has("error"), "clockwise concave polygon imports")
	if not reverse.has("error"):
		var tri: PackedInt32Array = reverse.indices
		var verts: PackedVector3Array = reverse.vertices
		var normal: Vector3 = (verts[tri[2]] - verts[tri[0]]).cross(verts[tri[1]] - verts[tri[0]])
		_check(normal.z < 0.0, "clockwise OBJ face orientation is preserved")
	var bad_path := _path("bad")
	_write(bad_path, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 42\n")
	_check(ObjIO.read_obj(bad_path).has("error"), "invalid index is rejected")
	_write(bad_path, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\nf 1 2 3\n")
	_check(ObjIO.read_obj(bad_path).has("error"), "inconsistent edge winding is rejected")
	_write(bad_path, "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 -1 0\nv 0 0 1\nf 1 2 3\nf 2 1 4\nf 1 2 5\n")
	_check(ObjIO.read_obj(bad_path).has("error"), "non-manifold edge is rejected")
	_write(bad_path, "")
	_check(ObjIO.read_obj(bad_path).has("error"), "empty OBJ is rejected")
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var center := root.get_visible_rect().size / 2.0
	var original: PackedVector3Array = app.model.vertices.duplicate()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = center
	click.pressed = true
	app._handle_mouse_button(click)
	app._finish_stroke()
	var sculpted: PackedVector3Array = app.model.vertices.duplicate()
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check(app.close_confirm.visible, "closing with unsaved sculpture requests confirmation")
	app.close_confirm.hide()
	app._request_open()
	_check(app.open_confirm.visible and app.model.vertices == sculpted, "opening with changes requests confirmation")
	app.open_confirm.hide()
	app._save_obj(prefix + "missing-folder\\bad.obj")
	_check(app.modified and app.model.vertices == sculpted, "failed save retains dirty state")
	await process_frame
	app.message_dialog.hide()
	var exported_path := _path("sculpt")
	app._save_obj(exported_path)
	await process_frame
	app.message_dialog.hide()
	_check(not app.modified and FileAccess.file_exists(exported_path), "saving OBJ clears modified state")
	var saved: Dictionary = ObjIO.read_obj(exported_path)
	_check(not saved.has("error"), "exported sphere can be read")
	if not saved.has("error"):
		_check(saved.vertices == sculpted and saved.indices.size() == app.model.indices.size(), "OBJ round-trip preserves sculpted vertices and triangle count")
	_check(ObjIO.write_obj(exported_path, app.model.vertices, app.model.indices).is_empty(), "existing OBJ can be overwritten")
	app._undo()
	_check(app.modified and app.model.vertices == original, "undo after save marks geometry modified")
	app._redo()
	_check(not app.modified and app.model.vertices == sculpted, "redo to saved state clears modified flag")
	_write(bad_path, "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 42\n")
	app._load_obj(bad_path)
	_check(app.model.vertices == sculpted and not app.undo_history.is_empty(), "failed import preserves geometry and history")
	await process_frame
	app.message_dialog.hide()
	app._save_obj(prefix + "missing-folder\\bad.obj")
	_check(not app.modified and app.model.vertices == sculpted, "failed save preserves saved state and geometry")
	await process_frame
	app.message_dialog.hide()
	app._load_obj(exported_path)
	_check(app.model.vertices == sculpted and app.undo_history.is_empty() and not app.modified, "successful import replaces mesh and clears history")
	var hit: Dictionary = app._pick(center)
	_check(not hit.is_empty() and hit.normal.z > 0.9, "imported mesh has outward normals and is pickable")
	app._handle_mouse_button(click)
	app._finish_stroke()
	_check(app.model.vertices != sculpted and app.undo_history.size() == 1, "imported OBJ is sculptable and undoable")
	app._undo()
	_check(app.model.vertices == sculpted and not app.modified, "undo returns imported mesh to saved state")
	app._load_obj(quad_path)
	_check(app.model.vertices.size() == 4 and app.model.indices.size() == 6, "opening different OBJ replaces topology")
	var save_key := InputEventKey.new()
	save_key.keycode = KEY_S
	save_key.ctrl_pressed = true
	save_key.pressed = true
	app._unhandled_input(save_key)
	_check(app.save_dialog.visible and not app.resizing_brush, "Ctrl+S opens the save dialog")
	app.save_dialog.hide()
	var open_key := InputEventKey.new()
	open_key.keycode = KEY_O
	open_key.ctrl_pressed = true
	open_key.pressed = true
	app._unhandled_input(open_key)
	_check(app.open_dialog.visible, "Ctrl+O opens the file dialog")
	app.open_dialog.hide()
	app.free()
	for path in test_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("OBJ tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
