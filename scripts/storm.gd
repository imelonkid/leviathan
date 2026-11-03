extends Node3D
## 风暴：光线步进的体积乌云（sky.gdshader）、缠绕利维坦的云环（cloud_ring.gdshader）、偶尔的闪电。
## 闪电时通过全局着色器参数 lightning 让天空和云一起亮，再打一盏短暂的平行光照亮整个场景，
## 画一道折线状的电光，过一两秒传来雷声（drone.gd）。
## 约三成闪电劈在玩家附近的迷宫墙头上：落点留下一团余光（蓝白转暗橙，约 1.5 秒熄掉）和一把火星。

const SkyShader = preload("res://scripts/sky.gdshader")
const CloudRingShader = preload("res://scripts/cloud_ring.gdshader")
const MazeGen = preload("res://scripts/maze_gen.gd")

const STRIKE_MIN := 5.0          # 两次闪电之间的间隔（秒）
const STRIKE_MAX := 14.0
const BOLT_WIDTH := 2.5
const FLICKER_STEP := 0.08
const RING_OUTER := 380.0        # 云环包围盒的半宽、半高、中心相对利维坦往上偏多少（米）
const RING_HALF_H := 180.0
const RING_Y_BIAS := 30.0
const NEAR_CHANCE := 0.3         # 闪电劈在玩家附近迷宫里的概率
const NEAR_MIN := 3              # 附近：离玩家几块以外、几块以内（一块 5 米）
const NEAR_MAX := 12
const GLOW_TIME := 1.5           # 落点余光多久熄掉（秒）
const GLOW_ENERGY := 12.0
const GLOW_HOT := Color(0.75, 0.85, 1.0)
const GLOW_COLD := Color(1.0, 0.42, 0.12)
## 乌云质量（settings 的 clouds：0 低 / 1 中 / 2 高）：天空步进次数、每步朝亮处探几次、
## 是否在半分辨率里步进、云环步进次数（0 = 不画云环）
const CLOUD_QUALITY := [
	{"steps": 32, "light": 1, "half": true, "ring": 0},
	{"steps": 40, "light": 2, "half": true, "ring": 24},
	{"steps": 48, "light": 3, "half": false, "ring": 40},
]

var env: Environment             # main 注入
var drone: Node                  # main 注入，用来打雷
var settings: Node               # main 注入，乌云质量跟着画质走
var maze: Node3D                 # main 注入，找附近的墙头当落点
var center := Vector3.ZERO       # 利维坦的位置，闪电围着它
var rng := RandomNumberGenerator.new()
var sky_mat: ShaderMaterial
var sky_half: Shader             # 半分辨率版的天空着色器
var ring: MeshInstance3D
var ring_mat: ShaderMaterial
var flash_light: DirectionalLight3D
var bolt: MeshInstance3D
var bolt_mat: ShaderMaterial
var next_strike := 3.0
var flash_t := -1.0              # 本次闪电开始后的时间；< 0 表示没有闪电
var flicker: Array[float] = []   # 本次闪电的亮度变化，每 FLICKER_STEP 秒一个值
var glow: OmniLight3D            # 落点余光
var glow_t := -1.0               # 余光亮起后的时间；< 0 表示没有
var spark_mat: StandardMaterial3D
var halo: MeshInstance3D         # 落点的一团光晕：站在街上看不见墙头，也看得出那里烧着
var halo_mat: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	_build_sky()
	_build_cloud_ring()

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

	glow = OmniLight3D.new()
	glow.omni_range = 16.0
	glow.omni_attenuation = 1.5
	glow.light_energy = 0.0
	glow.light_volumetric_fog_energy = 1.5
	glow.shadow_enabled = false
	glow.visible = false
	add_child(glow)

	halo_mat = StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.no_depth_test = false
	halo_mat.disable_fog = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1))
	g.set_color(1, Color(0, 0, 0))
	g.add_point(0.25, Color(0.35, 0.35, 0.35))
	soft.gradient = g
	halo_mat.albedo_texture = soft
	var hq := QuadMesh.new()
	hq.size = Vector2(6, 6)
	hq.material = halo_mat
	halo = MeshInstance3D.new()
	halo.mesh = hq
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.visible = false
	add_child(halo)

	spark_mat = StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_mat.vertex_color_use_as_albedo = true
	spark_mat.albedo_texture = soft

	if settings:
		settings.changed.connect(_apply_quality)
	_apply_quality()


func _build_sky() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SkyShader
	sky_half = Shader.new()
	sky_half.code = SkyShader.code.replace("shader_type sky;",
		"shader_type sky;\nrender_mode use_half_res_pass;\n#define HALF_RES")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.background_mode = Environment.BG_SKY


## 云环：一个包住利维坦周围的盒子，着色器在里面做体积云（盒子只是给它一块画布）
func _build_cloud_ring() -> void:
	ring_mat = ShaderMaterial.new()
	ring_mat.shader = CloudRingShader
	ring_mat.set_shader_parameter("center", center)
	ring_mat.set_shader_parameter("r_outer", RING_OUTER)
	ring_mat.set_shader_parameter("half_h", RING_HALF_H)
	ring_mat.set_shader_parameter("y_bias", RING_Y_BIAS)
	var box := BoxMesh.new()
	box.size = Vector3(RING_OUTER * 2.0, RING_HALF_H * 2.0, RING_OUTER * 2.0)
	ring = MeshInstance3D.new()
	ring.mesh = box
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = center + Vector3(0, RING_Y_BIAS, 0)
	add_child(ring)


