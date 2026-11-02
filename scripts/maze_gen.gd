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
## - 部分通道上方架着拱门（通向观景台的门一律是拱门）；
## - 每层有几个 2×2 格子打通成的方形庭院，围墙一样高，贴墙一段楼梯爬上挑台，
##   挑台和围墙顶齐平，墙顶就是一圈步道；
## - 每层有一间带屋顶的大房间，四周原有的通道都是拱门门洞；另有十来间小房间（死胡同的格子），
##   门是厚墙上的窄拱门。屋里长什么样由 scripts/rooms/ 在玩家走近时按种子组合出来；
## - 部分隔墙是拱廊墙：墙身开一排透空的拱洞，看得见隔壁，过不去（庭院围墙上更多）。

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
const COURTYARDS_PER_TIER := 2
const COURT_H := STAIR_RISE * 2.0      # 庭院围墙高出地面多少（两块楼梯的升高，8 米）；挑台和墙顶步道也在这个高度
const ROOM_H := 6.0                    # 大房间屋顶离地高度
const SMALL_ROOMS := 12                # 小房间（死胡同的格子）的数量
const SMALL_ROOM_H := 3.6
const ARCADE_CHANCE := 0.15            # 隔墙做成拱廊墙的概率
const COURT_ARCADE_CHANCE := 0.6       # 庭院围墙上的概率

var cells := 25
var n := 0
var kind: Array = []              # kind[z][x]：上面的枚举
var height: Array = []            # height[z][x]：开放块的地面高度（米）；楼梯记低端
var link: Array = []              # link[z][x]：楼梯 / 桥的走向（Vector2i），楼梯指向上坡
var wall_top: Array = []          # wall_top[z][x]：墙、矮墙顶部的绝对高度（米）
var arch: Array = []              # arch[z][x]：这条通道上方有拱门
var arcade: Array = []            # arcade[z][x]：这块墙是拱廊墙（仍算 WALL，只是外观透空）
var courtyards: Array[Rect2i] = [] # 庭院，以块为单位（3×3 块）
var rooms: Array[Dictionary] = []  # 房间：{rect: Rect2i（大 3×3 块 / 小 1 块）, small: bool, height: 屋顶高, base: 地面高度, doors: 门所在的块}
var doorway: Array = []           # doorway[z][x]：这条通道是小房间的门——厚墙上开一个窄拱门
var chasms: Array[Rect2i] = []    # 深渊区，以格子为单位
var stairs: Array[Vector2i] = []  # 每段大楼梯最低一块的位置，调试和测试用
var spawn := Vector2i(1, 1)       # 出生点所在的块
var rng := RandomNumberGenerator.new()


func generate(seed_value: int) -> void:
	rng.seed = seed_value
	n = cells * 2 + 1
	kind = _grid(WALL)
	height = _grid(0.0)
	link = _grid(Vector2i.ZERO)
	wall_top = _grid(0.0)
	arch = _grid(false)
	arcade = _grid(false)
	doorway = _grid(false)
	courtyards.clear()
	rooms.clear()
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
	_make_rooms()
	_make_courtyards()
	_make_arches()
	_make_arcades()
	_make_small_rooms()
	_pick_spawn()


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


## 站在这块上时“所在层的地面高度”：滑翔的升空上限以它为准。
## 取地面高度往下对齐到层高，庭院楼梯和挑台、大楼梯中段都算本层，墙顶不是开放块，返回 NAN
func tier_floor(x: int, z: int) -> float:
	if not is_open(x, z):
		return NAN
	return floorf(height[z][x] / TIER_H + 0.001) * TIER_H


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


## 在第 t 层随机找一块 2×2 个格子（3×3 块）的空地，用来做庭院或房间。
## 它和外面一圈墙里只能有本层平地和墙（避开深渊、楼梯、观景台、最外圈），也不能挨着别的庭院和房间。
## 找不到（这一次随机没选中）返回大小为 0 的矩形。
## 庭院会把围墙改成 8 米，不能挨着最外圈围墙；房间只会加高围墙，可以（最外一层只有两格宽，不然放不下）
func _find_square(t: int, allow_border := false) -> Rect2i:
	var c := cells / 2
	var cx := rng.randi_range(0, cells - 2)
	var cz := rng.randi_range(0, cells - 2)
	for dz in 2:
		for dx in 2:
			var cc := Vector2i(cx + dx, cz + dz)
			if _cell_tier(cc) != t or (cell_dist(cc.x, cc.y) >= c and not allow_border):
				return Rect2i()
	var r := Rect2i(cx * 2 + 1, cz * 2 + 1, 3, 3)
	for z in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var k: int = kind[z][x]
			if k != FLOOR and k != WALL and k != PARAPET:
				return Rect2i()
			if k == FLOOR and not is_equal_approx(height[z][x], t * TIER_H):
				return Rect2i()
	for other in courtyards:
		if r.grow(2).intersects(other):
			return Rect2i()
	for room: Dictionary in rooms:
		if r.grow(2).intersects(room["rect"]):
			return Rect2i()
	return r


