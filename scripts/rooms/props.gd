extends RefCounted
## 实体库：房间里能摆的东西。一部分是 Blender 脚本建的模型（tools/blender/room_props.py → room_props.glb），
## 其余的还是用方块和圆柱拼出来的小模型。
## 每个实体登记在 ENTITIES 里：放哪（place）、占地多大（foot：宽 × 深，米）、带什么气质（tags）。
## 房间配方（recipes.gd）按气质给权重挑实体，room.gd 负责摆放；这里只管“一件东西长什么样”。
##
## 约定：模型的原点在占地中心的地面上，正面朝局部 +z（靠墙的东西背面贴墙）；
## 挂墙的（hang）原点在挂点、贴着墙面；吊顶的（ceiling）原点在天花板上，往下垂。
## dread（0～1）是房间的不安程度：越高越脏、越锈、越多血、东西越歪。

const BodyShader = preload("res://scripts/leviathan.gdshader")
const BloodShader = preload("res://scripts/rooms/blood.gdshader")
const PropModels = preload("res://assets/models/room_props.glb")

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
	"doll": {"place": "floor", "foot": Vector2(0.3, 0.3), "tags": ["domestic", "nursery"]},
	"optable": {"place": "center", "foot": Vector2(0.9, 2.1), "tags": ["clinical"]},
	"altar": {"place": "center", "foot": Vector2(2.6, 2.6), "tags": ["ritual"]},
	"grandfather": {"place": "corner", "foot": Vector2(0.95, 0.6), "tags": ["clocks", "domestic"]},
	"clock": {"place": "hang", "foot": Vector2(1.2, 0.1), "tags": ["clocks", "domestic"]},
	"picture": {"place": "hang", "foot": Vector2(1.0, 0.1), "tags": ["domestic", "ritual"]},
	"mirror": {"place": "hang", "foot": Vector2(0.8, 0.1), "tags": ["domestic", "clinical"]},
	"chains": {"place": "ceiling", "foot": Vector2(0.6, 0.6), "tags": ["cell", "ritual"]},
	"sheet": {"place": "ceiling", "foot": Vector2(1.4, 0.3), "tags": ["clinical", "domestic", "morgue"]},
	"wheelchair": {"place": "floor", "foot": Vector2(0.65, 0.9), "tags": ["clinical"]},
	"iv_stand": {"place": "floor", "foot": Vector2(0.5, 0.5), "tags": ["clinical", "morgue"]},
	"gurney": {"place": "floor", "foot": Vector2(0.75, 2.0), "tags": ["morgue", "clinical"]},
	"coffin": {"place": "floor", "foot": Vector2(0.8, 2.1), "tags": ["ritual", "morgue"]},
	"rocking_chair": {"place": "floor", "foot": Vector2(0.6, 1.0), "tags": ["nursery", "domestic"]},
	"crib": {"place": "wall", "foot": Vector2(1.3, 0.75), "tags": ["nursery"]},
	"mannequin": {"place": "floor", "foot": Vector2(0.5, 0.5), "tags": ["domestic", "nursery", "clinical"]},
	"sink": {"place": "wall", "foot": Vector2(0.6, 0.5), "tags": ["clinical", "domestic"]},
	"stool": {"place": "floor", "foot": Vector2(0.4, 0.4), "tags": ["cell", "clinical", "storage"]},
	"bones": {"place": "floor", "foot": Vector2(0.9, 0.9), "tags": ["cell", "ritual", "morgue"]},
	"lockers": {"place": "wall", "foot": Vector2(1.4, 0.5), "tags": ["morgue", "storage", "clinical"]},
	"bench": {"place": "wall", "foot": Vector2(1.8, 0.5), "tags": ["waiting", "ritual"]},
	"desk": {"place": "floor", "foot": Vector2(0.7, 1.0), "tags": ["classroom"]},
	"blackboard": {"place": "hang", "foot": Vector2(2.4, 0.1), "tags": []},   # 只当教室的前墙用，不随机挑
	"long_table": {"place": "center", "foot": Vector2(3.4, 2.0), "tags": ["domestic"]},
	"noticeboard": {"place": "hang", "foot": Vector2(1.0, 0.1), "tags": ["waiting", "classroom", "clinical"]},
	"coat_rack": {"place": "corner", "foot": Vector2(0.5, 0.5), "tags": ["waiting", "domestic"]},
}

