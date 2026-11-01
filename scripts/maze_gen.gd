extends RefCounted
## 迷宫数据生成：只产出网格数据（每块的类型、地面层、方向、墙高），不创建任何节点。
## 节点构建在 maze.gd；这一层与引擎无关，将来迁移时可以照搬。
##
## 网格由 cells × cells 个“格子”展开成 n × n 个“块”（n = cells * 2 + 1）：
## 奇数行奇数列是格子，格子之间夹着的块是通道或墙，偶数行偶数列永远是墙角。
##
## 空间结构：
## - 每个格子有一个地面层（0 层是中心广场），相邻格子最多差一层，差一层的通道变成楼梯；
## - 广场是最低处，越往外越高，走向利维坦就是一路下行；
## - 若干“深渊区”去掉墙和地面，格子变成悬空平台，通道变成窄桥；
## - 部分隔墙降成矮墙，能看见隔壁走道却过不去。

enum { WALL, FLOOR, STAIR, BRIDGE, PLATFORM, VOID, PARAPET }

const LEVEL_H := 3.0              # 一层的高度（米）
const MAX_LEVEL := 4
const TERRAIN_FREQ := 0.07        # 地形起伏的频率：越大楼梯越密
const PARAPET_H := 1.4            # 矮墙高出较高一侧地面的高度，跳不过去
const CHASM_COUNT := 2

var cells := 17
var n := 0
var kind: Array = []              # kind[z][x]：上面的枚举
var level: Array = []             # level[z][x]：开放块的地面层；楼梯和斜桥记低端
var link: Array = []              # link[z][x]：楼梯 / 桥的走向（Vector2i），有高差时指向上坡
var wall_top: Array = []          # wall_top[z][x]：墙和矮墙顶部的绝对高度（米）
var chasms: Array[Rect2i] = []    # 深渊区，以格子为单位
var rng := RandomNumberGenerator.new()

var _cell_level: Array = []       # _cell_level[cz][cx]


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	n = cells * 2 + 1
	kind = _grid(WALL)
	level = _grid(0)
	link = _grid(Vector2i.ZERO)
	wall_top = _grid(0.0)
	chasms.clear()

	_carve_tree()
	_add_loops()
	_carve_plaza()
	_assign_levels()
	_classify_links()
	_make_chasms()
	_make_parapets()
	_assign_wall_heights()


