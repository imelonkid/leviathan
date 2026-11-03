extends RefCounted
## 实体库：房间里能摆的东西，模型由 Blender 脚本生成（tools/blender/room_props.py → room_props.glb）；
## 绑带、器械、外套这类随手加的小东西和血迹、粉笔痕迹还是在这里用方块和面片摆。
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


## 摆一件 Blender 建的模型：材质槽按名字套 m 里的材质；over 里给了的槽换成指定的（比如 frame 给铁或锈）
func model(name: String, parent: Node3D, over := {}, xf := Transform3D.IDENTITY) -> MeshInstance3D:
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
		mi.set_surface_override_material(i, over.get(key, m.get(key, m["cloth"])))
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
	model("bed_frame", n, {"frame": _metal()})
	if rng.randf() < 0.8:
		model("bed_mattress", n)
		if rng.randf() < dread:
			blood(n, Vector3(rng.randf_range(-0.2, 0.2), 0.632, rng.randf_range(-0.3, 0.5)), rng.randf_range(0.5, 0.9))
		# 带子：不安的床上有绑带
		if rng.randf() < dread * 0.6:
			for z: float in [-0.3, 0.5]:
				room.box(Vector3(0.9, 0.02, 0.07), Vector3(0, 0.645, z), m["black"], false, Basis.IDENTITY, n)
	solid(n, Vector3(0.9, 0.7, 2.0), Vector3(0, 0.35, 0))


## 柜子：顶冠、踢脚、两扇嵌板门；不安的时候一扇半开，里面黑洞洞的
func _cabinet(n: Node3D) -> void:
	var wood: Material = m["dark_wood"] if rng.randf() < 0.5 else m["wood"]
	model("cabinet", n, {"wood": wood})
	var ajar := rng.randf() < dread * 0.7
	for side: float in [-1.0, 1.0]:
		var door := Node3D.new()
		door.position = Vector3(side * 0.5, 0, 0.255)
		n.add_child(door)
		model("cabinet_door_r" if side > 0.0 else "cabinet_door_l", door, {"wood": wood})
		if ajar and side > 0.0:
			door.rotation.y = deg_to_rad(-55.0)
			room.box(Vector3(0.46, 1.78, 0.02), Vector3(0.25, 1.0, 0.24), m["black"], false, Basis.IDENTITY, n)
	solid(n, Vector3(1.0, 1.9, 0.5), Vector3(0, 0.95, 0))


## 架子：四层隔板，摆着瓶瓶罐罐（三套摆法挑一套）；不安的深色罐子里是暗红的
func _shelf(n: Node3D) -> void:
	model("shelf", n)
	var dark: Material = m["gore"] if rng.randf() < dread * 0.8 else m["glass"]
	model("shelf_jars_" + "abc"[rng.randi_range(0, 2)], n, {"jar_dark": dark})
	solid(n, Vector3(1.4, 2.0, 0.4), Vector3(0, 1.0, 0))


## 爪脚浴缸：卷边的铸铁缸、四只铜爪脚；不安的里面是一缸暗红
func _bathtub(n: Node3D) -> void:
	model("bathtub", n)
	model("bathtub_fill", n, {"black": m["gore"] if rng.randf() < dread * 0.8 else m["black"]})
	if rng.randf() < dread:
		blood(n, Vector3(0.45, 0.003, rng.randf_range(-0.4, 0.4)), 0.9)
	solid(n, Vector3(0.8, 0.7, 1.7), Vector3(0, 0.35, 0))


# ---------- 地上的 ----------

## 手术推车：两层带边的托盘、一头推把，上层摆着器械
func _cart(n: Node3D) -> void:
	model("cart", n, {"frame": _metal()})
	for i in rng.randi_range(3, 7):
		var l := rng.randf_range(0.12, 0.25)
		room.box(Vector3(0.015, 0.01, l), Vector3(rng.randf_range(-0.22, 0.22), 0.9, rng.randf_range(-0.3, 0.3)),
			m["steel"], false, Basis(Vector3.UP, rng.randf_range(-0.6, 0.6)), n)
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.892, 0.1), 0.4)
	solid(n, Vector3(0.6, 0.9, 0.9), Vector3(0, 0.45, 0))


## 椅子：车削腿、弯顶梁；不安的时候可能翻倒
func _chair(n: Node3D) -> void:
	var wood: Material = m["wood"] if rng.randf() < 0.6 else _metal()
	var c := Node3D.new()
	n.add_child(c)
	model("chair", c, {"wood": wood})
	if rng.randf() < dread * 0.3:
		c.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), Vector3(0, 0.2, 0.45))
	solid(n, Vector3(0.46, 0.9, 0.46), Vector3(0, 0.45, 0))