## 房间：每层一间，同样占 2×2 个格子，有屋顶。原来通进这几个格子的通道全部保留成门（上面架拱门），
## 所以迷宫的连通性不变；围墙不开拱廊。里面放什么由 maze.gd 按 theme 交给 scripts/rooms/ 下的脚本
func _make_rooms() -> void:
	for t in TOP_TIER:
		for attempt in 300:
			var r := _find_square(t, true)
			if r.size == Vector2i.ZERO:
				continue
			var base := t * TIER_H
			var doors: Array[Vector2i] = []
			for z in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					if not r.has_point(Vector2i(x, z)) and kind[z][x] == FLOOR:
						doors.append(Vector2i(x, z))
			if doors.is_empty():
				continue
			for z in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					kind[z][x] = FLOOR
					height[z][x] = base
			for z in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					if r.has_point(Vector2i(x, z)) or kind[z][x] == FLOOR:
						continue
					if kind[z][x] == PARAPET:
						kind[z][x] = WALL
						wall_top[z][x] = 0.0
					wall_top[z][x] = maxf(wall_top[z][x], base + ROOM_H + 1.5)
			for d in doors:
				arch[d.y][d.x] = true
			rooms.append({"rect": r, "small": false, "height": ROOM_H, "base": base, "doors": doors})
			break


## 小房间：挑一些死胡同的格子（只有一条通道通进来），盖上屋顶；那条通道变成厚墙上的窄拱门。
## 死胡同本来就只连一条路，改成房间不影响连通性。四周的矮墙改成实墙，免得屋顶下面漏一圈
func _make_small_rooms() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var candidates: Array[Array] = []
	for cz in cells:
		for cx in cells:
			var b := _cell_block(Vector2i(cx, cz))
			var t := _cell_tier(Vector2i(cx, cz))
			if t < 0 or block_dist(b.x, b.y) < BANDS[0] * 2:
				continue
			if kind[b.y][b.x] != FLOOR or not is_equal_approx(height[b.y][b.x], t * TIER_H):
				continue
			var exits: Array[Vector2i] = []
			for d in dirs:
				if is_open(b.x + d.x, b.y + d.y):
					exits.append(d)
			if exits.size() != 1:
				continue
			var p := b + exits[0]
			var q := b + exits[0] * 2
			if kind[p.y][p.x] != FLOOR or kind[q.y][q.x] != FLOOR \
					or not is_equal_approx(height[p.y][p.x], height[b.y][b.x]) \
					or not is_equal_approx(height[q.y][q.x], height[b.y][b.x]):
				continue
			var taken := false
			for r in courtyards:
				if r.grow(1).has_point(b):
					taken = true
			for room: Dictionary in rooms:
				if (room["rect"] as Rect2i).grow(1).has_point(b):
					taken = true
			if not taken:
				candidates.append([b, p])
	for i in candidates.size():
		var j := rng.randi_range(i, candidates.size() - 1)
		var tmp: Array = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var made := 0
	for c in candidates:
		if made >= SMALL_ROOMS:
			break
		var b: Vector2i = c[0]
		var p: Vector2i = c[1]
		var near := false
		for room: Dictionary in rooms:
			if room["small"] and ((room["rect"] as Rect2i).position - b).length() < 6.0:
				near = true
		if near:
			continue
		var base: float = height[b.y][b.x]
		for z in range(b.y - 1, b.y + 2):
			for x in range(b.x - 1, b.x + 2):
				arcade[z][x] = false
				if kind[z][x] == PARAPET:
					kind[z][x] = WALL
					wall_top[z][x] = base + WALL_MIN
		doorway[p.y][p.x] = true
		arch[p.y][p.x] = false
		rooms.append({"rect": Rect2i(b, Vector2i.ONE), "small": true, "height": SMALL_ROOM_H, "base": base, "doors": [p]})
		made += 1


