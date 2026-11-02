extends RefCounted
## 实体库：房间里能摆的东西，每样是一个用方块和圆柱拼出来的小模型。
## 每个实体登记在 ENTITIES 里：放哪（place）、占地多大（foot：宽 × 深，米）、带什么气质（tags）。
## 房间配方（recipes.gd）按气质给权重挑实体，room.gd 负责摆放；这里只管“一件东西长什么样”。
##
## 约定：模型的原点在占地中心的地面上，正面朝局部 +z（靠墙的东西背面贴墙）；
## 挂墙的（hang）原点在挂点、贴着墙面；吊顶的（ceiling）原点在天花板上，往下垂。
## dread（0～1）是房间的不安程度：越高越脏、越锈、越多血、东西越歪。

const BodyShader = preload("res://scripts/leviathan.gdshader")
const BloodShader = preload("res://scripts/rooms/blood.gdshader")

## place：wall = 靠墙放在地上；floor = 地上随便放；center = 屋子正中（焦点）；
## corner = 屋角；hang = 挂在墙上；ceiling = 吊在天花板下
const ENTITIES := {
	"bed": {"place": "wall", "foot": Vector2(0.9, 2.0), "tags": ["clinical", "domestic", "cell"]},
	"cabinet": {"place": "wall", "foot": Vector2(1.0, 0.5), "tags": ["clinical", "domestic", "storage"]},
	"shelf": {"place": "wall", "foot": Vector2(1.4, 0.4), "tags": ["storage", "ritual", "clinical"]},
	"bathtub": {"place": "wall", "foot": Vector2(0.8, 1.7), "tags": ["clinical"]},
	"cart": {"place": "floor", "foot": Vector2(0.6, 0.9), "tags": ["clinical"]},
	"chair": {"place": "floor", "foot": Vector2(0.5, 0.5), "tags": ["domestic", "clinical", "cell"]},
	"table": {"place": "floor", "foot": Vector2(1.4, 0.8), "tags": ["domestic", "storage"]},
	"cage": {"place": "floor", "foot": Vector2(1.2, 1.2), "tags": ["cell", "ritual"]},
	"crate": {"place": "floor", "foot": Vector2(0.8, 0.8), "tags": ["storage"]},
	"bucket": {"place": "floor", "foot": Vector2(0.4, 0.4), "tags": ["cell", "clinical", "storage"]},
	"candles": {"place": "floor", "foot": Vector2(0.6, 0.6), "tags": ["ritual", "cell"]},
	"doll": {"place": "floor", "foot": Vector2(0.3, 0.3), "tags": ["domestic"]},
	"optable": {"place": "center", "foot": Vector2(0.9, 2.1), "tags": ["clinical"]},
	"altar": {"place": "center", "foot": Vector2(2.6, 2.6), "tags": ["ritual"]},
	"grandfather": {"place": "corner", "foot": Vector2(0.95, 0.6), "tags": ["clocks", "domestic"]},
	"clock": {"place": "hang", "foot": Vector2(1.2, 0.1), "tags": ["clocks", "domestic"]},
	"picture": {"place": "hang", "foot": Vector2(1.0, 0.1), "tags": ["domestic", "ritual"]},
	"mirror": {"place": "hang", "foot": Vector2(0.8, 0.1), "tags": ["domestic", "clinical"]},
	"chains": {"place": "ceiling", "foot": Vector2(0.6, 0.6), "tags": ["cell", "ritual"]},
	"sheet": {"place": "ceiling", "foot": Vector2(1.4, 0.3), "tags": ["clinical", "domestic"]},
}

var room: Node3D                 # Room：提供 box() / mesh_at() / mat() / glow() / lamp() / tick()
var rng: RandomNumberGenerator
var dread := 0.5
var m := {}                      # 材质


