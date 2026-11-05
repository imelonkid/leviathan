extends Node3D
## 中立的拖链者：在能容纳身体、铁板和链子的开阔区域独立巡游，忽视玩家。
## 整段路径按身体体积验证；靠近、进屋、走完一段都不会使它淡出。
## 只有离玩家足够远且整个模型离开画面后，才结束相遇并回收名额。

const MODEL := "res://assets/models/creatures.glb"
const CreatureMaterials = preload("res://scripts/creature_materials.gd")
const CreatureBudget = preload("res://scripts/creature_budget.gd")
const Space = preload("res://scripts/creature_space.gd")
const TEMPERAMENT = Space.Temperament.NEUTRAL

const FIRST_MIN := 70.0          # 开局后多久第一次可能出现（秒）
const FIRST_MAX := 110.0
const GAP_MIN := 130.0           # 之后每隔多久一次
const GAP_MAX := 220.0
const RETRY := 8.0               # 到点了但这会儿看不见它（你在街上、被墙挡着），隔多久再试
const FAR := 120.0              # 离得足够远、身体和拖板都不在画面中时才能回收
const SPEED := 1.3               # 走多快（米/秒）
const STRIDE := 3.6              # 一步多长（米）：腿摆一个来回走两步
const FADE_TIME := 0.6
const SCALE := 1.05              # 模型驼着背最高处约 15 米，再放大一点，上半身高出墙头
const PLATE_BACK := 10.0         # 铁板拖在身后多远（米）
const RING := Vector3(0, 8.9, -1.35) * SCALE  # 与 tools/blender/creatures.py 的挽具铁环一致

var player: Node3D               # main 注入
var maze: Node3D
var soundscape: Node
var distant: Node                # distant_sounds.gd：借它的“远处的金属”放拖地声
var budget: Node                 # creature_budget.gd

var model: Node3D                # 没加载时是 null
var skel: Skeleton3D
var bones := {}                  # 骨头名 → 下标
var rest := {}                   # 骨头名 → 静止时的局部旋转
var axis := {}                   # 骨头名 → 在这根骨头自己的坐标里，“左右”那根轴（绕它前后摆）
var plate: MeshInstance3D
var chain: MeshInstance3D
var mats: Array[BaseMaterial3D] = []
var rng := RandomNumberGenerator.new()
var next_t := 0.0
var walking := false
var dir := Vector3.FORWARD
var travelled := 0.0
var alpha := 0.0
var sound_t := 0.0
var idle_t := 0.0                # 模型加载着、但没在走，已经多久了
var last_gen: RefCounted
var patrol_cache: Array[Dictionary] = []
var patrol_center := Vector3.ZERO
var patrol_radius := 3.0
var patrol_angle := 0.0
var body_space: RefCounted
var plate_space: RefCounted
var chain_space: RefCounted


func _ready() -> void:
	# 包住模型的约 6.6 米宽身体、前伸的头，以及拖板；不把它硬塞进 5 米窄巷。
	body_space = Space.new(self, player, AABB(Vector3(-4.0, 0.12, -3.8), Vector3(8.0, 16.6, 13.2)))
	plate_space = Space.new(self, player, AABB(Vector3(-2.5, 0.06, -3.9), Vector3(5, 1.1, 4.4)))
	chain_space = Space.new(self, player, AABB(Vector3.ONE * -0.6, Vector3.ONE * 1.2))
	rng.randomize()
	next_t = rng.randf_range(FIRST_MIN, FIRST_MAX)
	visible = false


## 拿到模型：实例化、把铁板和链子摘出来单独摆、记下骨骼、换上材质
func _build(scene: PackedScene) -> void:
	model = scene.instantiate()
	add_child(model)
	idle_t = 0.0
	plate = model.find_child("hauler_plate", true, false)
	chain = model.find_child("hauler_chain", true, false)
	for n: Node3D in [plate, chain]:
		n.get_parent().remove_child(n)
		add_child(n)
		n.top_level = true
	for c in model.find_children("*", "Skeleton3D", true, false):
		skel = c
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		bones[name] = i
		rest[name] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		axis[name] = (skel.get_bone_global_rest(i).basis.inverse() * Vector3.RIGHT).normalized()
	CreatureMaterials.apply(self, _materials(), "skin")


## 退场一阵了：释放模型，还回名额
func _unload() -> void:
	for n: Node in [model, plate, chain]:
		n.queue_free()
	model = null
	skel = null
	bones.clear()
	mats.clear()
	budget.release(self)


