extends Node3D
## 利维坦：竖直悬浮的巨大菱形体，旧黄铜表面刻满纹样（leviathan.gdshader），
## 绕自身竖轴缓慢旋转，从腰部射出两束稳定旋转的“黑光”。

const BodyShader = preload("res://scripts/leviathan.gdshader")

const HALF_WIDTH := 42.0         # 宽高比约 1:4，太瘦就没有分量
const HALF_HEIGHT := 170.0
const BEAM_LEN := 420.0
const BEAM_COUNT := 2
const BEAM_DIP := 66.0           # 光束从水平往下的角度：从 250 米高空斜射，落地处离中心约 110 米，扫过迷宫各层
const BEAM_CONES := [            # 每束由三层锥体叠成：[起点半径, 远端半径, 不透明度, 锐度]
	[2.5, 16.0, 1.0, 0.5],       # 实心的芯
	[5.0, 34.0, 1.0, 1.4],       # 主体
	[10.0, 75.0, 0.6, 1.0],      # 外面的暗晕
]
const BEAM_SPEED := 0.12         # 光束旋转的角速度（弧度/秒），约 52 秒转一圈
const BODY_LAYER := 2            # 本体单独放一个渲染层，专属主光只照它

var spin: Node3D
var beam_pivot: Node3D
var beams: Array[Node3D] = []


func _ready() -> void:
	_build_body()
	_build_beams()

	# 专属主光：从云层亮处（左上方）斜照过来，只照本体（cull_mask），
	# 让它一面亮一面暗，棱线分明；不影响迷宫的阴沉
	var key := DirectionalLight3D.new()
	key.light_color = Color(0.92, 0.88, 0.8)
	key.light_energy = 0.9
	key.light_cull_mask = 1 << (BODY_LAYER - 1)
	key.light_volumetric_fog_energy = 0.0
	key.shadow_enabled = false
	add_child(key)
	key.rotation_degrees = Vector3(-20, -140, 0)


func _build_body() -> void:
	spin = Node3D.new()
	add_child(spin)

	var body := MeshInstance3D.new()
	body.mesh = _make_diamond(HALF_WIDTH, HALF_HEIGHT)
	var mat := ShaderMaterial.new()
	mat.shader = BodyShader
	mat.set_shader_parameter("half_width", HALF_WIDTH)
	mat.set_shader_parameter("half_height", HALF_HEIGHT)
	body.material_override = mat
	body.layers = 1 | (1 << (BODY_LAYER - 1))
	spin.add_child(body)


func _diamond_points(w: float, h: float) -> Array[Vector3]:
	return [
		Vector3(0, h, 0), Vector3(0, -h, 0),
		Vector3(w, 0, 0), Vector3(0, 0, w), Vector3(-w, 0, 0), Vector3(0, 0, -w),
	]


func _make_diamond(w: float, h: float) -> ArrayMesh:
	var p := _diamond_points(w, h)
	var ring := [2, 3, 4, 5]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: int = ring[i]
		var b: int = ring[(i + 1) % 4]
		_add_tri(st, p[0], p[a], p[b])
		_add_tri(st, p[1], p[b], p[a])
	return st.commit()


## 三角形法线统一朝外，避免光照反了
func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot((a + b + c) / 3.0) < 0.0:
		nrm = -nrm
		var tmp := b
		b = c
		c = tmp
	for v: Vector3 in [a, b, c]:
		st.set_normal(nrm)
		st.add_vertex(v)


## 黑光：从腰部射出两束，方向相反，以固定的俯角稳定旋转，像探照灯一样扫过迷宫。
## 每束是一个越往外越宽的锥体：正中浓黑、边缘渐淡、远端消散，里面有往外流动的暗纹，
## 外面再罩一层更宽更淡的暗晕——是“黑色的光”，不是黑棍子。
## （不再套黑色雾体：长圆柱在近处的体积雾里会切出生硬的黑边）
func _build_beams() -> void:
	beam_pivot = Node3D.new()
	add_child(beam_pivot)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float length = 420.0;
uniform float strength = 1.0;     // 不透明度上限
uniform float sharpness = 2.0;    // 越大中间越实、边缘越虚
varying float along;
varying float angle;
void vertex() {
	along = 0.5 - VERTEX.y / length;   // 0 = 射出的一端，1 = 远端
	angle = atan(VERTEX.z, VERTEX.x);
}
void fragment() {
	float core = pow(abs(dot(NORMAL, VIEW)), sharpness);
	float fade = smoothstep(0.0, 0.04, along) * (1.0 - smoothstep(0.62, 0.95, along));
	// 往外流动的暗纹，让它像在“发射”而不是静止的柱子
	float flow = 0.8 + 0.2 * sin(angle * 7.0 + along * 60.0 - TIME * 4.0) * sin(angle * 3.0 - TIME * 1.1);
	ALBEDO = vec3(0.0);
	ALPHA = clamp(core * fade * flow * strength, 0.0, 1.0);
}
"""
	var mats: Array[ShaderMaterial] = []
	for c: Array in BEAM_CONES:
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("length", BEAM_LEN)
		m.set_shader_parameter("strength", c[2])
		m.set_shader_parameter("sharpness", c[3])
		m.render_priority = 1
		mats.append(m)

	for i in BEAM_COUNT:
		var root := Node3D.new()
		root.rotation.y = TAU * i / BEAM_COUNT
		beam_pivot.add_child(root)

		# 俯角：从水平往下 BEAM_DIP 度
		var tilt := Node3D.new()
		tilt.rotation.x = deg_to_rad(90.0 - BEAM_DIP)
		root.add_child(tilt)

		for k in BEAM_CONES.size():
			var cone := CylinderMesh.new()
			cone.top_radius = BEAM_CONES[k][0]
			cone.bottom_radius = BEAM_CONES[k][1]
			cone.height = BEAM_LEN
			cone.radial_segments = 48
			cone.cap_top = false
			cone.cap_bottom = false
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = mats[k]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position.y = -BEAM_LEN / 2.0
			tilt.add_child(mi)

		beams.append(tilt)


func _process(delta: float) -> void:
	spin.rotate_y(delta * 0.06)
	beam_pivot.rotate_y(delta * BEAM_SPEED)


## 某一点被黑光照到的程度（0～1）：在光锥的芯里是 1，到暗晕外缘降到 0。
## main 用它给镜头加“被黑光打中”的画面和声音
func beam_exposure(p: Vector3) -> float:
	var best := 0.0
	var origin := beam_pivot.global_position
	for b in beams:
		var dir := -b.global_transform.basis.y
		var v := p - origin
		var along := v.dot(dir)
		if along <= 0.0 or along > BEAM_LEN * 0.95:
			continue
		var k := along / BEAM_LEN
		var radial := (v - dir * along).length()
		var inner := lerpf(BEAM_CONES[1][0], BEAM_CONES[1][1], k) * 0.6
		var outer := lerpf(BEAM_CONES[2][0], BEAM_CONES[2][1], k)
		best = maxf(best, 1.0 - smoothstep(inner, outer, radial))
	return best