func _init(r: Node3D, generator: RandomNumberGenerator, d: float) -> void:
	room = r
	rng = generator
	dread = d
	m = {
		"iron": r.mat(Color(0.2, 0.19, 0.18), 0.6, 0.7),
		"rust": r.mat(Color(0.3, 0.16, 0.09), 0.9, 0.3),
		"wood": r.mat(Color(0.24, 0.16, 0.1), 0.75),
		"dark_wood": r.mat(Color(0.12, 0.08, 0.05), 0.7),
		"cloth": r.mat(Color(0.52, 0.49, 0.42), 0.95),
		"sheet": r.mat(Color(0.6, 0.58, 0.52), 0.95),
		"porcelain": r.mat(Color(0.62, 0.62, 0.58), 0.3),
		"steel": r.mat(Color(0.5, 0.5, 0.5), 0.3, 0.9),
		"wax": r.mat(Color(0.62, 0.56, 0.45), 0.7),
		"flame": r.glow(Color(1.0, 0.62, 0.28), 4.0),
		"brass": r.mat(Color(0.55, 0.42, 0.22), 0.35, 0.9),
		"stone": r.mat(Color(0.2, 0.19, 0.18), 0.95),
		"black": r.mat(Color(0.03, 0.03, 0.03), 0.4, 0.3),
		"face": r.mat(Color(0.7, 0.66, 0.55), 0.6),
		"skin": r.mat(Color(0.62, 0.55, 0.5), 0.6),
		"gore": r.mat(Color(0.18, 0.01, 0.01), 0.15),
		"glass": r.mat(Color(0.25, 0.27, 0.28), 0.08, 0.95),
	}


func make(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = id
	call("_" + id, n)
	return n


## 锈不锈：越不安越容易是锈的
func _metal() -> Material:
	return m["rust"] if rng.randf() < 0.2 + dread * 0.5 else m["iron"]


## 一块血迹：kind 0 = 地上一摊（平放），1 = 墙上淌下来（竖着，贴在 nrm 朝向的面上）
func blood(parent: Node3D, pos: Vector3, sz: float, kind := 0, nrm := Vector3.UP) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz * (1.0 if kind == 0 else 1.6))
	var sm := ShaderMaterial.new()
	sm.shader = BloodShader
	sm.set_shader_parameter("seed", rng.randf() * 100.0)
	sm.set_shader_parameter("kind", kind)
	var basis: Basis = Basis(Vector3.RIGHT, -PI / 2.0) if kind == 0 else room.facing(nrm)
	room.mesh_at(q, Transform3D(basis, pos), sm, parent)


