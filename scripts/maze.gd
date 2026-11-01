extends Node3D
## 程序化迷宫：递归回溯生成 + 少量回路，中心留出一片广场，正对利维坦。
## 所有墙块合进一个 MultiMesh（一次绘制），碰撞是一个静态体下挂多个盒子。

@export var cells := 17          # 每边的格子数
@export var block := 5.0         # 一个网格块的边长（米），走道和墙同宽
@export var seed_value := 666

var n := 0                       # 网格块数 = cells * 2 + 1
var grid: Array = []             # grid[z][x] == true 表示墙
var rng := RandomNumberGenerator.new()
var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var boxes: Array = []            # 本次生成的墙块 [[中心, 尺寸], ...]
var body: StaticBody3D


## 可重复调用：换了 seed_value 再调一次就是新迷宫
func build() -> void:
	for child in get_children():
		child.queue_free()
	if wall_mat == null:
		_make_materials()

	rng.seed = seed_value
	n = cells * 2 + 1
	boxes.clear()
	_generate()
	_add_loops()
	_carve_plaza()

	body = StaticBody3D.new()
	add_child(body)
	_build_floor()
	_build_walls()
	_build_plaza_monoliths()
	_commit_boxes()


## 出生点：左下角第一个格子
func get_spawn_position() -> Vector3:
	return _block_to_world(1, 1) + Vector3(0, 0.2, 0)


func _block_to_world(x: int, z: int) -> Vector3:
	var half := n / 2.0
	return Vector3((x - half + 0.5) * block, 0.0, (z - half + 0.5) * block)


## 世界坐标 → 网格块坐标（小地图用），不做越界裁剪
func world_to_block(p: Vector3) -> Vector2:
	var half := n / 2.0
	return Vector2(p.x / block + half, p.z / block + half)


func _open_cell(c: Vector2i) -> void:
	grid[c.y * 2 + 1][c.x * 2 + 1] = false


func _generate() -> void:
	grid = []
	for z in n:
		var row := []
		row.resize(n)
		row.fill(true)
		grid.append(row)

	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start := Vector2i(0, 0)
	var stack: Array[Vector2i] = [start]
	var visited := {start: true}
	_open_cell(start)

	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir: Vector2i in dirs:
			var nb := cur + dir
			if nb.x >= 0 and nb.y >= 0 and nb.x < cells and nb.y < cells and not visited.has(nb):
				options.append(dir)
		if options.is_empty():
			stack.pop_back()
			continue
		var step: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		var nxt := cur + step
		grid[cur.y * 2 + 1 + step.y][cur.x * 2 + 1 + step.x] = false
		_open_cell(nxt)
		visited[nxt] = true
		stack.append(nxt)


## 打通少量墙，制造回路，让人更容易迷失
func _add_loops() -> void:
	var count := int(cells * cells / 6.0)
	for i in count:
		var x := rng.randi_range(1, n - 2)
		var z := rng.randi_range(1, n - 2)
		if grid[z][x] and ((x % 2 == 0) != (z % 2 == 0)):
			grid[z][x] = false


func _carve_plaza() -> void:
	var c := n / 2
	for z in range(c - 4, c + 5):
		for x in range(c - 4, c + 5):
			grid[z][x] = false


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
	wall_mat.uv1_world_triplanar = true   # 墙块是缩放过的实例，按世界坐标贴图才不会拉伸
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


func _add_box(center: Vector3, size: Vector3) -> void:
	boxes.append([center, size])
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


## 把收集到的墙块一次性写进 MultiMesh：单位立方体按尺寸缩放
func _commit_boxes() -> void:
	var cube := BoxMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cube
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var center: Vector3 = boxes[i][0]
		var size: Vector3 = boxes[i][1]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(size), center))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = wall_mat
	add_child(mmi)


func _build_floor() -> void:
	var size := Vector3(n * block, 1.0, n * block)
	var center := Vector3(0, -0.5, 0)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = floor_mat
	mi.position = center
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = center
	body.add_child(cs)


## 按行合并连续的墙块，减少实例和碰撞体数量；每段墙高度随机，外圈最高
func _build_walls() -> void:
	for z in n:
		var x := 0
		while x < n:
			if not grid[z][x]:
				x += 1
				continue
			var start := x
			while x < n and grid[z][x]:
				x += 1
			var length := x - start
			var border := z == 0 or z == n - 1 or start == 0 or x == n
			var h := 70.0 if border else rng.randf_range(18.0, 42.0)
			var a := _block_to_world(start, z)
			var b := _block_to_world(x - 1, z)
			var center := (a + b) / 2.0 + Vector3(0, h / 2.0, 0)
			_add_box(center, Vector3(length * block, h, block))


## 广场四角的方尖柱，给中心一点仪式感
func _build_plaza_monoliths() -> void:
	var c := n / 2
	for off: Vector2i in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
		var p := _block_to_world(c + off.x, c + off.y)
		var h := 55.0
		_add_box(p + Vector3(0, h / 2.0, 0), Vector3(2.0, h, 2.0))
