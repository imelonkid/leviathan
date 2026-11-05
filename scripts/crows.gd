extends Node3D
## 四只装饰乌鸦：三组 MultiMesh、一个声音节点，无骨骼/物理体/寻路器/阴影。
const Models = preload("res://assets/models/crows.glb")
const Caw = preload("res://assets/audio/crows/caw.ogg")
const Flap = preload("res://assets/audio/threshold/cloth_02.wav")
const COUNT := 4
const ACTIVE_DISTANCE := 50.0
const STARTLE_DISTANCE := 4.5
const REST_STEP := 0.1
const FLIGHT_STEP := 1.0 / 30.0
const FAR_STEP := 1.0
const ROUTE_STEPS := 24
const BRANCHES := [Vector3(-1.75, 4.84, -0.0625), Vector3(1.775, 4.565, 0.95)]
const HEAD_PIVOT := Vector3(0, 0.184930636, -0.020764716)
const WING_PIVOT := Vector3(0.056182187, 0.17, -0.038051538)

var maze: Node3D
var batches := {}
var perches: Array[Vector3] = []
var perch_out: Array[Vector3] = []
var birds: Array[Dictionary] = []
var voice: AudioStreamPlayer3D
var rng := RandomNumberGenerator.new()
var center := Vector3.ZERO
var clock := 0.0
var interval := FAR_STEP
var awake := false
var silenced := false
var recovery := 0.0
var call_timer := 0.0


func build(trees: Array[StaticBody3D]) -> void:
	if trees.is_empty():
		set_process(false)
		return
	rng.seed = maze.seed_value + 90471
	for tree: StaticBody3D in trees:
		for branch: Vector3 in BRANCHES:
			perches.append(tree.global_transform * branch)
			perch_out.append((tree.global_basis * Vector3(branch.x, 0, branch.z)).normalized())
		center += tree.global_position
	center /= trees.size()
	center.y += 4.0
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.albedo_color = Color(0.12, 0.14, 0.18)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # 左翅镜像，仍使用同一个翅膀网格。
	var kit := Models.instantiate()
	for part: MeshInstance3D in kit.find_children("*", "MeshInstance3D", true, false):
		var batch := MultiMeshInstance3D.new()
		batch.name = part.name
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = part.mesh
		batch.multimesh.instance_count = COUNT * (2 if part.name == "crow_wing" else 1)
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batch.visibility_range_end = ACTIVE_DISTANCE
		add_child(batch)
		batches[String(part.name)] = batch
	kit.free()
	for i in COUNT:
		var perch: int = [0, 2, 4, 1][i]
		birds.append({"perch": perch, "destination": perch, "position": perches[perch],
			"route": PackedVector3Array(), "progress": 0.0, "duration": 0.0,
			"time": rng.randf_range(0, TAU), "yaw": atan2(-perch_out[perch].x, -perch_out[perch].z), "cooldown": 0.0})
	voice = AudioStreamPlayer3D.new()
	voice.bus = "World"
	voice.unit_size = 5.0
	voice.max_distance = 32.0
	voice.max_polyphony = 1
	add_child(voice)
	call_timer = rng.randf_range(24, 42)
	_draw_birds()
	_set_awake(false)


func _set_awake(value: bool) -> void:
	awake = value
	for batch: MultiMeshInstance3D in batches.values():
		batch.visible = value
	if not value:
		voice.stop()


func _process(delta: float) -> void:
	clock += delta
	if clock < interval:
		return
	var elapsed := clock
	clock = 0.0
	var camera := get_viewport().get_camera_3d()
	var main: Node3D = maze.get_parent()
	if camera == null or not main.settings.has_focus or camera.global_position.distance_squared_to(center) > ACTIVE_DISTANCE * ACTIVE_DISTANCE:
		_set_awake(false)
		interval = FAR_STEP
		return
	_set_awake(true)
	var exposed := false
	for bird: Dictionary in birds:
		exposed = exposed or main.lev.beam_exposure(bird.position) > 0.01
	# 远处休眠的时间不补成一次大步移动。
	advance(minf(elapsed, REST_STEP), camera.global_position, exposed, main.lev.global_position)
	interval = FLIGHT_STEP if flying_count() > 0 else REST_STEP


func flying_count() -> int:
	var count := 0
	for bird: Dictionary in birds:
		if not bird.route.is_empty():
			count += 1
	return count