## 碰撞盒挂在实体自己身上，实体被整体挪动（比如倒挂）时碰撞跟着走
func solid(n: Node3D, sz: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	n.add_child(body)


# ---------- 靠墙的 ----------

## 铁床：床头（-z）顶着墙；有的没床垫，不安的床垫上有血
func _bed(n: Node3D) -> void:
	var frame := _metal()
	var hl := 1.0
	var hw := 0.45
	for sx: float in [-hw, hw]:
		for sz: float in [-hl, hl]:
			room.box(Vector3(0.05, 0.5, 0.05), Vector3(sx, 0.25, sz), frame, false, Basis.IDENTITY, n)
		room.box(Vector3(0.05, 0.06, 2.0), Vector3(sx, 0.45, 0), frame, false, Basis.IDENTITY, n)
		room.box(Vector3(0.05, 1.1, 0.05), Vector3(sx, 0.55, -hl), frame, false, Basis.IDENTITY, n)
	for y: float in [0.75, 1.05]:
		room.box(Vector3(0.9, 0.04, 0.04), Vector3(0, y, -hl), frame, false, Basis.IDENTITY, n)
	for i in 5:
		room.box(Vector3(0.025, 0.3, 0.025), Vector3(-hw + 0.9 * (i + 1) / 6.0, 0.9, -hl), frame, false, Basis.IDENTITY, n)
	room.box(Vector3(0.9, 0.04, 0.04), Vector3(0, 0.7, hl), frame, false, Basis.IDENTITY, n)
	if rng.randf() < 0.8:
		room.box(Vector3(0.84, 0.16, 1.9), Vector3(0, 0.56, 0), m["cloth"], false, Basis.IDENTITY, n)
		if rng.randf() < dread:
			blood(n, Vector3(rng.randf_range(-0.2, 0.2), 0.645, rng.randf_range(-0.5, 0.5)), rng.randf_range(0.5, 0.9))
		# 带子：不安的床上有绑带
		if rng.randf() < dread * 0.6:
			for z: float in [-0.3, 0.5]:
				room.box(Vector3(0.9, 0.02, 0.07), Vector3(0, 0.65, z), m["black"], false, Basis.IDENTITY, n)
	solid(n, Vector3(0.9, 0.7, 2.0), Vector3(0, 0.35, 0))


## 柜子：两扇门，不安的时候一扇半开，里面黑洞洞的
func _cabinet(n: Node3D) -> void:
	var wood: Material = m["dark_wood"] if rng.randf() < 0.5 else m["wood"]
	room.box(Vector3(1.0, 1.9, 0.5), Vector3(0, 0.95, 0), wood, false, Basis.IDENTITY, n)
	var ajar := rng.randf() < dread * 0.7
	for side: float in [-1.0, 1.0]:
		var door := Node3D.new()
		door.position = Vector3(side * 0.5, 0, 0.255)
		n.add_child(door)
		room.box(Vector3(0.48, 1.8, 0.03), Vector3(-side * 0.25, 1.0, 0), wood, false, Basis.IDENTITY, door)
		room.box(Vector3(0.03, 0.15, 0.04), Vector3(-side * 0.44, 1.0, 0.03), m["brass"], false, Basis.IDENTITY, door)
		if ajar and side > 0.0:
			door.rotation.y = deg_to_rad(-55.0)
			room.box(Vector3(0.46, 1.78, 0.02), Vector3(0.25, 1.0, 0.24), m["black"], false, Basis.IDENTITY, n)
	solid(n, Vector3(1.0, 1.9, 0.5), Vector3(0, 0.95, 0))


## 架子：三层隔板，摆着瓶瓶罐罐；不安的罐子里是暗红的
func _shelf(n: Node3D) -> void:
	var wood: Material = m["wood"]
	for sx: float in [-0.68, 0.68]:
		room.box(Vector3(0.04, 2.0, 0.38), Vector3(sx, 1.0, 0), wood, false, Basis.IDENTITY, n)
	for i in 4:
		var y := 0.15 + i * 0.6
		room.box(Vector3(1.4, 0.03, 0.38), Vector3(0, y, 0), wood, false, Basis.IDENTITY, n)
		if i == 3:
			continue
		var x := -0.6
		while x < 0.6:
			var r := rng.randf_range(0.05, 0.1)
			var h := rng.randf_range(0.12, 0.35)
			if rng.randf() < 0.75:
				var jar := CylinderMesh.new()
				jar.top_radius = r * 0.8
				jar.bottom_radius = r
				jar.height = h
				jar.radial_segments = 10
				var mat: Material = m["gore"] if rng.randf() < dread * 0.6 else m["glass"]
				room.mesh_at(jar, Transform3D(Basis.IDENTITY, Vector3(x + r, y + 0.015 + h / 2.0, rng.randf_range(-0.08, 0.08))), mat, n)
			x += r * 2.0 + 0.06
	solid(n, Vector3(1.4, 2.0, 0.4), Vector3(0, 1.0, 0))


## 铸铁浴缸：四只脚；不安的里面是一缸暗红
func _bathtub(n: Node3D) -> void:
	var porcelain: Material = m["porcelain"]
	room.box(Vector3(0.8, 0.55, 1.7), Vector3(0, 0.42, 0), porcelain, false, Basis.IDENTITY, n)
	var inside: Material = m["gore"] if rng.randf() < dread * 0.8 else m["black"]
	room.box(Vector3(0.66, 0.02, 1.56), Vector3(0, 0.64, 0), inside, false, Basis.IDENTITY, n)
	for sx: float in [-0.32, 0.32]:
		for sz: float in [-0.7, 0.7]:
			room.box(Vector3(0.08, 0.15, 0.08), Vector3(sx, 0.075, sz), m["brass"], false, Basis.IDENTITY, n)
	if rng.randf() < dread:
		blood(n, Vector3(0.45, 0.003, rng.randf_range(-0.4, 0.4)), 0.9)
	solid(n, Vector3(0.8, 0.7, 1.7), Vector3(0, 0.35, 0))


# ---------- 地上的 ----------

## 手术推车：两层托盘，上层摆着器械
func _cart(n: Node3D) -> void:
	var frame := _metal()
	for sx: float in [-0.27, 0.27]:
		for sz: float in [-0.42, 0.42]:
			room.box(Vector3(0.03, 0.9, 0.03), Vector3(sx, 0.45, sz), frame, false, Basis.IDENTITY, n)
	for y: float in [0.3, 0.88]:
		room.box(Vector3(0.6, 0.02, 0.9), Vector3(0, y, 0), m["steel"], false, Basis.IDENTITY, n)
	for i in rng.randi_range(3, 7):
		var l := rng.randf_range(0.12, 0.25)
		room.box(Vector3(0.015, 0.01, l), Vector3(rng.randf_range(-0.22, 0.22), 0.9, rng.randf_range(-0.3, 0.3)),
			m["steel"], false, Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), n)
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.892, 0.1), 0.4)
	solid(n, Vector3(0.6, 0.9, 0.9), Vector3(0, 0.45, 0))


