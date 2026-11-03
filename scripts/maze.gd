extends Node3D
## 把 maze_gen.gd 生成的网格数据搭成场景：墙、观景台、地面、楼梯、平台、窄桥、拱门、拱窗，
## 再在围墙外铺一圈走不到的迷宫，一直延伸进雾里。
## 同一种几何合进一个 MultiMesh（各一次绘制），碰撞是一个静态体下挂多个盒子。

const MazeGen = preload("res://scripts/maze_gen.gd")
const ArchMesh = preload("res://scripts/arch_mesh.gd")
const WallShader = preload("res://scripts/wall.gdshader")
const InteriorShader = preload("res://scripts/interior.gdshader")
const TrimKit = preload("res://assets/models/trim_kit.glb")   # 建筑装饰件，tools/blender/trim_kit.py 生成
const Landmarks = preload("res://assets/models/landmarks.glb")   # 塔楼和门楼，tools/blender/landmarks.py 生成
const Houses = preload("res://assets/models/houses.glb")         # 带拱廊的小楼，tools/blender/houses.py 生成
const Room = preload("res://scripts/rooms/room.gd")
const ROOM_NEAR := 30.0          # 走到离房间中心这么近才把屋里搭出来
const ROOM_FAR := 60.0           # 走远到这么远再拆掉
const DOOR_R := 0.65             # 小房间的门：厚墙上的窄拱门，半宽、起拱高度、这段墙的高度
const DOOR_SPRING := 1.9
const DOOR_H := 3.2
const ROOM_FOG_CUT := -0.02      # 房间里抵消全局体积雾（= main.gd 的 volumetric_fog_density），房间自己要雾再加

const BOTTOM := -60.0            # 墙和地面柱一直延伸到这里，深渊底下是雾
const KILL_Y := -25.0            # 掉到这个高度以下就重生
const STEPS := 8                 # 每块楼梯的台阶数
const FIELD_RADIUS := 420.0      # 围墙外装饰迷宫的范围（米）
const PLANK_W := 1.4             # 窄桥宽度
const PLANK_T := 0.4
const PLATFORM_W := 3.4
const RAIL_T := 0.35             # 观景台栏杆：看起来齐腰高，碰撞做高一些，跳不过去
const RAIL_H := 1.0
const RAIL_BLOCK_H := 2.4
const WALK_RAIL_H := 0.7         # 墙顶步道两侧的矮护墙：看得出是条路；碰撞稍高，能跳过去
const WALK_RAIL_BLOCK_H := 1.0
const SPAN_DECK := 0.8            # 步道跨过通道处桥面的厚度
const FLY_DECK_W := 3.0           # 飞桥：桥面宽、厚，桥下龙骨的宽和高
const FLY_DECK_T := 0.8
const FLY_KEEL_W := 1.6
const FLY_KEEL_H := 1.0
const FLY_STAIR_W := 2.4          # 悬空楼梯的宽度、每级台阶石块的厚度
const FLY_STEP_T := 0.9
const GATE_R := 1.7              # 拱门：门洞半宽、起拱高度、拱门这段墙的高度和厚度
const GATE_SPRING := 3.2
const GATE_H := 6.0
const GATE_D := 1.0
const WINDOW_R := 0.75           # 盲拱窗：窗洞半宽、起拱高度、一层的高度
const WINDOW_SPRING := 1.9
const WINDOW_STOREY := 4.2
const WINDOW_CHANCE := 0.55      # 一面墙开拱窗的概率（开就整面墙每层都开）
const ARCADE_SILL := 1.0         # 拱廊墙：拱洞下沿离地多高、拱洞半宽、起拱高度（相对下沿）、拱洞这一段墙的高度
const ARCADE_R := 0.85
const ARCADE_SPRING := 1.6
const ARCADE_BAND := 3.4

@export var cells := 25          # 每边的格子数
@export var block := 5.0         # 一个网格块的边长（米），走道和墙同宽
@export var seed_value := 666

var gen: RefCounted              # MazeGen：网格数据，小地图也读它
var n := 0
var wall_mat: ShaderMaterial
var floor_mat: ShaderMaterial
var window_mat: ShaderMaterial
var trim_mat: ShaderMaterial
var trim_meshes := {}            # 装饰件名 → 网格（来自 trim_kit.glb）
var trims := {}                  # 装饰件名 → 这一件的所有摆放位置
var landmark_meshes := {}        # 地标名 → 网格（来自 landmarks.glb）
var landmark_mats := {}          # 材质槽名（stone / roof / dark，小楼还有 wood / frame / cloth）→ 游戏里的材质
var window_faces := {}           # 开了拱窗的墙面：Vector4i(x, z, dx, dz)，壁柱避开它们
var gate_mesh: ArrayMesh
var window_mesh: ArrayMesh
var arcade_mesh: ArrayMesh
var wall_boxes: Array[Transform3D] = []
var floor_boxes: Array[Transform3D] = []
var field_boxes: Array[Transform3D] = []
var gates: Array[Transform3D] = []
var windows: Array[Transform3D] = []
var arcades: Array[Transform3D] = []
var doorways: Array[Transform3D] = []
var doorway_mesh: ArrayMesh
var room_visits := {}            # 房间序号 → 会变的屋子变过几次（屋里拆掉后还记着）
var room_nodes := {}             # 房间序号 → 已经搭出来的屋里（Room 节点）
var room_check := 0.0
var body: StaticBody3D


## 可重复调用：换了 seed_value 再调一次就是新迷宫
func build() -> void:
	for child in get_children():
		child.queue_free()
	if wall_mat == null:
		_make_materials()

	gen = MazeGen.new()
	gen.cells = cells
	gen.generate(seed_value)
	n = gen.n
	wall_boxes.clear()
	floor_boxes.clear()
	field_boxes.clear()
	gates.clear()
	windows.clear()
	arcades.clear()
	doorways.clear()
	window_faces.clear()
	for k: String in trim_meshes:
		trims[k] = [] as Array[Transform3D]
	room_nodes.clear()
	room_visits.clear()

	body = StaticBody3D.new()
	add_child(body)
	_build_walls()
	_build_band_rails()
	_build_walkway_rails()
	_build_spans()
	_build_overpasses()
	_build_plaza_bridges()
	_build_floors()
	for z in n:
		for x in n:
			match gen.kind[z][x]:
				MazeGen.STAIR:
					_build_stair(x, z)
				MazeGen.BRIDGE:
					_build_bridge(x, z)
				MazeGen.PLATFORM:
					_build_platform(x, z)
	_build_gates()
	_build_doorways()
	_build_arcades()
	_build_windows()
	_build_trim()
	_build_landmarks()
	_build_houses()
	_build_plaza_monoliths()
	_build_rooms()
	_build_outer_field()
	_commit(wall_boxes, wall_mat)
	_commit(floor_boxes, floor_mat)
	_commit(field_boxes, wall_mat, false)
	_commit_mesh(gates, gate_mesh)
	_commit_mesh(arcades, arcade_mesh)
	_commit_mesh(doorways, doorway_mesh)
	_commit_mesh(windows, window_mesh)
	for k: String in trims:
		_commit_mesh(trims[k], trim_meshes[k])


