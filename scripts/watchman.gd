extends Node3D
## 守夜人：追人的怪物。瘦高的人形（约 2.8 米），头是一只铁笼提灯，没有脸，笼里一团冷白的火；
## 那团火往前照出一道冷白的光——那道光就是它的眼睛。深灰绿长大衣、短披肩，左手拎着一大串钥匙。
## 模型来自 tools/blender/watchman.py（watchman.glb）：身体和衣服绑在一副骨骼上，走路的动作在这里按骨骼摆。
##
## 开局一会儿后它出现在你这一层、离你几十米、你看不见的地方，沿着街巷慢慢游荡，越游越往你这边靠。
## 发现你：你在它那道光里（前方 GAZE_RANGE 米、SIGHT_ANGLE 度以内），或者你的提灯开着、离它不到 LAMP_SEEN 米，
## 或者你就在它身边——而且中间没有墙挡着。发现后它停下、灯一亮、转向你，接着追；比你走得快、比你跑得慢。
## 甩掉它：跑开、躲进屋里（它进不了房间）、爬上墙头、滑翔到下一层；看不见你 LOSE_TIME 秒后，
## 它走到最后看见你的地方张望一会儿，再回去游荡。你走远了，它在离开画面且距离足够远后才换到你附近。
## 追到你身边发出 caught，它停在你面前；接下来的事（黑屏、在低一层醒来）在 caught.gd，那边会让它退下（retreat）。
## 模型不常驻：快出场时由 creature_budget.gd 在后台加载、给名额，退下一阵后释放（灯也跟着模型走）。
## 声音在 watchman_sounds.gd：脚步、钥匙叮当、火声，发现你、抓住你各一声。

signal caught

const MODEL := "res://assets/models/watchman.glb"
const CreatureMaterials = preload("res://scripts/creature_materials.gd")
const CreatureBudget = preload("res://scripts/creature_budget.gd")
const GridPath = preload("res://scripts/grid_path.gd")
const Sounds = preload("res://scripts/watchman_sounds.gd")
const Space = preload("res://scripts/creature_space.gd")
const TEMPERAMENT = Space.Temperament.DANGEROUS

enum { HIDDEN, ROAM, ALERT, CHASE, SEARCH, HOLD }

const LANTERN := Vector3(0, 2.78, 0.1)   # 提灯笼子的中心（模型坐标，和 watchman.py 一致）
const STRIDE := 1.4                      # 一步多长（米）：腿摆一个来回走两步
const GAZE_RANGE := 18.0                 # 目光那道光照多远
const GAZE_ANGLE := 22.0                 # 光束半角（度）
const LIGHT := Color(0.75, 0.87, 1.0)    # 冷白的火
const FIRST := 40.0                      # 开局多久后出现（秒）
const ROAM_SPEED := 1.2                  # 游荡（米/秒）
const SEARCH_SPEED := 2.4                # 去最后看见你的地方
const CHASE_SPEED := 5.6                 # 追：比你走（5）快，比你跑（10）慢
const SIGHT_ANGLE := 35.0                # 看得见的半角（度），比光束宽一点
const LAMP_SEEN := 12.0                  # 你的提灯开着，这么近它从哪边都看得见
const NEAR := 3.5                        # 这么近，背对着也觉察得到
const ALERT_TIME := 1.0                  # 发现你后愣一下再追
const LOSE_TIME := 5.0                   # 看不见你多久算跟丢
const LOOK_TIME := 4.0                   # 跟丢后在原地张望多久
const REACH := 1.8                       # 碰到你
const PLACE_MIN := 4                     # 出现在离你多少步（块）以外
const PLACE_MAX := 10
const FAR := 110.0                       # 游荡时离你超过这么远（米），或者不在你这一层，就换到你附近

