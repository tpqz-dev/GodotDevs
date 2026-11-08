extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_back;
varying float local_z;
void vertex() { local_z = VERTEX.z; }
void fragment() { ALBEDO = local_z > 0.0 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0); }
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	app.mesh_instance.material_override = material
	var center := root.get_visible_rect().size / 2.0
	var failures := 0
	for step in range(2):
		if step == 1:
			app._apply_at(center, false)
		for i in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		if pixel.g <= pixel.r or pixel.g < 0.5:
			printerr("FAIL: front surface is not visible at step ", step, ": ", pixel)
			failures += 1
		else:
			print("PASS: front surface renders with back-face culling at step ", step)
	app.free()
	quit(1 if failures else 0)