## 出生点：最外一圈观景台上（离中心约 100 米），远远望得见利维坦，要穿过两层迷宫才走到它下面
func get_spawn_position() -> Vector3:
	var b: Vector2i = gen.spawn
	return _block_to_world(b.x, b.y) + Vector3(0, gen.floor_height(b.x, b.y) + 0.2, 0)


## 块中心的世界坐标（y = 0），怪物找路用
func block_center(x: int, z: int) -> Vector3:
	return _block_to_world(x, z)


func _block_to_world(x: int, z: int) -> Vector3:
	var half := n / 2.0
	return Vector3((x - half + 0.5) * block, 0.0, (z - half + 0.5) * block)


## 世界坐标 → 网格块坐标（小地图用），不做越界裁剪
func world_to_block(p: Vector3) -> Vector2:
	var half := n / 2.0
	return Vector2(p.x / block + half, p.z / block + half)


func _make_materials() -> void:
	# 墙和地面用同一个着色器：竖直面是旧灰泥 / 土坯，朝上的面是踩实的土地；地面另一份材质，下雨会积水洼
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = WallShader
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = WallShader
	floor_mat.set_shader_parameter("puddles", 1.0)
	# 装饰件：同一个墙面着色器，灰泥浅一点、不怎么剥落，看上去是另砌的石头线脚
	trim_mat = ShaderMaterial.new()
	trim_mat.shader = WallShader
	trim_mat.set_shader_parameter("plaster_color", Color(0.56, 0.52, 0.46))
	trim_mat.set_shader_parameter("peel", 0.08)
	trim_mat.set_shader_parameter("crack", 0.35)
	for scene: PackedScene in [Landmarks, Houses]:
		var lm: Node = scene.instantiate()
		for c in lm.find_children("*", "MeshInstance3D", true, false):
			landmark_meshes[String(c.name)] = (c as MeshInstance3D).mesh
		lm.free()
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.11, 0.11, 0.12)
	roof.roughness = 0.55
	roof.metallic = 0.25
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.012, 0.012, 0.014)
	hole.roughness = 1.0
	var boards := StandardMaterial3D.new()
	boards.albedo_color = Color(0.17, 0.11, 0.07)
	boards.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.14)
	iron.roughness = 0.6
	iron.metallic = 0.6
	var rag := StandardMaterial3D.new()
	rag.albedo_color = Color(0.42, 0.39, 0.33)
	rag.roughness = 1.0
	landmark_mats = {"stone": wall_mat, "roof": roof, "dark": hole, "wood": boards, "frame": iron, "cloth": rag}
	var kit: Node = TrimKit.instantiate()
	for c in kit.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (c as MeshInstance3D).mesh
		mesh.surface_set_material(0, trim_mat)
		trim_meshes[String(c.name)] = mesh
	kit.free()


	gate_mesh = ArchMesh.gate(block / 2.0, GATE_H, GATE_D, GATE_R, GATE_SPRING)
	gate_mesh.surface_set_material(0, wall_mat)
	# 拱廊墙每块墙开两个拱洞，每个拱洞是半块宽的一扇“拱门”，厚度就是整块墙
	arcade_mesh = ArchMesh.gate(block / 4.0, ARCADE_BAND, block, ARCADE_R, ARCADE_SPRING)
	arcade_mesh.surface_set_material(0, wall_mat)
	doorway_mesh = ArchMesh.gate(block / 2.0, DOOR_H, block, DOOR_R, DOOR_SPRING)
	doorway_mesh.surface_set_material(0, wall_mat)
	window_mesh = ArchMesh.window(WINDOW_R, WINDOW_SPRING, 0.28, 0.18)
	window_mesh.surface_set_material(0, wall_mat)
	# 窗洞里画一间并不存在的毛坯房（假室内），见 interior.gdshader
	window_mat = ShaderMaterial.new()
	window_mat.shader = InteriorShader
	window_mesh.surface_set_material(1, window_mat)


## 加一个方块：list 决定材质；rot 用于斜放的楼梯坡道和斜桥
func _add_box(list: Array[Transform3D], center: Vector3, size: Vector3,
		rot := Basis.IDENTITY, collide := true) -> void:
	list.append(Transform3D(rot * Basis.from_scale(size), center))
	if collide:
		_add_collider(center, size, rot)


func _add_collider(center: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(rot, center)
	body.add_child(cs)


## 竖直的柱体：从 BOTTOM 到 top，横跨 x0..x1 这几块
func _add_column(list: Array[Transform3D], x0: int, x1: int, z: int, top: float) -> void:
	var a := _block_to_world(x0, z)
	var b := _block_to_world(x1, z)
	var h := top - BOTTOM
	var center := (a + b) / 2.0 + Vector3(0, BOTTOM + h / 2.0, 0)
	_add_box(list, center, Vector3((x1 - x0 + 1) * block, h, block))


## 沿 dir 方向、升高 rise、水平跨度 run 的斜板朝向：x 是宽，y 是厚，z 是长
func _slope_basis(dir: Vector2i, rise: float, run: float) -> Basis:
	var f := Vector3(dir.x, 0, dir.y)
	var along := (f * run + Vector3.UP * rise).normalized()
	var side := f.cross(Vector3.UP).normalized()
	var up := side.cross(along)
	return Basis(side, up, side.cross(up))


func _is_solid(x: int, z: int) -> bool:
	var k: int = gen.kind[z][x]
	return k == MazeGen.WALL or k == MazeGen.PARAPET


## 按行合并：同样高度的连续墙（含矮墙）合成一段；拱廊墙另外搭，小楼占的墙由楼身代替
func _build_walls() -> void:
	for z in n:
		var x := 0
		while x < n:
			if not _is_solid(x, z) or gen.arcade[z][x] or gen.house[z][x]:
				x += 1
				continue
			var start := x
			var top: float = gen.wall_top[z][x]
			while x < n and _is_solid(x, z) and not gen.arcade[z][x] and not gen.house[z][x] \
					and is_equal_approx(gen.wall_top[z][x], top):
				x += 1
			_add_column(wall_boxes, start, x - 1, z, top)


## 步道跨过通道的地方：通道两头各一道拱，拱上补墙到桥面，顶上一块和墙顶齐平的桥面。
## 人在下面照样走通道，在上面沿步道走过去
func _build_spans() -> void:
	for z in n:
		for x in n:
			if not gen.span[z][x]:
				continue
			var h: float = gen.height[z][x]
			var top: float = gen.wall_top[z][x]
			var center := _block_to_world(x, z) + Vector3(0, h, 0)
			var along_x := x % 2 == 0
			var rot := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)) if along_x else Basis.IDENTITY
			var run := rot.z   # 顺着通道的方向
			var pier := block / 2.0 - GATE_R
			for end: float in [-1.0, 1.0]:
				var c := center + run * end * (block - GATE_D) / 2.0
				gates.append(Transform3D(rot, c))
				_add_voussoirs(rot, c, GATE_D)
				for side: float in [-1.0, 1.0]:
					var off := rot.x * side * (block / 2.0 - pier / 2.0)
					_add_collider(c + off + Vector3(0, GATE_SPRING / 2.0, 0), Vector3(pier, GATE_SPRING, GATE_D), rot)
				var fill := top - h - GATE_H
				if fill > 0.0:
					_add_box(wall_boxes, c + Vector3(0, GATE_H + fill / 2.0, 0), (rot * Vector3(block, fill, GATE_D)).abs(), Basis.IDENTITY, false)
			var deck := Vector3(block, SPAN_DECK, block)
			_add_box(wall_boxes, center + Vector3(0, top - h - SPAN_DECK / 2.0, 0), deck, Basis.IDENTITY, false)
			_add_collider(center + Vector3(0, top - h - SPAN_DECK / 2.0, 0), deck)