var model: Node3D
var skel: Skeleton3D
var bones := {}                          # 骨头名 → 下标
var rest := {}                           # 骨头名 → 静止时的局部旋转
var axis := {}                           # 骨头名 → 在这根骨头自己的坐标里，“左右”那根轴（绕它前后摆）
var lamp: OmniLight3D                    # 笼子里的火照亮自己和身边
var gaze: SpotLight3D                    # 往前下方的一道光：它的目光
var flame: StandardMaterial3D
var mats: Array[BaseMaterial3D] = []
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var t := 0.0
var player: CharacterBody3D              # main 注入
var maze: Node3D
var budget: Node                         # creature_budget.gd
var paths: RefCounted                    # GridPath
var idle_t := 0.0                        # 模型加载着、但没出场，已经多久了
var sounds: Node3D                       # watchman_sounds.gd（常驻，跟着守夜人走）
var last_step := 0                       # 走到第几步了（落脚时出声）
var state := HIDDEN
var timer := FIRST
var route: Array[Vector2i] = []          # 要走的块
var seg_from := Vector3.ZERO             # 正在走的这一段（两块中心之间）
var seg_to := Vector3.ZERO
var seg_t := 1.0
var walked := 0.0                        # 累计走了多远，摆腿用
var heading := 0.0                       # 朝向（绕 y，0 = 朝 +z）
var seen := false
var sight_t := 0.0
var unseen := 0.0
var last_seen := Vector2i.ZERO
var relocate_t := 0.0
var repath_t := 0.0
var glare := 1.0                         # 灯的亮度倍数：发现你时亮一下
var body_space: RefCounted


func _ready() -> void:
	# 下沿避开斜坡，覆盖大衣、手臂和高于 3 米的提灯。
	body_space = Space.new(self, player, AABB(Vector3(-0.7, 0.6, -0.7), Vector3(1.4, 2.8, 1.4)))
	rng.randomize()
	noise.seed = rng.randi()
	noise.frequency = 3.0
	if maze:
		paths = GridPath.new(maze.gen)
	sounds = Sounds.new()
	add_child(sounds)
	visible = false


## 拿到模型：实例化、记下骨骼、换上材质、在提灯里挂上灯
func _build(scene: PackedScene) -> void:
	model = scene.instantiate()
	add_child(model)
	idle_t = 0.0
	for c in model.find_children("*", "Skeleton3D", true, false):
		skel = c
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		bones[name] = i
		rest[name] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		axis[name] = (skel.get_bone_global_rest(i).basis.inverse() * Vector3.RIGHT).normalized()
	CreatureMaterials.apply(self, _materials(), "coat")
	# 灯挂在 head 骨头上，跟着提灯一起晃
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var head_rest := skel.get_bone_global_rest(bones["head"]).affine_inverse()
	lamp = OmniLight3D.new()
	lamp.light_color = LIGHT
	lamp.omni_range = 4.0
	lamp.light_energy = 1.2
	lamp.shadow_enabled = true
	lamp.transform = head_rest * Transform3D(Basis(), LANTERN)
	att.add_child(lamp)
	gaze = SpotLight3D.new()
	gaze.light_color = LIGHT
	gaze.spot_range = GAZE_RANGE
	gaze.spot_angle = GAZE_ANGLE
	gaze.spot_angle_attenuation = 0.6
	gaze.light_energy = 6.0
	gaze.light_volumetric_fog_energy = 2.0
	gaze.shadow_enabled = true
	gaze.transform = head_rest * Transform3D(Basis.looking_at(Vector3(0, -0.35, 1)), LANTERN + Vector3(0, 0, 0.12))
	att.add_child(gaze)


## 退下一阵了：释放模型（灯、材质跟着走），还回名额
func _unload() -> void:
	model.queue_free()
	model = null
	skel = null
	lamp = null
	gaze = null
	flame = null
	bones.clear()
	mats.clear()
	budget.release(self)


## 材质（creature_materials.gd）；玻璃半透，火不受光照、自己发光
func _materials() -> Dictionary:
	var spec := {
		# 槽: [底色, 斑块颜色（乘在底色上）, 纹理密度, 凹凸, 粗糙度, 金属度, 双面]
		"skin": [Color(0.44, 0.42, 0.38), Color(0.72, 0.6, 0.66), 1.6, 0.5, 0.5, 0.0, false],
		"coat": [Color(0.14, 0.15, 0.12), Color(0.55, 0.5, 0.45), 1.8, 0.45, 0.95, 0.0, true],
		"cape": [Color(0.1, 0.105, 0.09), Color(0.55, 0.5, 0.45), 1.8, 0.45, 0.95, 0.0, true],
		"leather": [Color(0.09, 0.06, 0.045), Color(0.6, 0.5, 0.45), 3.0, 0.4, 0.6, 0.0, false],
		"bandage": [Color(0.52, 0.48, 0.38), Color(0.65, 0.55, 0.42), 4.0, 0.3, 0.95, 0.0, false],
		"brass": [Color(0.42, 0.31, 0.13), Color(0.6, 0.55, 0.5), 4.0, 0.2, 0.35, 0.8, false],
		"iron": [Color(0.09, 0.075, 0.065), Color(0.55, 0.4, 0.3), 3.0, 0.6, 0.65, 0.6, false],
		"glass": [Color(0.22, 0.25, 0.24, 0.35), Color(1, 1, 1), 1.0, 0.0, 0.1, 0.0, true],
		"flame": [LIGHT, Color(1, 1, 1), 1.0, 0.0, 1.0, 0.0, true],
	}
	var out := CreatureMaterials.make(spec, rng, ["glass", "flame"])
	flame = out["flame"]
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.emission_enabled = true
	flame.emission = LIGHT
	flame.emission_energy_multiplier = 4.0
	for m: BaseMaterial3D in out.values():
		mats.append(m)
	return out


