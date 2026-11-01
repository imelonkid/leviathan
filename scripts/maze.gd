extends Node3D
## 把 maze_gen.gd 生成的网格数据搭成场景：墙、挡土墙、地面、楼梯、平台、窄桥，
## 再在围墙外铺一圈走不到的迷宫，一直延伸进雾里。
## 所有方块按材质合进几个 MultiMesh（各一次绘制），碰撞是一个静态体下挂多个盒子。

const MazeGen = preload("res://scripts/maze_gen.gd")

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

@export var cells := 25          # 每边的格子数
@export var block := 5.0         # 一个网格块的边长（米），走道和墙同宽
@export var seed_value := 666

var gen: RefCounted              # MazeGen：网格数据，小地图也读它
var n := 0
var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var wall_boxes: Array[Transform3D] = []
var floor_boxes: Array[Transform3D] = []
var field_boxes: Array[Transform3D] = []
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
	_build_plaza_monoliths()
	_build_outer_field()
	_commit(wall_boxes, wall_mat)
	_commit(floor_boxes, floor_mat)
	_commit(field_boxes, wall_mat, false)


## 出生点：左下角第一个格子
func get_spawn_position() -> Vector3:
	return _block_to_world(1, 1) + Vector3(0, gen.floor_height(1, 1) + 0.2, 0)


func _block_to_world(x: int, z: int) -> Vector3:
	var half := n / 2.0
	return Vector3((x - half + 0.5) * block, 0.0, (z - half + 0.5) * block)


## 世界坐标 → 网格块坐标（小地图用），不做越界裁剪
func world_to_block(p: Vector3) -> Vector2:
	var half := n / 2.0
	return Vector2(p.x / block + half, p.z / block + half)


func _make_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	noise.fractal_octaves = 3

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.07, 0.075, 0.08))
	ramp.set_color(1, Color(0.3, 0.31, 0.32))

	var albedo := NoiseTexture2D.new()
	albedo.width = 512
	albedo.height = 512
	albedo.seamless = true
	albedo.noise = noise
	albedo.color_ramp = ramp

	var normal := NoiseTexture2D.new()
	normal.width = 512
	normal.height = 512
	normal.seamless = true
	normal.as_normal_map = true
	normal.bump_strength = 8.0
	normal.noise = noise

	wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_texture = albedo
	wall_mat.normal_enabled = true
	wall_mat.normal_texture = normal
	wall_mat.roughness = 0.92
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_world_triplanar = true   # 方块是缩放过的实例，按世界坐标贴图才不会拉伸
	wall_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)

	floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_texture = albedo
	floor_mat.albedo_color = Color(0.6, 0.62, 0.65)
	floor_mat.normal_enabled = true
	floor_mat.normal_texture = normal
	floor_mat.roughness = 0.55   # 略带潮湿反光
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)


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


## 按行合并：同样高度的连续墙（含矮墙）合成一段
func _build_walls() -> void:
	for z in n:
		var x := 0
		while x < n:
			if not _is_solid(x, z):
				x += 1
				continue
			var start := x
			var top: float = gen.wall_top[z][x]
			while x < n and _is_solid(x, z) and is_equal_approx(gen.wall_top[z][x], top):
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