## 墙顶步道：沿着步道的边砌一道矮护墙。旁边也是步道、是同高的挑台、或者是更高的墙，就不砌
func _build_walkway_rails() -> void:
	for z in n:
		for x in n:
			if not gen.walkway[z][x]:
				continue
			var top: float = gen.wall_top[z][x]
			var center := _block_to_world(x, z)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var nz := z + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n or gen.walkway[nz][nx]:
					continue
				if _is_solid(nx, nz) and gen.wall_top[nz][nx] > top + WALK_RAIL_H:
					continue
				if gen.is_open(nx, nz) and is_equal_approx(gen.height[nz][nx], top):
					continue
				var f := Vector3(d.x, 0, d.y)
				var edge := center + f * (block - RAIL_T) / 2.0
				var size := Vector3(RAIL_T, 0, block) if d.x != 0 else Vector3(block, 0, RAIL_T)
				if _plaza_bridge_end(Vector2i(x, z), d):
					# 广场高架桥从这里接上步道：护墙只留桥面两旁的两小段
					var w := (block - FLY_DECK_W) / 2.0
					var side := Vector3(absf(f.z), 0, absf(f.x))
					size = size - side * (block - w)
					for s: float in [-1.0, 1.0]:
						var c := edge + side * s * (FLY_DECK_W + w) / 2.0
						_add_box(wall_boxes, c + Vector3(0, top + WALK_RAIL_H / 2.0, 0), size + Vector3(0, WALK_RAIL_H, 0), Basis.IDENTITY, false)
						_add_collider(c + Vector3(0, top + WALK_RAIL_BLOCK_H / 2.0, 0), size + Vector3(0, WALK_RAIL_BLOCK_H, 0))
					continue
				_add_box(wall_boxes, edge + Vector3(0, top + WALK_RAIL_H / 2.0, 0), size + Vector3(0, WALK_RAIL_H, 0), Basis.IDENTITY, false)
				_add_collider(edge + Vector3(0, top + WALK_RAIL_BLOCK_H / 2.0, 0), size + Vector3(0, WALK_RAIL_BLOCK_H, 0))


## 观景台：一根实心柱顶到高层地面；凡是邻块比它低（崖边、楼梯槽、深渊）的那条边立一道栏杆。
## 栏杆看起来齐腰高，不挡往下看的视线；碰撞做到 RAIL_BLOCK_H，跳不过去
func _build_band_rails() -> void:
	for z in n:
		for x in n:
			if gen.kind[z][x] != MazeGen.TERRACE:
				continue
			var top: float = gen.height[z][x]
			_add_column(floor_boxes, x, x, z, top)
			var center := _block_to_world(x, z)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var nz := z + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var nk: int = gen.kind[nz][nx]
				var same_level: bool = gen.is_open(nx, nz) and nk != MazeGen.STAIR \
					and is_equal_approx(gen.height[nz][nx], top)
				var tall_wall: bool = _is_solid(nx, nz) and gen.wall_top[nz][nx] > top + RAIL_BLOCK_H
				if same_level or tall_wall:
					continue
				var f := Vector3(d.x, 0, d.y)
				var edge := center + f * (block - RAIL_T) / 2.0
				var size := Vector3(RAIL_T, 0, block) if d.x != 0 else Vector3(block, 0, RAIL_T)
				if _overpass_root(Vector2i(x, z), d):
					# 飞桥从这条边伸出去：栏杆只留桥面两旁的两小段
					var w := (block - FLY_DECK_W) / 2.0
					var side := Vector3(absf(f.z), 0, absf(f.x))
					size = size - side * (block - w)
					for s: float in [-1.0, 1.0]:
						var c := edge + side * s * (FLY_DECK_W + w) / 2.0
						_add_box(wall_boxes, c + Vector3(0, top + RAIL_H / 2.0, 0), size + Vector3(0, RAIL_H, 0), Basis.IDENTITY, false)
						_add_collider(c + Vector3(0, top + RAIL_BLOCK_H / 2.0, 0), size + Vector3(0, RAIL_BLOCK_H, 0))
					continue
				_add_box(wall_boxes, edge + Vector3(0, top + RAIL_H / 2.0, 0), size + Vector3(0, RAIL_H, 0), Basis.IDENTITY, false)
				_add_collider(edge + Vector3(0, top + RAIL_BLOCK_H / 2.0, 0), size + Vector3(0, RAIL_BLOCK_H, 0))


func _overpass_root(b: Vector2i, d: Vector2i) -> bool:
	for o: Dictionary in gen.overpasses:
		if o["root"] == b and o["out"] == d:
			return true
	return false