## 桌子：车削腿、牙板；桌上摆着两套餐具
func _table(n: Node3D) -> void:
	model("table", n)
	model("table_setting", n)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.3, 0.3), 0.788, 0), 0.5)
	solid(n, Vector3(1.4, 0.8, 0.8), Vector3(0, 0.4, 0))


## 铁笼：一圈竖栏杆、顶上横栏、一扇挂着锁的门；高矮不一
func _cage(n: Node3D) -> void:
	var h := rng.randf_range(1.2, 1.9)
	model("cage", n, {"frame": _metal()}, Transform3D(Basis.from_scale(Vector3(1.0, h / 1.5, 1.0)), Vector3.ZERO))
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.004, 0), 0.9)
	solid(n, Vector3(1.2, h, 1.2), Vector3(0, h / 2.0, 0))


## 木箱：一到三只摞着，大小不一、各自歪一点
func _crate(n: Node3D) -> void:
	var y := 0.0
	for i in rng.randi_range(1, 3):
		var sz := rng.randf_range(0.55, 0.8)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * (sz / 0.7))
		model("crate", n, {}, Transform3D(rot, Vector3(0, y, 0)))
		y += sz
	solid(n, Vector3(0.8, y, 0.8), Vector3(0, y / 2.0, 0))


## 铁桶：卷边、两道箍、提梁；不安的桶里是血
func _bucket(n: Node3D) -> void:
	model("bucket", n, {"frame": _metal()})
	model("bucket_fill", n, {"black": m["gore"] if rng.randf() < dread else m["black"]})


## 一簇蜡烛（两种摆法），淌着蜡泪，带一盏暖光
func _candles(n: Node3D) -> void:
	model("candles_" + "ab"[rng.randi_range(0, 1)], n, {}, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3.ZERO))
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

## 手术台：立柱底座、三段皮垫台面、头枕，台上台下都是血
func _optable(n: Node3D) -> void:
	model("optable", n)
	for z: float in [-0.4, 0.2, 0.7]:
		room.box(Vector3(0.8, 0.02, 0.07), Vector3(0, 0.85, z), m["black"], false, Basis.IDENTITY, n)
	if dread > 0.3:
		blood(n, Vector3(0, 0.846, rng.randf_range(-0.3, 0.3)), 0.8)
		blood(n, Vector3(rng.randf_range(-0.4, 0.4), 0.004, rng.randf_range(-0.6, 0.6)), 1.6)
	solid(n, Vector3(0.75, 0.85, 2.0), Vector3(0, 0.42, 0))


## 祭台：三级带线脚和竖槽的台座，上方悬着缩小的黄铜菱形（刻纹和天上的利维坦一样），缓缓自转
func _altar(n: Node3D) -> void:
	model("altar", n)
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
	model("grandfather", n)
	_dial(n, Vector3(0, 2.65, 0.27), 0.33, 1.0)
	var pend := Node3D.new()
	pend.position = Vector3(0, 2.15, 0.05)
	n.add_child(pend)
	model("pendulum", pend)
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
	model("clock_case", n, {}, Transform3D(Basis.from_scale(Vector3(r, r, 1.0)), Vector3.ZERO))
	var speeds: Array[float] = [1.0, 3.0, 12.0, -2.0, -0.5, 0.0, 40.0]
	_dial(n, Vector3(0, 0, 0.09), r, speeds[rng.randi_range(0, speeds.size() - 1)])


## 表盘：盘面、刻度、铜圈（模型，按半径缩放），时针分针单独转（speed = 分针每分钟几圈）
func _dial(n: Node3D, pos: Vector3, r: float, speed: float) -> void:
	model("dial", n, {}, Transform3D(Basis.from_scale(Vector3(r, r, 1.0)), pos))
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


const PICTURES := {"picture_a": Vector2(0.6, 0.8), "picture_b": Vector2(0.9, 0.62), "picture_c": Vector2(0.5, 0.5)}   # 画布尺寸


## 画框：三种尺寸；画面黑乎乎看不清，只有一块人影；不安的被划破，或者整幅翻过来朝着墙
func _picture(n: Node3D) -> void:
	var name: String = PICTURES.keys()[rng.randi_range(0, PICTURES.size() - 1)]
	var w: float = PICTURES[name].x
	var h: float = PICTURES[name].y
	if rng.randf() < dread * 0.3:
		model(name, n, {"canvas": m["wood"], "figure": m["wood"]})   # 背面朝外
		return
	var tone := Color(0.12, 0.1, 0.08).lerp(Color(0.3, 0.26, 0.2), rng.randf())
	# 人影只比画布亮一点，看得出有个人，看不清是谁
	model(name, n, {"canvas": room.mat(tone, 0.9), "figure": room.mat(tone.lerp(Color(0.4, 0.35, 0.3), 0.35), 0.9)})
	if rng.randf() < dread * 0.6:
		for i in 2:
			room.box(Vector3(0.02, h * 0.9, 0.006), Vector3(rng.randf_range(-0.3, 0.3) * w, 0, 0.045), m["black"],
				false, Basis(Vector3.BACK, rng.randf_range(-0.4, 0.4)), n)