## 椅子：不安的时候可能翻倒
func _chair(n: Node3D) -> void:
	var wood: Material = m["wood"] if rng.randf() < 0.6 else _metal()
	var c := Node3D.new()
	n.add_child(c)
	for sx: float in [-0.2, 0.2]:
		for sz: float in [-0.2, 0.2]:
			room.box(Vector3(0.04, 0.45, 0.04), Vector3(sx, 0.225, sz), wood, false, Basis.IDENTITY, c)
		room.box(Vector3(0.04, 0.5, 0.04), Vector3(sx, 0.7, -0.2), wood, false, Basis.IDENTITY, c)
	room.box(Vector3(0.46, 0.04, 0.46), Vector3(0, 0.46, 0), wood, false, Basis.IDENTITY, c)
	room.box(Vector3(0.44, 0.12, 0.03), Vector3(0, 0.88, -0.2), wood, false, Basis.IDENTITY, c)
	if rng.randf() < dread * 0.3:
		c.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), Vector3(0, 0.2, 0.45))
	solid(n, Vector3(0.46, 0.9, 0.46), Vector3(0, 0.45, 0))


## 桌子：桌上随手放几样；正常的屋子里摆着餐具
func _table(n: Node3D) -> void:
	var wood: Material = m["wood"]
	room.box(Vector3(1.4, 0.05, 0.8), Vector3(0, 0.76, 0), wood, false, Basis.IDENTITY, n)
	for sx: float in [-0.64, 0.64]:
		for sz: float in [-0.34, 0.34]:
			room.box(Vector3(0.05, 0.74, 0.05), Vector3(sx, 0.37, sz), wood, false, Basis.IDENTITY, n)
	for sx: float in [-0.35, 0.35]:
		var plate := CylinderMesh.new()
		plate.top_radius = 0.12
		plate.bottom_radius = 0.1
		plate.height = 0.015
		room.mesh_at(plate, Transform3D(Basis.IDENTITY, Vector3(sx, 0.79, 0)), m["porcelain"], n)
		room.box(Vector3(0.015, 0.005, 0.18), Vector3(sx + 0.16, 0.787, 0), m["steel"], false, Basis.IDENTITY, n)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.3, 0.3), 0.788, 0), 0.5)
	solid(n, Vector3(1.4, 0.8, 0.8), Vector3(0, 0.4, 0))


