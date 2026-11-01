extends RefCounted
## 迷宫数据生成：只产出网格数据（每块的类型、地面高度、方向、墙高），不创建任何节点。
## 节点构建在 maze.gd；这一层与引擎无关，将来迁移时可以照搬。
##
## 网格由 cells × cells 个“格子”展开成 n × n 个“块”（n = cells * 2 + 1）：
## 奇数行奇数列是格子，格子之间夹着的块是通道或墙，偶数行偶数列永远是墙角。
##
## 空间结构是一座阶梯状的金字塔，从外到内一层比一层高：
##   第 0 层（外环，出生点）→ 第 1 层 → 第 2 层 → 顶层广场（正上方是利维坦）
## - 每一层是一圈独立的迷宫，墙比层高矮，站在高层能越过护墙俯瞰下面各层；
## - 层与层之间是一道 12 米高的挡土墙，墙顶是高层边缘的观景台（沿崖边一圈，有栏杆），
##   高层迷宫的外墙上开了几道门通向观景台，站在栏杆边能看见下面各层；
## - 每道挡土墙只开两段大楼梯，从低层最里一排爬进高层迷宫，与下一道的楼梯错开 90°；
## - 部分层里有深渊区：格子变成悬空平台，通道变成窄桥；
## - 部分隔墙降成矮墙，能看见隔壁走道却过不去；
## - 部分通道上方架着拱门（通向观景台的门一律是拱门）。

enum { WALL, FLOOR, STAIR, BRIDGE, PLATFORM, VOID, PARAPET, TERRACE }

const BANDS: Array[int] = [2, 6, 10]   # 挡土墙所在的格子环（到中心的格子距离），由内到外
const TOP_TIER := 3                    # 顶层广场的层号
const TIER_H := 12.0                   # 层高（米）
const STAIR_BLOCKS := 3                # 一段大楼梯占几块：通道 + 挡土墙 + 通道
const STAIR_RISE := TIER_H / STAIR_BLOCKS
const STAIRS_PER_BAND := 2
const GATES_PER_BAND := 3              # 高层迷宫通向观景台的门
const WALL_MIN := 8.0                  # 层内墙高（米，高出本层地面），要比层高矮
const WALL_MAX := 11.0
const OUTER_WALL_H := 18.0             # 最外圈围墙
const PARAPET_H := 1.4                 # 矮墙高出地面的高度，跳不过去（跳跃高度约 1.28 米）
const CHASM_COUNT := 2
const ARCH_CHANCE := 0.3               # 普通通道架拱门的概率

var cells := 25
var n := 0
var kind: Array = []              # kind[z][x]：上面的枚举
var height: Array = []            # height[z][x]：开放块的地面高度（米）；楼梯记低端
var link: Array = []              # link[z][x]：楼梯 / 桥的走向（Vector2i），楼梯指向上坡
var wall_top: Array = []          # wall_top[z][x]：墙、矮墙顶部的绝对高度（米）
var arch: Array = []              # arch[z][x]：这条通道上方有拱门
var chasms: Array[Rect2i] = []    # 深渊区，以格子为单位
var stairs: Array[Vector2i] = []  # 每段大楼梯最低一块的位置，调试和测试用
var rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	n = cells * 2 + 1
	kind = _grid(WALL)
	height = _grid(0.0)
	link = _grid(Vector2i.ZERO)
	wall_top = _grid(0.0)
	arch = _grid(false)
	chasms.clear()
	stairs.clear()

	for t in TOP_TIER:
		_carve_ring(t)
	_add_loops()
	_carve_summit()
	_assign_heights()
	_make_bands()
	_make_stairs()
	_make_chasms()
	_make_parapets()
	_assign_wall_heights()
	_make_arches()


## 格子到中心的距离（切比雪夫距离，按格子计）
func cell_dist(cx: int, cz: int) -> int:
	var c := cells / 2
	return maxi(absi(cx - c), absi(cz - c))


## 块到中心的距离（按块计）；格子 d 对应块 2d
func block_dist(x: int, z: int) -> int:
	var c := n / 2
	return maxi(absi(x - c), absi(z - c))


## 格子属于哪一层；落在挡土墙环上返回 -1
func tier_of(d: int) -> int:
	if d in BANDS:
		return -1
	var t := 0
	for b in BANDS:
		if b > d:
			t += 1
	return t


## 地面类（不含观景台）的块：用来决定旁边的墙从多高算起
func _is_ground(x: int, z: int) -> bool:
	return is_open(x, z) and kind[z][x] != TERRACE


