extends RefCounted

const TRIANGLES_PER_BLOCK := 64

var vertices := PackedVector3Array()
var indices := PackedInt32Array()
var normals := PackedVector3Array()
var wire_indices := PackedInt32Array()
var triangle_bounds: Array[AABB] = []
var neighbor_offsets := PackedInt32Array()
var neighbors := PackedInt32Array()


func create_sphere(segments: int = 150, rings: int = 101) -> void:
	vertices.clear()
	indices.clear()
	wire_indices.clear()
	vertices.append(Vector3.UP)
	for ring in range(1, rings):
		var theta := PI * float(ring) / float(rings)
		for segment in range(segments):
			var phi := TAU * float(segment) / float(segments)
			vertices.append(Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)))
	vertices.append(Vector3.DOWN)

	for segment in range(segments):
		var next := (segment + 1) % segments
		indices.append_array(PackedInt32Array([0, 1 + segment, 1 + next]))
		for ring in range(rings - 2):
			var a := 1 + ring * segments + segment
			var b := 1 + ring * segments + next
			var c := a + segments
			var d := b + segments
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
		var last := 1 + (rings - 2) * segments
		indices.append_array(PackedInt32Array([last + segment, vertices.size() - 1, last + next]))
	recalculate_normals()
	_rebuild_triangle_bounds()
	_build_neighbors()


func load_geometry(new_vertices: PackedVector3Array, new_indices: PackedInt32Array) -> void:
	vertices = new_vertices.duplicate()
	indices = new_indices.duplicate()
	wire_indices.clear()
	recalculate_normals()
	_rebuild_triangle_bounds()
	_build_neighbors()


func _build_neighbors() -> void:
	var adjacency := []
	adjacency.resize(vertices.size())
	for i in range(adjacency.size()):
		adjacency[i] = {}
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		adjacency[a][b] = true
		adjacency[a][c] = true
		adjacency[b][a] = true
		adjacency[b][c] = true
		adjacency[c][a] = true
		adjacency[c][b] = true
	neighbor_offsets.resize(vertices.size() + 1)
	var count := 0
	for i in range(vertices.size()):
		neighbor_offsets[i] = count
		count += adjacency[i].size()
	neighbor_offsets[vertices.size()] = count
	neighbors.resize(count)
	var cursor := 0
	for adjacent in adjacency:
		for vertex_index in adjacent:
			neighbors[cursor] = vertex_index
			cursor += 1


func _rebuild_triangle_bounds() -> void:
	triangle_bounds.clear()
	var block_indices := TRIANGLES_PER_BLOCK * 3
	for start in range(0, indices.size(), block_indices):
		var bounds := AABB(vertices[indices[start]], Vector3.ZERO)
		for i in range(start + 1, mini(start + block_indices, indices.size())):
			bounds = bounds.expand(vertices[indices[i]])
		triangle_bounds.append(bounds.grow(0.00001))


func restore_vertices(snapshot: PackedVector3Array) -> void:
	assert(snapshot.size() == vertices.size())
	vertices = snapshot.duplicate()
	recalculate_normals()
	_rebuild_triangle_bounds()


func recalculate_normals() -> void:
	normals.resize(vertices.size())
	normals.fill(Vector3.ZERO)
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		# Godot treats clockwise triangle winding as front-facing.
		var face_normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized()