## 铁笼：一圈竖栏杆，上下两道框
func _cage(n: Node3D) -> void:
	var frame := _metal()
	var h := rng.randf_range(1.2, 1.9)
	for y: float in [0.03, h]:
		for s: Array in [[Vector3(1.2, 0.04, 0.04), Vector3(0, 0, -0.58)], [Vector3(1.2, 0.04, 0.04), Vector3(0, 0, 0.58)],
				[Vector3(0.04, 0.04, 1.2), Vector3(-0.58, 0, 0)], [Vector3(0.04, 0.04, 1.2), Vector3(0.58, 0, 0)]]:
			room.box(s[0], s[1] + Vector3(0, y, 0), frame, false, Basis.IDENTITY, n)
	for i in 8:
		var t := -0.58 + 1.16 * i / 7.0
		for p: Vector3 in [Vector3(t, 0, -0.58), Vector3(t, 0, 0.58), Vector3(-0.58, 0, t), Vector3(0.58, 0, t)]:
			room.box(Vector3(0.025, h, 0.025), p + Vector3(0, h / 2.0, 0), frame, false, Basis.IDENTITY, n)
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.004, 0), 0.9)
	solid(n, Vector3(1.2, h, 1.2), Vector3(0, h / 2.0, 0))


## 木箱：一到三只摞着
func _crate(n: Node3D) -> void:
	var y := 0.0
	for i in rng.randi_range(1, 3):
		var s := rng.randf_range(0.55, 0.8)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3))
		room.box(Vector3(s, s, s), Vector3(0, y + s / 2.0, 0), m["wood"], false, rot, n)
		room.box(Vector3(s + 0.02, 0.06, 0.06), Vector3(0, y + s / 2.0, 0), m["dark_wood"], false, rot, n)
		y += s
	solid(n, Vector3(0.8, y, 0.8), Vector3(0, y / 2.0, 0))


## 铁桶
func _bucket(n: Node3D) -> void:
	var b := CylinderMesh.new()
	b.top_radius = 0.17
	b.bottom_radius = 0.14
	b.height = 0.35
	b.radial_segments = 14
	room.mesh_at(b, Transform3D(Basis.IDENTITY, Vector3(0, 0.175, 0)), _metal(), n)
	var top := CylinderMesh.new()
	top.top_radius = 0.155
	top.bottom_radius = 0.155
	top.height = 0.01
	room.mesh_at(top, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), m["gore"] if rng.randf() < dread else m["black"], n)


## 一簇蜡烛，带一盏暖光
func _candles(n: Node3D) -> void:
	for i in rng.randi_range(3, 7):
		var h := rng.randf_range(0.08, 0.4)
		var c := CylinderMesh.new()
		c.top_radius = 0.035
		c.bottom_radius = 0.04
		c.height = h
		c.radial_segments = 8
		var pos := Vector3(rng.randf_range(-0.25, 0.25), h / 2.0, rng.randf_range(-0.25, 0.25))
		room.mesh_at(c, Transform3D(Basis.IDENTITY, pos), m["wax"], n)
		if rng.randf() < 0.8:
			room.box(Vector3(0.02, 0.05, 0.02), pos + Vector3(0, h / 2.0 + 0.03, 0), m["flame"], false, Basis.IDENTITY, n)
	var l: OmniLight3D = room.lamp(Vector3.ZERO, Color(1.0, 0.6, 0.3), 0.7, 3.5, false, n)
	l.position = Vector3(0, 0.5, 0)
	var phase := rng.randf() * 10.0
	room.tick(func(t: float) -> void: l.light_energy = 0.7 + 0.12 * sin(t * 13.0 + phase) * sin(t * 7.3))


## 玩偶：坐在地上，脑袋歪着
func _doll(n: Node3D) -> void:
	room.box(Vector3(0.14, 0.18, 0.1), Vector3(0, 0.12, 0), m["cloth"], false, Basis.IDENTITY, n)
	for sx: float in [-0.05, 0.05]:
		room.box(Vector3(0.05, 0.04, 0.16), Vector3(sx, 0.03, 0.08), m["cloth"], false, Basis.IDENTITY, n)
		room.box(Vector3(0.04, 0.12, 0.04), Vector3(sx * 2.0, 0.12, 0.02), m["cloth"], false, Basis(Vector3.BACK, sx * 4.0), n)
	var head := SphereMesh.new()
	head.radius = 0.07
	head.height = 0.14
	room.mesh_at(head, Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.6, 0.6)), Vector3(0, 0.27, 0)), m["porcelain"], n)
	for sx: float in [-0.025, 0.025]:
		room.box(Vector3(0.015, 0.015, 0.01), Vector3(sx, 0.28, 0.068), m["black"], false, Basis.IDENTITY, n)