## 镜子：雕花木框；多半蒙着一块布
func _mirror(n: Node3D) -> void:
	model("mirror", n)
	if rng.randf() < 0.4 + dread * 0.5:
		model("mirror_cover", n, {"cloth": m["sheet"]}, Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.08, 0.08)), Vector3.ZERO))


# ---------- 吊顶的 ----------

## 吊链：几根铁链从天花板垂下来，有的末端挂着钩子，慢慢晃
func _chains(n: Node3D) -> void:
	var frame := _metal()
	for c in rng.randi_range(1, 3):
		var chain := Node3D.new()
		chain.position = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		n.add_child(chain)
		var links: int = [8, 12, 16, 22][rng.randi_range(0, 3)]
		model("chain_%d" % links, chain, {"frame": frame})
		var end := -0.05 - links * 0.09
		if rng.randf() < 0.4 + dread * 0.4:
			model("chain_hook", chain, {"frame": frame}, Transform3D(Basis.IDENTITY, Vector3(0, end + 0.03, 0)))
		var phase := rng.randf() * TAU
		var amp := rng.randf_range(0.02, 0.06)
		room.tick(func(t: float) -> void:
			chain.rotation.x = amp * sin(t * 0.9 + phase)
			chain.rotation.z = amp * 0.6 * sin(t * 0.7 + phase * 1.3))


## 垂布：从天花板的一根杆上挂下来的一块旧布，微微晃；不安的上面有血
func _sheet(n: Node3D) -> void:
	model("sheet_rod", n, {"frame": _metal()})
	var cloth := Node3D.new()
	cloth.position = Vector3(0, -0.07, 0)
	n.add_child(cloth)
	var h := rng.randf_range(1.6, 2.4)
	model("hanging_sheet", cloth, {"cloth": m["sheet"]}, Transform3D(Basis.from_scale(Vector3(1.0, h / 2.0, 1.0)), Vector3.ZERO))
	if rng.randf() < dread:
		blood(cloth, Vector3(rng.randf_range(-0.3, 0.3), -h * 0.6, 0.05), 0.6, 1, Vector3.BACK)
	var phase := rng.randf() * TAU
	room.tick(func(t: float) -> void: cloth.rotation.x = 0.03 * sin(t * 0.8 + phase))


# ---------- 第二批 ----------

## 轮椅：辐条大轮、帆布座；进门时可能自己滑开
func _wheelchair(n: Node3D) -> void:
	model("wheelchair", n, {"frame": _metal()})
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.49, 0.05), 0.35)
	solid(n, Vector3(0.65, 1.0, 0.9), Vector3(0, 0.5, 0))
	room.drifters.append(n)


## 输液架：五脚带轮的底座、顶上弯钩挂着一袋——不安的袋子里是血
func _iv_stand(n: Node3D) -> void:
	model("iv_stand", n)
	model("iv_bag", n, {"glass": m["gore"] if rng.randf() < dread else m["glass"]})


## 停尸推床：带轮的窄床，多半盖着一张白布，布下面有个人形
func _gurney(n: Node3D) -> void:
	model("gurney", n, {"frame": _metal()})
	if rng.randf() < 0.4 + dread * 0.5:
		model("gurney_sheet", n, {"cloth": m["sheet"]})
		if rng.randf() < dread:
			blood(n, Vector3(rng.randf_range(-0.1, 0.1), 1.005, -0.25), 0.4)
	solid(n, Vector3(0.7, 0.85, 2.0), Vector3(0, 0.42, 0))


## 棺材：六边形的深色棺身、铜把手，棺盖错开一截，里面黑洞洞的
func _coffin(n: Node3D) -> void:
	model("coffin", n)
	var open := rng.randf_range(0.2, 0.7) * (0.3 + dread)
	model("coffin_lid", n, {}, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)), Vector3(0.1, 0.505, open)))
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


## 洗手池：车削立柱、圆角台盆、十字把手和鹅颈龙头；不安的盆里积着血
func _sink(n: Node3D) -> void:
	model("sink", n)
	model("sink_fill", n, {"black": m["gore"] if rng.randf() < dread else m["black"]})
	solid(n, Vector3(0.6, 0.9, 0.5), Vector3(0, 0.45, 0))


## 三脚凳
func _stool(n: Node3D) -> void:
	model("stool", n, {"wood": m["wood"] if rng.randf() < 0.6 else _metal()})
	if rng.randf() < dread * 0.4:
		n.rotation.x = deg_to_rad(90)
		n.position.y += 0.17