func _process(delta: float) -> void:
	t += delta
	if paths == null or player == null:
		return
	if paths.gen != maze.gen:
		paths = GridPath.new(maze.gen)
		retreat(FIRST)
	if state == HIDDEN:
		_hidden(delta)
		return
	# 火苗一跳一跳：灯和火的亮度跟着噪声走；发现你、追你的时候更亮
	glare = move_toward(glare, 1.8 if state in [ALERT, CHASE, HOLD] else 1.0, delta * 2.0)
	var f := (0.85 + 0.15 * noise.get_noise_1d(t * 10.0) + 0.05 * sin(t * 23.0)) * glare
	lamp.light_energy = 1.2 * f
	gaze.light_energy = 6.0 * f
	flame.emission_energy_multiplier = 4.0 * f
	sight_t -= delta
	if sight_t <= 0.0:
		sight_t = 0.15
		seen = _can_see()
	var moved := 0.0
	match state:
		ROAM:
			if seen:
				_alert()
			else:
				moved = _follow(ROAM_SPEED, delta)
				if route.is_empty():
					_roam_target()
				relocate_t -= delta
				if relocate_t <= 0.0:
					relocate_t = 8.0
					if _too_far() and not body_space.on_screen(global_position, Basis.IDENTITY, player.cam):
						_place()
		ALERT:
			_face(player.global_position, delta, 8.0)
			timer -= delta
			if timer <= 0.0:
				state = CHASE
				repath_t = 0.0
		CHASE:
			if seen:
				unseen = 0.0
				last_seen = _block_of(player.global_position)
			else:
				unseen += delta
			if unseen > LOSE_TIME:
				state = SEARCH
				timer = LOOK_TIME
				_go(last_seen)
			else:
				repath_t -= delta
				if repath_t <= 0.0:
					repath_t = 0.4
					_go(_block_of(player.global_position))
				moved = _follow(CHASE_SPEED, delta)
				if route.is_empty() and seg_t >= 1.0 and seen:
					moved = _approach(player.global_position, CHASE_SPEED * delta, delta)
				if seen and _clear(lamp.global_position, player.cam.global_position) and _flat_dist(player.global_position) < REACH and absf(player.global_position.y - global_position.y) < 2.5:
					state = HOLD
					sounds.caught()
					caught.emit()
		SEARCH:
			if seen:
				_alert()
			elif not route.is_empty() or seg_t < 1.0:
				moved = _follow(SEARCH_SPEED, delta)
			else:
				# 走到最后看见你的地方，左右张望一会儿
				timer -= delta
				heading += sin(t * 1.3) * delta * 1.2
				rotation.y = heading
				if timer <= 0.0:
					state = ROAM
		HOLD:
			_face(player.global_position, delta, 6.0)
			if _flat_dist(player.global_position) > REACH * 2.0:
				state = CHASE
				repath_t = 0.0
	# 停下来时腿慢慢收拢
	if moved > 0.0:
		walked += moved
	else:
		walked = move_toward(walked, roundf(walked / STRIDE) * STRIDE, delta * 1.5)
	pose(walked)
	# 每走一步（两腿交替时 sin 过零）落一次脚：脚步声、钥匙叮当
	var step_i := floori(walked / STRIDE)
	if step_i != last_step:
		last_step = step_i
		if moved > 0.0:
			sounds.step(state == CHASE)


## ---------- 行为 ----------