## 飞桥：从观景台边沿水平伸出去的桥面，下面一道龙骨，两边齐腰的栏杆（碰撞做到 RAIL_BLOCK_H，
## 从下层升空也翻不上来）。断桥的尽头参差地断开，也拦一道看不见的栏杆；
## 通的那座桥面尽头接三块悬空楼梯：一级级石块叠成，前两块悬着（下面照样走人），最后一块落地是实心的，
## 比通道窄，两旁还能挤过去
func _build_overpasses() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 5
	for o: Dictionary in gen.overpasses:
		var root: Vector2i = o["root"]
		var out: Vector2i = o["out"]
		var deck: float = o["deck"]
		var broken: bool = o["stair"] == 0
		var f := Vector3(out.x, 0, out.y)
		var side := Vector3(-f.z, 0, f.x)
		var start := _block_to_world(root.x, root.y) + f * block / 2.0
		var length: float = o["level"] * block
		var slab := length - (1.2 if broken else 0.0)
		var keel := slab - (1.0 if broken else 0.0)
		_add_box(wall_boxes, start + f * slab / 2.0 + Vector3(0, deck - FLY_DECK_T / 2.0, 0), _flat(f, slab, FLY_DECK_T, FLY_DECK_W))
		_add_box(wall_boxes, start + f * keel / 2.0 + Vector3(0, deck - FLY_DECK_T - FLY_KEEL_H / 2.0, 0), _flat(f, keel, FLY_KEEL_H, FLY_KEEL_W), Basis.IDENTITY, false)
		for s: float in [-1.0, 1.0]:
			var rail := length - (r.randf_range(0.6, 2.4) if broken else 0.0)
			var c := start + side * s * (FLY_DECK_W - RAIL_T) / 2.0 + f * rail / 2.0
			_add_box(wall_boxes, c + Vector3(0, deck + RAIL_H / 2.0, 0), _flat(f, rail, RAIL_H, RAIL_T), Basis.IDENTITY, false)
			_add_collider(c + Vector3(0, deck + RAIL_BLOCK_H / 2.0, 0), _flat(f, rail, RAIL_BLOCK_H, RAIL_T))
		if broken:
			# 断口：三条宽窄的碎板，各自伸出不同的长度、往下塌一点
			var piece := FLY_DECK_W / 3.0
			for i in 3:
				var reach := r.randf_range(0.2, 1.6)
				var sag := r.randf_range(0.0, 0.25)
				var c := start + f * (slab + reach / 2.0) + side * (i - 1) * piece
				_add_box(wall_boxes, c + Vector3(0, deck - sag - FLY_DECK_T / 2.0, 0), _flat(f, reach, FLY_DECK_T, piece * 0.92))
			_add_collider(start + f * (length + 0.3) + Vector3(0, deck + RAIL_BLOCK_H / 2.0, 0), _flat(f, RAIL_T, RAIL_BLOCK_H, FLY_DECK_W))
			continue
		_build_hanging_stair(start + f * length, out, deck, o["stair"])


func _plaza_bridge_end(b: Vector2i, d: Vector2i) -> bool:
	for pb: Dictionary in gen.plaza_bridges:
		var start: Vector2i = pb["start"]
		var dir: Vector2i = pb["dir"]
		if b == start and d == dir or b == start + dir * (pb["span"] + 1) and d == -dir:
			return true
	return false


## 广场高架桥：两头搭在步道上的桥面、龙骨和齐膝的护墙（同步道）；楼梯接上来的那一段护墙断开，
## 楼梯是两块悬空楼梯，从桥边往下落到广场地面
func _build_plaza_bridges() -> void:
	for pb: Dictionary in gen.plaza_bridges:
		var start: Vector2i = pb["start"]
		var dir: Vector2i = pb["dir"]
		var sd: Vector2i = pb["stair_dir"]
		var deck: float = pb["deck"]
		var f := Vector3(dir.x, 0, dir.y)
		var s := Vector3(sd.x, 0, sd.y)
		var a := _block_to_world(start.x, start.y) + f * block / 2.0
		var length: float = pb["span"] * block
		_add_box(wall_boxes, a + f * length / 2.0 + Vector3(0, deck - FLY_DECK_T / 2.0, 0), _flat(f, length, FLY_DECK_T, FLY_DECK_W))
		_add_box(wall_boxes, a + f * length / 2.0 + Vector3(0, deck - FLY_DECK_T - FLY_KEEL_H / 2.0, 0), _flat(f, length, FLY_KEEL_H, FLY_KEEL_W), Basis.IDENTITY, false)
		var at := _block_to_world(pb["stair_at"].x, pb["stair_at"].y)
		var off := (at - a).dot(f)   # 楼梯中线离桥头多远
		var gap := FLY_STAIR_W + 0.2
		for side: float in [-1.0, 1.0]:
			var pieces: Array = [[0.0, length]]
			if s.dot(Vector3(-f.z, 0, f.x)) * side > 0.0:
				pieces = [[0.0, off - gap / 2.0], [off + gap / 2.0, length]]
			for pc: Array in pieces:
				var l: float = pc[1] - pc[0]
				var c: Vector3 = a + Vector3(-f.z, 0, f.x) * side * (FLY_DECK_W - RAIL_T) / 2.0 + f * (pc[0] + l / 2.0)
				_add_box(wall_boxes, c + Vector3(0, deck + WALK_RAIL_H / 2.0, 0), _flat(f, l, WALK_RAIL_H, RAIL_T), Basis.IDENTITY, false)
				_add_collider(c + Vector3(0, deck + WALK_RAIL_BLOCK_H / 2.0, 0), _flat(f, l, WALK_RAIL_BLOCK_H, RAIL_T))
		_build_hanging_stair(at + s * FLY_DECK_W / 2.0, sd, deck, MazeGen.PLAZA_STAIR_BLOCKS)


## 悬空楼梯：从 top（桥面尽头，高 deck）朝 out 一块块往下，每块降 STAIR_RISE
func _build_hanging_stair(top: Vector3, out: Vector2i, deck: float, blocks: int) -> void:
	var f := Vector3(out.x, 0, out.y)
	var rise := MazeGen.STAIR_RISE
	var depth := block / STEPS
	for j in blocks:
		var ground := j == blocks - 1
		for i in STEPS:
			var h := deck - j * rise - (i + 0.5) * rise / STEPS
			var bottom := deck - blocks * rise if ground else h - FLY_STEP_T
			var c := top + f * (j * block + (i + 0.5) * depth) + Vector3(0, (h + bottom) / 2.0, 0)
			_add_box(floor_boxes, c, _flat(f, depth, h - bottom, FLY_STAIR_W), Basis.IDENTITY, false)
			if ground and h - bottom > 0.5:
				# 落地那块是实心的：碰撞比台阶低一点，藏在坡道下面，免得绊脚
				_add_collider(c - Vector3(0, 0.15, 0), _flat(f, depth, h - bottom - 0.3, FLY_STAIR_W))
		var rot := _slope_basis(-out, rise, block)
		var lo := deck - (j + 1) * rise
		var c := top + f * (j + 0.5) * block + Vector3(0, lo + rise / 2.0, 0) - rot.y * 0.1
		_add_collider(c, Vector3(FLY_STAIR_W, 0.2, sqrt(block * block + rise * rise)), rot)


## 顺着 f（水平、沿 x 或 z）摆的方块尺寸：长 length、高 h、宽 w
func _flat(f: Vector3, length: float, h: float, w: float) -> Vector3:
	return Vector3(length, h, w) if f.x != 0.0 else Vector3(w, h, length)


## 按行合并：同样高度的连续平地合成一根实心柱
func _build_floors() -> void:
	for z in n:
		var x := 0
		while x < n:
			if gen.kind[z][x] != MazeGen.FLOOR:
				x += 1
				continue
			var start := x
			var h: float = gen.height[z][x]
			while x < n and gen.kind[z][x] == MazeGen.FLOOR and is_equal_approx(gen.height[z][x], h):
				x += 1
			_add_column(floor_boxes, start, x - 1, z, h)


