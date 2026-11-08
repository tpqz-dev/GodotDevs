extends Node3D

const SculptMesh = preload("res://sculpt_mesh.gd")
const ObjIO = preload("res://obj_io.gd")
const BYTES_PER_VERTEX := 12
const MIB := 1024 * 1024
const SIZE_PER_PIXEL := 0.002

var model = SculptMesh.new()
var mesh_instance: MeshInstance3D
var wire_instance: MeshInstance3D
var camera: Camera3D
var cursor: MeshInstance3D
var radius := 0.3
var radius_slider: HSlider
var resizing_brush := false
var resize_value := 0.0
var strength := 0.5
var symmetry_x := false
var yaw := 0.0
var pitch := 0.0
var distance := 4.0
var target := Vector3.ZERO
var rotating := false
var panning := false
var sculpting := false
var last_sample := Vector2.ZERO
var sample_remainder := 0.0
var status: Label
var modified := false
var undo_button: Button
var redo_button: Button
var history_status: Label
var undo_history: Array[Dictionary] = []
var redo_history: Array[Dictionary] = []
var history_bytes := 0
var history_limit_bytes := 64 * MIB
var stroke_before := PackedVector3Array()
var current_state_id := 0
var next_state_id := 1
var saved_state_id := 0
var open_dialog: FileDialog
var save_dialog: FileDialog
var message_dialog: AcceptDialog
var open_confirm: ConfirmationDialog
var close_confirm: ConfirmationDialog


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_setup_world()
	_setup_ui()
	model.create_sphere()
	_refresh_mesh()
	_update_camera()


func _setup_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("252a32")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c2d0e0")
	env.ambient_light_energy = 0.5
	environment.environment = env
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.2
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20, 140, 0)
	fill.light_energy = 0.35
	add_child(fill)

	mesh_instance = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c7a38e")
	material.roughness = 0.8
	mesh_instance.material_override = material
	add_child(mesh_instance)

	wire_instance = MeshInstance3D.new()
	wire_instance.visible = false
	wire_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wire_shader := Shader.new()
	wire_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
