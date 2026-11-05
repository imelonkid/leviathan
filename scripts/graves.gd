extends Node3D
## 破墓只占安静墙边，不改迷宫连通图；始终留出中心和每个出口的 2.4 米净空。
const Models = preload("res://assets/models/graves.glb")
const Materials = preload("res://scripts/creature_materials.gd")
const Gen = preload("res://scripts/maze_gen.gd")
const Tap = preload("res://assets/audio/threshold/measure_tap.wav")
const DragShader = preload("res://scripts/rooms/blood.gdshader")
const KINDS := ["grave_mound", "grave_open", "grave_wall"]
const QUOTAS := [7, 6, 5]
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CLEAR_WIDTH := 2.4
const WALL_GAP := 0.2
const MIN_GAP := 7.5
const SPAWN_GAP := 20.0
const COLLISION_LAYER := 2       # 同时属于普通世界层 1；层 2 供独立通行验证。
const QUIET_NEAR := 5.0

var maze: Node3D
var meshes := {}
var shapes := {}
var bounds := {}
var sites: Array[Dictionary] = []
var voice: AudioStreamPlayer3D
var sound_rng := RandomNumberGenerator.new()
var sound_timer := 0.0


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = maze.seed_value + 73091
	var palette := Materials.make({
		"stone": [Color(0.39, 0.36, 0.31), Color(0.45, 0.47, 0.4), 3.0, 0.75, 0.96, 0.0, false],
		"earth": [Color(0.24, 0.17, 0.1), Color(0.45, 0.4, 0.32), 5.0, 0.9, 1.0, 0.0, false],
		"wood": [Color(0.3, 0.19, 0.1), Color(0.5, 0.43, 0.31), 4.0, 0.7, 0.96, 0.0, false],
		"iron": [Color(0.25, 0.12, 0.055), Color(0.45, 0.4, 0.32), 3.0, 0.5, 0.85, 0.65, false],
		"void": [Color(0.016, 0.012, 0.011), Color.WHITE, 1.0, 0.0, 1.0, 0.0, false],
	}, rng, ["void"])
	for material: StandardMaterial3D in palette.values():
		material.vertex_color_use_as_albedo = true
	var kit: Node3D = Models.instantiate()
	for part: MeshInstance3D in kit.find_children("*", "MeshInstance3D", true, false):
		var key := String(part.name)
		var mesh: Mesh = part.mesh.duplicate()
		for surface in mesh.get_surface_count():
			var source: Material = mesh.surface_get_material(surface)
			mesh.surface_set_material(surface, palette[source.resource_name])
		meshes[key] = mesh
		bounds[key] = mesh.get_aabb()
		shapes[key] = mesh.create_trimesh_shape()
	kit.free()
	sites = plan()
	for site: Dictionary in sites:
		var body := StaticBody3D.new()
		body.name = site.kind
		body.collision_layer = 1 | COLLISION_LAYER
		body.collision_mask = 0
		add_child(body)
		body.global_transform = site.transform
		var model := MeshInstance3D.new()
		model.mesh = meshes[site.kind]
		body.add_child(model)
		var collider := CollisionShape3D.new()
		collider.shape = shapes[site.kind]
		body.add_child(collider)
		site["body"] = body
		if site.kind == "grave_open":
			_drag_marks(body)
	voice = AudioStreamPlayer3D.new()
	voice.stream = Tap
	voice.volume_db = -24.0
	voice.unit_size = 3.0
	voice.max_distance = 24.0
	add_child(voice)
	sound_rng.seed = maze.seed_value + 73092
	sound_timer = sound_rng.randf_range(20, 40)


func lanes(p: Vector2i) -> Array[Rect2]:
	var center: Vector3 = maze.block_center(p.x, p.y)
	var a := Vector2(center.x, center.z)
	var out: Array[Rect2] = [Rect2(a - Vector2.ONE * CLEAR_WIDTH / 2.0, Vector2.ONE * CLEAR_WIDTH)]
	for d: Vector2i in DIRS:
		if maze.gen.is_open(p.x + d.x, p.y + d.y):
			var b: Vector2 = a + Vector2(d) * maze.block / 2.0
			out.append(Rect2(a.min(b) - Vector2.ONE * CLEAR_WIDTH / 2.0, (a - b).abs() + Vector2.ONE * CLEAR_WIDTH))
	return out


func footprint(kind: String, transform: Transform3D) -> Rect2:
	var box: AABB = transform * bounds[kind]
	return Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))