## 楼梯：低端的实心柱 + 台阶（只是外观）+ 一块斜坡碰撞（走起来顺）
func _build_stair(x: int, z: int) -> void:
	var base: float = gen.height[z][x]
	var rise := MazeGen.STAIR_RISE
	var dir: Vector2i = gen.link[z][x]
	var f := Vector3(dir.x, 0, dir.y)
	var side := Vector3(absf(f.z), 0, absf(f.x))
	var center := _block_to_world(x, z)
	_add_column(floor_boxes, x, x, z, base)

	var depth := block / STEPS
	for i in STEPS:
		var top := base + (i + 0.5) * rise / STEPS
		var c := center + f * (-block / 2.0 + (i + 0.5) * depth) + Vector3(0, (base + top) / 2.0, 0)
		var size := side * block + absf(f.x) * Vector3(depth, 0, 0) + absf(f.z) * Vector3(0, 0, depth)
		size.y = top - base
		_add_box(floor_boxes, c, size, Basis.IDENTITY, false)

	var rot := _slope_basis(dir, rise, block)
	var length := sqrt(block * block + rise * rise)
	var ramp_center := center + Vector3(0, base + rise / 2.0, 0) - rot.y * 0.1
	_add_collider(ramp_center, Vector3(block, 0.2, length), rot)


## 窄桥：从一个格子中心搭到下一个格子中心，有高差就斜着搭
func _build_bridge(x: int, z: int) -> void:
	var dir: Vector2i = gen.link[z][x]
	var lo: float = gen.height[z - dir.y][x - dir.x]
	var hi: float = gen.height[z + dir.y][x + dir.x]
	var rise := hi - lo
	var run := block * 2.0
	var rot := _slope_basis(dir, rise, run)
	var center := _block_to_world(x, z) + Vector3(0, lo + rise / 2.0, 0) \
		- rot.y * (PLANK_T / 2.0)
	_add_box(floor_boxes, center, Vector3(PLANK_W, PLANK_T, sqrt(run * run + rise * rise)), rot)


## 悬空平台：一块石板立在细柱上；朝区外开口的方向补一段短桥接上通道
func _build_platform(x: int, z: int) -> void:
	var top: float = gen.height[z][x]
	var center := _block_to_world(x, z)
	_add_box(floor_boxes, center + Vector3(0, top - 0.5, 0), Vector3(PLATFORM_W, 1.0, PLATFORM_W))
	var pillar_h := top - 1.0 - BOTTOM
	_add_box(wall_boxes, center + Vector3(0, BOTTOM + pillar_h / 2.0, 0), Vector3(0.8, pillar_h, 0.8))

	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var k: int = gen.kind[z + d.y][x + d.x]
		if k != MazeGen.FLOOR and k != MazeGen.STAIR:
			continue
		var f := Vector3(d.x, 0, d.y)
		var c := center + f * (block / 2.0) / 2.0 + Vector3(0, top - PLANK_T / 2.0, 0)
		var size := Vector3(PLANK_W, PLANK_T, PLANK_W)
		if d.x != 0:
			size.x = block / 2.0
		else:
			size.z = block / 2.0
		_add_box(floor_boxes, c, size)


## 拱门：通道上方横一段墙，下面开拱形门洞；拱门以上一直补到两侧墙顶。
## 门墩站在走道里，要有碰撞；拱顶在头顶上方，不用碰撞
const TOWER_MESH := ["tower_bell", "tower_watch", "tower_spire"]
const TOWER_SOLID := [25.7, 24.2, 23.6]   # 每种塔楼碰撞做到多高（尖顶不算）
const LANDMARK_PAD := 1.02       # 地标比一块大一点点，盖住下面的墙柱，免得两个面重合闪烁


## 地标：塔楼立在墙角块上，随机转 90° 的倍数；门楼的两个墩子压在通道两侧的墙角上，楼身横跨通道。
## 碰撞：塔身、门楼的墩子和楼身（楼身下面 7.5 米以内空着，照样走）
func _build_landmarks() -> void:
	if landmark_meshes.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 3
	var pad := Basis.from_scale(Vector3(LANDMARK_PAD, 1.0, LANDMARK_PAD))
	for t: Dictionary in gen.towers:
		var b: Vector2i = t["block"]
		var base: float = t["base"]
		var pos := _block_to_world(b.x, b.y) + Vector3(0, base, 0)
		var rot := Basis(Vector3.UP, PI / 2.0 * r.randi_range(0, 3)) * pad
		_place_landmark(TOWER_MESH[t["kind"]], Transform3D(rot, pos))
		var h: float = TOWER_SOLID[t["kind"]]
		_add_collider(pos + Vector3(0, h / 2.0, 0), Vector3(block, h, block))
	for g: Dictionary in gen.gatehouses:
		var b: Vector2i = g["block"]
		var base: float = g["base"]
		var pos := _block_to_world(b.x, b.y) + Vector3(0, base, 0)
		var turn := Basis.IDENTITY if g["along_x"] else Basis(Vector3.UP, PI / 2.0)
		_place_landmark("gatehouse", Transform3D(turn * pad, pos))
		var across := turn * Vector3(0, 0, 1)
		for s: float in [-1.0, 1.0]:
			_add_collider(pos + across * s * block + Vector3(0, 8.8, 0), Vector3(block, 17.6, block))
		_add_collider(pos + Vector3(0, 11.55, 0), (turn * Vector3(block, 8.1, block)).abs())


## 小楼（houses.glb）的尺寸，和 tools/blender/houses.py 一致：楼长 15、进深 5，底层（拱廊层）4.6 米、楼上每层 4.2 米
const HOUSE_LEN := 15.0
const HOUSE_GROUND := 4.6
const HOUSE_STOREY := 4.2
const HOUSE_PORCH := 2.0
const HOUSE_ROOF := 2.6          # 檐口线脚 0.6 + 屋脊升高 2.0


## 拱洞的位置（局部 x）：和 houses.py 的 arcade_layout 同一套算法
func _house_arches(arches: int) -> Array[Vector2]:
	var span := HOUSE_LEN / arches
	var pier := 1.0 if arches == 3 else 0.8
	var out: Array[Vector2] = []
	for i in arches:
		var cx := -HOUSE_LEN / 2.0 + span * (i + 0.5)
		out.append(Vector2(cx - (span - pier) / 2.0, cx + (span - pier) / 2.0))
	return out