void vertex() {
	VERTEX += NORMAL * 0.001;
}
void fragment() {
	ALBEDO = vec3(0.08, 0.09, 0.11);
	ALPHA = 0.08;
}
"""
	var wire_material := ShaderMaterial.new()
	wire_material.shader = wire_shader
	wire_instance.material_override = wire_material
	add_child(wire_instance)

	camera = Camera3D.new()
	camera.current = true
	add_child(camera)

	cursor = MeshInstance3D.new()
	cursor.visible = false
	var cursor_material := StandardMaterial3D.new()
	cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_material.albedo_color = Color("f6dc90")
	cursor_material.no_depth_test = true
	cursor.material_override = cursor_material
	add_child(cursor)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 266
	panel.offset_bottom = -16
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.text = "SCULPT  ·  Prototype"
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	open_dialog = FileDialog.new()
	open_dialog.title = "Ouvrir un fichier OBJ"
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.add_filter("*.obj", "Maillage OBJ")
	open_dialog.file_selected.connect(_load_obj)
	layer.add_child(open_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "Enregistrer au format OBJ"
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.add_filter("*.obj", "Maillage OBJ")
	save_dialog.file_selected.connect(_save_obj)
	layer.add_child(save_dialog)
	message_dialog = AcceptDialog.new()
	message_dialog.title = "Fichier OBJ"
	layer.add_child(message_dialog)
	open_confirm = ConfirmationDialog.new()
	open_confirm.title = "Ouvrir un fichier OBJ"
	open_confirm.dialog_text = "La sculpture actuelle et son historique seront remplacés. Continuer ?"
	open_confirm.confirmed.connect(func() -> void: open_dialog.call_deferred("popup_centered_ratio", 0.75))
	layer.add_child(open_confirm)
	close_confirm = ConfirmationDialog.new()
	close_confirm.title = "Fermer la sculpture"
	close_confirm.dialog_text = "La sculpture contient des modifications non enregistrées. Fermer sans enregistrer ?"
	close_confirm.confirmed.connect(func() -> void: get_tree().quit())
	layer.add_child(close_confirm)
	var file_buttons := HBoxContainer.new()
	column.add_child(file_buttons)
	var open_button := Button.new()
	open_button.text = "Ouvrir OBJ"
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(_request_open)
	file_buttons.add_child(open_button)
	var save_button := Button.new()
	save_button.text = "Enregistrer OBJ"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_request_save)
	file_buttons.add_child(save_button)
	var brush := Label.new()
	brush.text = "Pinceau : Standard"
	column.add_child(brush)
	radius_slider = _add_slider(column, "Taille", 0.08, 0.8, radius, func(value: float) -> void:
		radius = value
	)
	_add_slider(column, "Intensité", 0.05, 1.0, strength, func(value: float) -> void:
		strength = value
	)
	var symmetry_toggle := CheckBox.new()
	symmetry_toggle.text = "Symétrie X"
	symmetry_toggle.toggled.connect(func(enabled: bool) -> void:
		symmetry_x = enabled
	)
	column.add_child(symmetry_toggle)
	var history_buttons := HBoxContainer.new()
	column.add_child(history_buttons)
	undo_button = Button.new()
	undo_button.text = "Annuler"
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.pressed.connect(_undo)
	history_buttons.add_child(undo_button)
	redo_button = Button.new()
	redo_button.text = "Rétablir"
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_button.pressed.connect(_redo)
	history_buttons.add_child(redo_button)
	var limit_label := Label.new()
	limit_label.text = "Mémoire historique (Mio)"
	column.add_child(limit_label)
	var limit := SpinBox.new()
	limit.min_value = 1
	limit.max_value = 512
	limit.step = 1
	limit.value = 64
	limit.value_changed.connect(func(value: float) -> void:
		history_limit_bytes = int(value) * MIB
		_trim_history()
		history_status.text = ""
		_update_history_ui()
	)
	column.add_child(limit)
	history_status = Label.new()
	history_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(history_status)
	_update_history_ui()
	var reset := Button.new()
	reset.text = "Nouvelle sphère"
	var confirm := ConfirmationDialog.new()
	confirm.title = "Nouvelle sphère"
	confirm.dialog_text = "La sculpture actuelle et son historique seront perdus. Continuer ?"
	layer.add_child(confirm)
	confirm.confirmed.connect(_reset_sphere)
	reset.pressed.connect(func() -> void:
		if modified or not undo_history.is_empty() or not redo_history.is_empty():
			confirm.popup_centered()
		else:
			_reset_sphere()
	)
	column.add_child(reset)
	status = Label.new()
	column.add_child(status)
	var help := Label.new()
	help.text = "Clic gauche : sculpter\nAlt + clic : creuser\nMaj + clic : lisser\nS + mouvement horizontal : taille\nCtrl + O : ouvrir OBJ\nCtrl + S : enregistrer OBJ\nCtrl + Z : annuler\nCtrl + Y / Ctrl + Maj + Z : rétablir\nClic milieu : tourner\nMaj + clic milieu : déplacer\nMolette : zoom  ·  F : cadrer\nMaj + F : maillage"
	column.add_child(help)


func _add_slider(parent: VBoxContainer, title: String, minimum: float, maximum: float, value: float, callback: Callable) -> HSlider:
	var label := Label.new()
	label.text = "%s : %.2f" % [title, value]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size.x = 220
	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = "%s : %.2f" % [title, new_value]
		callback.call(new_value)
	)
	parent.add_child(slider)
	return slider


func _reset_sphere() -> void:
	_clear_history()
	model.create_sphere()
	modified = false
	_refresh_mesh()
	_frame_model()


func _clear_history() -> void:
	sculpting = false
	stroke_before.clear()
	undo_history.clear()
	redo_history.clear()
	history_bytes = 0
	current_state_id = 0
	next_state_id = 1
	saved_state_id = 0
	history_status.text = ""
	_update_history_ui()


func _request_open() -> void:
	_finish_stroke()
	if modified or not undo_history.is_empty() or not redo_history.is_empty():
		open_confirm.popup_centered()
	else:
		open_dialog.popup_centered_ratio(0.75)


func _request_save() -> void:
	_finish_stroke()
	save_dialog.popup_centered_ratio(0.75)


func _load_obj(path: String) -> void:
	var result: Dictionary = ObjIO.read_obj(path)
	if result.has("error"):
		_show_file_message("Échec de l'ouverture :\n%s" % result.error)
		return
	var imported = SculptMesh.new()
	imported.load_geometry(result.vertices, result.indices)
	model = imported
	_clear_history()
	modified = false
	cursor.visible = false
	_refresh_mesh()
	_frame_model()


func _save_obj(path: String) -> void:
	_finish_stroke()
	if path.get_extension().to_lower() != "obj":
		path += ".obj"
	var error: String = ObjIO.write_obj(path, model.vertices, model.indices)
	if not error.is_empty():
		_show_file_message("Enregistrement OBJ :\n%s" % error)
		return
	saved_state_id = current_state_id
	modified = false
	_show_file_message("Objet enregistré :\n%s" % path)


func _show_file_message(message: String) -> void:
	message_dialog.dialog_text = message
	message_dialog.call_deferred("popup_centered")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_finish_stroke()
		rotating = false
		panning = false
		resizing_brush = false
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finish_stroke()
		if modified:
			close_confirm.popup_centered()
		else:
			get_tree().quit()


func _finish_stroke() -> void:
	if not sculpting:
		return
	sculpting = false
	if stroke_before != model.vertices:
		history_status.text = ""
		for entry in redo_history:
			history_bytes -= entry.bytes
		redo_history.clear()
		var before_id := current_state_id
		current_state_id = next_state_id
		next_state_id += 1
		var bytes: int = (stroke_before.size() + model.vertices.size()) * BYTES_PER_VERTEX
		undo_history.append({
			"before": stroke_before,
			"after": model.vertices.duplicate(),
			"before_id": before_id,
			"after_id": current_state_id,
			"bytes": bytes,
		})
		history_bytes += bytes
		_trim_history()
		if undo_history.is_empty():
			history_status.text = "Trait trop volumineux pour la limite d'historique."
		modified = current_state_id != saved_state_id
	stroke_before = PackedVector3Array()
	_update_history_ui()


func _trim_history() -> void:
	while history_bytes > history_limit_bytes:
		if not undo_history.is_empty():
			history_bytes -= undo_history.pop_front().bytes
		elif not redo_history.is_empty():
			history_bytes -= redo_history.pop_front().bytes
		else:
			break


func _update_history_ui() -> void:
	if undo_button:
		undo_button.disabled = sculpting or undo_history.is_empty()
	if redo_button:
		redo_button.disabled = sculpting or redo_history.is_empty()
	if history_status and history_bytes <= history_limit_bytes:
		if not history_status.text.begins_with("Trait trop volumineux"):
			history_status.text = "Historique : %.1f / %.0f Mio" % [float(history_bytes) / MIB, float(history_limit_bytes) / MIB]


func _restore_history(snapshot: PackedVector3Array, state_id: int) -> void:
	model.restore_vertices(snapshot)
	current_state_id = state_id
	modified = current_state_id != saved_state_id
	history_status.text = ""
	cursor.visible = false
	_refresh_mesh()
	_update_history_ui()


func _undo() -> void:
	_finish_stroke()
	if undo_history.is_empty():
		return
	var entry: Dictionary = undo_history.pop_back()
	redo_history.append(entry)
	_restore_history(entry.before, entry.before_id)


func _redo() -> void:
	_finish_stroke()
	if redo_history.is_empty():
		return
	var entry: Dictionary = redo_history.pop_back()
	undo_history.append(entry)
	_restore_history(entry.after, entry.after_id)


func _refresh_mesh() -> void:
	mesh_instance.mesh = model.make_mesh()
	if wire_instance.visible:
		wire_instance.mesh = model.make_wire_mesh()
	if status:
		status.text = "%d sommets  ·  %d triangles" % [model.vertices.size(), model.indices.size() / 3]


func _update_camera() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = target + offset * distance
	camera.look_at(target, Vector3.UP)


func _frame_model() -> void:
	var bounds := AABB(model.vertices[0], Vector3.ZERO)
	for vertex in model.vertices:
		bounds = bounds.expand(vertex)
	target = bounds.get_center()
	var half_diagonal := bounds.size.length() * 0.5
	var viewport := get_viewport().get_visible_rect().size
	var vertical_fov := deg_to_rad(camera.fov)
	var horizontal_fov := 2.0 * atan(tan(vertical_fov * 0.5) * viewport.x / maxf(viewport.y, 1.0))
	distance = maxf(1.2, half_diagonal / sin(minf(vertical_fov, horizontal_fov) * 0.5) * 1.1)
	_update_camera()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed and event.keycode == KEY_S:
		resizing_brush = false
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_finish_stroke()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			rotating = false
			panning = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			_finish_stroke()
			rotating = false
			panning = false
			resizing_brush = true
			resize_value = radius
		elif event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if event.keycode == KEY_Z and event.shift_pressed:
				_redo()
			elif event.keycode == KEY_Z:
				_undo()
			elif event.keycode == KEY_Y and not event.shift_pressed:
				_redo()
			elif event.keycode == KEY_O and not event.shift_pressed:
				_request_open()
			elif event.keycode == KEY_S and not event.shift_pressed:
				_request_save()
		elif event.keycode == KEY_F and not event.alt_pressed and not event.meta_pressed:
			if event.shift_pressed:
				wire_instance.visible = not wire_instance.visible
				if wire_instance.visible:
					wire_instance.mesh = model.make_wire_mesh()
			else:
				_frame_model()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if resizing_brush and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if sculpting:
				_finish_stroke()
			sculpting = true
			stroke_before = model.vertices.duplicate()
			_update_history_ui()
			last_sample = event.position
			sample_remainder = 0.0
			_apply_at(event.position, event.alt_pressed, event.shift_pressed)
		MOUSE_BUTTON_MIDDLE:
			panning = event.shift_pressed
			rotating = not panning
			cursor.visible = false
		MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.2, distance * 0.9)
			_update_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(30.0, distance * 1.1)
			_update_camera()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if resizing_brush:
		resize_value = clampf(resize_value + event.relative.x * SIZE_PER_PIXEL, radius_slider.min_value, radius_slider.max_value)
		radius_slider.value = resize_value
		_update_cursor(event.position)
	elif rotating:
		yaw -= event.relative.x * 0.01
		pitch = clampf(pitch + event.relative.y * 0.01, -1.5, 1.5)
		_update_camera()
	elif panning:
		target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * distance * 0.0015
		_update_camera()
	elif sculpting:
		_sample_stroke(event.position, event.alt_pressed, event.shift_pressed)
	else:
		_update_cursor(event.position)


func _sample_stroke(position: Vector2, inverted: bool, smoothing: bool = false) -> void:
	var delta := position - last_sample
	var length := delta.length()
	if length < 0.001:
		return
	# Screen-space spacing scales with the projected brush radius.
	var center := camera.unproject_position(target)
	var edge := camera.unproject_position(target + camera.global_basis.x * radius)
	var spacing := maxf(2.0, center.distance_to(edge) * 0.18)
	var travelled := spacing - sample_remainder
	while travelled <= length:
		_apply_at(last_sample + delta * (travelled / length), inverted, smoothing)
		travelled += spacing
	sample_remainder = fmod(sample_remainder + length, spacing)
	last_sample = position


func _pick(screen_position: Vector2) -> Dictionary:
	return model.intersect_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))


func _apply_at(screen_position: Vector2, inverted: bool, smoothing: bool = false) -> void:
	var hit := _pick(screen_position)
	if hit.is_empty():
		cursor.visible = false
		return
	var changed: bool
	if smoothing:
		changed = model.apply_smooth(hit.position, radius, strength * 0.5, symmetry_x)
	else:
		var amount := strength * radius * 0.035 * (-1.0 if inverted else 1.0)
		changed = model.apply_standard(hit.position, hit.normal, radius, amount, symmetry_x)
	if changed:
		modified = true
		_refresh_mesh()
	_update_cursor(screen_position)


func _update_cursor(screen_position: Vector2) -> void:
	var hit := _pick(screen_position)
	if hit.is_empty():
		cursor.visible = false
		return
	var normal: Vector3 = hit.normal
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	var center: Vector3 = hit.position + normal * 0.005
	var ring := ImmediateMesh.new()
	ring.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(65):
		var angle := TAU * float(i) / 64.0
		ring.surface_add_vertex(center + radius * (tangent * cos(angle) + bitangent * sin(angle)))
	ring.surface_end()
	cursor.mesh = ring
	cursor.visible = true