func _apply_quality() -> void:
	var q: Dictionary = CLOUD_QUALITY[clampi(settings.get_value("clouds") if settings else 2, 0, 2)]
	var shader: Shader = sky_half if q["half"] else SkyShader
	if sky_mat.shader != shader:
		sky_mat.shader = shader
	sky_mat.set_shader_parameter("steps", q["steps"])
	sky_mat.set_shader_parameter("light_steps", q["light"])
	ring.visible = q["ring"] > 0
	ring_mat.set_shader_parameter("steps", maxi(q["ring"], 1))


func _process(delta: float) -> void:
	next_strike -= delta
	if next_strike <= 0.0:
		_strike()
		next_strike = rng.randf_range(STRIKE_MIN, STRIKE_MAX)

	var v := 0.0
	if flash_t >= 0.0:
		flash_t += delta
		var i := int(flash_t / FLICKER_STEP)
		if i < flicker.size():
			v = flicker[i]
		else:
			flash_t = -1.0
	RenderingServer.global_shader_parameter_set("lightning", v)
	flash_light.light_energy = v * 2.2
	bolt.visible = v > 0.15

	if glow_t >= 0.0:
		glow_t += delta
		var k := clampf(glow_t / GLOW_TIME, 0.0, 1.0)
		glow.light_color = GLOW_HOT.lerp(GLOW_COLD, sqrt(k))
		var e := pow(1.0 - k, 2.0) * (0.85 + 0.15 * sin(glow_t * 40.0))
		glow.light_energy = GLOW_ENERGY * e
		halo_mat.albedo_color = glow.light_color * e * 1.5
		if k >= 1.0:
			glow_t = -1.0
			glow.visible = false
			halo.visible = false


## 一次闪电：选起点终点、画电光、排好闪烁节奏、预约雷声。from / to 不给就随机
func _strike(from := Vector3.INF, to := Vector3.INF) -> void:
	var ang := rng.randf() * TAU
	# 从云底劈下来
	var start := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(120.0, 320.0) \
		+ Vector3(0, center.y + rng.randf_range(120.0, 220.0), 0)
	var end: Vector3
	if rng.randf() < 0.7:
		# 劈向地面：迷宫里或远处的装饰迷宫
		var a2 := ang + rng.randf_range(-0.8, 0.8)
		end = Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(40.0, 380.0)
	else:
		# 云间闪电：横着窜
		var a2 := ang + rng.randf_range(0.4, 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		end = Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(120.0, 320.0) \
			+ Vector3(0, center.y + rng.randf_range(60.0, 180.0), 0)
	var near := Vector3.INF
	if from == Vector3.INF and rng.randf() < NEAR_CHANCE:
		near = _near_target()
	if near != Vector3.INF:
		# 劈在身边的墙头上：从正上方偏一点的云底下来
		end = near
		start = near + Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
		start.y = center.y + rng.randf_range(120.0, 220.0)
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
	if near != Vector3.INF:
		_afterglow(near)

	if drone and drone.has_method("thunder"):
		var cam := get_viewport().get_camera_3d()
		var dist := cam.global_position.distance_to((start + end) / 2.0) if cam else 300.0
		# 声速约 340 米/秒；越远越轻
		drone.thunder(dist / 340.0, clampf(1.4 - dist / 600.0, 0.4, 1.2))


## 玩家附近的一段墙头：随便挑几块墙，取最高的那块（闪电爱劈高处）；找不到返回 INF
func _near_target() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if maze == null or maze.gen == null or cam == null:
		return Vector3.INF
	var gen: RefCounted = maze.gen
	var here: Vector2 = maze.world_to_block(cam.global_position)
	var best := Vector3.INF
	for i in 24:
		var a := rng.randf() * TAU
		var r := rng.randf_range(NEAR_MIN, NEAR_MAX)
		var x := int(here.x + cos(a) * r)
		var z := int(here.y + sin(a) * r)
		if x < 0 or z < 0 or x >= gen.n or z >= gen.n or gen.kind[z][x] != MazeGen.WALL:
			continue
		var top: float = gen.wall_top[z][x]
		if best == Vector3.INF or top > best.y:
			best = maze._block_to_world(x, z) + Vector3(0, top, 0)
	return best


## 落点余光：一盏从蓝白转暗橙、慢慢熄掉的灯，加一把四散落下的火星
func _afterglow(at: Vector3) -> void:
	glow.global_position = at + Vector3(0, 2.5, 0)
	glow.visible = true
	halo.global_position = at + Vector3(0, 2.0, 0)
	halo.visible = true
	glow_t = 0.0

	var sparks := GPUParticles3D.new()
	sparks.one_shot = true
	sparks.amount = 60
	sparks.lifetime = 1.4
	sparks.explosiveness = 0.95
	sparks.local_coords = false
	sparks.visibility_aabb = AABB(Vector3(-10, -14, -10), Vector3(20, 20, 20))
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.lifetime_randomness = 0.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.4))
	fade.set_color(1, Color(0.5, 0.08, 0.0, 0.0))
	fade.add_point(0.3, Color(1.0, 0.4, 0.06))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	sparks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	q.material = spark_mat
	sparks.draw_pass_1 = q
	add_child(sparks)
	sparks.global_position = at + Vector3(0, 0.3, 0)
	sparks.emitting = true
	get_tree().create_timer(2.5).timeout.connect(sparks.queue_free)


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