## 带拱廊的小楼：楼身、楼上的拱窗（窗洞里是假室内）、阳台，以及碰撞——
## 廊子后面的实心部分、拱之间的墩子、拱上的墙、楼上整块，屋顶两面坡和屋脊（站得住）
func _build_houses() -> void:
	if landmark_meshes.is_empty():
		return
	for h: Dictionary in gen.houses:
		var c: Vector2i = h["block"]
		var face: Vector2i = h["face"]
		var along: Vector2i = h["along"]
		var storeys: int = h["storeys"]
		var base: float = h["base"]
		var f := Vector3(face.x, 0, face.y)
		var rot := Basis(Vector3.UP.cross(f), Vector3.UP, f)
		var origin := _block_to_world(c.x, c.y) + Vector3(0, base, 0)
		var xf := Transform3D(rot, origin)
		_place_landmark("house_s%d_a%d" % [storeys, h["arches"]], xf)
		var top := HOUSE_GROUND + HOUSE_STOREY * (storeys - 1)
		var hl := HOUSE_LEN / 2.0
		var d := block / 2.0
		# 窗：朝街那面楼上每层三扇；背面只在对着平地的那几段开，底层也开
		var back := Basis(Vector3.UP.cross(-f), Vector3.UP, -f)
		for k in storeys:
			var y := 1.0 + (0.0 if k == 0 else HOUSE_GROUND + HOUSE_STOREY * (k - 1))
			for i in 3:
				var x := (i - 1) * block
				if k > 0:
					windows.append(Transform3D(rot, xf * Vector3(x, y, d)))
				var bk: Vector2i = c - face + along * (i - 1)
				if gen.kind[bk.y][bk.x] == MazeGen.FLOOR and is_equal_approx(gen.height[bk.y][bk.x], base):
					windows.append(Transform3D(back, xf * Vector3(x, y, -d)))
		if h["balcony"]:
			_place_landmark("house_balcony", Transform3D(rot, xf * Vector3(0, HOUSE_GROUND + 0.08, d)))
		# 碰撞（局部坐标里算，再变到世界）
		var zp := d - HOUSE_PORCH
		var boxes: Array[AABB] = [
			AABB(Vector3(-hl, 0, -d), Vector3(HOUSE_LEN, HOUSE_GROUND, zp + d)),                  # 廊子后面
			AABB(Vector3(-hl, HOUSE_GROUND - 0.5, zp), Vector3(HOUSE_LEN, 0.5, HOUSE_PORCH)),       # 廊顶
			AABB(Vector3(-hl, HOUSE_GROUND, -d), Vector3(HOUSE_LEN, top - HOUSE_GROUND + 0.6, block)),   # 楼上整块，到檐口
		]
		var spring := 2.4 if h["arches"] == 3 else 2.2
		var edges: Array[float] = [-hl]
		for a in _house_arches(h["arches"]):
			edges.append(a.x)
			edges.append(a.y)
			var r := (a.y - a.x) / 2.0
			boxes.append(AABB(Vector3(a.x, spring + r * 0.7, d - 0.5), Vector3(a.y - a.x, HOUSE_GROUND - spring - r * 0.7, 0.5)))
		edges.append(hl)
		for i in range(0, edges.size(), 2):
			if edges[i + 1] - edges[i] > 0.01:
				boxes.append(AABB(Vector3(edges[i], 0, d - 0.5), Vector3(edges[i + 1] - edges[i], spring, 0.5)))
		for sx: float in [-1.0, 1.0]:                                                          # 廊子两头的端墙
			boxes.append(AABB(Vector3(-hl if sx < 0.0 else hl - 0.6, 0, zp), Vector3(0.6, HOUSE_GROUND, HOUSE_PORCH)))
		for b in boxes:
			_add_collider(xf * b.get_center(), b.size, rot)
		# 屋顶：两面坡 + 屋脊一条平的，站得住
		var eave := top + 0.6
		var half_d := d + 0.4
		var slope := Vector2(half_d, HOUSE_ROOF - 0.6)
		var tilt := atan2(slope.y, slope.x)
		for s: float in [-1.0, 1.0]:
			var mid := Vector3(0, eave + slope.y / 2.0 + 0.06, s * half_d / 2.0)
			var roof_rot := rot * Basis(Vector3.RIGHT, s * tilt)
			_add_collider(xf * mid, Vector3(HOUSE_LEN + 0.8, 0.12, slope.length()), roof_rot)
		_add_collider(xf * Vector3(0, top + HOUSE_ROOF + 0.12, 0), Vector3(HOUSE_LEN + 0.8, 0.2, 0.6), rot)


func _place_landmark(name: String, xf: Transform3D) -> void:
	var mesh: Mesh = landmark_meshes[name]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var key := m.resource_name if m else "stone"
		mi.set_surface_override_material(i, landmark_mats.get(key, wall_mat))
	add_child(mi)


## 拱门两面各贴一圈拱石（rot 的 z 是拱门厚度方向）
func _add_voussoirs(rot: Basis, center: Vector3, depth: float) -> void:
	if not trims.has("voussoirs"):
		return
	trims["voussoirs"].append(Transform3D(rot, center + rot.z * depth / 2.0))
	var back := Basis(-rot.x, Vector3.UP, -rot.z)
	trims["voussoirs"].append(Transform3D(back, center - rot.z * depth / 2.0))


func _next_to_room(b: Vector2i) -> bool:
	for room: Dictionary in gen.rooms:
		if (room["rect"] as Rect2i).grow(1).has_point(b):
			return true
	return false


