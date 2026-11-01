extends Node3D
## 利维坦：拉长的菱形体，在迷宫上空缓慢旋转，间歇射出扫掠的"黑光"。

const HALF_WIDTH := 16.0
const HALF_HEIGHT := 70.0
const BEAM_LEN := 280.0
const BEAM_COUNT := 3

var spin: Node3D
var beam_pivot: Node3D
var beams: Array[Node3D] = []
var t := 0.0


func _ready() -> void:
	_build_body()
	_build_beams()

	# 自身的冷光，让菱形在雾中能被看见
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.7, 0.85)
	glow.light_energy = 3.0
	glow.omni_range = 120.0
	glow.light_volumetric_fog_energy = 0.0
	add_child(glow)


func _build_body() -> void:
	spin = Node3D.new()
	add_child(spin)

	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(0, 0, 14)
	spin.add_child(tilt)

	var body := MeshInstance3D.new()
	body.mesh = _make_diamond(HALF_WIDTH, HALF_HEIGHT)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.57, 0.6)
	mat.metallic = 0.7
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.4, 0.5)
	mat.emission_energy_multiplier = 0.3
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true   # 远景雾会把本体洗成一团灰，只保留体积雾的朦胧感
	body.material_override = mat
	tilt.add_child(body)

	# 发光的棱线
	var edges := MeshInstance3D.new()
	edges.mesh = _make_edges(HALF_WIDTH * 1.01, HALF_HEIGHT * 1.01)
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = Color(0.85, 0.92, 1.0)
	emat.disable_fog = true
	edges.material_override = emat
	edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tilt.add_child(edges)


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


func _make_edges(w: float, h: float) -> ArrayMesh:
	var p := _diamond_points(w, h)
	var pairs := [[0, 2], [0, 3], [0, 4], [0, 5], [1, 2], [1, 3], [1, 4], [1, 5],
		[2, 3], [3, 4], [4, 5], [5, 2]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for pair: Array in pairs:
		st.add_vertex(p[pair[0]])
		st.add_vertex(p[pair[1]])
	return st.commit()


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