var room: Node3D                 # Room：提供 box() / mesh_at() / mat() / glow() / lamp() / tick()
var rng: RandomNumberGenerator
var dread := 0.5
var m := {}                      # 材质
static var models := {}          # 模型名 → 网格（来自 room_props.glb），第一次用时读一遍


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


## 摆一件 Blender 建的模型：材质槽按名字套 m 里的材质，frame 槽给传进来的那份（铁或锈）
func model(name: String, parent: Node3D, frame: Material = null, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	if models.is_empty():
		var scene: Node = PropModels.instantiate()
		for c in scene.find_children("*", "MeshInstance3D", true, false):
			models[String(c.name)] = (c as MeshInstance3D).mesh
		scene.free()
	var mesh: Mesh = models[name]
	var mi: MeshInstance3D = room.mesh_at(mesh, xf, null, parent)
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i)
		var key := src.resource_name if src else "cloth"
		mi.set_surface_override_material(i, frame if key == "frame" and frame else m.get(key, m["cloth"]))
	return mi


## 锈不锈：越不安越容易是锈的
func _metal() -> Material:
	return m["rust"] if rng.randf() < 0.2 + dread * 0.5 else m["iron"]


enum { SPLAT, DRIP, HAND, DRAG, TALLY }
const BLOOD_ASPECT := [1.0, 1.6, 2.0, 8.0, 0.4]   # 每种血迹方片的高 / 宽
const BLOOD_FLOOR := [true, false, false, true, false]


## 一块血迹（种类见 blood.gdshader）：地上的平放、绕竖轴转 yaw；墙上的竖着贴在 nrm 朝向的面上。sz 是宽度
func blood(parent: Node3D, pos: Vector3, sz: float, kind := SPLAT, nrm := Vector3.UP, yaw := 0.0) -> void:
	var aspect: float = BLOOD_ASPECT[kind]
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz * aspect)
	var sm := ShaderMaterial.new()
	sm.shader = BloodShader
	sm.set_shader_parameter("seed", rng.randf() * 100.0)
	sm.set_shader_parameter("kind", kind)
	sm.set_shader_parameter("aspect", aspect)
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2.0) if BLOOD_FLOOR[kind] else room.facing(nrm)
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

## 铁床：床头（-z）顶着墙，弯管床头床尾；有的没床垫，不安的床垫上有血
func _bed(n: Node3D) -> void:
	model("bed_frame", n, _metal())
	if rng.randf() < 0.8:
		model("bed_mattress", n)
		if rng.randf() < dread:
			blood(n, Vector3(rng.randf_range(-0.2, 0.2), 0.632, rng.randf_range(-0.3, 0.5)), rng.randf_range(0.5, 0.9))
		# 带子：不安的床上有绑带
		if rng.randf() < dread * 0.6:
			for z: float in [-0.3, 0.5]:
				room.box(Vector3(0.9, 0.02, 0.07), Vector3(0, 0.645, z), m["black"], false, Basis.IDENTITY, n)
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


## 瓷娃娃：坐在地上，头会转过来看你
func _doll(n: Node3D) -> void:
	model("doll_body", n)
	var head := Node3D.new()
	head.position = Vector3(0, 0.27, 0)
	head.rotation.z = rng.randf_range(-0.6, 0.6)
	n.add_child(head)
	model("doll_head", head)
	room.watchers.append(head)


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


# ---------- 第二批 ----------

