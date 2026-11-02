extends "res://scripts/rooms/room.gd"
## 钟房：四面墙上挂满大大小小的钟，各走各的——有的飞转、有的倒走、有的停了；
## 角落里一座落地钟，钟摆来回摆。滴答声此起彼伏，从不对齐。屋子正中吊着一只昏黄的灯泡。

const SPEEDS: Array[float] = [1.0, 1.0, 3.0, 12.0, -2.0, -0.5, 0.0, 40.0]   # 分针转速（每分钟几圈）

var hands: Array[Array] = []     # [[指针节点, 每秒转多少弧度], ...]
var tickers: Array[Array] = []   # [[声音, 间隔, 计时], ...]
var pendulum: Node3D
var tock: AudioStreamPlayer3D
var t := 0.0
var last_side := 0.0


func _build() -> void:
	var wood := mat(Color(0.16, 0.1, 0.06), 0.7)
	var face := mat(Color(0.7, 0.66, 0.55), 0.6)
	var black := mat(Color(0.03, 0.03, 0.03), 0.4, 0.3)
	var brass := mat(Color(0.55, 0.42, 0.22), 0.35, 0.9)
	var tick := _tick_wav()

	for slot in wall_slots():
		var count := rng.randi_range(1, 3)
		for i in count:
			var r := rng.randf_range(0.25, 0.75)
			var y := 1.4 + (size.y - 2.4) * (i + rng.randf_range(0.2, 0.8)) / count
			var off := rng.randf_range(-1.6, 1.6)
			var pos: Vector3 = slot["pos"] + slot["along"] * off + Vector3(0, y, 0)
			_clock(pos, slot["normal"], r, wood, face, black)
		# 每段墙一个滴答声，间隔各不相同
		var s := sound(tick, slot["pos"] + slot["normal"] * 0.3 + Vector3(0, 2.5, 0), -10.0, 2.0, false)
		tickers.append([s, rng.randf_range(0.45, 1.4), rng.randf()])

	_grandfather(wood, face, black, brass)

	# 正中的灯泡
	box(Vector3(0.015, 1.6, 0.015), Vector3(0, size.y - 0.8, 0), black)
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	mesh_at(bulb, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 1.7, 0)), glow(Color(1.0, 0.72, 0.4), 3.0))
	lamp(Vector3(0, size.y - 1.8, 0), Color(1.0, 0.72, 0.42), 1.3, 11.0)


## 一只挂钟：背板、表盘、12 个刻度、时针分针。局部 +z 朝屋里
func _clock(pos: Vector3, nrm: Vector3, r: float, wood: Material, face: Material, black: Material) -> void:
	var clock := Node3D.new()
	clock.transform = Transform3D(facing(nrm), pos + nrm * 0.04)
	add_child(clock)
	var axis := Basis(Vector3.RIGHT, PI / 2.0)   # 圆柱的轴转到 z 上
	var back := CylinderMesh.new()
	back.top_radius = r * 1.15
	back.bottom_radius = r * 1.15
	back.height = 0.08
	back.radial_segments = 32
	mesh_at(back, Transform3D(axis, Vector3.ZERO), wood, clock)
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.02
	disc.radial_segments = 32
	mesh_at(disc, Transform3D(axis, Vector3(0, 0, 0.05)), face, clock)
	for i in 12:
		var a := TAU * i / 12.0
		var long := i % 3 == 0
		box(Vector3(r * 0.04, r * (0.16 if long else 0.08), 0.01),
			Vector3(sin(a), cos(a), 0) * r * 0.82 + Vector3(0, 0, 0.065), black,
			false, Basis(Vector3.BACK, -a), clock)

	var speed: float = SPEEDS[rng.randi_range(0, SPEEDS.size() - 1)]
	var minute_rate := -TAU * speed / 60.0           # 顺时针为负
	var start := rng.randf() * TAU
	for spec: Array in [[0.5, 0.07, minute_rate / 12.0, 0.07], [0.78, 0.04, minute_rate, 0.08]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, spec[3])
		pivot.rotation.z = start * (1.0 if spec[2] == minute_rate else 0.3)
		clock.add_child(pivot)
		var length: float = r * spec[0]
		box(Vector3(r * spec[1], length, 0.01), Vector3(0, length / 2.0 - r * 0.08, 0), black, false, Basis.IDENTITY, pivot)
		hands.append([pivot, spec[2]])