func eligible(p: Vector2i) -> bool:
	var g: RefCounted = maze.gen
	if g.kind[p.y][p.x] != Gen.FLOOR or g.height[p.y][p.x] >= Gen.TOP_TIER * Gen.TIER_H:
		return false
	if g.arch[p.y][p.x] or g.span[p.y][p.x] or g.doorway[p.y][p.x] or not is_nan(g.overpass[p.y][p.x]) or maze._next_to_room(p):
		return false
	var at: Vector3 = maze.block_center(p.x, p.y) + Vector3.UP * g.height[p.y][p.x]
	if at.distance_to(maze.get_spawn_position()) < SPAWN_GAP:
		return false
	# 除门和楼梯本身外，也避开旁边的落脚点、窄桥及建筑伸出的碰撞。
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dz)
			if g.house[q.y][q.x] or g.landmark[q.y][q.x] or g.kind[q.y][q.x] in [Gen.STAIR, Gen.BRIDGE, Gen.PLATFORM, Gen.VOID, Gen.TERRACE]:
				return false
	var exits := 0
	for d: Vector2i in DIRS:
		if g.is_open(p.x + d.x, p.y + d.y):
			exits += 1
	var courtyard := false
	for court: Rect2i in g.courtyards:
		courtyard = courtyard or court.has_point(p)
	return exits == 1 or courtyard


func candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g: RefCounted = maze.gen
	for z in range(1, g.n - 1):
		for x in range(1, g.n - 1):
			var p := Vector2i(x, z)
			if not eligible(p):
				continue
			for d: Vector2i in DIRS:
				var w := p + d
				if g.kind[w.y][w.x] != Gen.WALL or g.arcade[w.y][w.x] or g.house[w.y][w.x] or g.landmark[w.y][w.x]:
					continue
				# 保留原有窗和角柱，墓龛贴在完整墙面上。
				if (w.x % 2 == 0 and w.y % 2 == 0) or maze.window_faces.has(Vector4i(w.x, w.y, -d.x, -d.y)):
					continue
				var normal := Vector3(-d.x, 0, -d.y)
				var at: Vector3 = maze.block_center(x, z) - normal * (maze.block / 2.0 - WALL_GAP) + Vector3.UP * g.height[z][x]
				var transform := Transform3D(Basis(Vector3.UP.cross(normal), Vector3.UP, normal), at)
				out.append({"block": p, "wall": w, "transform": transform})
	return out


func plan() -> Array[Dictionary]:
	var options := candidates()
	var rng := RandomNumberGenerator.new()
	rng.seed = maze.seed_value + 73091
	# 独立随机数，不扰动迷宫和怪物使用的全局随机序列。
	for i in range(options.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := options[i]
		options[i] = options[j]
		options[j] = swap
	var chosen: Array[Dictionary] = []
	var used := {}
	for type_index in KINDS.size():
		var kind: String = KINDS[type_index]
		var count := 0
		for option: Dictionary in options:
			if used.has(option.block):
				continue
			var at: Vector3 = option.transform.origin
			var apart := true
			for placed: Dictionary in chosen:
				if placed.transform.origin.distance_to(at) < MIN_GAP:
					apart = false
					break
			if not apart:
				continue
			var rect := footprint(kind, option.transform).grow(0.03)
			var clear := true
			for lane: Rect2 in lanes(option.block):
				if rect.intersects(lane):
					clear = false
					break
			if not clear:
				continue
			var site := option.duplicate()
			site["kind"] = kind
			chosen.append(site)
			used[option.block] = true
			count += 1
			if count >= QUOTAS[type_index]:
				break
	return chosen


func _drag_marks(parent: Node3D) -> void:
	# 沿用现有断续拖痕着色器，改为泥土色，不用笔直的黑色几何线。
	var material := ShaderMaterial.new()
	material.shader = DragShader
	material.set_shader_parameter("kind", 3)
	material.set_shader_parameter("aspect", 4.0)
	material.set_shader_parameter("seed", parent.global_position.x * 13.0 + parent.global_position.z * 7.0)
	material.set_shader_parameter("wet", Color(0.08, 0.046, 0.021))
	material.set_shader_parameter("dry", Color(0.035, 0.027, 0.017))
	var strip := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 1.8)
	strip.mesh = quad
	strip.material_override = material
	strip.rotation.x = -PI / 2.0
	strip.position = Vector3(0.0, 0.018, 1.5)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(strip)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if voice.playing and camera.global_position.distance_to(voice.global_position) < QUIET_NEAR:
		voice.stop()
	sound_timer -= delta
	if sound_timer > 0.0:
		return
	sound_timer = sound_rng.randf_range(20, 40)
	for site: Dictionary in sites:
		if site.kind != "grave_wall":
			continue
		var at: Vector3 = site.transform * Vector3(0, 1.3, 0.6)
		var distance := camera.global_position.distance_to(at)
		if distance > QUIET_NEAR and distance < 22.0:
			voice.global_position = at
			voice.bus = "World"
			voice.pitch_scale = sound_rng.randf_range(0.65, 0.8)
			voice.play()
			break
