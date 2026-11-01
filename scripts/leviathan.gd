extends Node3D
## 利维坦：竖直悬浮的巨大菱形体，旧黄铜表面刻满纹样（leviathan.gdshader），
## 绕自身竖轴缓慢旋转，从下端间歇射出扫掠的“黑光”。

const BodyShader = preload("res://scripts/leviathan.gdshader")

const HALF_WIDTH := 42.0         # 宽高比约 1:4，太瘦就没有分量
const HALF_HEIGHT := 170.0
const BEAM_LEN := 420.0
const BEAM_COUNT := 3
const BODY_LAYER := 2            # 本体单独放一个渲染层，专属主光只照它

var spin: Node3D
var beam_pivot: Node3D
var beams: Array[Node3D] = []
var t := 0.0


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


## 黑光：从下端尖角射出。光柱正中是不透光的纯黑，往边缘渐渐变淡、越往远端越淡，
## 看起来是一道“黑色的光”而不是一根黑棍子；外面再套一圈黑色雾体，在体积雾里显出晕
func _build_beams() -> void:
	beam_pivot = Node3D.new()
	beam_pivot.position.y = -HALF_HEIGHT * 0.92
	add_child(beam_pivot)

	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = Shader.new()
	beam_mat.shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float length = 420.0;
varying float along;
void vertex() {
	along = 0.5 - VERTEX.y / length;   // 0 = 射出的一端，1 = 远端
}
void fragment() {
	float core = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float fade = 1.0 - smoothstep(0.55, 1.0, along);
	ALBEDO = vec3(0.0);
	ALPHA = core * fade;
}
"""
	beam_mat.set_shader_parameter("length", BEAM_LEN)

	# 黑色雾体：在体积雾里"吸走"光，形成黑光柱
	var fog_mat := FogMaterial.new()
	fog_mat.density = 0.8
	fog_mat.albedo = Color(0, 0, 0)
	fog_mat.emission = Color(0, 0, 0)

	for i in BEAM_COUNT:
		var root := Node3D.new()
		root.rotation.y = TAU * i / BEAM_COUNT
		beam_pivot.add_child(root)

		var tilt := Node3D.new()
		root.add_child(tilt)

		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.5
		cyl.bottom_radius = 5.0
		cyl.height = BEAM_LEN
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = -BEAM_LEN / 2.0
		tilt.add_child(mi)

		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		fv.size = Vector3(16.0, BEAM_LEN, 16.0)
		fv.material = fog_mat
		fv.position.y = -BEAM_LEN / 2.0
		tilt.add_child(fv)

		beams.append(tilt)


func _process(delta: float) -> void:
	t += delta
	spin.rotate_y(delta * 0.06)
	beam_pivot.rotate_y(delta * 0.1)
	for i in beams.size():
		var b := beams[i]
		# 光束在 20°~60° 之间来回摆动（从下端射出，角度要大才扫得到外圈）
		b.rotation.x = deg_to_rad(40.0 + 20.0 * sin(t * 0.25 + i * 2.1))
		# 每束光亮 7 秒、灭 5 秒，彼此错开
		b.visible = fmod(t + i * 4.0, 12.0) < 7.0