## 实心块（墙、矮墙、观景台柱、步道跨过通道的桥面、小房间门口的厚墙）的顶高；不是实心块返回 -INF
func _solid_top(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= n or z >= n:
		return INF
	var k: int = gen.kind[z][x]
	if k == MazeGen.WALL or k == MazeGen.PARAPET:
		return gen.wall_top[z][x]
	if k == MazeGen.TERRACE:
		return gen.height[z][x]
	if gen.span[z][x]:
		return gen.wall_top[z][x]
	if gen.doorway[z][x]:
		return INF
	return -INF


## 建筑装饰件（tools/blender/trim_kit.py）：
## - 墙顶压檐：凡是墙顶比旁边高出一截的那一面，沿顶边挑出一道线脚；两面都露着的外角补一块角件；
## - 墙脚基座：朝着平地通道的墙面，墙根一道凸出的基座；
## - 转角壁柱：墙角块（偶数行偶数列）朝通道的那一面，从基座顶一直到压檐下面，顶上一个柱头。
## 朝着房间里的墙面一律不加（屋里有自己的内衬），开了拱窗、架着拱门或桥面的那一面不加壁柱
func _build_trim() -> void:
	if trim_meshes.is_empty():
		return
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var room_blocks := {}
	for room: Dictionary in gen.rooms:
		var r: Rect2i = room["rect"]
		for z in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				room_blocks[Vector2i(x, z)] = true
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			var k: int = gen.kind[z][x]
			if k != MazeGen.WALL and k != MazeGen.PARAPET and k != MazeGen.TERRACE or gen.landmark[z][x]:
				continue
			var top := _solid_top(x, z)
			var center := _block_to_world(x, z)
			var cope: Array[bool] = []
			var foot: Array[float] = []   # 这一面墙脚的地面高度；没有基座是 NAN
			for d in dirs:
				var nb := Vector2i(x + d.x, z + d.y)
				var into_room := room_blocks.has(nb)
				cope.append(not into_room and _solid_top(nb.x, nb.y) < top - 0.3)
				var h := NAN
				if not into_room and gen.kind[nb.y][nb.x] == MazeGen.FLOOR and not gen.doorway[nb.y][nb.x] \
						and k != MazeGen.PARAPET and top - gen.height[nb.y][nb.x] > 1.5:
					h = gen.height[nb.y][nb.x]
				foot.append(h)
			for i in 4:
				var d := dirs[i]
				var f := Vector3(d.x, 0, d.y)
				var rot := Basis(Vector3.UP.cross(f), Vector3.UP, f)
				var face := center + f * (block / 2.0)
				if cope[i]:
					trims["coping"].append(Transform3D(rot, face + Vector3(0, top, 0)))
				var h: float = foot[i]
				if not is_nan(h):
					trims["plinth"].append(Transform3D(rot, face + Vector3(0, h, 0)))
					var nb := Vector2i(x + d.x, z + d.y)
					if k == MazeGen.WALL and x % 2 == 0 and z % 2 == 0 and top - h > 5.0 \
							and not window_faces.has(Vector4i(x, z, d.x, d.y)) \
							and not gen.arch[nb.y][nb.x] and not gen.span[nb.y][nb.x]:
						var cap_y := top - 0.48
						var shaft := cap_y - 0.34 - (h + 0.72)
						trims["pilaster"].append(Transform3D(rot.scaled_local(Vector3(1, shaft, 1)), face + Vector3(0, h + 0.72, 0)))
						trims["pilaster_cap"].append(Transform3D(rot, face + Vector3(0, cap_y, 0)))
				# 外角：这一面和下一面（逆时针转 90°）都露着
				var j := (i + 1) % 4
				var d2 := dirs[j]
				var f2 := Vector3(d2.x, 0, d2.y)
				var corner := center + (f + f2) * (block / 2.0)
				# 角件往 +x、+z 两边挑出：x 取 f、z 取 f2，保证右手系（不然面会翻过去）
				var cb := Basis(f, Vector3.UP, f2) if f.cross(Vector3.UP).is_equal_approx(f2) else Basis(f2, Vector3.UP, f)
				if cope[i] and cope[j]:
					trims["coping_corner"].append(Transform3D(cb, corner + Vector3(0, top, 0)))
				if not is_nan(foot[i]) and not is_nan(foot[j]) and is_equal_approx(foot[i], foot[j]):
					trims["plinth_corner"].append(Transform3D(cb, corner + Vector3(0, foot[i], 0)))


func _build_gates() -> void:
	for z in n:
		for x in n:
			if not gen.arch[z][x]:
				continue
			var h: float = gen.height[z][x]
			var center := _block_to_world(x, z) + Vector3(0, h, 0)
			# 门洞朝通道方向；局部 x 横跨走道，局部 z 是拱门厚度（顺着通道）
			var along_x := x % 2 == 0
			var rot := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)) if along_x else Basis.IDENTITY
			gates.append(Transform3D(rot, center))
			if not _in_room(Vector2i(x, z)) and not _next_to_room(Vector2i(x, z)):
				_add_voussoirs(rot, center, GATE_D)
			var pier := block / 2.0 - GATE_R
			for side: float in [-1.0, 1.0]:
				var off := rot.x * side * (block / 2.0 - pier / 2.0)
				_add_collider(center + off + Vector3(0, GATE_SPRING / 2.0, 0), Vector3(pier, GATE_SPRING, GATE_D), rot)
			var across := Vector2i(0, 1) if along_x else Vector2i(1, 0)
			var top := minf(gen.wall_top[z - across.y][x - across.x], gen.wall_top[z + across.y][x + across.x])
			if top > h + GATE_H:
				var fill := top - h - GATE_H
				var size := rot * Vector3(block, fill, GATE_D)
				_add_box(wall_boxes, center + Vector3(0, GATE_H + fill / 2.0, 0), size.abs(), Basis.IDENTITY, false)


## 拱廊墙：下沿以下一段实墙，中间一段并排两个穿透整块墙的拱洞，上面一直补到墙顶。
## 碰撞仍是整块实墙：看得过去，走不过去，也滑翔不过去
func _build_arcades() -> void:
	for z in n:
		for x in n:
			if not gen.arcade[z][x]:
				continue
			# 隔开左右两格的墙（x 为偶数）拱洞沿 x 方向穿过；隔开上下两格的沿 z
			var across_x := x % 2 == 0
			var a := Vector2i(x - 1, z) if across_x else Vector2i(x, z - 1)
			var floor_y: float = gen.height[a.y][a.x]
			var top: float = gen.wall_top[z][x]
			var center := _block_to_world(x, z)
			var sill := floor_y + ARCADE_SILL
			var rot := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)) if across_x else Basis.IDENTITY
			for side: float in [-1.0, 1.0]:
				arcades.append(Transform3D(rot, center + rot.x * side * block / 4.0 + Vector3(0, sill, 0)))
			var below := sill - BOTTOM
			_add_box(wall_boxes, center + Vector3(0, BOTTOM + below / 2.0, 0), Vector3(block, below, block), Basis.IDENTITY, false)
			var above := top - sill - ARCADE_BAND
			_add_box(wall_boxes, center + Vector3(0, top - above / 2.0, 0), Vector3(block, above, block), Basis.IDENTITY, false)
			_add_collider(center + Vector3(0, (BOTTOM + top) / 2.0, 0), Vector3(block, top - BOTTOM, block))


## 盲拱窗：朝着平地的墙面上，按层开一排拱窗；同一面墙要开就每层都开，看起来像一栋楼的立面
func _build_windows() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 2
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			if gen.kind[z][x] != MazeGen.WALL or gen.arcade[z][x] or gen.landmark[z][x]:
				continue
			var top: float = gen.wall_top[z][x]
			for d in dirs:
				var nk: int = gen.kind[z + d.y][x + d.x]
				if nk != MazeGen.FLOOR and nk != MazeGen.TERRACE:
					continue
				if gen.arch[z + d.y][x + d.x] or r.randf() > WINDOW_CHANCE:
					continue
				if _in_room(Vector2i(x + d.x, z + d.y)) or gen.doorway[z + d.y][x + d.x] or gen.span[z + d.y][x + d.x]:
					continue
				var f := Vector3(d.x, 0, d.y)
				var rot := Basis(Vector3.UP.cross(f), Vector3.UP, f)
				var face := _block_to_world(x, z) + f * (block / 2.0)
				var y: float = gen.height[z + d.y][x + d.x] + 1.0
				while y + WINDOW_SPRING + WINDOW_R + 0.6 < top:
					windows.append(Transform3D(rot, face + Vector3(0, y, 0)))
					window_faces[Vector4i(x, z, d.x, d.y)] = true
					y += WINDOW_STOREY


func _in_room(b: Vector2i) -> bool:
	for room: Dictionary in gen.rooms:
		if (room["rect"] as Rect2i).has_point(b):
			return true
	return false