## 材质（creature_materials.gd）；锅炉罩的观察窗另加一点自发光
func _materials() -> Dictionary:
	var spec := {
		# 槽: [底色, 斑块颜色（乘在底色上）, 纹理密度, 凹凸, 粗糙度, 金属度, 双面]
		"skin": [Color(0.46, 0.44, 0.39), Color(0.72, 0.6, 0.66), 0.9, 0.6, 0.5, 0.0, false],
		"coat": [Color(0.36, 0.09, 0.07), Color(0.55, 0.4, 0.35), 1.6, 0.4, 0.95, 0.0, true],
		"leather": [Color(0.13, 0.085, 0.055), Color(0.6, 0.5, 0.45), 2.0, 0.5, 0.6, 0.0, true],
		"canvas": [Color(0.42, 0.33, 0.17), Color(0.5, 0.42, 0.33), 1.8, 0.35, 0.95, 0.0, true],
		"bandage": [Color(0.56, 0.51, 0.39), Color(0.65, 0.55, 0.42), 3.0, 0.3, 0.95, 0.0, false],
		"brass": [Color(0.45, 0.33, 0.15), Color(0.6, 0.55, 0.5), 2.0, 0.2, 0.35, 0.8, false],
		"iron": [Color(0.2, 0.11, 0.06), Color(0.5, 0.42, 0.4), 1.2, 0.6, 0.75, 0.5, false],
		"glass": [Color(0.03, 0.035, 0.025), Color(1, 1, 1), 1.0, 0.0, 0.15, 0.0, false],
	}
	var out := CreatureMaterials.make(spec, rng, ["glass"])
	# 观察窗：玻璃后面透出一点发黄发绿的暗光，雾里远远看得见
	var glass: StandardMaterial3D = out["glass"]
	glass.emission_enabled = true
	glass.emission = Color(0.55, 0.6, 0.25)
	glass.emission_energy_multiplier = 0.8
	for m: BaseMaterial3D in out.values():
		mats.append(m)
	return out


func _process(delta: float) -> void:
	if last_gen != maze.gen:
		last_gen = maze.gen
		patrol_cache.clear()
		walking = false
		visible = false
		next_t = rng.randf_range(FIRST_MIN, FIRST_MAX)
	var cam: Camera3D = player.cam
	if not walking:
		next_t -= delta
		if model != null:
			idle_t += delta
			if idle_t > CreatureBudget.KEEP:
				_unload()
		if next_t > 0.0:
			if model == null and next_t < CreatureBudget.PREFETCH:
				budget.prefetch(MODEL)
			return
		next_t = RETRY
		var site := find_patrol(cam)
		if site.is_empty():
			return
		if model == null:
			var scene: PackedScene = budget.take(self, MODEL)
			if scene == null:
				return
			_build(scene)
		start_patrol(site)
		return
	_walk(delta, cam)


func patrol_transform(center: Vector3, radius: float, angle: float) -> Transform3D:
	var at := center + Vector3(cos(angle), 0, sin(angle)) * radius
	var forward := Vector3(-sin(angle), 0, cos(angle))
	return Transform3D(Basis.looking_at(-forward), at)


func plate_transform(at: Transform3D) -> Transform3D:
	return Transform3D(at.basis, at.origin - at.basis.z * PLATE_BACK)


func _supported(at: Vector3) -> bool:
	var block_at: Vector2 = maze.world_to_block(at)
	var p := Vector2i(floori(block_at.x), floori(block_at.y))
	return maze.gen.is_open(p.x, p.y) and absf(maze.gen.floor_height(p.x, p.y) - at.y) < 0.1


func patrol_step_clear(a: Transform3D, b: Transform3D) -> bool:
	if not body_space.can_move(a, b) or not plate_space.can_move(plate_transform(a), plate_transform(b)):
		return false
	# 链子本身也不能斜穿墙：铁板的钩到背后铁环之间留出厚度。
	var hook: Vector3 = plate_transform(b).origin + Vector3.UP * 0.7
	var ring: Vector3 = b * RING
	if not chain_space.can_move(Transform3D(Basis.IDENTITY, hook), Transform3D(Basis.IDENTITY, ring)):
		return false
	for box: AABB in [body_space.bounds, plate_space.bounds]:
		var at := b if box == body_space.bounds else plate_transform(b)
		for x: float in [box.position.x, box.end.x]:
			for z: float in [box.position.z, box.end.z]:
				if not _supported(at * Vector3(x, 0, z)):
					return false
	return true


func patrol_routes() -> Array[Dictionary]:
	if not patrol_cache.is_empty():
		return patrol_cache
	var centers: Array[Vector3] = [maze.block_center(maze.gen.n / 2, maze.gen.n / 2) + Vector3.UP * maze.gen.TOP_TIER * maze.gen.TIER_H]
	for court: Rect2i in maze.gen.courtyards:
		var p := court.position + court.size / 2
		centers.append(maze.block_center(p.x, p.y) + Vector3.UP * maze.gen.floor_height(p.x, p.y))
	for center: Vector3 in centers:
		# 顶层入口的楼梯会切掉平地一角；按实际空间选巡游半径。
		for radius: float in [3.0, 2.0]:
			var valid := true
			var previous := patrol_transform(center, radius, 0.0)
			for step in 128:
				var at := patrol_transform(center, radius, TAU * (step + 1) / 128.0)
				if not patrol_step_clear(previous, at):
					valid = false
					break
				previous = at
			if valid:
				patrol_cache.append({"center": center, "radius": radius})
				break
	return patrol_cache