func advance(delta: float, viewer: Vector3, exposed: bool, threat: Vector3) -> void:
	silenced = exposed
	if exposed:
		voice.stop()
		recovery = 1.5
		for bird: Dictionary in birds:
			var direction: Vector3 = threat - bird.position
			bird.yaw = lerp_angle(bird.yaw, atan2(-direction.x, -direction.z), minf(1, delta * 4.0))
		_draw_birds()
		return
	if recovery > 0.0:
		recovery = maxf(0, recovery - delta)
		return
	for bird: Dictionary in birds:
		bird.time += delta
		bird.cooldown = maxf(0, bird.cooldown - delta)
		if not bird.route.is_empty():
			bird.progress = minf(1, bird.progress + delta / bird.duration)
			var sample: float = bird.progress * ROUTE_STEPS
			var index := mini(int(sample), ROUTE_STEPS - 1)
			var a: Vector3 = bird.route[index]
			var b: Vector3 = bird.route[index + 1]
			bird.position = a.lerp(b, sample - index)
			var direction := b - a
			bird.yaw = atan2(-direction.x, -direction.z)
			if bird.progress >= 1.0:
				bird.perch = bird.destination
				bird.route = PackedVector3Array()
		elif bird.cooldown <= 0.0 and flying_count() < 2 and bird.position.distance_squared_to(viewer) < STARTLE_DISTANCE * STARTLE_DISTANCE:
			_startle(bird, viewer)
	call_timer -= delta
	if call_timer <= 0.0:
		call_timer = rng.randf_range(24, 42)
		var bird: Dictionary = birds[rng.randi_range(0, COUNT - 1)]
		if bird.route.is_empty() and not voice.playing:
			_sound(Caw, bird.position, -18.0, rng.randf_range(0.9, 1.05))
	_draw_birds()


func _startle(bird: Dictionary, viewer: Vector3) -> void:
	var available: Array[int] = []
	for i in perches.size():
		var occupied := false
		for other: Dictionary in birds:
			occupied = occupied or other.perch == i or other.destination == i
		if not occupied:
			available.append(i)
	available.sort_custom(func(a: int, b: int) -> bool: return perches[a].distance_squared_to(viewer) > perches[b].distance_squared_to(viewer))
	for target: int in available:
		var route := _flight_route(bird.position, perches[target], perch_out[bird.perch], perch_out[target])
		if route.is_empty():
			continue
		bird.destination = target
		bird.route = route
		bird.progress = 0.0
		var length := 0.0
		for i in ROUTE_STEPS:
			length += route[i].distance_to(route[i + 1])
		bird.duration = length / 6.0
		bird.cooldown = rng.randf_range(18, 30)
		if not voice.playing:
			_sound(Flap, bird.position, -25.0, 1.25)
		return
	# 枝杈挡住起飞方向时稍后再试，不在每个动画更新重复做扫掠。
	bird.cooldown = 3.0


func _flight_route(a: Vector3, b: Vector3, out_a: Vector3, out_b: Vector3) -> PackedVector3Array:
	var route := PackedVector3Array()
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.13
	query.shape = sphere
	query.collision_mask = 1
	var space := get_world_3d().direct_space_state
	for i in ROUTE_STEPS + 1:
		var t := float(i) / ROUTE_STEPS
		# 先沿枝端向外抬升、最后从外侧降落，避免直飞穿过枝杈和树干。
		var point := a.bezier_interpolate(a + out_a * 2 + Vector3.UP * 4, b + out_b * 2 + Vector3.UP * 4, b, t)
		if i > 0:
			query.transform.origin = route[i - 1] + Vector3.UP * 0.2
			query.motion = point - route[i - 1]
			if not space.intersect_shape(query, 1).is_empty() or space.cast_motion(query)[0] < 1.0:
				return PackedVector3Array()
		route.append(point)
	return route


func _sound(stream: AudioStream, at: Vector3, volume: float, pitch: float) -> void:
	voice.stream = stream
	voice.global_position = at
	voice.volume_db = volume
	voice.pitch_scale = pitch
	voice.play()


func _draw_birds() -> void:
	for i in birds.size():
		var bird: Dictionary = birds[i]
		var flying: bool = not bird.route.is_empty()
		var pitch := 0.0 if flying else 0.4
		var transform := Transform3D(Basis(Vector3.UP, bird.yaw) * Basis(Vector3.RIGHT, pitch), bird.position)
		batches.crow_body.multimesh.set_instance_transform(i, transform)
		var head_turn: float = 0.0 if silenced else sin(bird.time * 0.7 + i) * 0.3
		var nod: float = 0.0 if silenced or flying else pow(maxf(0, sin(bird.time * 0.4 + i)), 12) * 0.3
		var head := Transform3D(Basis(Vector3.UP, head_turn) * Basis(Vector3.RIGHT, nod - pitch), HEAD_PIVOT)
		batches.crow_head.multimesh.set_instance_transform(i, transform * head)
		for side in [-1, 1]:
			var wing_basis := Basis(Vector3.BACK, side * sin(bird.time * TAU * 5.0) * 0.8) if flying else Basis(Vector3.UP, -side * 1.25)
			wing_basis = wing_basis * Basis.from_scale(Vector3(side, 1, 1))
			var wing := Transform3D(wing_basis, Vector3(side * WING_PIVOT.x, WING_PIVOT.y, WING_PIVOT.z))
			batches.crow_wing.multimesh.set_instance_transform(i * 2 + (0 if side == -1 else 1), transform * wing)