## 一堆骨头：长长短短的骨头和几根肋骨散在一起（两种堆法），有时有一个头骨
func _bones(n: Node3D) -> void:
	var bone := mat_bone()
	model("bones_" + "ab"[rng.randi_range(0, 1)], n, {"bone": bone}, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3.ZERO))
	if rng.randf() < 0.5 + dread * 0.3:
		model("skull", n, {"bone": bone}, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(0.1, 0, 0.05)))
	if rng.randf() < dread:
		blood(n, Vector3(0, 0.004, 0), 1.0)


func mat_bone() -> Material:
	return room.mat(Color(0.55, 0.5, 0.4), 0.8)


## 一排铁皮柜：三格，门上有百叶缝，有一格开着，里面漆黑
func _lockers(n: Node3D) -> void:
	var metal: Material = room.mat(Color(0.28, 0.3, 0.28), 0.5, 0.6) if rng.randf() < 0.6 else _metal()
	var open := rng.randi_range(0, 2) if rng.randf() < 0.3 + dread * 0.5 else -1
	model("lockers_body", n, {"frame": metal})
	for i in 3:
		var x := -0.46 + i * 0.46
		var door := Node3D.new()
		door.position = Vector3(x + 0.21, 0, 0.25)
		n.add_child(door)
		model("locker_door", door, {"frame": metal})
		if i == open:
			room.box(Vector3(0.4, 1.84, 0.02), Vector3(x, 0.95, 0.235), m["black"], false, Basis.IDENTITY, n)
			door.rotation.y = deg_to_rad(rng.randf_range(-100.0, -40.0))
	solid(n, Vector3(1.4, 1.9, 0.5), Vector3(0, 0.95, 0))


# ---------- 第三批 ----------

## 候诊长椅：铸铁侧架、木条座面和靠背；不安的长椅上留着一件外套，像有人刚起身
func _bench(n: Node3D) -> void:
	model("bench", n, {"frame": _metal()})
	if rng.randf() < 0.2 + dread * 0.4:
		room.box(Vector3(0.45, 0.06, 0.5), Vector3(rng.randf_range(-0.6, 0.6), 0.51, 0.02), m["cloth"], false,
			Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), n)
	if rng.randf() < dread * 0.5:
		blood(n, Vector3(rng.randf_range(-0.6, 0.6), 0.004, 0.45), 0.6)
	solid(n, Vector3(1.8, 0.9, 0.5), Vector3(0, 0.45, 0))


## 课桌连椅：桌在前（+z），椅在后，坐着的人面朝 +z；不安的桌面上刻满了计数
func _desk(n: Node3D) -> void:
	model("desk", n, {"frame": _metal()})
	if rng.randf() < dread * 0.6:
		blood(n, Vector3(rng.randf_range(-0.2, 0.2), 0.748, 0.25), 0.3)
	solid(n, Vector3(0.7, 0.75, 1.0), Vector3(0, 0.375, 0))


## 黑板：木框、墨绿的板面，上面是粉笔画的计数；越不安划得越多，还有几道用血画的
func _blackboard(n: Node3D) -> void:
	model("blackboard", n, {"board": room.mat(Color(0.05, 0.08, 0.06), 0.9), "paper": room.mat(Color(0.75, 0.74, 0.7), 0.9)})
	var rows := 1 + int(dread * 3.0)
	for i in rows:
		var y := 0.35 - i * 0.3
		chalk(n, Vector3(rng.randf_range(-0.3, 0.3), y, 0.037), rng.randf_range(1.0, 1.6), TALLY)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.8, 0.8), 0.1, 0.039), 0.3, DRIP, Vector3.BACK)


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
	model("long_table", n, {"cloth": m["sheet"]})
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
	room.lamp(Vector3(0, 1.4, 0), Color(1.0, 0.66, 0.35), 0.8, 4.0, false, n)
	if rng.randf() < dread:
		blood(n, Vector3(rng.randf_range(-0.8, 0.8), 0.796, 0), 0.6)
	solid(n, Vector3(2.6, 0.8, 1.0), Vector3(0, 0.4, 0))


## 布告板：软木板上钉着几张发黄的纸（两种钉法），有的是寻人启事的样子（只有一块灰影，没有字）
func _noticeboard(n: Node3D) -> void:
	model("noticeboard", n, {"cork": room.mat(Color(0.32, 0.22, 0.13), 0.95)})
	model("notice_papers_" + "ab"[rng.randi_range(0, 1)], n, {"paper": room.mat(Color(0.55, 0.52, 0.42), 0.95),
		"pin": m["gore"] if rng.randf() < dread else m["brass"]})


## 衣帽架：车削立杆、三条弯脚、顶上一圈铜钩，多半挂着一件长外套
func _coat_rack(n: Node3D) -> void:
	model("coat_rack", n)
	if rng.randf() < 0.7:
		model("coat", n, {"cloth": m["black"] if rng.randf() < 0.5 else m["cloth"]})