# ---------- 屋子正中 ----------

## 手术台：底座 + 台面 + 头枕，台上台下都是血
func _optable(n: Node3D) -> void:
	room.box(Vector3(0.35, 0.75, 0.6), Vector3(0, 0.375, 0), m["steel"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.75, 0.08, 2.0), Vector3(0, 0.8, 0), m["steel"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.4, 0.1, 0.3), Vector3(0, 0.89, -0.85), m["cloth"], false, Basis.IDENTITY, n)
	for z: float in [-0.4, 0.2, 0.7]:
		room.box(Vector3(0.8, 0.02, 0.07), Vector3(0, 0.85, z), m["black"], false, Basis.IDENTITY, n)
	if dread > 0.3:
		blood(n, Vector3(0, 0.842, rng.randf_range(-0.3, 0.3)), 0.8)
		blood(n, Vector3(rng.randf_range(-0.4, 0.4), 0.004, rng.randf_range(-0.6, 0.6)), 1.6)
	solid(n, Vector3(0.75, 0.85, 2.0), Vector3(0, 0.42, 0))


## 祭台：三级台座，上方悬着缩小的黄铜菱形（刻纹和天上的利维坦一样），缓缓自转
func _altar(n: Node3D) -> void:
	for i in 3:
		var w := 2.6 - i * 0.7
		room.box(Vector3(w, 0.25, w), Vector3(0, 0.125 + i * 0.25, 0), m["stone"], false, Basis.IDENTITY, n)
	solid(n, Vector3(2.6, 0.75, 2.6), Vector3(0, 0.375, 0))
	# 菱形按屋子高度缩放：大屋子 2.8 米高，5 米的小屋子里小一半
	var room_h: float = room.size.y
	var h := clampf((room_h - 1.6) / 3.2, 0.5, 1.4)
	var w := h * 0.32
	var y := 0.75 + 0.35 + h
	var k := w / 42.0
	var sm := ShaderMaterial.new()
	sm.shader = BodyShader
	sm.set_shader_parameter("half_width", w)
	sm.set_shader_parameter("half_height", h)
	sm.set_shader_parameter("groove_w", 0.9 * k)
	sm.set_shader_parameter("band_period", 34.0 * k)
	sm.set_shader_parameter("cell", 7.0 * k)
	sm.set_shader_parameter("bump", 0.2)
	sm.set_shader_parameter("self_lit", 0.3)
	var idol: MeshInstance3D = room.mesh_at(_diamond(w, h), Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), sm, n)
	room.lamp(Vector3(1.6, y + 0.8, 1.3), Color(0.75, 0.8, 0.9), 2.5, 5.0, false, n)
	room.tick(func(t: float) -> void:
		idol.rotation.y = t * 0.25
		idol.position.y = y + sin(t * 0.7) * 0.08)
	if dread > 0.5:
		blood(n, Vector3(0, 0.752, 0), 1.0)


## 八面体：上下两个尖、腰部四个角；每面平的
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


# ---------- 屋角 ----------

