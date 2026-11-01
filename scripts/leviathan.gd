extends Node3D
## 利维坦：拉长的菱形体，旧黄铜表面刻满纹样（leviathan.gdshader），
## 在迷宫上空缓慢旋转，间歇射出扫掠的"黑光"。

const BodyShader = preload("res://scripts/leviathan.gdshader")

const HALF_WIDTH := 20.0
const HALF_HEIGHT := 120.0
const BEAM_LEN := 340.0
const BEAM_COUNT := 3

var spin: Node3D
var beam_pivot: Node3D
var beams: Array[Node3D] = []
var t := 0.0


func _ready() -> void:
	_build_body()
	_build_beams()

	# 照亮本体的两盏灯，放在外面（放在中心会只照亮内侧）：
	# 一侧偏暖的主光照出黄铜和刻纹，另一侧冷色的补光，像被云层反射的天光
	for l: Array in [[Vector3(110, 60, 90), Color(1.0, 0.86, 0.66), 14.0], [Vector3(-100, -20, -110), Color(0.55, 0.65, 0.85), 6.0]]:
		var light := OmniLight3D.new()
		light.position = l[0]
		light.light_color = l[1]
		light.light_energy = l[2]
		light.omni_range = 340.0
		light.omni_attenuation = 0.6
		light.light_volumetric_fog_energy = 0.0
		add_child(light)


func _build_body() -> void:
	spin = Node3D.new()
	add_child(spin)

	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(0, 0, 14)
	spin.add_child(tilt)

	var body := MeshInstance3D.new()
	body.mesh = _make_diamond(HALF_WIDTH, HALF_HEIGHT)
	var mat := ShaderMaterial.new()
	mat.shader = BodyShader
	mat.set_shader_parameter("half_width", HALF_WIDTH)
	mat.set_shader_parameter("half_height", HALF_HEIGHT)
	body.material_override = mat
	tilt.add_child(body)


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


func _build_beams() -> void:
	beam_pivot = Node3D.new()
	add_child(beam_pivot)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(0, 0, 0, 0.85)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

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
		cyl.top_radius = 1.0
		cyl.bottom_radius = 2.2
		cyl.height = BEAM_LEN
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.material_override = beam_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = -BEAM_LEN / 2.0
		tilt.add_child(mi)

		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		fv.size = Vector3(8.0, BEAM_LEN, 8.0)
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
		# 光束在 8°~36° 之间来回摆动，扫过迷宫
		b.rotation.x = deg_to_rad(22.0 + 14.0 * sin(t * 0.25 + i * 2.1))
		# 每束光亮 7 秒、灭 5 秒，彼此错开
		b.visible = fmod(t + i * 4.0, 12.0) < 7.0
