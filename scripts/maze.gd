extends Node3D
## 把 maze_gen.gd 生成的网格数据搭成场景：墙、观景台、地面、楼梯、平台、窄桥、拱门、拱窗，
## 再在围墙外铺一圈走不到的迷宫，一直延伸进雾里。
## 同一种几何合进一个 MultiMesh（各一次绘制），碰撞是一个静态体下挂多个盒子。

const MazeGen = preload("res://scripts/maze_gen.gd")
const ArchMesh = preload("res://scripts/arch_mesh.gd")
const WallShader = preload("res://scripts/wall.gdshader")
const ROOM_SCRIPTS := {
	"ward": preload("res://scripts/rooms/ward.gd"),
	"shrine": preload("res://scripts/rooms/shrine.gd"),
	"clocks": preload("res://scripts/rooms/clocks.gd"),
}
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
var hole_mat: StandardMaterial3D
var gate_mesh: ArrayMesh
var window_mesh: ArrayMesh
var arcade_mesh: ArrayMesh
var wall_boxes: Array[Transform3D] = []
var floor_boxes: Array[Transform3D] = []
var field_boxes: Array[Transform3D] = []
var gates: Array[Transform3D] = []
var windows: Array[Transform3D] = []
var arcades: Array[Transform3D] = []
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

	body = StaticBody3D.new()
	add_child(body)
	_build_walls()
	_build_band_rails()
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
	_build_arcades()
	_build_windows()
	_build_plaza_monoliths()
	_build_rooms()
	_build_outer_field()
	_commit(wall_boxes, wall_mat)
	_commit(floor_boxes, floor_mat)
	_commit(field_boxes, wall_mat, false)
	_commit_mesh(gates, gate_mesh)
	_commit_mesh(arcades, arcade_mesh)
	_commit_mesh(windows, window_mesh)


## 出生点：最外一圈观景台上（离中心约 100 米），远远望得见利维坦，要穿过两层迷宫才走到它下面
func get_spawn_position() -> Vector3:
	var b: Vector2i = gen.spawn
	return _block_to_world(b.x, b.y) + Vector3(0, gen.floor_height(b.x, b.y) + 0.2, 0)


func _block_to_world(x: int, z: int) -> Vector3:
	var half := n / 2.0
	return Vector3((x - half + 0.5) * block, 0.0, (z - half + 0.5) * block)


## 世界坐标 → 网格块坐标（小地图用），不做越界裁剪
func world_to_block(p: Vector3) -> Vector2:
	var half := n / 2.0
	return Vector2(p.x / block + half, p.z / block + half)


func _make_materials() -> void:
	# 墙和地面用同一个着色器：竖直面是旧灰泥 / 土坯，朝上的面是踩实的土地
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = WallShader
	floor_mat = wall_mat

	hole_mat = StandardMaterial3D.new()
	hole_mat.albedo_color = Color(0.015, 0.016, 0.018)
	hole_mat.roughness = 1.0

	gate_mesh = ArchMesh.gate(block / 2.0, GATE_H, GATE_D, GATE_R, GATE_SPRING)
	gate_mesh.surface_set_material(0, wall_mat)
	# 拱廊墙每块墙开两个拱洞，每个拱洞是半块宽的一扇“拱门”，厚度就是整块墙
	arcade_mesh = ArchMesh.gate(block / 4.0, ARCADE_BAND, block, ARCADE_R, ARCADE_SPRING)
	arcade_mesh.surface_set_material(0, wall_mat)
	window_mesh = ArchMesh.window(WINDOW_R, WINDOW_SPRING, 0.28, 0.18)
	window_mesh.surface_set_material(0, wall_mat)
	window_mesh.surface_set_material(1, hole_mat)


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


## 按行合并：同样高度的连续墙（含矮墙）合成一段；拱廊墙另外搭
func _build_walls() -> void:
	for z in n:
		var x := 0
		while x < n:
			if not _is_solid(x, z) or gen.arcade[z][x]:
				x += 1
				continue
			var start := x
			var top: float = gen.wall_top[z][x]
			while x < n and _is_solid(x, z) and not gen.arcade[z][x] and is_equal_approx(gen.wall_top[z][x], top):
				x += 1
			_add_column(wall_boxes, start, x - 1, z, top)


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
				_add_box(wall_boxes, edge + Vector3(0, top + RAIL_H / 2.0, 0), size + Vector3(0, RAIL_H, 0), Basis.IDENTITY, false)
				_add_collider(edge + Vector3(0, top + RAIL_BLOCK_H / 2.0, 0), size + Vector3(0, RAIL_BLOCK_H, 0))


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
			if gen.kind[z][x] != MazeGen.WALL or gen.arcade[z][x]:
				continue
			var top: float = gen.wall_top[z][x]
			for d in dirs:
				var nk: int = gen.kind[z + d.y][x + d.x]
				if nk != MazeGen.FLOOR and nk != MazeGen.TERRACE:
					continue
				if gen.arch[z + d.y][x + d.x] or r.randf() > WINDOW_CHANCE:
					continue
				if _in_room(Vector2i(x + d.x, z + d.y)):
					continue
				var f := Vector3(d.x, 0, d.y)
				var rot := Basis(Vector3.UP.cross(f), Vector3.UP, f)
				var face := _block_to_world(x, z) + f * (block / 2.0)
				var y: float = gen.height[z + d.y][x + d.x] + 1.0
				while y + WINDOW_SPRING + WINDOW_R + 0.6 < top:
					windows.append(Transform3D(rot, face + Vector3(0, y, 0)))
					y += WINDOW_STOREY


func _in_room(b: Vector2i) -> bool:
	for room: Dictionary in gen.rooms:
		if (room["rect"] as Rect2i).has_point(b):
			return true
	return false


## 房间：盖屋顶，再用负密度的雾抵消全局体积雾。
## 屋里的内衬（不吃环境光的墙面、地面、天花板）和东西交给 scripts/rooms/ 下对应主题的脚本
func _build_rooms() -> void:
	for i in gen.rooms.size():
		var room: Dictionary = gen.rooms[i]
		var r: Rect2i = room["rect"]
		var base: float = room["base"]
		var center := _block_to_world(r.position.x + 1, r.position.y + 1)
		var inner := Vector3(r.size.x * block, MazeGen.ROOM_H, r.size.y * block)
		_add_box(wall_boxes, center + Vector3(0, base + MazeGen.ROOM_H + 0.3, 0), Vector3(inner.x, 0.6, inner.z))

		var mid := center + Vector3(0, base + inner.y / 2.0, 0)

		var fog := FogVolume.new()
		fog.size = inner
		fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		var fm := FogMaterial.new()
		fm.density = ROOM_FOG_CUT
		fog.material = fm
		add_child(fog)
		fog.global_position = mid

		var node: Node3D = ROOM_SCRIPTS[room["theme"]].new()
		node.name = "Room_" + String(room["theme"])
		node.size = inner
		node.seed_value = seed_value * 31 + i
		node.wall_shader = WallShader
		node.gate_shape = Vector3(GATE_R, GATE_SPRING, GATE_H)
		for d: Vector2i in room["doors"]:
			# 门在围墙上：取门洞正中、贴着屋里那一面墙
			var off := _block_to_world(d.x, d.y) - center
			off = Vector3(signf(off.x) * inner.x / 2.0 if absf(off.x) > absf(off.z) else off.x, 0,
				signf(off.z) * inner.z / 2.0 if absf(off.z) > absf(off.x) else off.z)
			node.doors.append(off)
		add_child(node)
		node.global_position = center + Vector3(0, base, 0)
		node.build()


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
