extends "res://scripts/rooms/room.gd"
## 神龛：屋顶正中开着一圈“天光”，一束冷光照在三级台座上；台座上方悬着一个缩小的黄铜菱形，
## 刻纹和天上的利维坦一样，缓缓自转、上下浮动。地上一圈残烛。越走近，低沉的嗡鸣越响。

const BodyShader = preload("res://scripts/leviathan.gdshader")

const IDOL_W := 0.45             # 菱形半宽、半高（天上的利维坦是 42 × 170，约 1:94）
const IDOL_H := 1.4
const IDOL_Y := 3.0              # 悬浮中心的高度
const CANDLES := 11

var idol: MeshInstance3D
var candle_light: OmniLight3D
var t := 0.0


func _build() -> void:
	var stone := mat(Color(0.2, 0.19, 0.18), 0.95)
	var dark := mat(Color(0.26, 0.24, 0.22), 1.0)

	# 地上一圈深色的石盘，台座立在正中
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.2
	disc.height = 0.04
	disc.radial_segments = 48
	mesh_at(disc, Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), dark)
	for i in 3:
		var w := 2.6 - i * 0.7
		box(Vector3(w, 0.25, w), Vector3(0, 0.125 + i * 0.25, 0), stone, true)

	# 天光：屋顶上一块发光的圆，加一盏往下照的聚光灯；一小柱雾让光束显形
	var sky := CylinderMesh.new()
	sky.top_radius = 1.1
	sky.bottom_radius = 1.1
	sky.height = 0.04
	mesh_at(sky, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 0.02, 0)), glow(Color(0.55, 0.6, 0.68), 1.2))
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.75, 0.82, 0.95)
	spot.light_energy = 7.0
	spot.spot_range = size.y + 2.0
	spot.spot_angle = 16.0
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 4.0
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = VIS - 10.0
	spot.distance_fade_length = 10.0
	spot.position = Vector3(0, size.y - 0.05, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	add_child(spot)
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
	fog.size = Vector3(3.0, size.y, 3.0)
	var fm := FogMaterial.new()
	fm.density = 0.08
	fm.albedo = Color(0.8, 0.85, 0.9)
	fog.material = fm
	fog.position = Vector3(0, size.y / 2.0, 0)
	add_child(fog)

	# 黄铜菱形：用利维坦的着色器，纹样尺度按比例缩小
	var k := IDOL_W / 42.0
	var m := ShaderMaterial.new()
	m.shader = BodyShader
	m.set_shader_parameter("half_width", IDOL_W)
	m.set_shader_parameter("half_height", IDOL_H)
	m.set_shader_parameter("groove_w", 0.45 * k * 2.0)
	m.set_shader_parameter("band_period", 34.0 * k)
	m.set_shader_parameter("cell", 7.0 * k)
	m.set_shader_parameter("bump", 0.2)
	m.set_shader_parameter("self_lit", 0.3)
	idol = mesh_at(_diamond(IDOL_W, IDOL_H), Transform3D(Basis.IDENTITY, Vector3(0, IDOL_Y, 0)), m)

	# 斜侧方一盏冷光，照亮菱形的侧面（天光从正上方来，只擦过它的斜面）
	lamp(Vector3(1.8, IDOL_Y + 1.0, 1.4), Color(0.75, 0.8, 0.9), 2.5, 5.0)
	lamp(Vector3(-1.6, IDOL_Y - 0.5, -1.8), Color(1.0, 0.7, 0.4), 1.5, 5.0)
	_candles()
	sound(_hum_wav(), Vector3(0, IDOL_Y, 0), -6.0, 2.5)


## 八面体：上下两个尖、腰部四个角；法线朝外、每面平的
func _diamond(w: float, h: float) -> ArrayMesh:
	var top := Vector3(0, h, 0)
	var bottom := Vector3(0, -h, 0)
	var ring: Array[Vector3] = [Vector3(w, 0, 0), Vector3(0, 0, w), Vector3(-w, 0, 0), Vector3(0, 0, -w)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a := ring[i]
		var b := ring[(i + 1) % 4]
		for tri: Array in [[top, b, a], [bottom, a, b]]:
			var p0: Vector3 = tri[0]
			var p1: Vector3 = tri[1]
			var p2: Vector3 = tri[2]
			var nrm := (p1 - p0).cross(p2 - p0).normalized()
			if nrm.dot(p0 + p1 + p2) < 0.0:
				nrm = -nrm
				var tmp := p1
				p1 = p2
				p2 = tmp
			for v: Vector3 in [p0, p1, p2]:
				st.set_normal(nrm)
				st.add_vertex(v)
	return st.commit()


## 一圈高矮不一的残烛，一盏暖光微微跳动
func _candles() -> void:
	var wax := mat(Color(0.62, 0.56, 0.45), 0.7)
	var flame := glow(Color(1.0, 0.62, 0.28), 4.0)
	for i in CANDLES:
		var a := TAU * i / CANDLES + rng.randf_range(-0.1, 0.1)
		var r := 3.3 + rng.randf_range(-0.2, 0.2)
		var h := rng.randf_range(0.12, 0.5)
		var c := CylinderMesh.new()
		c.top_radius = 0.06
		c.bottom_radius = 0.07
		c.height = h
		c.radial_segments = 10
		var pos := Vector3(cos(a) * r, h / 2.0, sin(a) * r)
		mesh_at(c, Transform3D(Basis.IDENTITY, pos), wax)
		if rng.randf() < 0.75:
			box(Vector3(0.03, 0.07, 0.03), pos + Vector3(0, h / 2.0 + 0.04, 0), flame)
	candle_light = lamp(Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.3), 1.5, 6.5)


## 低沉的嗡鸣：55 Hz 加泛音，两个频率差一点点，听起来像在缓慢地呼吸；4 秒一循环
func _hum_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 4
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var v := 0.5 * sin(TAU * 55.0 * tt) + 0.3 * sin(TAU * 55.5 * tt) \
			+ 0.18 * sin(TAU * 110.0 * tt) + 0.08 * sin(TAU * 165.25 * tt)
		s[i] = v * (0.75 + 0.25 * sin(TAU * tt / 4.0)) * 0.7
	return wav(s, rate, true)


func _process(delta: float) -> void:
	t += delta
	idol.rotation.y = t * 0.25
	idol.position.y = IDOL_Y + sin(t * 0.7) * 0.08
	candle_light.light_energy = 1.5 + 0.2 * sin(t * 13.0) * sin(t * 7.3)