func is_open(x: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= n or z >= n:
		return false
	var k: int = kind[z][x]
	return k == FLOOR or k == STAIR or k == BRIDGE or k == PLATFORM or k == TERRACE


## 块的地面高度（米）；楼梯取中点
func floor_height(x: int, z: int) -> float:
	var h: float = height[z][x]
	if kind[z][x] == STAIR:
		h += STAIR_RISE / 2.0
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


func _cell_tier(c: Vector2i) -> int:
	return tier_of(cell_dist(c.x, c.y))


## 递归回溯生成树，只在同一层的格子里走：保证这一层连通
func _carve_ring(t: int) -> void:
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start := Vector2i(-1, -1)
	for cz in cells:
		for cx in cells:
			if start.x < 0 and _cell_tier(Vector2i(cx, cz)) == t:
				start = Vector2i(cx, cz)
	var stack: Array[Vector2i] = [start]
	var visited := {start: true}
	var b := _cell_block(start)
	kind[b.y][b.x] = FLOOR

	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for dir: Vector2i in dirs:
			var nb := cur + dir
			if nb.x >= 0 and nb.y >= 0 and nb.x < cells and nb.y < cells \
					and not visited.has(nb) and _cell_tier(nb) == t:
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


## 打通少量同层的墙，制造回路，让人更容易迷失
func _add_loops() -> void:
	var count := int(cells * cells / 8.0)
	for i in count:
		var x := rng.randi_range(1, n - 2)
		var z := rng.randi_range(1, n - 2)
		if kind[z][x] != WALL or (x % 2 == 0) == (z % 2 == 0):
			continue
		var axis := Vector2i(1, 0) if x % 2 == 0 else Vector2i(0, 1)
		var a := Vector2i((x - axis.x - 1) / 2, (z - axis.y - 1) / 2)
		var b := Vector2i((x + axis.x - 1) / 2, (z + axis.y - 1) / 2)
		var ta := _cell_tier(a)
		if ta >= 0 and ta == _cell_tier(b):
			kind[z][x] = FLOOR


## 顶层广场：挡土墙以内全部打通
func _carve_summit() -> void:
	for z in n:
		for x in n:
			if block_dist(x, z) < BANDS[0] * 2:
				kind[z][x] = FLOOR


## 开放块的地面高度 = 所在层 × 层高；通道取两侧格子的层
func _assign_heights() -> void:
	for z in n:
		for x in n:
			if kind[z][x] != FLOOR:
				continue
			var cx := (x - 1) / 2 if x % 2 == 1 else (x - 2) / 2
			var cz := (z - 1) / 2 if z % 2 == 1 else (z - 2) / 2
			var t := tier_of(cell_dist(cx, cz))
			if block_dist(x, z) < BANDS[0] * 2:
				t = TOP_TIER
			height[z][x] = maxi(t, 0) * TIER_H


## 观景台：格子环 b 上的一圈块，与高层地面齐平；崖边的栏杆由 maze.gd 搭。
## 高层迷宫的外墙（紧贴观景台内侧那一行）上开几道门，顶层广场直接连着观景台。
func _make_bands() -> void:
	for z in n:
		for x in n:
			for b in BANDS:
				if block_dist(x, z) == b * 2:
					kind[z][x] = TERRACE
					height[z][x] = tier_of(b - 1) * TIER_H

	var c := cells / 2
	var center := Vector2i(n / 2, n / 2)
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for b in BANDS:
		if b == BANDS[0]:
			continue
		for g in GATES_PER_BAND:
			var out: Vector2i = sides[rng.randi_range(0, 3)]
			var along := Vector2i(-out.y, out.x)
			var k := rng.randi_range(-(b - 2), b - 2)
			var p: Vector2i = center + out * (b * 2 - 1) + along * (2 * k)
			kind[p.y][p.x] = FLOOR
			height[p.y][p.x] = tier_of(b - 1) * TIER_H


## 大楼梯：从低层最里一排格子，穿过挡土墙，爬到高层最外一排格子
func _make_stairs() -> void:
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var first := rng.randi_range(0, 3)
	var center := Vector2i(n / 2, n / 2)
	for i in range(BANDS.size() - 1, -1, -1):
		var b := BANDS[i]
		var lower := tier_of(b + 1)
		# 每往里一层，楼梯转 90°，逼着玩家绕这一层走半圈
		var rot := first + (BANDS.size() - 1 - i)
		for s in STAIRS_PER_BAND:
			var out: Vector2i = sides[(rot + s * 4 / STAIRS_PER_BAND) % 4]
			var along := Vector2i(-out.y, out.x)
			var k := rng.randi_range(-(b - 1), b - 1)
			for seg in STAIR_BLOCKS:
				var db := b * 2 + 1 - seg
				var p: Vector2i = center + out * db + along * (2 * k)
				# 楼梯从观景台中间穿过，是一道下沉的槽，两侧由栏杆围住
				kind[p.y][p.x] = STAIR
				link[p.y][p.x] = -out
				height[p.y][p.x] = lower * TIER_H + seg * STAIR_RISE
				if seg == 0:
					stairs.append(p)


## 深渊区：放在某一层的一条边上，横跨整层宽度；区内的墙和墙角消失，格子变平台，通道变桥
func _make_chasms() -> void:
	var c := cells / 2
	var stair_cells := {}
	for p in stairs:
		for d in [-1, 3]:   # 楼梯两端的格子：低端前一块、高端后一块
			var q: Vector2i = p + link[p.y][p.x] * d
			stair_cells[Vector2i((q.x - 1) / 2, (q.y - 1) / 2)] = true

	for attempt in 80:
		if chasms.size() >= CHASM_COUNT:
			break
		var t := rng.randi_range(0, TOP_TIER - 1)
		var lo := 99
		var hi := -1
		for d in c + 1:
			if tier_of(d) == t:
				lo = mini(lo, d)
				hi = maxi(hi, d)
		var out: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][rng.randi_range(0, 3)]
		var along := Vector2i(-out.y, out.x)
		var s := rng.randi_range(-(lo - 1), lo - 3)
		var a: Vector2i = Vector2i(c, c) + out * lo + along * s
		var b: Vector2i = Vector2i(c, c) + out * hi + along * (s + 2)
		var r := Rect2i(a.min(b), (a - b).abs() + Vector2i.ONE)
		var ok := true
		for other in chasms:
			if r.grow(1).intersects(other):
				ok = false
		for cz in range(r.position.y, r.end.y):
			for cx in range(r.position.x, r.end.x):
				if stair_cells.has(Vector2i(cx, cz)):
					ok = false
		if ok:
			chasms.append(r)

	for r in chasms:
		for z in range(r.position.y * 2 + 1, r.end.y * 2):
			for x in range(r.position.x * 2 + 1, r.end.x * 2):
				if x % 2 == 1 and z % 2 == 1:
					kind[z][x] = PLATFORM
				elif kind[z][x] == FLOOR:
					kind[z][x] = BRIDGE
					link[z][x] = Vector2i(1, 0) if x % 2 == 0 else Vector2i(0, 1)
				else:
					kind[z][x] = VOID