## 没出场：快到点时在后台加载模型，到点拿名额、在你附近找地方出来；退下太久就把模型释放
func _hidden(delta: float) -> void:
	timer -= delta
	if model == null:
		if timer < CreatureBudget.PREFETCH:
			budget.prefetch(MODEL)
		if timer > 0.0:
			return
		var scene: PackedScene = budget.take(self, MODEL)
		if scene == null:
			timer = 2.0                   # 名额满了或者还没加载完
			return
		_build(scene)
	else:
		idle_t += delta
		if idle_t > CreatureBudget.KEEP and timer > CreatureBudget.PREFETCH:
			_unload()
			return
	if timer <= 0.0:
		timer = 5.0
		if _place():
			state = ROAM


## 抓完人退下：after 秒后再在你附近出现
func retreat(after: float) -> void:
	state = HIDDEN
	timer = after
	idle_t = 0.0
	route.clear()
	seg_t = 1.0
	visible = false
	sounds.burn(false)


func _alert() -> void:
	sounds.alert()
	state = ALERT
	timer = ALERT_TIME
	route.clear()
	seg_t = 1.0
	unseen = 0.0
	last_seen = _block_of(player.global_position)


## 它看不看得见你：在它的光里、你的提灯开着且不远、或者就在它身边——而且中间没有墙
func _can_see() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var eye := lamp.global_position
	var to := cam.global_position - eye
	var d := to.length()
	var fwd := global_basis.z
	var flat := Vector3(to.x, 0.0, to.z)
	var in_cone := d < GAZE_RANGE and flat.length() > 0.01 and rad_to_deg(fwd.angle_to(flat)) < SIGHT_ANGLE
	var by_lamp: bool = player.lamp.visible and d < LAMP_SEEN
	if not (in_cone or by_lamp or d < NEAR):
		return false
	return _clear(eye, cam.global_position)


## 你看不看得见它：提灯在你的视野里，中间没有墙
func _player_sees_me() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var p := lamp.global_position
	return cam.is_position_in_frustum(p) and _clear(cam.global_position, p)


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _too_far() -> bool:
	return global_position.distance_to(player.global_position) > FAR


## 出现在你附近：从你所在的块往外走 PLACE_MIN～PLACE_MAX 步、你看不见的一块（还在出生的观景台上时找不到，等你进了迷宫）
func _place() -> bool:
	var pb := _block_of(player.global_position)
	if pb.x < 0:
		return false
	var dist: Dictionary = paths.reach(pb, PLACE_MAX)
	var cands: Array[Vector2i] = []
	for b: Vector2i in dist:
		if dist[b] >= PLACE_MIN and maze.gen.kind[b.y][b.x] != maze.gen.TERRACE:   # 不在空荡荡的观景台上冒出来
			cands.append(b)
	cands.shuffle()
	var cam := get_viewport().get_camera_3d()
	for b in cands.slice(0, 20):
		var p := _center(b)
		if not body_space.fits(p):
			continue
		if cam and _clear(cam.global_position, p + Vector3(0, 2.8, 0)):
			continue
		global_position = p
		heading = rng.randf_range(-PI, PI)
		rotation.y = heading
		route.clear()
		seg_t = 1.0
		visible = true
		sounds.burn(true)
		return true
	return false


## 游荡：在附近挑几块能走到的，取离你最近的那块走过去——它总是慢慢往你这边靠
func _roam_target() -> void:
	var here := _block_of(global_position)
	var dist: Dictionary = paths.reach(here, 12)
	var cands: Array[Vector2i] = []
	for b: Vector2i in dist:
		if dist[b] >= 4:
			cands.append(b)
	if cands.is_empty():
		return
	var pp := player.global_position
	var best := cands[rng.randi() % cands.size()]
	for i in 5:
		var c := cands[rng.randi() % cands.size()]
		if _center(c).distance_to(pp) < _center(best).distance_to(pp):
			best = c
	_go(best)


## 规划一条到 target 的路（target 走不进去就取它旁边能走的一块）
func _go(target: Vector2i) -> void:
	# 追击每 0.4 秒重规划，先走完当前段，避免从拐角外侧斜切过墙。
	var in_segment := seg_t < 1.0
	var here := _block_of(seg_to if in_segment else global_position)
	var to: Vector2i = paths.nearest(target)
	if here.x < 0 or to.x < 0:
		route.clear()
		return
	var r: Array[Vector2i] = paths.path(here, to)
	if r.is_empty():
		route.clear()
		return
	if in_segment or global_position.distance_to(_center(here)) < 0.05:
		r.pop_front()
	route = r