## 轮椅：辐条大轮、帆布座；进门时可能自己滑开
func _wheelchair(n: Node3D) -> void:
	model("wheelchair", n, _metal())
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.49, 0.05), 0.35)
	solid(n, Vector3(0.65, 1.0, 0.9), Vector3(0, 0.5, 0))
	room.drifters.append(n)


## 输液架：细杆、三脚底座、顶上挂着一袋——不安的袋子里是血
func _iv_stand(n: Node3D) -> void:
	var frame: Material = m["steel"]
	room.box(Vector3(0.025, 1.9, 0.025), Vector3(0, 0.95, 0), frame, false, Basis.IDENTITY, n)
	for i in 3:
		room.box(Vector3(0.025, 0.025, 0.3), Vector3(0, 0.03, 0), frame, false, Basis(Vector3.UP, TAU * i / 3.0), n)
	room.box(Vector3(0.3, 0.02, 0.02), Vector3(0, 1.88, 0), frame, false, Basis.IDENTITY, n)
	var bag: Material = m["gore"] if rng.randf() < dread else m["glass"]
	room.box(Vector3(0.14, 0.22, 0.05), Vector3(0.12, 1.72, 0), bag, false, Basis.IDENTITY, n)
	room.box(Vector3(0.006, 0.9, 0.006), Vector3(0.12, 1.15, 0), bag, false, Basis(Vector3.BACK, 0.15), n)


## 停尸推床：带轮的窄床，多半盖着一张白布，布下面有个人形
func _gurney(n: Node3D) -> void:
	var frame := _metal()
	for sx: float in [-0.32, 0.32]:
		for sz: float in [-0.9, 0.9]:
			room.box(Vector3(0.03, 0.75, 0.03), Vector3(sx, 0.4, sz), frame, false, Basis.IDENTITY, n)
			var w := SphereMesh.new()
			w.radius = 0.05
			w.height = 0.1
			room.mesh_at(w, Transform3D(Basis.IDENTITY, Vector3(sx, 0.05, sz)), m["black"], n)
	room.box(Vector3(0.7, 0.04, 2.0), Vector3(0, 0.78, 0), m["steel"], false, Basis.IDENTITY, n)
	if rng.randf() < 0.4 + dread * 0.5:
		# 白布下面：头、躯干、两条腿的轮廓
		var cloth: Material = m["sheet"]
		var head := SphereMesh.new()
		head.radius = 0.13
		head.height = 0.22
		room.mesh_at(head, Transform3D(Basis.IDENTITY, Vector3(0, 0.88, -0.78)), cloth, n)
		room.box(Vector3(0.45, 0.2, 0.75), Vector3(0, 0.9, -0.2), cloth, false, Basis.IDENTITY, n)
		for sx: float in [-0.1, 0.1]:
			room.box(Vector3(0.17, 0.13, 0.8), Vector3(sx, 0.86, 0.55), cloth, false, Basis.IDENTITY, n)
		room.box(Vector3(0.72, 0.02, 1.95), Vector3(0, 0.81, 0), cloth, false, Basis.IDENTITY, n)
		if rng.randf() < dread:
			blood(n, Vector3(rng.randf_range(-0.1, 0.1), 1.005, -0.25), 0.4)
	solid(n, Vector3(0.7, 0.85, 2.0), Vector3(0, 0.42, 0))


## 棺材：深色木头，棺盖错开一截，里面黑洞洞的
func _coffin(n: Node3D) -> void:
	var wood: Material = m["dark_wood"]
	room.box(Vector3(0.7, 0.5, 2.0), Vector3(0, 0.25, 0), wood, false, Basis.IDENTITY, n)
	room.box(Vector3(0.6, 0.02, 1.9), Vector3(0, 0.5, 0), m["black"], false, Basis.IDENTITY, n)
	var open := rng.randf_range(0.2, 0.7) * (0.3 + dread)
	room.box(Vector3(0.74, 0.06, 2.04), Vector3(0.1, 0.53, open), wood, false, Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), n)
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.003, 1.2), 0.7)
	solid(n, Vector3(0.75, 0.56, 2.05), Vector3(0, 0.28, 0))