## 同层的隔墙偶尔降成矮墙，制造“看得见到不了”
func _make_parapets() -> void:
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			if kind[z][x] != WALL or (x % 2 == 0) == (z % 2 == 0):
				continue
			var axis := Vector2i(1, 0) if x % 2 == 0 else Vector2i(0, 1)
			if kind[z - axis.y][x - axis.x] != FLOOR or kind[z + axis.y][x + axis.x] != FLOOR:
				continue
			if rng.randf() < 0.1:
				kind[z][x] = PARAPET
				wall_top[z][x] = height[z - axis.y][x - axis.x] + PARAPET_H


## 按行合并连续的墙，每段一个随机高度，从周围最高的地面算起；最外圈是围墙
func _assign_wall_heights() -> void:
	for z in n:
		var x := 0
		while x < n:
			if kind[z][x] != WALL:
				x += 1
				continue
			var start := x
			var base := 0.0
			while x < n and kind[z][x] == WALL:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if _is_ground(x + dx, z + dz):
							base = maxf(base, height[z + dz][x + dx])
				x += 1
			var border := z == 0 or z == n - 1 or start == 0 or x == n
			var h := OUTER_WALL_H if border else rng.randf_range(WALL_MIN, WALL_MAX)
			for i in range(start, x):
				wall_top[z][i] = base + h


## 拱门：只架在两侧都是墙角的平地通道上（这样拱的两脚有墙可靠）
func _make_arches() -> void:
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			if kind[z][x] != FLOOR or (x % 2 == 0) == (z % 2 == 0):
				continue
			if block_dist(x, z) < BANDS[0] * 2:
				continue
			var across := Vector2i(0, 1) if x % 2 == 0 else Vector2i(1, 0)
			if kind[z - across.y][x - across.x] != WALL or kind[z + across.y][x + across.x] != WALL:
				continue
			var along := Vector2i(across.y, across.x)
			var to_terrace: bool = kind[z - along.y][x - along.x] == TERRACE \
				or kind[z + along.y][x + along.x] == TERRACE
			if to_terrace or rng.randf() < ARCH_CHANCE:
				arch[z][x] = true