## 沿 route 走 speed × delta；返回这一帧走了多远。到了终点 route 变空
func _follow(speed: float, delta: float) -> float:
	var left := speed * delta
	var moved := 0.0
	while left > 0.0:
		if seg_t >= 1.0:
			if route.is_empty():
				break
			seg_from = global_position
			seg_to = _center(route.pop_front())
			seg_t = 0.0
		var length := maxf(seg_from.distance_to(seg_to), 0.01)
		var step := minf(left, (1.0 - seg_t) * length)
		var next_seg_t := seg_t + step / length
		var destination := _grounded(seg_from.lerp(seg_to, next_seg_t))
		if is_nan(destination.y) or not body_space.can_move(Transform3D(Basis.IDENTITY, global_position), Transform3D(Basis.IDENTITY, destination)):
			route.clear()
			seg_t = 1.0
			break
		seg_t = next_seg_t
		left -= step
		moved += step
		global_position = destination
	if moved > 0.0:
		_face(seg_to, delta, 4.0 if speed < CHASE_SPEED else 7.0)
	return moved


## 同一块里最后几步：直接朝你走过去（高度不变）
func _approach(target: Vector3, step: float, delta: float) -> float:
	var d := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var s := minf(step, maxf(d.length() - REACH * 0.8, 0.0))
	if s <= 0.0:
		return 0.0
	var destination := _grounded(global_position + d.normalized() * s)
	if is_nan(destination.y) or not paths.walkable(_block_of(destination)) or not body_space.can_move(Transform3D(Basis.IDENTITY, global_position), Transform3D(Basis.IDENTITY, destination)):
		return 0.0
	global_position = destination
	_face(target, delta, 7.0)
	return s


func _grounded(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.2, at - Vector3.UP * 4.5)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	# 射线没有找到地面就是无支撑，本步不能沿原高度继续悬空前进。
	at.y = hit.position.y if not hit.is_empty() else NAN
	return at


func _face(target: Vector3, delta: float, rate: float) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var want := atan2(d.x, d.z)
	heading = rotate_toward(heading, want, rate * delta)
	rotation.y = heading


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func _block_of(p: Vector3) -> Vector2i:
	var b: Vector2 = maze.world_to_block(p)
	return Vector2i(floori(b.x), floori(b.y))


func _center(b: Vector2i) -> Vector3:
	return maze.block_center(b.x, b.y) + Vector3(0, maze.gen.floor_height(b.x, b.y), 0)


## 按走过的距离摆姿势：腿一前一后迈，往前摆的那条腿半路弯膝、落地前伸直，蹬地的那条脚跟抬起；
## 右臂反着晃，左手拎着钥匙几乎不动；两腿叉开时身子往下沉，提灯往前探着、走一步晃一下
func pose(dist: float) -> void:
	var ph := dist / STRIDE * PI
	model.position = Vector3(0, -absf(sin(ph)) * 0.1, 0)
	model.rotation = Vector3(0, sin(ph) * 0.05, sin(ph) * 0.02)
	for side in [["l", 1.0], ["r", -1.0]]:
		var sn: String = side[0]
		var sw: float = sin(ph) * side[1]
		_swing("thigh_" + sn, -sw * 0.38)
		var swing := maxf(cos(ph) * side[1], 0.0)      # 这条腿正往前摆
		_swing("shin_" + sn, swing * 0.6 + maxf(-sw, 0.0) * 0.15)
		_swing("foot_" + sn, -swing * 0.2 - maxf(-sw, 0.0) * 0.3)
	_swing("upperarm_r", sin(ph) * 0.22)
	_swing("forearm_r", -0.15 + sin(ph) * 0.1)
	_swing("upperarm_l", -sin(ph) * 0.08)
	_swing("hand_l", sin(ph + 0.8) * 0.12)
	_swing("spine", 0.05 + sin(ph * 2.0) * 0.02)
	_swing("neck", 0.1 + sin(ph * 2.0 + 0.5) * 0.04)
	_swing("head", sin(ph * 2.0 + 1.0) * 0.06)


## 绕骨头自己的“左右”轴转 angle
func _swing(name: String, angle: float) -> void:
	if not bones.has(name):
		return
	skel.set_bone_pose_rotation(bones[name], rest[name] * Quaternion(axis[name], angle))