## 落地钟：放在一个两边都不是门的屋角，钟摆露在外面来回摆
func _grandfather(wood: Material, face: Material, black: Material, brass: Material) -> void:
	var half := size.x / 2.0
	for corner: Vector3 in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		if is_door(Vector3(corner.x * half, 0, corner.z * WALL_STEP)) or is_door(Vector3(corner.x * WALL_STEP, 0, corner.z * half)):
			continue
		var pos := Vector3(corner.x * (half - 0.9), 0, corner.z * (half - 0.9))
		var nrm := -Vector3(corner.x, 0, corner.z).normalized()
		var root := Node3D.new()
		root.transform = Transform3D(facing(nrm), pos)
		add_child(root)
		box(Vector3(0.9, 0.6, 0.55), Vector3(0, 0.3, 0), wood, false, Basis.IDENTITY, root)
		box(Vector3(0.1, 1.6, 0.5), Vector3(-0.4, 1.4, 0), wood, false, Basis.IDENTITY, root)
		box(Vector3(0.1, 1.6, 0.5), Vector3(0.4, 1.4, 0), wood, false, Basis.IDENTITY, root)
		box(Vector3(0.9, 1.6, 0.06), Vector3(0, 1.4, -0.24), wood, false, Basis.IDENTITY, root)
		box(Vector3(0.95, 0.9, 0.6), Vector3(0, 2.65, 0), wood, false, Basis.IDENTITY, root)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.33
		disc.bottom_radius = 0.33
		disc.height = 0.02
		mesh_at(disc, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 2.65, 0.31)), face, root)
		for i in 12:
			var a := TAU * i / 12.0
			box(Vector3(0.015, 0.06, 0.01), Vector3(sin(a), cos(a), 0) * 0.27 + Vector3(0, 2.65, 0.33), black,
				false, Basis(Vector3.BACK, -a), root)
		pendulum = Node3D.new()
		pendulum.position = Vector3(0, 2.15, 0.05)
		root.add_child(pendulum)
		box(Vector3(0.02, 1.2, 0.02), Vector3(0, -0.6, 0), brass, false, Basis.IDENTITY, pendulum)
		var bob := CylinderMesh.new()
		bob.top_radius = 0.12
		bob.bottom_radius = 0.12
		bob.height = 0.03
		mesh_at(bob, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, -1.2, 0)), brass, pendulum)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.95, 3.1, 0.6)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		cs.global_transform = root.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 0))
		tock = sound(_tick_wav(), pos + Vector3(0, 1.5, 0), -4.0, 3.0, false)
		tock.pitch_scale = 0.55
		return


## 一声滴答：短促的噪声 + 一点高频的金属声，30 毫秒
func _tick_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var env := exp(-tt * 180.0)
		s[i] = (randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 2600.0 * tt) * 0.5) * env * 0.8
	return wav(s, rate, false)


func _process(delta: float) -> void:
	t += delta
	for h in hands:
		(h[0] as Node3D).rotation.z += h[1] * delta
	for tk in tickers:
		tk[2] += delta
		if tk[2] >= tk[1]:
			tk[2] -= tk[1]
			var s: AudioStreamPlayer3D = tk[0]
			s.pitch_scale = rng.randf_range(0.85, 1.25)
			s.play()
	if pendulum:
		# 两秒一个来回；摆到两头各“咔”一声
		var a := sin(t * PI)
		pendulum.rotation.z = deg_to_rad(12.0) * a
		var side := signf(cos(t * PI))
		if side != last_side:
			last_side = side
			tock.play()