## 房间：这里只盖屋顶、用负密度的雾抵消全局体积雾；屋里（内衬、道具、灯、声音）由 Room 在玩家走近时
## 按房间的种子组合出来，走远了拆掉（_process 里每 0.25 秒看一次距离）
func _build_rooms() -> void:
	for room: Dictionary in gen.rooms:
		var r: Rect2i = room["rect"]
		var base: float = room["base"]
		var h: float = room["height"]
		var inner := Vector3(r.size.x * block, h, r.size.y * block)
		var center := _room_center(room)
		_add_box(wall_boxes, center + Vector3(0, h + 0.3, 0), Vector3(inner.x, 0.6, inner.z))
		var fog := FogVolume.new()
		fog.size = inner
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var fm := FogMaterial.new()
		fm.density = ROOM_FOG_CUT
		fog.material = fm
		add_child(fog)
		fog.global_position = center + Vector3(0, h / 2.0, 0)


## 房间地面正中的世界坐标
func _room_center(room: Dictionary) -> Vector3:
	var r: Rect2i = room["rect"]
	var a := _block_to_world(r.position.x, r.position.y)
	var b := _block_to_world(r.end.x - 1, r.end.y - 1)
	return (a + b) / 2.0 + Vector3(0, room["base"], 0)


func _process(delta: float) -> void:
	room_check -= delta
	if room_check > 0.0 or gen == null:
		return
	room_check = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for i in gen.rooms.size():
		var room: Dictionary = gen.rooms[i]
		var d := eye.distance_to(_room_center(room))
		if d < ROOM_NEAR and not room_nodes.has(i):
			room_nodes[i] = _make_room(i)
		elif d > ROOM_FAR and room_nodes.has(i):
			(room_nodes[i] as Node).queue_free()
			room_nodes.erase(i)


## 搭出第 i 间房的屋里
func _make_room(i: int) -> Node3D:
	var room: Dictionary = gen.rooms[i]
	var r: Rect2i = room["rect"]
	var center := _room_center(room)
	var node: Node3D = Room.new()
	node.name = "Room_%d" % i
	node.size = Vector3(r.size.x * block, room["height"], r.size.y * block)
	node.seed_value = seed_value * 131 + i
	node.visits = room_visits.get(i, 0)
	node.on_shift = func(v: int) -> void: room_visits[i] = v
	node.wall_shader = WallShader
	node.gate_shape = Vector2(DOOR_R, DOOR_SPRING) if room["small"] else Vector2(GATE_R, GATE_SPRING)
	for d: Vector2i in room["doors"]:
		# 门在围墙上：取门洞正中、贴着屋里那一面墙
		var off := _block_to_world(d.x, d.y) + Vector3(0, room["base"], 0) - center
		off = Vector3(signf(off.x) * node.size.x / 2.0 if absf(off.x) > absf(off.z) else off.x, 0,
			signf(off.z) * node.size.z / 2.0 if absf(off.z) > absf(off.x) else off.z)
		node.doors.append(off)
	add_child(node)
	node.global_position = center
	node.build()
	return node


## 小房间的门：整块通道变成一段厚墙，中间开一个窄拱门（穿透 5 米厚的墙，像一条短隧道），上面补到墙顶。
## 碰撞：两侧门墩一直到这段墙顶，上面的补墙另算；拱顶在头顶以上，不用碰撞
func _build_doorways() -> void:
	for z in n:
		for x in n:
			if not gen.doorway[z][x]:
				continue
			var h: float = gen.height[z][x]
			var center := _block_to_world(x, z) + Vector3(0, h, 0)
			var along_x := x % 2 == 0
			var rot := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)) if along_x else Basis.IDENTITY
			doorways.append(Transform3D(rot, center))
			var pier := block / 2.0 - DOOR_R
			for side: float in [-1.0, 1.0]:
				var off := rot.x * side * (block / 2.0 - pier / 2.0)
				_add_collider(center + off + Vector3(0, DOOR_H / 2.0, 0), Vector3(pier, DOOR_H, block), rot)
			var across := Vector2i(0, 1) if along_x else Vector2i(1, 0)
			var top := minf(gen.wall_top[z - across.y][x - across.x], gen.wall_top[z + across.y][x + across.x])
			var fill := top - h - DOOR_H
			if fill > 0.0:
				_add_box(wall_boxes, center + Vector3(0, DOOR_H + fill / 2.0, 0), Vector3(block, fill, block))


## 顶层广场四角的方尖柱，给中心一点仪式感
func _build_plaza_monoliths() -> void:
	var c := n / 2
	var base: float = gen.height[c][c]
	for off: Vector2i in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
		var p := _block_to_world(c + off.x, c + off.y)
		var h := 30.0
		_add_box(wall_boxes, p + Vector3(0, base + h / 2.0, 0), Vector3(2.0, h, 2.0))


## 围墙外的装饰迷宫：走不到、没有碰撞、不投影，只是让迷宫看起来一直延伸到地平线。
## 网格规则同主迷宫：偶数行偶数列是墙角，奇数行奇数列是空地，其余随机立墙。
func _build_outer_field() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value + 1
	var inner := n * block / 2.0 + block
	var count := int(FIELD_RADIUS / block)
	for zi in range(-count, count + 1):
		var row: Array[bool] = []
		for xi in range(-count, count + 1):
			var inside := absf(xi * block) < inner and absf(zi * block) < inner
			var corner := xi % 2 == 0 and zi % 2 == 0
			var between := (xi + zi) % 2 != 0
			row.append(not inside and (corner or (between and r.randf() < 0.55)))
		var i := 0
		while i < row.size():
			if not row[i]:
				i += 1
				continue
			var start := i
			while i < row.size() and row[i]:
				i += 1
			var h := r.randf_range(6.0, 26.0)
			var x0 := (start - count) * block
			var x1 := (i - 1 - count) * block
			var center := Vector3((x0 + x1) / 2.0, (BOTTOM + h) / 2.0, zi * block)
			field_boxes.append(Transform3D(Basis.from_scale(Vector3(x1 - x0 + block, h - BOTTOM, block)), center))
	# 装饰迷宫的地面：围着主迷宫的四块，不能伸到主迷宫底下（深渊区会露出来）
	var w := FIELD_RADIUS - inner
	var mid := (FIELD_RADIUS + inner) / 2.0
	var full := FIELD_RADIUS * 2.0
	for t: Array in [[Vector3(0, 0, mid), Vector3(full, 1, w)], [Vector3(0, 0, -mid), Vector3(full, 1, w)],
			[Vector3(mid, 0, 0), Vector3(w, 1, inner * 2.0)], [Vector3(-mid, 0, 0), Vector3(w, 1, inner * 2.0)]]:
		field_boxes.append(Transform3D(Basis.from_scale(t[1]), t[0] + Vector3(0, -0.5, 0)))


## 带自身材质的网格（拱门、拱窗）成批摆放
func _commit_mesh(list: Array[Transform3D], mesh: Mesh) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _commit(list: Array[Transform3D], mat: Material, shadows := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