## 摇椅：进门时可能自己摇起来（整件绕原点摇）
func _rocking_chair(n: Node3D) -> void:
	var rocker := Node3D.new()
	n.add_child(rocker)
	model("rocking_chair", rocker)
	solid(n, Vector3(0.6, 1.0, 1.0), Vector3(0, 0.5, 0))
	room.rockers.append(rocker)


## 婴儿床：车削角柱、一圈栏杆（断了一根），里面一条皱成一团的小毯子
func _crib(n: Node3D) -> void:
	model("crib", n)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.4, 0.0), 0.418, 0), 0.4)
	solid(n, Vector3(1.3, 1.0, 0.75), Vector3(0, 0.5, 0))


## 人台：没有脸的人形，立在一根杆子上；进门时可能已经转过来对着你
func _mannequin(n: Node3D) -> void:
	model("mannequin_stand", n)
	var body := Node3D.new()
	n.add_child(body)
	model("mannequin_body", body)
	if rng.randf() < dread * 0.5:
		blood(body, Vector3(0, 1.25, 0.11), 0.25, DRIP, Vector3.BACK)
	solid(n, Vector3(0.4, 1.8, 0.3), Vector3(0, 0.9, 0))
	room.watchers.append(body)


## 洗手池：立柱、台盆、水龙头；不安的盆里积着血
func _sink(n: Node3D) -> void:
	room.box(Vector3(0.2, 0.75, 0.2), Vector3(0, 0.375, -0.05), m["porcelain"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.6, 0.15, 0.45), Vector3(0, 0.82, 0), m["porcelain"], false, Basis.IDENTITY, n)
	var inside: Material = m["gore"] if rng.randf() < dread else m["black"]
	room.box(Vector3(0.46, 0.01, 0.3), Vector3(0, 0.9, 0.03), inside, false, Basis.IDENTITY, n)
	room.box(Vector3(0.03, 0.15, 0.03), Vector3(0, 0.97, -0.18), m["steel"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.03, 0.03, 0.12), Vector3(0, 1.04, -0.13), m["steel"], false, Basis.IDENTITY, n)
	solid(n, Vector3(0.6, 0.9, 0.5), Vector3(0, 0.45, 0))


## 三脚凳
func _stool(n: Node3D) -> void:
	var wood: Material = m["wood"] if rng.randf() < 0.6 else _metal()
	var seat := CylinderMesh.new()
	seat.top_radius = 0.17
	seat.bottom_radius = 0.17
	seat.height = 0.04
	room.mesh_at(seat, Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0)), wood, n)
	for i in 3:
		var a := TAU * i / 3.0
		room.box(Vector3(0.03, 0.5, 0.03), Vector3(cos(a) * 0.11, 0.24, sin(a) * 0.11), wood, false,
			Basis(Vector3(-sin(a), 0, cos(a)), 0.12), n)
	if rng.randf() < dread * 0.4:
		n.rotation.x = deg_to_rad(90)
		n.position.y += 0.17


## 一堆骨头：长长短短的骨头散在一起，有时有一个头骨
func _bones(n: Node3D) -> void:
	var bone := mat_bone()
	for i in rng.randi_range(6, 14):
		var b := CylinderMesh.new()
		var l := rng.randf_range(0.15, 0.45)
		b.top_radius = 0.018
		b.bottom_radius = 0.022
		b.height = l
		b.radial_segments = 6
		var rot := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, PI / 2.0 + rng.randf_range(-0.3, 0.3))
		room.mesh_at(b, Transform3D(rot, Vector3(rng.randf_range(-0.35, 0.35), 0.03 + i * 0.008, rng.randf_range(-0.35, 0.35))), bone, n)
	if rng.randf() < 0.5 + dread * 0.3:
		var skull := SphereMesh.new()
		skull.radius = 0.1
		skull.height = 0.19
		room.mesh_at(skull, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0.1, 0.1, 0.05)), bone, n)
		for sx: float in [-0.035, 0.035]:
			room.box(Vector3(0.03, 0.03, 0.02), Vector3(0.1 + sx, 0.11, 0.14), m["black"], false, Basis.IDENTITY, n)
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.004, 0), 1.0)


