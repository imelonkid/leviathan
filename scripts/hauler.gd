extends Node3D
## 拖链者：比墙还高的佝偻巨影，拖着链子和一块锈铁板，在远处横穿过去。不攻击、不追人，也从不靠近——
## 你走近到 FADE_NEAR 以内，它就慢慢淡进雾里。每隔几分钟，你在屋外、又看得见远处的时候（街上两边的墙挡得死，
## 多半要在墙头步道、观景台、屋顶上或者滑翔时），它会在你前方 45～75 米处
## 走过一段（约 36 米、二十几秒；头顶离地约 17 米，上半身高出墙头），铁板拖地的声音从它那里传来（借 distant_sounds.gd 的“远处的金属”）。
## 模型来自 tools/blender/creatures.py（creatures.glb），各部分在这里用代码摆：腿、胳膊前后摆，身子一起一伏。

const Creatures = preload("res://assets/models/creatures.glb")

const FIRST_MIN := 70.0          # 开局后多久第一次可能出现（秒）
const FIRST_MAX := 110.0
const GAP_MIN := 130.0           # 之后每隔多久一次
const GAP_MAX := 220.0
const RETRY := 8.0               # 到点了但这会儿看不见它（你在街上、被墙挡着），隔多久再试
const DIST_MIN := 45.0           # 出现在多远（再远就被雾吞了）
const DIST_MAX := 75.0
const PATH := 36.0               # 一次走多长
const SPEED := 1.4               # 走多快（米/秒）
const FADE_NEAR := 28.0          # 走近到这么近它就淡掉
const FADE_TIME := 2.5
const STEP := 0.55               # 每走一米腿摆几个弧度（越小步子越大）
const HIP := 6.0                 # 和 creatures.py 一致：髋关节离地、髋宽、肩的位置
const HIP_X := 0.8
const SHOULDER := Vector3(0, 3.9, 1.6)
const SHOULDER_X := 1.7
const WRIST := Vector3(0, -5.4, 0.9)   # 右手腕相对肩关节
const PLATE_BACK := 7.0          # 铁板拖在身后多远（模型尺度，乘 SCALE）
const SCALE := 1.6               # 整体放大：模型佝偻着只有 10 米多高，放大后头顶约 17 米，上半身高出墙头

var player: Node3D               # main 注入
var maze: Node3D
var soundscape: Node
var distant: Node                # distant_sounds.gd：借它的“远处的金属”放拖地声

var rig: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var plate: Node3D
var chain: MeshInstance3D
var mats: Array[BaseMaterial3D] = []
var rng := RandomNumberGenerator.new()
var next_t := 0.0
var walking := false
var from := Vector3.ZERO
var dir := Vector3.FORWARD
var travelled := 0.0
var alpha := 0.0
var leaving := false
var sound_t := 0.0


func _ready() -> void:
	rng.randomize()
	next_t = rng.randf_range(FIRST_MIN, FIRST_MAX)
	var meshes := {}
	var scene: Node = Creatures.instantiate()
	for c in scene.find_children("*", "MeshInstance3D", true, false):
		meshes[String(c.name)] = (c as MeshInstance3D).mesh
	scene.free()
	var colors := {"skin": Color(0.09, 0.08, 0.075), "rag": Color(0.11, 0.095, 0.08),
		"iron": Color(0.17, 0.1, 0.06), "dark": Color(0.005, 0.005, 0.006)}
	var by_slot := {}
	for k: String in colors:
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[k]
		m.roughness = 0.95 if k != "iron" else 0.7
		m.metallic = 0.5 if k == "iron" else 0.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH   # 淡入淡出用抖动，不用排序
		by_slot[k] = m
		mats.append(m)

	rig = Node3D.new()
	add_child(rig)
	_part(meshes["hauler_body"], rig, by_slot)
	for s: float in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(s * HIP_X, 0, 0)
		rig.add_child(leg)
		_part(meshes["hauler_leg"], leg, by_slot)
		legs.append(leg)
		var arm := Node3D.new()
		arm.position = SHOULDER + Vector3(s * SHOULDER_X, 0, 0)
		rig.add_child(arm)
		_part(meshes["hauler_arm"], arm, by_slot)
		arms.append(arm)
	plate = Node3D.new()
	add_child(plate)
	_part(meshes["hauler_plate"], plate, by_slot)
	chain = _part(meshes["hauler_chain"], self, by_slot)
	visible = false


