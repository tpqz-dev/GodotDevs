extends RefCounted

const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_VERTICES := 500000
const MAX_TRIANGLES := 500000
const MAX_FACE_VERTICES := 4096


static func read_obj(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Impossible d'ouvrir le fichier : %s" % error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_FILE_BYTES:
		return {"error": "Fichier trop volumineux (limite : 64 Mio)."}
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var edges := {}
	var line_number := 0
	while file.get_position() < file.get_length():
		var line := file.get_line().get_slice("#", 0).strip_edges()
		line_number += 1
		if line.is_empty():
			continue
		var words := line.split(" ", false)
		var normalized := line.replace("\t", " ")
		words = normalized.split(" ", false)
		match words[0]:
			"v":
				if words.size() < 4 or words.size() > 5:
					return _line_error(line_number, "sommet invalide")
				if not words[1].is_valid_float() or not words[2].is_valid_float() or not words[3].is_valid_float():
					return _line_error(line_number, "coordonnées de sommet invalides")
				var vertex := Vector3(words[1].to_float(), words[2].to_float(), words[3].to_float())
				if not vertex.is_finite() or (words.size() == 5 and (not words[4].is_valid_float() or words[4].to_float() != 1.0)):
					return _line_error(line_number, "coordonnées non finies ou poids de sommet non pris en charge")
				vertices.append(vertex)
				if vertices.size() > MAX_VERTICES:
					return _line_error(line_number, "limite de 500 000 sommets dépassée")
			"f":
				if words.size() < 4 or words.size() > MAX_FACE_VERTICES + 1:
					return _line_error(line_number, "face invalide ou trop grande")
				var face := PackedInt32Array()
				var unique := {}
				for token in words.slice(1):
					var parts := token.split("/", true)
					if parts.size() > 3 or not parts[0].is_valid_int():
						return _line_error(line_number, "indice de face invalide")
					var raw_index := parts[0].to_int()
					var index := raw_index - 1 if raw_index > 0 else vertices.size() + raw_index
					if raw_index == 0 or index < 0 or index >= vertices.size() or unique.has(index):
						return _line_error(line_number, "indice de sommet hors limites ou répété")
					unique[index] = true
					face.append(index)
				var result := _triangulate(face, vertices)
				if result.has("error"):
					return _line_error(line_number, result.error)
				for triangle in result.triangles:
					var a: int = triangle.x
					var b: int = triangle.y
					var c: int = triangle.z
					for edge in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
						var key := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
						var direction := 1 if edge.x < edge.y else -1
						if edges.has(key):
							if edges[key] == 0 or edges[key] == direction:
								return _line_error(line_number, "arête non-manifold ou faces d'orientation incohérente")
							edges[key] = 0
						else:
							edges[key] = direction
					# OBJ uses counter-clockwise front faces; Godot uses clockwise.
					indices.append_array(PackedInt32Array([a, c, b]))
					if indices.size() / 3 > MAX_TRIANGLES:
						return _line_error(line_number, "limite de 500 000 triangles dépassée")
			"vp", "curv", "curv2", "surf", "parm", "trim", "hole", "scrv", "sp", "end":
				return _line_error(line_number, "géométrie non polygonale non prise en charge")
	if file.get_error() != OK and file.get_error() != ERR_FILE_EOF:
		return {"error": "Erreur de lecture : %s" % error_string(file.get_error())}
	if vertices.is_empty() or indices.is_empty():
		return {"error": "Le fichier ne contient aucun maillage polygonal."}
	var referenced := PackedByteArray()
	referenced.resize(vertices.size())
	for index in indices:
		referenced[index] = 1
	for value in referenced:
		if value == 0:
			return {"error": "Le maillage contient des sommets non utilisés ; supprimez-les avant l'import."}
	return {"vertices": vertices, "indices": indices}


static func _line_error(line: int, message: String) -> Dictionary:
	return {"error": "Ligne %d : %s." % [line, message]}


static func _triangulate(face: PackedInt32Array, vertices: PackedVector3Array) -> Dictionary:
	var normal := Vector3.ZERO
	for i in range(face.size()):
		var a := vertices[face[i]]
		var b := vertices[face[(i + 1) % face.size()]]
		normal.x += (a.y - b.y) * (a.z + b.z)
		normal.y += (a.z - b.z) * (a.x + b.x)
		normal.z += (a.x - b.x) * (a.y + b.y)
	if normal.length_squared() < 1e-20:
		return {"error": "face dégénérée"}
	var projection := PackedVector2Array()
	var axis := normal.abs().max_axis_index()
	for index in face:
		var vertex := vertices[index]
		if axis == Vector3.AXIS_X:
			projection.append(Vector2(vertex.y, vertex.z))
		elif axis == Vector3.AXIS_Y:
			projection.append(Vector2(vertex.z, vertex.x))
		else:
			projection.append(Vector2(vertex.x, vertex.y))
	var tessellation := Geometry2D.triangulate_polygon(projection)
	if tessellation.size() != (face.size() - 2) * 3:
		return {"error": "face impossible à trianguler"}
	var orientation := 0.0
	for i in range(projection.size()):
		orientation += projection[i].cross(projection[(i + 1) % projection.size()])
	var triangles: Array[Vector3i] = []
	for i in range(0, tessellation.size(), 3):
		var a := face[tessellation[i]]
		var b := face[tessellation[i + 1]]
		var c := face[tessellation[i + 2]]
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() < 1e-20:
			return {"error": "triangle dégénéré"}
		if orientation < 0.0:
			triangles.append(Vector3i(a, c, b))
		else:
			triangles.append(Vector3i(a, b, c))
	return {"triangles": triangles}


static func write_obj(path: String, vertices: PackedVector3Array, indices: PackedInt32Array) -> String:
	var temporary := _unique_path(path, "tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Impossible de créer le fichier temporaire : %s" % error_string(FileAccess.get_open_error())
	file.store_line("# Sculpt OBJ")
	for vertex in vertices:
		file.store_line("v %s %s %s" % [String.num_scientific(vertex.x), String.num_scientific(vertex.y), String.num_scientific(vertex.z)])
	for i in range(0, indices.size(), 3):
		file.store_line("f %d %d %d" % [indices[i] + 1, indices[i + 2] + 1, indices[i + 1] + 1])
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Échec de l'écriture : %s" % error_string(write_error)
	var backup := ""
	if FileAccess.file_exists(path):
		backup = _unique_path(path, "backup")
		var backup_error := DirAccess.rename_absolute(path, backup)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary)
			return "Impossible de préserver le fichier existant : %s" % error_string(backup_error)
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		var restore_error := OK
		if not backup.is_empty():
			restore_error = DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temporary)
		if restore_error != OK:
			return "Échec de remplacement. L'ancien fichier est conservé ici : %s" % backup
		return "Impossible de finaliser le fichier : %s" % error_string(rename_error)
	if not backup.is_empty():
		var cleanup_error := DirAccess.remove_absolute(backup)
		if cleanup_error != OK:
			return "Fichier enregistré, mais impossible de supprimer la copie de sécurité : %s" % backup
	return ""


static func _unique_path(path: String, suffix: String) -> String:
	var candidate := ""
	while true:
		candidate = "%s.sculpt-%s-%d-%d" % [path, suffix, Time.get_ticks_usec(), randi()]
		if not FileAccess.file_exists(candidate) and not DirAccess.dir_exists_absolute(candidate):
			return candidate
	return candidate
