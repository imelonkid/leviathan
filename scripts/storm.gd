extends Node3D
## 风暴：乌云密布的天空（sky.gdshader）、围着利维坦翻滚的云团（cloud.gdshader）、偶尔的闪电。
## 闪电时通过全局着色器参数 lightning 让天空和云一起亮，再打一盏短暂的平行光照亮整个场景，
## 画一道折线状的电光，过一两秒传来雷声（drone.gd）。

const SkyShader = preload("res://scripts/sky.gdshader")
const CloudShader = preload("res://scripts/cloud.gdshader")

const STRIKE_MIN := 5.0          # 两次闪电之间的间隔（秒）
const STRIKE_MAX := 14.0
const BOLT_WIDTH := 2.5

var env: Environment             # main 注入
var drone: Node                  # main 注入，用来打雷
var center := Vector3.ZERO       # 利维坦的位置，云围着它
var rng := RandomNumberGenerator.new()
var flash_light: DirectionalLight3D
var bolt: MeshInstance3D
var bolt_mat: ShaderMaterial
var next_strike := 3.0
var flash_t := -1.0              # 本次闪电开始后的时间；< 0 表示没有闪电
var flicker: Array[float] = []   # 本次闪电的亮度变化，每 0.05 秒一个值


func _ready() -> void:
	rng.randomize()
	_build_sky()
	_build_clouds()

	flash_light = DirectionalLight3D.new()
	flash_light.light_color = Color(0.75, 0.82, 1.0)
	flash_light.light_energy = 0.0
	flash_light.light_volumetric_fog_energy = 0.6
	flash_light.shadow_enabled = false
	add_child(flash_light)

	bolt_mat = ShaderMaterial.new()
	bolt_mat.shader = Shader.new()
	# 叠加混合、排在云后面画：电光穿过云团时不会被云盖住
	bolt_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float energy = 6.0;
void fragment() {
	ALBEDO = vec3(0.78, 0.86, 1.0) * energy;
}
"""
	bolt_mat.render_priority = 10
	bolt = MeshInstance3D.new()
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.visible = false
	add_child(bolt)


func _build_sky() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SkyShader
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY


## 云团：一圈围着利维坦腰部和头顶，一层低垂在整片迷宫上空
func _build_clouds() -> void:
	var xforms: Array[Transform3D] = []
	# 围着利维坦的环：贴得近一些、厚一些，半遮半掩
	for i in 140:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(60.0, 240.0)
		var y := center.y + rng.randf_range(-40.0, 140.0)
		var s := rng.randf_range(70.0, 150.0)
		xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(cos(ang) * r, y, sin(ang) * r)))
	# 头顶的云层：盖住整片地狱，比利维坦顶还高一点
	for i in 160:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 700.0
		var y := center.y + rng.randf_range(110.0, 220.0)
		var s := rng.randf_range(140.0, 260.0)
		xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(cos(ang) * r, y, sin(ang) * r)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	mm.mesh = quad
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mat := ShaderMaterial.new()
	mat.shader = CloudShader
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 云团很大，包围盒手动放大，免得镜头一转整片被剔掉
	mmi.custom_aabb = AABB(Vector3(-1000, -200, -1000), Vector3(2000, 800, 2000))
	add_child(mmi)


func _process(delta: float) -> void:
	next_strike -= delta
	if next_strike <= 0.0:
		_strike()
		next_strike = rng.randf_range(STRIKE_MIN, STRIKE_MAX)

	var v := 0.0
	if flash_t >= 0.0:
		flash_t += delta
		var i := int(flash_t / 0.05)
		if i < flicker.size():
			v = flicker[i]
		else:
			flash_t = -1.0
	RenderingServer.global_shader_parameter_set("lightning", v)
	flash_light.light_energy = v * 2.2
	bolt.visible = v > 0.15


## 一次闪电：选起点终点、画电光、排好闪烁节奏、预约雷声。from / to 不给就随机
func _strike(from := Vector3.INF, to := Vector3.INF) -> void:
	var ang := rng.randf() * TAU
	var start := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(80.0, 260.0) \
		+ Vector3(0, center.y + rng.randf_range(20.0, 90.0), 0)
	var end: Vector3
	if rng.randf() < 0.7:
		# 劈向地面：迷宫里或远处的装饰迷宫
		var a2 := ang + rng.randf_range(-0.8, 0.8)
		end = Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(40.0, 380.0)
	else:
		# 云间闪电：横着窜
		var a2 := ang + rng.randf_range(0.4, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		end = Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(80.0, 260.0) \
			+ Vector3(0, center.y + rng.randf_range(-20.0, 60.0), 0)
	if from != Vector3.INF:
		start = from
		end = to
	bolt.mesh = _make_bolt(start, end)
	flash_light.look_at_from_position(start, end, Vector3.UP if absf((end - start).normalized().y) < 0.99 else Vector3.FORWARD)

	# 亮一下、暗一下、再亮一下，然后熄灭
	flicker = [1.0, 0.7, 0.15, 0.0, 0.9, 0.5, 0.25, 0.1]
	if rng.randf() < 0.4:
		flicker.append_array([0.0, 0.0, 0.8, 0.4, 0.15])
	flash_t = 0.0

	if drone and drone.has_method("thunder"):
		var cam := get_viewport().get_camera_3d()
		var dist := cam.global_position.distance_to((start + end) / 2.0) if cam else 300.0
		# 声速约 340 米/秒；越远越轻
		drone.thunder(dist / 340.0, clampf(1.4 - dist / 600.0, 0.4, 1.2))


## 电光：中点位移出折线，再加两条分叉；每段做成朝向镜头的窄带，才看得见粗细
func _make_bolt(a: Vector3, b: Vector3) -> ArrayMesh:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.ZERO
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _jagged(a, b, 7)
	_ribbon(st, main, BOLT_WIDTH, eye)
	for i in 2:
		var from: Vector3 = main[rng.randi_range(main.size() / 5, main.size() * 3 / 4)]
		var dir := (b - a).normalized().rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
		var to := from + (dir + Vector3(0, -0.4, 0)).normalized() * (a.distance_to(b) * rng.randf_range(0.15, 0.35))
		_ribbon(st, _jagged(from, to, 5), BOLT_WIDTH * 0.6, eye)
	var mesh := st.commit()
	mesh.surface_set_material(0, bolt_mat)
	return mesh


## 中点位移：每轮把每段从中间折一下，偏移量随段长缩小
func _jagged(a: Vector3, b: Vector3, depth: int) -> Array[Vector3]:
	var pts: Array[Vector3] = [a, b]
	var amount := a.distance_to(b) * 0.18
	for d in depth:
		var next: Array[Vector3] = [pts[0]]
		for i in pts.size() - 1:
			var mid := (pts[i] + pts[i + 1]) / 2.0
			mid += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * amount
			next.append(mid)
			next.append(pts[i + 1])
		pts = next
		amount *= 0.55
	return pts


func _ribbon(st: SurfaceTool, pts: Array[Vector3], width: float, eye: Vector3) -> void:
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var side := (p1 - p0).cross(eye - (p0 + p1) / 2.0).normalized() * width / 2.0
		for v: Vector3 in [p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side]:
			st.add_vertex(v)