func make_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func make_wire_mesh() -> ArrayMesh:
	if wire_indices.is_empty():
		wire_indices.resize(indices.size() * 2)
		for i in range(0, indices.size(), 3):
			var j := i * 2
			wire_indices[j] = indices[i]
			wire_indices[j + 1] = indices[i + 1]
			wire_indices[j + 2] = indices[i + 1]
			wire_indices[j + 3] = indices[i + 2]
			wire_indices[j + 4] = indices[i + 2]
			wire_indices[j + 5] = indices[i]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = wire_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func intersect_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	var closest := INF
	var result := {}
	var end := origin + direction.normalized() * 10000.0
	var block_indices := TRIANGLES_PER_BLOCK * 3
	for block in range(triangle_bounds.size()):
		if not triangle_bounds[block].intersects_segment(origin, end):
			continue
		var start := block * block_indices
		for i in range(start, mini(start + block_indices, indices.size()), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(
				origin, end, vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]
			)
			if hit == null:
				continue
			var distance := origin.distance_squared_to(hit)
			if distance < closest:
				closest = distance
				var a := vertices[indices[i]]
				var b := vertices[indices[i + 1]]
				var c := vertices[indices[i + 2]]
				result = {"position": hit, "normal": (c - a).cross(b - a).normalized()}
	return result


func apply_standard(center: Vector3, normal: Vector3, radius: float, amount: float, symmetry_x: bool = false) -> bool:
	if radius <= 0.0 or amount == 0.0:
		return false
	var changed := false
	var mirror_center := Vector3(-center.x, center.y, center.z)
	var mirror_normal := Vector3(-normal.x, normal.y, normal.z)
	for i in range(vertices.size()):
		var distance := vertices[i].distance_to(center)
		var weight := 1.0 - smoothstep(0.0, radius, distance) if distance < radius else 0.0
		var mirror_distance := vertices[i].distance_to(mirror_center) if symmetry_x else radius
		var mirror_weight := 1.0 - smoothstep(0.0, radius, mirror_distance) if mirror_distance < radius else 0.0
		var total := weight + mirror_weight
		if total <= 0.0:
			continue
		# Blend overlapping dabs rather than doubling their strength at the seam.
		var displacement := (normal * weight + mirror_normal * mirror_weight) * (maxf(weight, mirror_weight) / total)
		vertices[i] += displacement * amount
		changed = true
	if changed:
		_finish_deformation(center, mirror_center, radius, absf(amount), symmetry_x)
	return changed


func apply_smooth(center: Vector3, radius: float, intensity: float, symmetry_x: bool = false) -> bool:
	if radius <= 0.0 or intensity <= 0.0:
		return false
	var source := vertices.duplicate()
	var mirror_center := Vector3(-center.x, center.y, center.z)
	var max_displacement := 0.0
	for i in range(source.size()):
		var distance := source[i].distance_to(center)
		var weight := 1.0 - smoothstep(0.0, radius, distance) if distance < radius else 0.0
		if symmetry_x:
			var mirror_distance := source[i].distance_to(mirror_center)
			if mirror_distance < radius:
				weight = maxf(weight, 1.0 - smoothstep(0.0, radius, mirror_distance))
		if weight <= 0.0 or neighbor_offsets[i] == neighbor_offsets[i + 1]:
			continue
		var average := Vector3.ZERO
		for j in range(neighbor_offsets[i], neighbor_offsets[i + 1]):
			average += source[neighbors[j]]
		average /= float(neighbor_offsets[i + 1] - neighbor_offsets[i])
		var displacement := (average - source[i]) * clampf(intensity, 0.0, 1.0) * weight
		vertices[i] = source[i] + displacement
		max_displacement = maxf(max_displacement, displacement.length())
	if max_displacement <= 0.0:
		return false
	_finish_deformation(center, mirror_center, radius, max_displacement, symmetry_x)
	return true


func _finish_deformation(center: Vector3, mirror_center: Vector3, radius: float, max_displacement: float, symmetry_x: bool) -> void:
	# Conservatively expand touched blocks so later raycasts follow deformation.
	var brush_bounds := AABB(center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	var mirror_bounds := AABB(mirror_center - Vector3.ONE * radius, Vector3.ONE * radius * 2.0)
	for block in range(triangle_bounds.size()):
		if triangle_bounds[block].intersects(brush_bounds) or (symmetry_x and triangle_bounds[block].intersects(mirror_bounds)):
			triangle_bounds[block] = triangle_bounds[block].grow(max_displacement)
	recalculate_normals()
