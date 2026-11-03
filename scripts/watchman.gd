extends Node3D
## 守夜人：追人的怪物。瘦高的人形（约 2.8 米），头是一只铁笼提灯，没有脸，笼里一团冷白的火；
## 那团火往前照出一道冷白的光——那道光就是它的眼睛。深灰绿长大衣、短披肩，左手拎着一大串钥匙。
## 模型来自 tools/blender/watchman.py（watchman.glb）：身体和衣服绑在一副骨骼上，走路的动作在这里按骨骼摆。
## 这一步只有外观：模型、材质、灯和走路的姿势；在迷宫里游荡、看见你就追、抓到你的部分另做。

const Model = preload("res://assets/models/watchman.glb")
const CreatureMaterials = preload("res://scripts/creature_materials.gd")

const LANTERN := Vector3(0, 2.78, 0.1)   # 提灯笼子的中心（模型坐标，和 watchman.py 一致）
const STRIDE := 1.4                      # 一步多长（米）：腿摆一个来回走两步
const GAZE_RANGE := 18.0                 # 目光那道光照多远
const GAZE_ANGLE := 22.0                 # 光束半角（度）
const LIGHT := Color(0.75, 0.87, 1.0)    # 冷白的火

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


func _ready() -> void:
	rng.randomize()
	noise.seed = rng.randi()
	noise.frequency = 3.0
	model = Model.instantiate()
	add_child(model)
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


## 材质（creature_materials.gd）；玻璃半透，火不受光照、自己发光
func _materials() -> Dictionary:
	var spec := {
		# 槽: [底色, 斑块颜色（乘在底色上）, 纹理密度, 凹凸, 粗糙度, 金属度, 双面]
		"skin": [Color(0.44, 0.42, 0.38), Color(0.72, 0.62, 0.68), 1.6, 0.5, 0.5, 0.0, false],
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
	# 火苗一跳一跳：灯和火的亮度跟着噪声走
	var f := 0.85 + 0.15 * noise.get_noise_1d(t * 10.0) + 0.05 * sin(t * 23.0)
	lamp.light_energy = 1.2 * f
	gaze.light_energy = 6.0 * f
	flame.emission_energy_multiplier = 4.0 * f


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