func mat_bone() -> Material:
	return room.mat(Color(0.55, 0.5, 0.4), 0.8)


## 一排铁皮柜：三格，门上有通风缝，有一格开着，里面漆黑
func _lockers(n: Node3D) -> void:
	var metal: Material = room.mat(Color(0.28, 0.3, 0.28), 0.5, 0.6) if rng.randf() < 0.6 else _metal()
	var open := rng.randi_range(0, 2) if rng.randf() < 0.3 + dread * 0.5 else -1
	for i in 3:
		var x := -0.46 + i * 0.46
		room.box(Vector3(0.44, 1.9, 0.48), Vector3(x, 0.95, 0), metal, false, Basis.IDENTITY, n)
		if i == open:
			room.box(Vector3(0.4, 1.84, 0.02), Vector3(x, 0.95, 0.235), m["black"], false, Basis.IDENTITY, n)
			var door := Node3D.new()
			door.position = Vector3(x + 0.21, 0, 0.25)
			door.rotation.y = deg_to_rad(rng.randf_range(-100.0, -40.0))
			n.add_child(door)
			room.box(Vector3(0.42, 1.86, 0.02), Vector3(-0.21, 0.95, 0), metal, false, Basis.IDENTITY, door)
		else:
			for k in 4:
				room.box(Vector3(0.25, 0.012, 0.01), Vector3(x, 1.6 + k * 0.05, 0.245), m["black"], false, Basis.IDENTITY, n)
	solid(n, Vector3(1.4, 1.9, 0.5), Vector3(0, 0.95, 0))


# ---------- 第三批 ----------

## 候诊长椅：铁架、木条座面和靠背；不安的长椅上留着一件外套，像有人刚起身
func _bench(n: Node3D) -> void:
	var frame := _metal()
	for sx: float in [-0.8, 0.0, 0.8]:
		room.box(Vector3(0.05, 0.44, 0.42), Vector3(sx, 0.22, 0.02), frame, false, Basis.IDENTITY, n)
		room.box(Vector3(0.05, 0.5, 0.05), Vector3(sx, 0.7, -0.2), frame, false, Basis.IDENTITY, n)
	for k in 3:
		room.box(Vector3(1.8, 0.03, 0.12), Vector3(0, 0.45, -0.12 + k * 0.14), m["wood"], false, Basis.IDENTITY, n)
	for k in 2:
		room.box(Vector3(1.8, 0.1, 0.03), Vector3(0, 0.7 + k * 0.18, -0.21), m["wood"], false, Basis(Vector3.RIGHT, -0.12), n)
	if rng.randf() < 0.2 + dread * 0.4:
		room.box(Vector3(0.45, 0.06, 0.5), Vector3(rng.randf_range(-0.6, 0.6), 0.5, 0.02), m["cloth"], false,
			Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), n)
	if rng.randf() < dread * 0.5:
		blood(n, Vector3(rng.randf_range(-0.6, 0.6), 0.004, 0.45), 0.6)
	solid(n, Vector3(1.8, 0.9, 0.5), Vector3(0, 0.45, 0))