## 落地钟：钟摆露在外面来回摆，摆到两头“咔”一声
func _grandfather(n: Node3D) -> void:
	var wood: Material = m["dark_wood"]
	room.box(Vector3(0.9, 0.6, 0.55), Vector3(0, 0.3, 0), wood, false, Basis.IDENTITY, n)
	room.box(Vector3(0.1, 1.6, 0.5), Vector3(-0.4, 1.4, 0), wood, false, Basis.IDENTITY, n)
	room.box(Vector3(0.1, 1.6, 0.5), Vector3(0.4, 1.4, 0), wood, false, Basis.IDENTITY, n)
	room.box(Vector3(0.9, 1.6, 0.06), Vector3(0, 1.4, -0.24), wood, false, Basis.IDENTITY, n)
	room.box(Vector3(0.95, 0.9, 0.6), Vector3(0, 2.65, 0), wood, false, Basis.IDENTITY, n)
	_dial(n, Vector3(0, 2.65, 0.31), 0.33, 1.0)
	var pend := Node3D.new()
	pend.position = Vector3(0, 2.15, 0.05)
	n.add_child(pend)
	room.box(Vector3(0.02, 1.2, 0.02), Vector3(0, -0.6, 0), m["brass"], false, Basis.IDENTITY, pend)
	var bob := CylinderMesh.new()
	bob.top_radius = 0.12
	bob.bottom_radius = 0.12
	bob.height = 0.03
	room.mesh_at(bob, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, -1.2, 0)), m["brass"], pend)
	solid(n, Vector3(0.95, 3.1, 0.6), Vector3(0, 1.55, 0))
	var tock: AudioStreamPlayer3D = room.sound(room.tick_wav(), Vector3(0, 1.5, 0), -4.0, 3.0, false, n)
	tock.pitch_scale = 0.55
	var last := [0.0]
	room.tick(func(t: float) -> void:
		pend.rotation.z = deg_to_rad(12.0) * sin(t * PI)
		var side := signf(cos(t * PI))
		if side != last[0]:
			last[0] = side
			tock.play())


# ---------- 挂墙的 ----------

## 挂钟：各走各的——有的飞转、有的倒走、有的停了
func _clock(n: Node3D) -> void:
	var r := rng.randf_range(0.25, 0.6)
	var back := CylinderMesh.new()
	back.top_radius = r * 1.15
	back.bottom_radius = r * 1.15
	back.height = 0.08
	back.radial_segments = 32
	room.mesh_at(back, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 0.04)), m["dark_wood"], n)
	var speeds: Array[float] = [1.0, 3.0, 12.0, -2.0, -0.5, 0.0, 40.0]
	_dial(n, Vector3(0, 0, 0.09), r, speeds[rng.randi_range(0, speeds.size() - 1)])


## 表盘：盘面、12 个刻度、时针分针（speed = 分针每分钟几圈）
func _dial(n: Node3D, pos: Vector3, r: float, speed: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.02
	disc.radial_segments = 32
	room.mesh_at(disc, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), pos), m["face"], n)
	for i in 12:
		var a := TAU * i / 12.0
		var long := i % 3 == 0
		room.box(Vector3(r * 0.04, r * (0.16 if long else 0.08), 0.01),
			pos + Vector3(sin(a), cos(a), 0) * r * 0.82 + Vector3(0, 0, 0.015), m["black"],
			false, Basis(Vector3.BACK, -a), n)
	var minute := -TAU * speed / 60.0
	for spec: Array in [[0.5, 0.07, minute / 12.0, 0.02], [0.78, 0.04, minute, 0.03]]:
		var pivot := Node3D.new()
		pivot.position = pos + Vector3(0, 0, spec[3])
		pivot.rotation.z = rng.randf() * TAU
		n.add_child(pivot)
		var length: float = r * spec[0]
		room.box(Vector3(r * spec[1], length, 0.01), Vector3(0, length / 2.0 - r * 0.08, 0), m["black"], false, Basis.IDENTITY, pivot)
		var rate: float = spec[2]
		room.tick(func(_t: float) -> void: pivot.rotation.z += rate * room.dt)