func _part(mesh: Mesh, parent: Node3D, by_slot: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		mi.set_surface_override_material(i, by_slot.get(src.resource_name if src else "rag", by_slot["rag"]))
	parent.add_child(mi)
	return mi


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if not walking:
		next_t -= delta
		if next_t <= 0.0:
			var indoor: bool = soundscape != null and soundscape.indoor
			next_t = rng.randf_range(GAP_MIN, GAP_MAX) if not indoor and start(cam) else RETRY
		return
	_walk(delta, cam)


## 在镜头前方挑一段路：离 DIST_MIN～DIST_MAX、横着走、整段落在同一层的地面上（腿不会插进挡土墙里），
## 而且从你这里看得见它的上半身（路上三处至少两处）——不然出来了也白出来；挑不到这次就不出来
func start(cam: Camera3D) -> bool:
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for attempt in 12:
		var look := fwd.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		var mid := eye + look * rng.randf_range(DIST_MIN, DIST_MAX)
		var side := look.cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
		var a := mid - side * PATH / 2.0
		var ground := _ground(mid)
		if is_nan(ground):
			continue
		var flat := true
		for k in 5:
			var g := _ground(a + side * PATH * k / 4.0)
			if is_nan(g) or absf(g - ground) > 0.5:
				flat = false
				break
		if not flat or not _seen(eye, a, side, ground):
			continue
		from = Vector3(a.x, ground, a.z)
		dir = side
		travelled = 0.0
		alpha = 0.0
		leaving = false
		sound_t = rng.randf_range(1.0, 3.0)
		walking = true
		visible = true
		_pose(0.0)
		return true
	return false


func _seen(eye: Vector3, a: Vector3, side: Vector3, ground: float) -> bool:
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	var clear := 0
	for k in 3:
		var p := a + side * PATH * (0.2 + 0.3 * k)
		var q := PhysicsRayQueryParameters3D.create(eye, Vector3(p.x, ground + 13.0, p.z))
		q.exclude = ex
		if space.intersect_ray(q).is_empty():
			clear += 1
	return clear >= 2


## 某处的地面高度：迷宫里取最近一块平地（墙块取它所在层的地面），出了迷宫是装饰迷宫的地面 0；拿不准返回 NAN
func _ground(p: Vector3) -> float:
	if maze == null or maze.gen == null:
		return NAN
	var gen: RefCounted = maze.gen
	var b: Vector2 = maze.world_to_block(p)
	var x := int(b.x)
	var z := int(b.y)
	if x < 0 or z < 0 or x >= gen.n or z >= gen.n:
		return 0.0
	for r in 3:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var qx := x + dx
				var qz := z + dz
				if qx < 0 or qz < 0 or qx >= gen.n or qz >= gen.n:
					continue
				if gen.kind[qz][qx] == 1 and is_nan(gen.overpass[qz][qx]):   # FLOOR
					return gen.height[qz][qx]
	return NAN


func _walk(delta: float, cam: Camera3D) -> void:
	travelled += SPEED * delta
	var pos := from + dir * travelled
	var near := Vector2(pos.x - cam.global_position.x, pos.z - cam.global_position.z).length() < FADE_NEAR
	var indoor: bool = soundscape != null and soundscape.indoor
	if near or indoor or travelled > PATH - SPEED * FADE_TIME:
		leaving = true
	alpha = move_toward(alpha, 0.0 if leaving else 1.0, delta / FADE_TIME)
	if leaving and alpha <= 0.0:
		walking = false
		visible = false
		return
	for m in mats:
		m.albedo_color.a = alpha
	_pose(travelled)
	sound_t -= delta
	if sound_t <= 0.0 and alpha > 0.5:
		sound_t = rng.randf_range(5.0, 8.0)
		if distant and distant.ready_lib:
			distant._play("metal", plate.global_position + Vector3(0, 0.5, 0), 30.0)


## 按走过的距离摆姿势：两腿前后摆、两臂反着摆、身子一起一伏左右晃；铁板拖在右后方，链子从右手拉到铁板
func _pose(dist: float) -> void:
	var ph := dist * STEP
	global_position = from + dir * dist
	global_basis = Basis.looking_at(-dir, Vector3.UP) * Basis.from_scale(Vector3.ONE * SCALE)
	rig.position = Vector3(0, HIP - absf(sin(ph)) * 0.35, 0)
	rig.rotation = Vector3(0.0, 0.0, sin(ph) * 0.05)
	legs[0].rotation.x = sin(ph) * 0.38
	legs[1].rotation.x = -sin(ph) * 0.38
	arms[0].rotation.x = -sin(ph) * 0.2
	arms[1].rotation.x = 0.15 + sin(ph) * 0.06        # 拖链子的那只手绷着，摆得少
	var right := global_basis.x.normalized()
	plate.global_position = global_position + (-dir * PLATE_BACK + right * (SHOULDER_X + 0.4)) * SCALE
	plate.global_basis = global_basis * Basis(Vector3.UP, sin(ph * 0.5) * 0.08)
	var hand := arms[1].global_transform * WRIST
	var hook := plate.global_position + Vector3(0, 0.55 * SCALE, 0)
	var span := hook.distance_to(hand)
	if span > 0.1:
		# 链子模型沿 +z 长 8 米：+z 指向手，按距离伸缩
		var b := Basis.looking_at(hook - hand, Vector3.UP) * Basis.from_scale(Vector3(SCALE, SCALE, span / 8.0))
		chain.global_transform = Transform3D(b, hook)