## 课桌连椅：桌在前（+z），椅在后，坐着的人面朝 +z；不安的桌面上刻满了计数
func _desk(n: Node3D) -> void:
	var frame := _metal()
	room.box(Vector3(0.7, 0.03, 0.45), Vector3(0, 0.72, 0.25), m["wood"], false, Basis(Vector3.RIGHT, 0.08), n)
	room.box(Vector3(0.66, 0.12, 0.4), Vector3(0, 0.63, 0.25), m["dark_wood"], false, Basis.IDENTITY, n)
	for sx: float in [-0.3, 0.3]:
		room.box(Vector3(0.04, 0.7, 0.04), Vector3(sx, 0.35, 0.25), frame, false, Basis.IDENTITY, n)
		room.box(Vector3(0.04, 0.03, 0.9), Vector3(sx, 0.03, 0.0), frame, false, Basis.IDENTITY, n)
		room.box(Vector3(0.04, 0.42, 0.04), Vector3(sx * 0.7, 0.21, -0.3), frame, false, Basis.IDENTITY, n)
	room.box(Vector3(0.44, 0.03, 0.36), Vector3(0, 0.43, -0.3), m["wood"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.44, 0.22, 0.03), Vector3(0, 0.66, -0.48), m["wood"], false, Basis.IDENTITY, n)
	if rng.randf() < dread * 0.6:
		blood(n, Vector3(rng.randf_range(-0.2, 0.2), 0.748, 0.25), 0.3)
	solid(n, Vector3(0.7, 0.75, 1.0), Vector3(0, 0.375, 0))


## 黑板：木框、墨绿的板面，上面是粉笔画的计数；越不安划得越多，还有几道用血画的
func _blackboard(n: Node3D) -> void:
	room.box(Vector3(2.5, 1.3, 0.05), Vector3(0, 0, 0.025), m["dark_wood"], false, Basis.IDENTITY, n)
	room.box(Vector3(2.36, 1.16, 0.01), Vector3(0, 0, 0.055), room.mat(Color(0.05, 0.08, 0.06), 0.9), false, Basis.IDENTITY, n)
	room.box(Vector3(2.4, 0.03, 0.08), Vector3(0, -0.6, 0.08), m["dark_wood"], false, Basis.IDENTITY, n)
	var rows := 1 + int(dread * 3.0)
	for i in rows:
		var y := 0.35 - i * 0.3
		chalk(n, Vector3(rng.randf_range(-0.3, 0.3), y, 0.062), rng.randf_range(1.0, 1.6), TALLY)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.8, 0.8), 0.1, 0.064), 0.3, DRIP, Vector3.BACK)


## 粉笔的痕迹：和血迹同一个着色器，换成粉笔的颜色
func chalk(parent: Node3D, pos: Vector3, sz: float, kind: int) -> void:
	var aspect: float = BLOOD_ASPECT[kind]
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz * aspect)
	var sm := ShaderMaterial.new()
	sm.shader = BloodShader
	sm.set_shader_parameter("seed", rng.randf() * 100.0)
	sm.set_shader_parameter("kind", kind)
	sm.set_shader_parameter("aspect", aspect)
	sm.set_shader_parameter("wet", Color(0.48, 0.48, 0.45))
	sm.set_shader_parameter("dry", Color(0.36, 0.37, 0.35))
	room.mesh_at(q, Transform3D(room.facing(Vector3.BACK), pos), sm, parent)