func find_patrol(cam: Camera3D) -> Dictionary:
	for site: Dictionary in patrol_routes():
		var center: Vector3 = site.center
		var dist := cam.global_position.distance_to(center)
		if dist > FAR or not cam.is_position_in_frustum(center + Vector3.UP * 13.0):
			continue
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, center + Vector3.UP * 13.0)
		query.exclude = [player.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return site
	return {}


func start_patrol(site: Dictionary) -> void:
	patrol_center = site.center
	patrol_radius = site.radius
	patrol_angle = rng.randf_range(0, TAU)
	global_transform = patrol_transform(patrol_center, patrol_radius, patrol_angle)
	dir = global_basis.z
	travelled = 0.0
	alpha = 0.0
	sound_t = rng.randf_range(1.0, 3.0)
	walking = true
	visible = true
	idle_t = 0.0
	_pose(0.0)


func _walk(delta: float, cam: Camera3D) -> void:
	# 循环巡游不参考玩家位置；分小段扫过转弯，不因低帧率跨过障碍。
	var remaining := SPEED * delta
	while remaining > 0.00001:
		var step := minf(remaining, patrol_radius * 0.04)
		var angle := patrol_angle + step / patrol_radius
		var destination := patrol_transform(patrol_center, patrol_radius, angle)
		if not patrol_step_clear(global_transform, destination):
			break
		patrol_angle = angle
		global_transform = destination
		dir = global_basis.z
		travelled += step
		remaining -= step
	alpha = move_toward(alpha, 1.0, delta / FADE_TIME)
	for m in mats:
		m.albedo_color.a = alpha
	_pose(travelled)
	var plate_at := plate_transform(global_transform)
	var hook: Vector3 = plate_at.origin + Vector3.UP * 0.7
	if global_position.distance_to(cam.global_position) > FAR and not body_space.on_screen(global_position, global_basis, cam) and not plate_space.on_screen(plate_at.origin, plate_at.basis, cam) and not chain_space.segment_on_screen(hook, global_transform * RING, cam):
		walking = false
		visible = false
		next_t = rng.randf_range(GAP_MIN, GAP_MAX)
		return
	sound_t -= delta
	if sound_t <= 0.0 and alpha > 0.5:
		sound_t = rng.randf_range(5.0, 8.0)
		if distant and distant.ready_lib:
			distant._play("metal", plate.global_position + Vector3(0, 0.5, 0), 30.0)


## 绕骨头自己的“左右”轴转 angle
func _swing(name: String, angle: float) -> void:
	if not bones.has(name):
		return
	skel.set_bone_pose_rotation(bones[name], rest[name] * Quaternion(axis[name], angle))


## 按走过的距离摆姿势：反关节的腿一前一后迈、膝盖跟着折，长臂反着晃，身子一起一伏、左右轻晃，
## 锅炉罩一点一点；铁板拖在身后，链子从挽具背后的铁环拉到铁板
func _pose(dist: float) -> void:
	var ph := dist / STRIDE * PI
	model.scale = Vector3.ONE * SCALE
	model.position = Vector3(0, -absf(sin(ph)) * 0.3, 0)
	model.rotation = Vector3(0, sin(ph) * 0.04, sin(ph) * 0.03)
	for side in [["l", 1.0], ["r", -1.0]]:
		var sn: String = side[0]
		var sw: float = sin(ph) * side[1]
		# 往前迈的那条腿：大腿往前抬、小腿往回折（反关节）、脚掌放平
		_swing("thigh_" + sn, -sw * 0.42)
		_swing("shin_" + sn, maxf(sw, 0.0) * 0.5)
		_swing("foot_" + sn, -maxf(sw, 0.0) * 0.3)
		_swing("upperarm_" + sn, sw * 0.28)
		_swing("forearm_" + sn, -0.1 + sw * 0.12)
	_swing("spine3", sin(ph * 2.0) * 0.03)
	_swing("neck", sin(ph * 2.0 + 0.6) * 0.06)
	_swing("head", sin(ph * 2.0 + 1.2) * 0.05)
	plate.global_position = global_position - dir * PLATE_BACK
	plate.global_basis = Basis.looking_at(-dir, Vector3.UP) * Basis(Vector3.UP, sin(ph * 0.5) * 0.06)
	var hook := plate.global_position + Vector3(0, 0.7, 0)
	var ring := (skel.global_transform * skel.get_bone_global_pose(bones["ring"])).origin if bones.has("ring") else global_position
	var span := hook.distance_to(ring)
	if span > 0.1:
		# 链子模型沿 +z 长 8 米：+z 指向铁环，按距离伸缩
		var b := Basis.looking_at(hook - ring, Vector3.UP) * Basis.from_scale(Vector3(1.4, 1.4, span / 8.0))
		chain.global_transform = Transform3D(b, hook)