func is_open(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < n and z < n and kind[z][x] != WALL \
		and kind[z][x] != VOID and kind[z][x] != PARAPET


func in_plaza(x: int, z: int) -> bool:
	var c := n / 2
	return absi(x - c) <= 4 and absi(z - c) <= 4


## 块的地面高度（米）；楼梯取中点
func floor_height(x: int, z: int) -> float:
	var h: float = level[z][x] * LEVEL_H
	if kind[z][x] == STAIR:
		h += LEVEL_H / 2.0
	return h


func _grid(value: Variant) -> Array:
	var g := []
	for z in n:
		var row := []
		row.resize(n)
		row.fill(value)
		g.append(row)
	return g


func _cell_block(c: Vector2i) -> Vector2i:
	return Vector2i(c.x * 2 + 1, c.y * 2 + 1)


## 递归回溯生成树：保证所有格子连通
func _carve_tree() -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start := Vector2i(0, 0)
	var stack: Array[Vector2i] = [start]
	var visited := {start: true}
	var b := _cell_block(start)
	kind[b.y][b.x] = FLOOR

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
		var cb := _cell_block(cur)
		kind[cb.y + step.y][cb.x + step.x] = FLOOR
		var nbk := _cell_block(nxt)
		kind[nbk.y][nbk.x] = FLOOR
		visited[nxt] = true
		stack.append(nxt)


## 打通少量墙，制造回路，让人更容易迷失
func _add_loops() -> void:
	var count := int(cells * cells / 6.0)
	for i in count:
		var x := rng.randi_range(1, n - 2)
		var z := rng.randi_range(1, n - 2)
		if kind[z][x] == WALL and ((x % 2 == 0) != (z % 2 == 0)):
			kind[z][x] = FLOOR


func _carve_plaza() -> void:
	for z in n:
		for x in n:
			if in_plaza(x, z):
				kind[z][x] = FLOOR


## 噪声给出起伏，再把广场钉在 0 层，并压平到“相邻格子最多差一层”
func _assign_levels() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = TERRAIN_FREQ
	_cell_level = []
	for cz in cells:
		var row := []
		for cx in cells:
			var v := (noise.get_noise_2d(cx, cz) + 1.0) / 2.0
			row.append(clampi(int(v * (MAX_LEVEL + 1)), 1, MAX_LEVEL))
		_cell_level.append(row)
	for cz in cells:
		for cx in cells:
			var b := _cell_block(Vector2i(cx, cz))
			if in_plaza(b.x, b.y):
				_cell_level[cz][cx] = 0

	# 反复放松直到稳定：任何格子都不比邻居高出一层以上
	var changed := true
	while changed:
		changed = false
		for cz in cells:
			for cx in cells:
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := cx + d.x
					var nz := cz + d.y
					if nx < 0 or nz < 0 or nx >= cells or nz >= cells:
						continue
					if _cell_level[cz][cx] > _cell_level[nz][nx] + 1:
						_cell_level[cz][cx] = _cell_level[nz][nx] + 1
						changed = true

	for cz in cells:
		for cx in cells:
			var b := _cell_block(Vector2i(cx, cz))
			level[b.y][b.x] = _cell_level[cz][cx]


## 通道：两端同层是平地，差一层是楼梯（level 记低端，link 指向上坡）
func _classify_links() -> void:
	for z in n:
		for x in n:
			if kind[z][x] != FLOOR or in_plaza(x, z):
				continue
			var horizontal := x % 2 == 0 and z % 2 == 1
			var vertical := x % 2 == 1 and z % 2 == 0
			if not (horizontal or vertical):
				continue
			var axis := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
			var la: int = level[z - axis.y][x - axis.x]
			var lb: int = level[z + axis.y][x + axis.x]
			level[z][x] = mini(la, lb)
			link[z][x] = axis if lb >= la else -axis
			if la != lb:
				kind[z][x] = STAIR


## 深渊区：区内的墙和墙角消失，格子变平台，通道变桥；区边上的墙保留
func _make_chasms() -> void:
	var c := cells / 2
	var forbidden: Array[Rect2i] = [
		Rect2i(c - 3, c - 3, 7, 7),   # 广场及一圈缓冲
		Rect2i(0, 0, 3, 3),           # 出生点附近
	]
	for attempt in 60:
		if chasms.size() >= CHASM_COUNT:
			break
		var size := Vector2i(4, 3) if rng.randf() < 0.5 else Vector2i(3, 4)
		var pos := Vector2i(rng.randi_range(1, cells - size.x - 1), rng.randi_range(1, cells - size.y - 1))
		var r := Rect2i(pos, size)
		var ok := true
		for f in forbidden:
			if r.grow(1).intersects(f):
				ok = false
				break
		for other in chasms:
			if r.grow(2).intersects(other):
				ok = false
				break
		if ok:
			chasms.append(r)

	for r in chasms:
		for z in range(r.position.y * 2 + 1, r.end.y * 2):
			for x in range(r.position.x * 2 + 1, r.end.x * 2):
				if x % 2 == 1 and z % 2 == 1:
					kind[z][x] = PLATFORM
				elif kind[z][x] == FLOOR or kind[z][x] == STAIR:
					kind[z][x] = BRIDGE
				else:
					kind[z][x] = VOID


## 隔墙降成矮墙：两侧有高差时更常见，制造“看得见到不了”
func _make_parapets() -> void:
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			if kind[z][x] != WALL or (x % 2 == 0) == (z % 2 == 0):
				continue
			var axis := Vector2i(1, 0) if x % 2 == 0 else Vector2i(0, 1)
			var ax := x - axis.x
			var az := z - axis.y
			var bx := x + axis.x
			var bz := z + axis.y
			if kind[az][ax] != FLOOR or kind[bz][bx] != FLOOR:
				continue
			var la: int = level[az][ax]
			var lb: int = level[bz][bx]
			var chance := 0.35 if la != lb else 0.1
			if rng.randf() < chance:
				kind[z][x] = PARAPET
				wall_top[z][x] = maxi(la, lb) * LEVEL_H + PARAPET_H


## 按行合并连续的墙，每段一个随机高度，从周围最高的地面算起；外圈最高
func _assign_wall_heights() -> void:
	for z in n:
		var x := 0
		while x < n:
			if kind[z][x] != WALL:
				x += 1
				continue
			var start := x
			var base := 0
			while x < n and kind[z][x] == WALL:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var nz := z + dz
						if nx >= 0 and nz >= 0 and nx < n and nz < n and kind[nz][nx] != WALL:
							base = maxi(base, level[nz][nx] + (1 if kind[nz][nx] == STAIR else 0))
				x += 1
			var border := z == 0 or z == n - 1 or start == 0 or x == n
			var h := 70.0 if border else rng.randf_range(18.0, 42.0)
			for i in range(start, x):
				wall_top[z][i] = base * LEVEL_H + h
