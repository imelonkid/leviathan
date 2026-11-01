extends Node3D
## 把 maze_gen.gd 生成的网格数据搭成场景：墙、地面、楼梯、平台、窄桥。
## 所有方块按材质合进两个 MultiMesh（各一次绘制），碰撞是一个静态体下挂多个盒子。

const MazeGen = preload("res://scripts/maze_gen.gd")

const BOTTOM := -60.0            # 墙和地面柱一直延伸到这里，深渊底下是雾
const KILL_Y := -25.0            # 掉到这个高度以下就重生
const STEPS := 6                 # 每段楼梯的台阶数
const PLANK_W := 1.4             # 窄桥宽度
const PLANK_T := 0.4
const PLATFORM_W := 3.4

@export var cells := 17          # 每边的格子数
@export var block := 5.0         # 一个网格块的边长（米），走道和墙同宽
@export var seed_value := 666

var gen: RefCounted              # MazeGen：网格数据，小地图也读它
var n := 0
var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var wall_boxes: Array[Transform3D] = []
var floor_boxes: Array[Transform3D] = []
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

	body = StaticBody3D.new()
	add_child(body)
	_build_walls()
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
	_commit(wall_boxes, wall_mat)
	_commit(floor_boxes, floor_mat)


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


## 按行合并：同样高度的连续墙（含矮墙）合成一段
func _build_walls() -> void:
	for z in n:
		var x := 0
		while x < n:
			var k: int = gen.kind[z][x]
			if k != MazeGen.WALL and k != MazeGen.PARAPET:
				x += 1
				continue
			var start := x
			var top: float = gen.wall_top[z][x]
			while x < n and (gen.kind[z][x] == MazeGen.WALL or gen.kind[z][x] == MazeGen.PARAPET) \
					and is_equal_approx(gen.wall_top[z][x], top):
				x += 1
			_add_column(wall_boxes, start, x - 1, z, top)


## 按行合并：同一层的连续平地合成一根实心柱
func _build_floors() -> void:
	for z in n:
		var x := 0
		while x < n:
			if gen.kind[z][x] != MazeGen.FLOOR:
				x += 1
				continue
			var start := x
			var lv: int = gen.level[z][x]
			while x < n and gen.kind[z][x] == MazeGen.FLOOR and gen.level[z][x] == lv:
				x += 1
			_add_column(floor_boxes, start, x - 1, z, lv * MazeGen.LEVEL_H)


## 楼梯：低端的实心柱 + 台阶（只是外观）+ 一块斜坡碰撞（走起来顺）
func _build_stair(x: int, z: int) -> void:
	var base: float = gen.level[z][x] * MazeGen.LEVEL_H
	var rise := MazeGen.LEVEL_H
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
	var lo: int = gen.level[z - dir.y][x - dir.x]
	var hi: int = gen.level[z + dir.y][x + dir.x]
	var rise := (hi - lo) * MazeGen.LEVEL_H
	var run := block * 2.0
	var rot := _slope_basis(dir, rise, run)
	var center := _block_to_world(x, z) + Vector3(0, lo * MazeGen.LEVEL_H + rise / 2.0, 0) \
		- rot.y * (PLANK_T / 2.0)
	_add_box(floor_boxes, center, Vector3(PLANK_W, PLANK_T, sqrt(run * run + rise * rise)), rot)


## 悬空平台：一块石板立在细柱上；朝区外开口的方向补一段短桥接上通道
func _build_platform(x: int, z: int) -> void:
	var top: float = gen.level[z][x] * MazeGen.LEVEL_H
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


## 广场四角的方尖柱，给中心一点仪式感
func _build_plaza_monoliths() -> void:
	var c := n / 2
	for off: Vector2i in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
		var p := _block_to_world(c + off.x, c + off.y)
		var h := 55.0
		_add_box(wall_boxes, p + Vector3(0, h / 2.0, 0), Vector3(2.0, h, 2.0))


func _commit(list: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
