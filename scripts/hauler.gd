extends Node3D
## 拖链者：比墙还高、驼背的苍白巨物，头焊在一截铆钉锅炉罐里（观察窗里透出一点暗光），穿着一身对它太小的旧衣服（褪色暗红外套、皮围裙、皮挽具、帆布裤、脏绷带），
## 挽具背后的铁环拴着链子，拖着一块锈铁板，在远处横穿过去。不攻击、不追人，也从不靠近——
## 你走近到 FADE_NEAR 以内，它就慢慢淡进雾里。每隔几分钟，你在屋外、又看得见远处的时候（街上两边的墙挡得死，
## 多半要在墙头步道、观景台、屋顶上或者滑翔时），它会在你前方 45～75 米处走过一段（约 36 米、二十几秒），
## 铁板拖地的声音从它那里传来（借 distant_sounds.gd 的“远处的金属”）。
## 模型来自 tools/blender/creatures.py（creatures.glb）：身体和衣服绑在一副骨骼上，走路的动作在这里按骨骼摆。

const Creatures = preload("res://assets/models/creatures.glb")

const FIRST_MIN := 70.0          # 开局后多久第一次可能出现（秒）
const FIRST_MAX := 110.0
const GAP_MIN := 130.0           # 之后每隔多久一次
const GAP_MAX := 220.0
const RETRY := 8.0               # 到点了但这会儿看不见它（你在街上、被墙挡着），隔多久再试
const DIST_MIN := 45.0           # 出现在多远（再远就被雾吞了）
const DIST_MAX := 75.0
const PATH := 36.0               # 一次走多长
const SPEED := 1.3               # 走多快（米/秒）
const STRIDE := 3.6              # 一步多长（米）：腿摆一个来回走两步
const FADE_NEAR := 28.0          # 走近到这么近它就淡掉
const FADE_TIME := 2.5
const SCALE := 1.05              # 模型驼着背最高处约 15 米，再放大一点，上半身高出墙头
const PLATE_BACK := 10.0         # 铁板拖在身后多远（米）

var player: Node3D               # main 注入
var maze: Node3D
var soundscape: Node
var distant: Node                # distant_sounds.gd：借它的“远处的金属”放拖地声

var model: Node3D
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
var from := Vector3.ZERO
var dir := Vector3.FORWARD
var travelled := 0.0
var alpha := 0.0
var leaving := false
var sound_t := 0.0


func _ready() -> void:
	rng.randomize()
	next_t = rng.randf_range(FIRST_MIN, FIRST_MAX)
	model = Creatures.instantiate()
	add_child(model)
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
	var by_slot := _materials()
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, by_slot.get(src.resource_name if src else "skin", by_slot["skin"]))
	visible = false


## 材质：颜色上叠一层噪声（斑驳、污渍、褪色），法线上叠一层（起皱、粗糙的布纹），三平面映射，不用展 UV。
## 都用抖动透明，淡入淡出不用排序；布料双面画（衣服是单层的）
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
	var out := {}
	for k: String in spec:
		var a: Array = spec[k]
		var m := StandardMaterial3D.new()
		m.albedo_color = a[0]
		m.roughness = a[4]
		m.metallic = a[5]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		if a[6]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if k == "glass":
			# 锅炉罩的观察窗：玻璃后面透出一点发黄发绿的暗光，雾里远远看得见
			m.emission_enabled = true
			m.emission = Color(0.55, 0.6, 0.25)
			m.emission_energy_multiplier = 0.8
		else:
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.02
			noise.fractal_octaves = 4
			noise.seed = rng.randi()
			var g := Gradient.new()
			g.set_color(0, a[1])
			g.set_color(1, Color(1, 1, 1))
			var tex := NoiseTexture2D.new()
			tex.width = 256
			tex.height = 256
			tex.seamless = true
			tex.noise = noise
			tex.color_ramp = g
			m.albedo_texture = tex
			var bump := NoiseTexture2D.new()
			bump.width = 256
			bump.height = 256
			bump.seamless = true
			bump.as_normal_map = true
			bump.bump_strength = 6.0
			var bn := FastNoiseLite.new()
			bn.noise_type = FastNoiseLite.TYPE_CELLULAR if k == "skin" else FastNoiseLite.TYPE_SIMPLEX
			bn.frequency = 0.06
			bump.noise = bn
			m.normal_enabled = true
			m.normal_texture = bump
			m.normal_scale = a[3]
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * a[2] * 0.25
		if k == "skin":
			# 发湿的皮：边上一圈微亮，雾里也读得出轮廓
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.4
		mats.append(m)
		out[k] = m
	return out


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


## 绕骨头自己的“左右”轴转 angle
func _swing(name: String, angle: float) -> void:
	if not bones.has(name):
		return
	skel.set_bone_pose_rotation(bones[name], rest[name] * Quaternion(axis[name], angle))


## 按走过的距离摆姿势：反关节的腿一前一后迈、膝盖跟着折，长臂反着晃，身子一起一伏、左右轻晃，
## 锅炉罩一点一点；铁板拖在身后，链子从挽具背后的铁环拉到铁板
func _pose(dist: float) -> void:
	var ph := dist / STRIDE * PI
	global_position = from + dir * dist
	global_basis = Basis.looking_at(-dir, Vector3.UP) * Basis.from_scale(Vector3.ONE * SCALE)
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