## 长餐桌：桌布、两排椅子和两头各一把，每个座位一套餐具，正中一座烛台
func _long_table(n: Node3D) -> void:
	room.box(Vector3(2.6, 0.05, 1.0), Vector3(0, 0.76, 0), m["dark_wood"], false, Basis.IDENTITY, n)
	room.box(Vector3(2.66, 0.01, 1.06), Vector3(0, 0.79, 0), m["sheet"], false, Basis.IDENTITY, n)
	for sx: float in [-1.2, 1.2]:
		for sz: float in [-0.42, 0.42]:
			room.box(Vector3(0.06, 0.74, 0.06), Vector3(sx, 0.37, sz), m["dark_wood"], false, Basis.IDENTITY, n)
	var seats: Array[Transform3D] = []
	for x: float in [-0.85, 0.0, 0.85]:
		seats.append(Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, 0.75)))
		seats.append(Transform3D(Basis.IDENTITY, Vector3(x, 0, -0.75)))
	seats.append(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(1.55, 0, 0)))
	seats.append(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(-1.55, 0, 0)))
	for xf in seats:
		var c := Node3D.new()
		c.transform = xf
		n.add_child(c)
		_chair(c)
		var plate := CylinderMesh.new()
		plate.top_radius = 0.12
		plate.bottom_radius = 0.1
		plate.height = 0.015
		var o := xf.origin
		var at := Vector3(o.x * (0.8 if absf(o.z) < 0.1 else 1.0), 0.8, o.z * 0.55)
		room.mesh_at(plate, Transform3D(Basis.IDENTITY, at), m["porcelain"], n)
	room.box(Vector3(0.06, 0.3, 0.06), Vector3(0, 0.94, 0), m["brass"], false, Basis.IDENTITY, n)
	for sx: float in [-0.12, 0.0, 0.12]:
		room.box(Vector3(0.03, 0.12, 0.03), Vector3(sx, 1.14, 0), m["wax"], false, Basis.IDENTITY, n)
		room.box(Vector3(0.015, 0.03, 0.015), Vector3(sx, 1.215, 0), m["flame"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.3, 0.02, 0.03), Vector3(0, 1.08, 0), m["brass"], false, Basis.IDENTITY, n)
	room.lamp(Vector3(0, 1.4, 0), Color(1.0, 0.66, 0.35), 0.8, 4.0, false, n)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.8, 0.8), 0.796, 0), 0.6)
	solid(n, Vector3(2.6, 0.8, 1.0), Vector3(0, 0.4, 0))


## 布告板：软木板上钉着几张发黄的纸，有一张是寻人启事的样子（只有一块灰影，没有字）
func _noticeboard(n: Node3D) -> void:
	room.box(Vector3(1.0, 0.7, 0.04), Vector3(0, 0, 0.02), m["dark_wood"], false, Basis.IDENTITY, n)
	room.box(Vector3(0.92, 0.62, 0.01), Vector3(0, 0, 0.045), room.mat(Color(0.32, 0.22, 0.13), 0.95), false, Basis.IDENTITY, n)
	var paper: Material = room.mat(Color(0.55, 0.52, 0.42), 0.95)
	for i in rng.randi_range(3, 6):
		var w := rng.randf_range(0.14, 0.24)
		var pos := Vector3(rng.randf_range(-0.34, 0.34), rng.randf_range(-0.2, 0.2), 0.052 + i * 0.001)
		room.box(Vector3(w, w * 1.35, 0.002), pos, paper, false, Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)), n)
		room.box(Vector3(w * 0.5, w * 0.5, 0.002), pos + Vector3(0, w * 0.25, 0.002), m["stone"], false, Basis.IDENTITY, n)
		room.box(Vector3(0.015, 0.015, 0.01), pos + Vector3(0, w * 0.6, 0.004), m["gore"] if rng.randf() < dread else m["brass"],
			false, Basis.IDENTITY, n)


## 衣帽架：一根立杆、三只脚、顶上几个钩子，挂着一件长外套
func _coat_rack(n: Node3D) -> void:
	var wood: Material = m["dark_wood"]
	room.box(Vector3(0.05, 1.8, 0.05), Vector3(0, 0.9, 0), wood, false, Basis.IDENTITY, n)
	for i in 3:
		var a := TAU * i / 3.0
		room.box(Vector3(0.04, 0.04, 0.4), Vector3(cos(a) * 0.15, 0.04, sin(a) * 0.15), wood, false, Basis(Vector3.UP, -a + PI / 2.0), n)
		room.box(Vector3(0.025, 0.025, 0.18), Vector3(cos(a) * 0.07, 1.72, sin(a) * 0.07), wood, false,
			Basis(Vector3.UP, -a + PI / 2.0) * Basis(Vector3.RIGHT, -0.5), n)
	if rng.randf() < 0.7:
		room.box(Vector3(0.42, 1.1, 0.18), Vector3(0.0, 1.12, 0.14), m["black"] if rng.randf() < 0.5 else m["cloth"], false,
			Basis(Vector3.RIGHT, 0.08), n)
	solid(n, Vector3(0.4, 1.8, 0.4), Vector3(0, 0.9, 0))