## 画框：画面黑乎乎看不清；不安的被划破，或者整幅翻过来朝着墙
func _picture(n: Node3D) -> void:
	var w := rng.randf_range(0.5, 1.0)
	var h := w * rng.randf_range(0.7, 1.3)
	room.box(Vector3(w + 0.1, h + 0.1, 0.05), Vector3(0, 0, 0.025), m["dark_wood"], false, Basis.IDENTITY, n)
	if rng.randf() < dread * 0.3:
		room.box(Vector3(w, h, 0.01), Vector3(0, 0, 0.055), m["wood"], false, Basis.IDENTITY, n)   # 背面朝外
		return
	var canvas: Material = room.mat(Color(0.12, 0.1, 0.08).lerp(Color(0.3, 0.26, 0.2), rng.randf()), 0.9)
	room.box(Vector3(w, h, 0.01), Vector3(0, 0, 0.055), canvas, false, Basis.IDENTITY, n)
	room.box(Vector3(w * 0.3, h * 0.4, 0.005), Vector3(rng.randf_range(-0.1, 0.1) * w, -h * 0.05, 0.062),
		room.mat(Color(0.35, 0.3, 0.26), 0.9), false, Basis.IDENTITY, n)
	if rng.randf() < dread * 0.6:
		for i in 2:
			room.box(Vector3(0.02, h * 0.9, 0.006), Vector3(rng.randf_range(-0.3, 0.3) * w, 0, 0.065), m["black"],
				false, Basis(Vector3.BACK, rng.randf_range(-0.4, 0.4)), n)


## 镜子：多半蒙着一块布
func _mirror(n: Node3D) -> void:
	var w := 0.6
	var h := 1.0
	room.box(Vector3(w + 0.12, h + 0.12, 0.05), Vector3(0, 0, 0.025), m["dark_wood"], false, Basis.IDENTITY, n)
	room.box(Vector3(w, h, 0.01), Vector3(0, 0, 0.055), m["glass"], false, Basis.IDENTITY, n)
	if rng.randf() < 0.4 + dread * 0.5:
		room.box(Vector3(w + 0.3, h + 0.4, 0.02), Vector3(0, -0.1, 0.075), m["sheet"], false,
			Basis(Vector3.BACK, rng.randf_range(-0.08, 0.08)), n)


# ---------- 吊顶的 ----------

## 吊链：几根铁链从天花板垂下来，有的末端挂着钩子，慢慢晃
func _chains(n: Node3D) -> void:
	var frame := _metal()
	for c in rng.randi_range(1, 3):
		var chain := Node3D.new()
		chain.position = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		n.add_child(chain)
		var links := rng.randi_range(8, 22)
		for i in links:
			var rot := Basis(Vector3.UP, PI / 2.0 if i % 2 == 1 else 0.0)
			room.box(Vector3(0.05, 0.11, 0.015), Vector3(0, -0.05 - i * 0.09, 0), frame, false, rot, chain)
		var end := -0.05 - links * 0.09
		if rng.randf() < 0.4 + dread * 0.4:
			room.box(Vector3(0.02, 0.18, 0.02), Vector3(0, end - 0.08, 0), frame, false, Basis.IDENTITY, chain)
			room.box(Vector3(0.12, 0.02, 0.02), Vector3(0.05, end - 0.17, 0), frame, false, Basis.IDENTITY, chain)
			room.box(Vector3(0.02, 0.07, 0.02), Vector3(0.1, end - 0.13, 0), frame, false, Basis.IDENTITY, chain)
		var phase := rng.randf() * TAU
		var amp := rng.randf_range(0.02, 0.06)
		room.tick(func(t: float) -> void:
			chain.rotation.x = amp * sin(t * 0.9 + phase)
			chain.rotation.z = amp * 0.6 * sin(t * 0.7 + phase * 1.3))


## 垂布：从天花板的一根杆上挂下来的一块旧布，微微晃；不安的上面有血
func _sheet(n: Node3D) -> void:
	room.box(Vector3(1.6, 0.03, 0.03), Vector3(0, -0.05, 0), _metal(), false, Basis.IDENTITY, n)
	var cloth := Node3D.new()
	cloth.position = Vector3(0, -0.07, 0)
	n.add_child(cloth)
	var h := rng.randf_range(1.6, 2.4)
	room.box(Vector3(1.4, h, 0.02), Vector3(0, -h / 2.0, 0), m["sheet"], false, Basis.IDENTITY, cloth)
	if rng.randf() < dread:
		blood(cloth, Vector3(rng.randf_range(-0.3, 0.3), -h * 0.6, 0.012), 0.6, 1, Vector3.BACK)
	var phase := rng.randf() * TAU
	room.tick(func(t: float) -> void: cloth.rotation.x = 0.03 * sin(t * 0.8 + phase))
