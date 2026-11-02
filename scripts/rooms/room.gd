extends Node3D
const ArchMesh = preload("res://scripts/arch_mesh.gd")
## 房间的公共部分：maze.gd 盖好屋顶、压暗环境光以后，把屋里交给各主题脚本（继承这个类，实现 _build()）。
## 坐标以房间地面中心为原点，x / z 是 ±size/2，y 从 0（地面）到 size.y（屋顶）。
## 道具和灯只在靠近时显示（VIS 米以内），声音按距离衰减，离远了听不见。
##
## 屋里要暗：全局环境光很亮（走道靠它照明），屋里不能吃它。围墙、地面是整座迷宫共用的材质改不了，
## 所以贴一层“内衬”——同样的土墙着色器，但关掉环境光；道具的材质也都关掉环境光，屋里只靠自己的灯。
## （本来用反射探针覆盖环境光，但 Godot 4.6 退出时会报贴图 RID 泄漏，换成这个办法）

const VIS := 40.0                # 道具的可见距离、灯的淡出距离（米）
const WALL_STEP := 5.0           # 围墙一格的宽度：每面墙分成三段，两边的段可能是门

var size := Vector3(15, 6, 15)   # maze 注入：屋里的长、高、宽
var doors: Array[Vector3] = []   # maze 注入：门洞正中，贴在屋里那一面墙上（y = 0）
var seed_value := 0
var wall_shader: Shader          # maze 注入：土墙着色器，内衬用它的“不吃环境光”版本
var gate_shape := Vector3(1.7, 3.2, 6.0)   # maze 注入：门洞拱的半宽、起拱高度、拱门墙高
var rng := RandomNumberGenerator.new()
var body: StaticBody3D           # 道具的碰撞都挂在这里


func build() -> void:
	rng.seed = seed_value
	body = StaticBody3D.new()
	add_child(body)
	_lining()
	_build()


## 内衬：贴着四面墙（门洞留空）、地面、天花板的薄板，用不吃环境光的土墙着色器
func _lining() -> void:
	var dark := Shader.new()
	dark.code = wall_shader.code.replace("render_mode blend_mix,", "render_mode blend_mix, ambient_light_disabled,")
	var m := ShaderMaterial.new()
	m.shader = dark
	const T := 0.02
	box(Vector3(size.x, T, size.z), Vector3(0, T / 2.0 + 0.002, 0), m)
	box(Vector3(size.x, T, size.z), Vector3(0, size.y - T / 2.0 - 0.002, 0), m)
	for slot in wall_slots():
		var nrm: Vector3 = slot["normal"]
		var along: Vector3 = slot["along"]
		var sz := along.abs() * WALL_STEP + nrm.abs() * T + Vector3(0, size.y, 0)
		box(sz, slot["pos"] + nrm * (T / 2.0 + 0.002) + Vector3(0, size.y / 2.0, 0), m)
	# 门洞：一片同样拱形开口的薄板贴在拱门里侧；拱门以上到屋顶再补一截
	var arch := ArchMesh.gate(WALL_STEP / 2.0, gate_shape.z, T, gate_shape.x, gate_shape.y)
	for d in doors:
		var nrm := -Vector3(signf(d.x) if absf(d.x) > absf(d.z) else 0.0, 0, signf(d.z) if absf(d.z) > absf(d.x) else 0.0)
		mesh_at(arch, Transform3D(facing(nrm), d + nrm * (T / 2.0 + 0.003)), m)
		if size.y > gate_shape.z:
			var along := Vector3(absf(nrm.z), 0, absf(nrm.x))
			box(along * WALL_STEP + nrm.abs() * T + Vector3(0, size.y - gate_shape.z, 0),
				d + nrm * (T / 2.0 + 0.002) + Vector3(0, (gate_shape.z + size.y) / 2.0, 0), m)


## 各主题实现
func _build() -> void:
	pass


## 四面墙上的“段”：每面墙三段（-5、0、+5），去掉门所在的段。
## 返回 [{pos: 段中心贴在墙面上（y = 0）, normal: 朝屋里, along: 沿墙方向}]
func wall_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := size.x / 2.0
	for nrm: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along := Vector3(nrm.z, 0, -nrm.x)
		for k: int in [-1, 0, 1]:
			var pos := -nrm * half + along * (k * WALL_STEP)
			if is_door(pos):
				continue
			out.append({"pos": pos, "normal": nrm, "along": along})
	return out


func is_door(pos: Vector3) -> bool:
	for d in doors:
		if Vector2(d.x - pos.x, d.z - pos.z).length() < 1.0:
			return true
	return false


## 方块道具：collide 时同时加一个同样大小的碰撞盒
func box(sz: Vector3, pos: Vector3, material: Material, collide := false, rot := Basis.IDENTITY,
		parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = Transform3D(rot, pos)
	mi.visibility_range_end = VIS
	mi.visibility_range_end_margin = 5.0
	(parent if parent else self).add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = sz
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = mi.global_transform
	return mi


func mesh_at(mesh: Mesh, xf: Transform3D, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	mi.visibility_range_end = VIS
	mi.visibility_range_end_margin = 5.0
	(parent if parent else self).add_child(mi)
	return mi


func mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.disable_ambient_light = true
	return m


func glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_ambient_light = true
	return m


## 点光源：离远了淡出，默认不投影（房间里灯多，投影太贵）
func lamp(pos: Vector3, color: Color, energy: float, radius: float, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = shadows
	l.distance_fade_enabled = true
	l.distance_fade_begin = VIS - 10.0
	l.distance_fade_length = 10.0
	l.position = pos
	add_child(l)
	return l


## 3D 声音，走 Ambience 总线（带混响）；max_distance 外听不见
func sound(stream: AudioStream, pos: Vector3, volume_db := 0.0, unit := 3.0, autoplay := true) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.stream = stream
	s.volume_db = volume_db
	s.unit_size = unit
	s.max_distance = 24.0
	s.bus = "Ambience"
	s.position = pos
	add_child(s)
	if autoplay:
		s.play()
	return s


## 把采样（-1～1）打包成 16 位单声道的 AudioStreamWAV
func wav(samples: PackedFloat32Array, rate := 22050, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


## 以 nrm 为朝向（局部 +z 指向 nrm）的基
func facing(nrm: Vector3) -> Basis:
	var z := nrm.normalized()
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)