## 庭院：同一层里 2×2 个格子打通成 3×3 块的方形院子，围墙统一 COURT_H 高。
## 贴着一面围墙放两块楼梯，爬到角上一块和围墙顶齐平的挑台，围墙顶连成一圈步道。
## 楼梯和挑台外侧、挑台尽头的围墙必须是实墙，否则原来通进院子的路会被挑台堵住
func _make_courtyards() -> void:
	for t in TOP_TIER:
		var made := 0
		for attempt in 300:
			if made >= COURTYARDS_PER_TIER:
				break
			var r := _find_square(t)
			if r.size == Vector2i.ZERO:
				continue
			var base := t * TIER_H
			var stair := _court_stair(r)
			if stair.is_empty():
				continue
			for z in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					kind[z][x] = FLOOR
					height[z][x] = base
			for z in range(r.position.y - 1, r.end.y + 1):
				for x in range(r.position.x - 1, r.end.x + 1):
					if not r.has_point(Vector2i(x, z)) and kind[z][x] != FLOOR:
						kind[z][x] = WALL
						wall_top[z][x] = base + COURT_H
			# stair = [第一块, 方向]：两块楼梯，接一块挑台
			var p: Vector2i = stair[0]
			var dir: Vector2i = stair[1]
			for seg in 2:
				var q := p + dir * seg
				kind[q.y][q.x] = STAIR
				link[q.y][q.x] = dir
				height[q.y][q.x] = base + seg * STAIR_RISE
			var top := p + dir * 2
			height[top.y][top.x] = base + COURT_H
			courtyards.append(r)
			made += 1


## 庭院里楼梯的位置：沿某条边的一排三块，前两块是楼梯、第三块是挑台。
## 要求这一排外侧的三块围墙和挑台尽头那块围墙都是实墙。找不到返回空数组
func _court_stair(r: Rect2i) -> Array:
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var start := rng.randi_range(0, 7)
	for i in 8:
		var out: Vector2i = sides[(start + i) % 4]
		var dir := Vector2i(-out.y, out.x) * (1 if (start + i) / 4 % 2 == 0 else -1)
		# 这条边上的一排：从起点沿 dir 走三块
		var mid := r.position + Vector2i(1, 1) + out
		var p := mid - dir
		var good := true
		for k in 3:
			var q := p + dir * k + out
			if kind[q.y][q.x] == FLOOR:
				good = false
		var end := p + dir * 3
		if kind[end.y][end.x] == FLOOR:
			good = false
		if good:
			return [p, dir]
	return []


## 拱廊墙：两侧都是同高平地、两头都是墙角的隔墙，墙身开一排透空拱洞
func _make_arcades() -> void:
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			if kind[z][x] != WALL or (x % 2 == 0) == (z % 2 == 0):
				continue
			var across := Vector2i(1, 0) if x % 2 == 0 else Vector2i(0, 1)
			var a := Vector2i(x, z) - across
			var b := Vector2i(x, z) + across
			if kind[a.y][a.x] != FLOOR or kind[b.y][b.x] != FLOOR \
					or not is_equal_approx(height[a.y][a.x], height[b.y][b.x]):
				continue
			var along := Vector2i(across.y, across.x)
			var e0 := Vector2i(x, z) - along
			var e1 := Vector2i(x, z) + along
			if kind[e0.y][e0.x] != WALL or kind[e1.y][e1.x] != WALL:
				continue
			if wall_top[z][x] - height[a.y][a.x] < 6.0:
				continue
			var in_court := false
			for r in courtyards:
				if r.grow(1).has_point(Vector2i(x, z)):
					in_court = true
			var in_room := false
			for room: Dictionary in rooms:
				if (room["rect"] as Rect2i).grow(1).has_point(Vector2i(x, z)):
					in_room = true
			if in_room:
				continue
			if rng.randf() < (COURT_ARCADE_CHANCE if in_court else ARCADE_CHANCE):
				arcade[z][x] = true


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


## 从 from 走到 to 要几步（按块计）；走不到返回 -1。
## 相邻开放块的高差不超过一块楼梯的升高就能走过去
func path_length(from: Vector2i, to: Vector2i) -> int:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p == to:
			return dist[p]
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := p + d
			if dist.has(q) or not is_open(q.x, q.y):
				continue
			if absf(floor_height(q.x, q.y) - floor_height(p.x, p.y)) > STAIR_RISE + 0.01:
				continue
			dist[q] = dist[p] + 1
			queue.append(q)
	return -1


## 出生点：最外一道挡土墙顶的观景台，各边中点附近挑一个能走到顶层广场的
## （观景台被楼梯槽截成几段，不是每段都有门通进迷宫）。
## 出生点正对着的那块墙降成矮墙，像一扇观景窗：视线越过它，能看见远处的利维坦
func _pick_spawn() -> void:
	var center := Vector2i(n / 2, n / 2)
	var db: int = BANDS[BANDS.size() - 1] * 2
	for out: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var along := Vector2i(-out.y, out.x)
		for k in [0, 2, -2, 4, -4, 6, -6]:
			var p: Vector2i = center + out * db + along * k
			var front: Vector2i = p - out
			if kind[p.y][p.x] != TERRACE or arch[front.y][front.x] or path_length(p, center) < 0:
				continue
			if kind[front.y][front.x] == WALL:
				kind[front.y][front.x] = PARAPET
				wall_top[front.y][front.x] = height[p.y][p.x] + PARAPET_H
			spawn = p
			return
