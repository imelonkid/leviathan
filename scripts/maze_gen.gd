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
## - 每层有几个 2×2 格子打通成的方形庭院，放得下的层再加一个 3×3 格子的大广场；围墙一样高，
##   贴墙一段楼梯爬上挑台，挑台和围墙顶齐平，墙顶就是一圈步道；
## - 同一层的庭院之间，沿着迷宫的墙把一串墙顶降 / 升到和庭院围墙一样高，连成墙顶步道网；
## - 每层有一间带屋顶的大房间，四周原有的通道都是拱门门洞；另有十来间小房间（死胡同的格子），
##   门是厚墙上的窄拱门。屋里长什么样由 scripts/rooms/ 在玩家走近时按种子组合出来；
## - 每层几座地标：墙角上立起的塔楼（钟楼、望楼、尖塔），横跨长直街的门楼，高出墙头，远远认得出；
## - 部分隔墙是拱廊墙：墙身开一排透空的拱洞，看得见隔壁，过不去（庭院围墙上更多）；
## - 第 1、2 层各两栋带拱廊的小楼：一段沿着直街的三块墙（墙角、墙、墙角）整段换成两三层的窄楼，
##   底层朝街一排拱，拱后是 2 米深、能进去避雨的廊子（穿不过去，迷宫走法不变）。

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
const BIG_COURTS_PER_TIER := 1         # 3×3 格子（5×5 块）的大广场；只有三格宽的层放得下
const WALKWAY_MAX := 40                # 两个庭院之间的墙顶步道最长多少块，再长就不连
const TOWERS_PER_TIER := 4
const GATEHOUSES_PER_TIER := 2
const LANDMARK_GAP := 8                # 两座地标至少隔多少块
const HOUSES_PER_TIER := 2             # 带拱廊的小楼：每层几栋（最外一层只有两格宽、挨着挡土墙，放不下）
const HOUSE_GAP := 5                   # 小楼离塔楼、门楼和别的小楼至少隔多少块
enum { TOWER_BELL, TOWER_WATCH, TOWER_SPIRE }
const FLY_STAIR_BAND := 6              # 这圈观景台伸出一座“通”的飞桥：平桥接悬空楼梯落到下层街上
const FLY_BROKEN_BANDS: Array[int] = [2, 10]   # 这几圈各伸出一座断在半空的飞桥
const FLY_LEVEL := 2                   # 通的飞桥：平桥几块，后面三块是悬空楼梯，再一块是落脚的格子
const FLY_BROKEN_MIN := 3              # 断桥伸出去几块
const FLY_BROKEN_MAX := 5
const PLAZA_STAIR_BLOCKS := 2         # 广场高架桥的悬空楼梯：两块，每块升 STAIR_RISE，正好爬到步道高度
const FLY_CLEAR := 4.0                 # 飞桥下面的墙压到桥面以下这么多（桥面厚 0.8，留出 3 米多的空当，从旁边看得出桥是悬着的）
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
var cemetery := Rect2i()          # 独立乱葬岗；外围一圈和墓区之间的格子保留通路
var burial_plots := {}            # 完整墓体占用的格子，寻路绕开
var courtyards: Array[Rect2i] = [] # 庭院，以块为单位（3×3 块；大广场 5×5 块）
var walkway: Array = []           # walkway[z][x]：这块的顶上是步道（庭院围墙和连接它们的墙），顶高记在 wall_top
var towers: Array[Dictionary] = [] # 塔楼：{block: 墙角块, kind: TOWER_*, base: 本层地面高度}
var gatehouses: Array[Dictionary] = [] # 门楼：{block: 跨过的通道块, along_x: 街是否沿 x, base}
var landmark: Array = []          # landmark[z][x]：被地标占了的块（塔楼、门楼的两个墩子和楼下的通道、小楼），墙面不再加窗和装饰件
var houses: Array[Dictionary] = [] # 小楼：{block: 中间那块墙, along: 楼身沿哪个方向, face: 朝街的一面, base, storeys: 2 / 3, arches: 3 / 5, balcony: bool}
var house: Array = []             # house[z][x]：这块墙被小楼占了（maze.gd 不再砌墙，由楼身代替）
var overpasses: Array[Dictionary] = [] # 飞桥：{root: 观景台上的起点块, out: 朝外的方向, level: 平桥几块, stair: 悬空楼梯几块（0 = 断桥）, deck: 桥面高度, base: 下层地面高度}
var plaza_bridges: Array[Dictionary] = [] # 广场高架桥：{start: 桥头那块围墙, dir: 过桥的方向, span: 跨过几块, deck: 桥面高度, base: 广场地面, stair_at: 楼梯接在桥上哪一块, stair_dir: 楼梯从桥边往下走的方向}
var overpass: Array = []          # overpass[z][x]：头顶有飞桥或悬空楼梯，记下层地面高度；没有是 NAN
var jumps := {}                   # 飞桥连起来的两块：块 → [另一头的块]，path_length 用
var span: Array = []              # span[z][x]：步道从这条通道上方跨过去——下面仍是通道（两头各一道拱），上面是步道的桥面
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
	walkway = _grid(false)
	span = _grid(false)
	landmark = _grid(false)
	house = _grid(false)
	overpass = _grid(NAN)
	overpasses.clear()
	plaza_bridges.clear()
	jumps.clear()
	towers.clear()
	gatehouses.clear()
	houses.clear()
	courtyards.clear()
	cemetery = Rect2i()
	burial_plots.clear()
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
	_make_cemetery()
	_make_courtyards()
	_make_arches()
	_make_arcades()
	_make_small_rooms()
	_pick_spawn()
	_make_walkways()
	_make_overpasses()
	_make_plaza_bridges()
	_make_landmarks()
	_make_houses()


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


## 站在 (x, z) 这块、高度 y 时所在层的地面高度：站在飞桥或悬空楼梯上按自己的高度往下对齐到层高，
## 其余同 tier_floor
func ground_tier(x: int, z: int, y: float) -> float:
	if x >= 0 and z >= 0 and x < n and z < n and not is_nan(overpass[z][x]) and y > overpass[z][x] + 1.0:
		return floorf(y / TIER_H + 0.001) * TIER_H
	return tier_floor(x, z)


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


## 在第 t 层随机找一块 size×size 个格子（2×2 格子 = 3×3 块，3×3 格子 = 5×5 块）的空地，用来做庭院或房间。
## 它和外面一圈墙里只能有本层平地和墙（避开深渊、楼梯、观景台、最外圈），也不能挨着别的庭院和房间。
## 找不到（这一次随机没选中）返回大小为 0 的矩形。
## 庭院会把围墙改成 8 米，不能挨着最外圈围墙；房间只会加高围墙，可以（最外一层只有两格宽，不然放不下）
func _find_square(t: int, allow_border := false, size := 2) -> Rect2i:
	var c := cells / 2
	var cx := rng.randi_range(0, cells - size)
	var cz := rng.randi_range(0, cells - size)
	for dz in size:
		for dx in size:
			var cc := Vector2i(cx + dx, cz + dz)
			if _cell_tier(cc) != t or (cell_dist(cc.x, cc.y) >= c and not allow_border):
				return Rect2i()
	var r := Rect2i(cx * 2 + 1, cz * 2 + 1, size * 2 - 1, size * 2 - 1)
	for z in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var k: int = kind[z][x]
			if k != FLOOR and k != WALL and k != PARAPET:
				return Rect2i()
			if k == FLOOR and not is_equal_approx(height[z][x], t * TIER_H):
				return Rect2i()
	if r.grow(2).intersects(cemetery):
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


## 打通同高的普通墙和通道，原有入口全部保留。墓区之间与外围都是连续通路。
func _make_cemetery() -> void:
	var options: Array[Rect2i] = []
	for z in range(2, n - 5):
		for x in range(2, n - 5):
			for size: Vector2i in [Vector2i(5, 7), Vector2i(7, 5)]:
				var r := Rect2i(Vector2i(x, z), size)
				if r.end.x >= n - 1 or r.end.y >= n - 1:
					continue
				var base := -1.0
				var good := true
				for zz in range(r.position.y - 1, r.end.y + 1):
					for xx in range(r.position.x - 1, r.end.x + 1):
						if kind[zz][xx] not in [FLOOR, WALL]:
							good = false
						if kind[zz][xx] == FLOOR:
							if base < 0.0:
								base = height[zz][xx]
							good = good and is_equal_approx(height[zz][xx], base)
				for room: Dictionary in rooms:
					good = good and not r.grow(2).intersects(room.rect)
				if good and base >= 0 and base < TOP_TIER * TIER_H:
					options.append(r)
	if options.is_empty():
		return
	cemetery = options[rng.randi_range(0, options.size() - 1)]
	var base := 0.0
	for z in range(cemetery.position.y, cemetery.end.y):
		for x in range(cemetery.position.x, cemetery.end.x):
			if kind[z][x] == FLOOR:
				base = height[z][x]
	for z in range(cemetery.position.y, cemetery.end.y):
		for x in range(cemetery.position.x, cemetery.end.x):
			kind[z][x] = FLOOR
			height[z][x] = base
	for z in range(cemetery.position.y + 1, cemetery.end.y - 1):
		for x in range(cemetery.position.x + 1, cemetery.end.x - 1):
			if x != cemetery.get_center().x and z != cemetery.get_center().y:
				burial_plots[Vector2i(x, z)] = true


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
			var taken := cemetery.grow(1).has_point(b)
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
		var big := 0
		for attempt in 600:
			if made >= COURTYARDS_PER_TIER + big:
				break
			# 前一半的尝试先找大广场，找不到（这一层太窄）再只放小庭院
			var want_big := big < BIG_COURTS_PER_TIER and attempt < 300
			var r := _find_square(t, false, 3 if want_big else 2)
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
			if want_big:
				big += 1


## 庭院里楼梯的位置：沿某条边的一排三块，前两块是楼梯、第三块是挑台。
## 要求这一排外侧的三块围墙是实墙；挑台尽头那块如果在院外，也得是实墙（不然原来通进院子的路会被挑台堵住）。
## 大广场一条边有五块，三块一排可以错开放。找不到返回空数组
func _court_stair(r: Rect2i) -> Array:
	var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var half := r.size.x / 2
	var start := rng.randi_range(0, 7)
	for i in 8:
		var out: Vector2i = sides[(start + i) % 4]
		var dir := Vector2i(-out.y, out.x) * (1 if (start + i) / 4 % 2 == 0 else -1)
		var mid := r.position + Vector2i(half, half) + out * half
		for s in range(-half, half - 1):
			var p := mid + dir * s
			var good := true
			for k in 3:
				var q := p + dir * k + out
				if kind[q.y][q.x] == FLOOR:
					good = false
			var end := p + dir * 3
			if not r.has_point(end) and kind[end.y][end.x] == FLOOR:
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


## 墙顶步道：庭院围墙一圈都是，通进院子的路口上方架桥面，围墙顶连成完整的一圈；
## 同一层的庭院之间，沿着墙（墙角和隔墙）找一条最短的路，路上的墙顶统一改成庭院围墙的高度，
## 遇到通道就从上面跨过去（span），连成一张步道网。按距离从近到远连，已经连通的不再连。
## 路只走本层的普通墙和平地通道：不走矮墙、最外圈围墙、房间和小房间门口，也不贴着楼梯、桥、深渊平台
func _make_walkways() -> void:
	for r in courtyards:
		var base := tier_floor(r.position.x, r.position.y)   # 角上可能是楼梯或挑台，往下对齐到层高
		for z in range(r.position.y - 1, r.end.y + 1):
			for x in range(r.position.x - 1, r.end.x + 1):
				var p := Vector2i(x, z)
				if r.has_point(p):
					continue
				if kind[z][x] == WALL:
					walkway[z][x] = true
				elif _spannable(p, base):
					_set_walk(p, base)
	for t in TOP_TIER:
		var base := t * TIER_H
		var courts: Array[Rect2i] = []
		for r in courtyards:
			if is_equal_approx(tier_floor(r.position.x, r.position.y), base):
				courts.append(r)
		var group := range(courts.size())   # 并查集（只有两三个，直接改标号）
		var links: Array[Array] = []
		for i in courts.size():
			for j in range(i + 1, courts.size()):
				var path := _wall_path(courts[i], courts[j], base)
				if not path.is_empty():
					links.append(path + [i, j])
		links.sort_custom(func(a: Array, b: Array) -> bool: return a.size() < b.size())
		for l in links:
			var j: int = l.pop_back()
			var i: int = l.pop_back()
			if group[i] == group[j]:
				continue
			var old: int = group[j]
			for k in group.size():
				if group[k] == old:
					group[k] = group[i]
			for p: Vector2i in l:
				_set_walk(p, base)


func _set_walk(p: Vector2i, base: float) -> void:
	walkway[p.y][p.x] = true
	wall_top[p.y][p.x] = base + COURT_H
	if kind[p.y][p.x] == FLOOR:
		span[p.y][p.x] = true
		arch[p.y][p.x] = false


## 通道能不能从上面架步道：本层的平地通道（夹在两块墙之间），两头的墙角在，不是小房间的门
func _spannable(p: Vector2i, base: float) -> bool:
	if kind[p.y][p.x] != FLOOR or (p.x % 2 == 0) == (p.y % 2 == 0) or doorway[p.y][p.x]:
		return false
	if not is_equal_approx(height[p.y][p.x], base):
		return false
	var ends := Vector2i(0, 1) if p.x % 2 == 0 else Vector2i(1, 0)
	var a := p - ends
	var b := p + ends
	return kind[a.y][a.x] == WALL and kind[b.y][b.x] == WALL


## 从庭院 a 的围墙沿着墙走到庭院 b 的围墙，返回路上（不含两头围墙）的块；走不通或太长返回空数组
func _wall_path(a: Rect2i, b: Rect2i, base: float) -> Array:
	var ring_a := a.grow(1)
	var ring_b := b.grow(1)
	var prev := {}
	var dist := {}
	var queue: Array[Vector2i] = []
	for z in range(ring_a.position.y, ring_a.end.y):
		for x in range(ring_a.position.x, ring_a.end.x):
			var p := Vector2i(x, z)
			if not a.has_point(p) and kind[z][x] == WALL:
				dist[p] = 0
				queue.append(p)
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if ring_b.has_point(p) and not b.has_point(p):
			var path: Array = []
			var q: Vector2i = prev.get(p, p)
			while dist[q] > 0:
				path.append(q)
				q = prev[q]
			return path
		if dist[p] >= WALKWAY_MAX:
			continue
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := p + d
			if dist.has(q) or not _walkway_ok(q, base) and not (ring_b.has_point(q) and kind[q.y][q.x] == WALL):
				continue
			dist[q] = dist[p] + 1
			prev[q] = p
			queue.append(q)
	return []


func _walkway_ok(p: Vector2i, base: float) -> bool:
	if cemetery.grow(1).has_point(p):
		return false
	if p.x <= 0 or p.y <= 0 or p.x >= n - 1 or p.y >= n - 1:
		return false
	if kind[p.y][p.x] != WALL and not _spannable(p, base):
		return false
	for r in courtyards:
		if r.has_point(p):
			return false
	for room: Dictionary in rooms:
		if (room["rect"] as Rect2i).grow(1).has_point(p):
			return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := p.x + dx
			var z := p.y + dz
			var k: int = kind[z][x]
			if k == STAIR or k == BRIDGE or k == PLATFORM or k == VOID:
				return false
			if k == FLOOR and not is_equal_approx(height[z][x], base):
				return false
	return true


## 地标：每层先找门楼（长直街上的一条通道，两侧墙角做墩子），再找塔楼（墙角块，越靠近庭院越优先）。
## 都不碰步道、房间、楼梯、桥和观景台，彼此至少隔 LANDMARK_GAP 块
## 飞桥：从观景台水平伸出去，沿下层一条放射方向的直线，在下层地面上方一个层高处越过墙头。
## 一座“通”的：平桥 FLY_LEVEL 块，接三块悬空楼梯（每块降 STAIR_RISE）落到下层的一个格子上；
## 几座断的：伸出去几块就断在半空。桥下的墙压到桥面以下 FLY_CLEAR
func _make_overpasses() -> void:
	for b in [FLY_STAIR_BAND] + FLY_BROKEN_BANDS:
		var stair := STAIR_BLOCKS if b == FLY_STAIR_BAND else 0
		var cands := _overpass_roots(b)
		_shuffle(cands)
		for c: Array in cands:
			var root: Vector2i = c[0]
			var out: Vector2i = c[1]
			var level := FLY_LEVEL if stair > 0 else rng.randi_range(FLY_BROKEN_MIN, FLY_BROKEN_MAX)
			level = mini(level, _overpass_room(b) - (stair + 1 if stair > 0 else 1))   # 断桥离对面留一排
			if level < 1 or not _overpass_ok(root, out, level, stair):
				continue
			var deck: float = height[root.y][root.x]
			var base := deck - TIER_H
			for k in range(1, level + stair + 1):
				var p := root + out * k
				overpass[p.y][p.x] = base
				if kind[p.y][p.x] == WALL or kind[p.y][p.x] == PARAPET:
					wall_top[p.y][p.x] = minf(wall_top[p.y][p.x], deck - FLY_CLEAR)
				if k > level:
					arch[p.y][p.x] = false   # 楼梯从这里穿过，拱门让开
			if stair > 0:
				var foot := root + out * (level + stair)
				jumps[root] = [foot]
				jumps[foot] = [root]
			overpasses.append({"root": root, "out": out, "level": level, "stair": stair, "deck": deck, "base": base})
			break


## 广场高架桥：大广场（5×5 块）上空，在墙顶步道的高度从一边围墙横架到对边，桥下照样是广场；
## 桥的中段一侧接一段悬空楼梯落到广场地面。优先走正中一排，避开院里的楼梯和挑台
func _make_plaza_bridges() -> void:
	for r in courtyards:
		if r.size.x < 5:
			continue
		var base := tier_floor(r.position.x, r.position.y)
		var deck := base + COURT_H
		var options: Array = []
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var perp := Vector2i(dir.y, dir.x)
			for row in [2, 1, 3]:
				var start: Vector2i = r.position + perp * row - dir
				for sd: Vector2i in [perp, -perp]:
					if _plaza_bridge_ok(r, start, dir, sd, base):
						options.append([(1.0 if row != 2 else 0.0) + rng.randf() * 0.5, start, dir, sd])
		if options.is_empty():
			continue
		options.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var o: Array = options[0]
		var start: Vector2i = o[1]
		var dir: Vector2i = o[2]
		var sd: Vector2i = o[3]
		var at := start + dir * 3
		for k in range(1, 6):
			var p := start + dir * k
			overpass[p.y][p.x] = base
		for k in range(1, PLAZA_STAIR_BLOCKS + 1):
			var p := at + sd * k
			overpass[p.y][p.x] = base
		plaza_bridges.append({"start": start, "dir": dir, "span": 5, "deck": deck, "base": base, "stair_at": at, "stair_dir": sd})


## 桥下五块都是广场地面（不是楼梯、挑台），两头的围墙顶是步道；楼梯那一溜也都是广场地面
func _plaza_bridge_ok(r: Rect2i, start: Vector2i, dir: Vector2i, sd: Vector2i, base: float) -> bool:
	for p: Vector2i in [start, start + dir * 6]:
		if not walkway[p.y][p.x]:
			return false
	var blocks: Array[Vector2i] = []
	for k in range(1, 6):
		blocks.append(start + dir * k)
	for k in range(1, PLAZA_STAIR_BLOCKS + 1):
		blocks.append(start + dir * 3 + sd * k)
	for p in blocks:
		if not r.has_point(p) or kind[p.y][p.x] != FLOOR or not is_equal_approx(height[p.y][p.x], base):
			return false
	return true


## 第 b 圈观景台上能伸出飞桥的块：每条边的直段上、对着下层一排格子的那些（偏移是偶数块）
func _overpass_roots(b: int) -> Array:
	var center := Vector2i(n / 2, n / 2)
	var roots: Array = []
	for out: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var along := Vector2i(-out.y, out.x)
		for a in range(-(b * 2 - 2), b * 2 - 1, 2):
			var p: Vector2i = center + out * (b * 2) + along * a
			if kind[p.y][p.x] == TERRACE:
				roots.append([p, out])
	return roots


## 第 b 圈外面那一层有几排块（到下一圈观景台或最外圈围墙之前）
func _overpass_room(b: int) -> int:
	var i := BANDS.find(b)
	var outer: int = BANDS[i + 1] * 2 if i + 1 < BANDS.size() else n / 2
	return outer - b * 2 - 1


## 飞桥伸出去的那一串块：平桥下面什么都行（墙会压低），只是不跨房间和庭院；
## 悬空楼梯和落脚的格子要是下层的平地，没有桥面、门口和步道（楼梯会从那里穿过；拱门拆掉）
func _overpass_ok(root: Vector2i, out: Vector2i, level: int, stair: int) -> bool:
	var deck: float = height[root.y][root.x]
	var base := deck - TIER_H
	var last := level + stair + (1 if stair > 0 else 0)
	for k in range(1, last + 1):
		var p := root + out * k
		if p.x < 1 or p.y < 1 or p.x >= n - 1 or p.y >= n - 1:
			return false
		if cemetery.grow(1).has_point(p):
			return false
		var kk: int = kind[p.y][p.x]
		if kk == TERRACE or kk == STAIR and k <= level:
			return false
		for r in courtyards:
			if r.has_point(p):
				return false
		for room: Dictionary in rooms:
			if (room["rect"] as Rect2i).has_point(p):
				return false
		if k > level:
			if kk != FLOOR or not is_equal_approx(height[p.y][p.x], base) \
					or span[p.y][p.x] or doorway[p.y][p.x] or walkway[p.y][p.x]:
				return false
	return true


func _make_landmarks() -> void:
	var placed: Array[Vector2i] = []
	for t in TOP_TIER:
		var base := t * TIER_H
		var gates: Array[Vector2i] = []
		for z in range(2, n - 2):
			for x in range(2, n - 2):
				if (x % 2 == 0) != (z % 2 == 0) and _gatehouse_ok(Vector2i(x, z), base):
					gates.append(Vector2i(x, z))
		_shuffle(gates)
		var made := 0
		for p in gates:
			if made >= GATEHOUSES_PER_TIER:
				break
			if not _far_from(p, placed):
				continue
			var along_x := p.x % 2 == 0
			var perp := Vector2i(0, 1) if along_x else Vector2i(1, 0)
			for q: Vector2i in [p, p - perp, p + perp]:
				landmark[q.y][q.x] = true
			gatehouses.append({"block": p, "along_x": along_x, "base": base})
			placed.append(p)
			made += 1

		var spots: Array[Array] = []
		for z in range(2, n - 2, 2):
			for x in range(2, n - 2, 2):
				var p := Vector2i(x, z)
				if not _tower_ok(p, base):
					continue
				var d := 999.0
				for r in courtyards:
					d = minf(d, (Vector2(r.get_center()) - Vector2(p)).length())
				spots.append([d + rng.randf() * 12.0, p])
		spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		made = 0
		for sp in spots:
			if made >= TOWERS_PER_TIER:
				break
			var p: Vector2i = sp[1]
			if not _far_from(p, placed):
				continue
			landmark[p.y][p.x] = true
			towers.append({"block": p, "kind": rng.randi_range(0, 2), "base": base})
			placed.append(p)
			made += 1


## 小楼：每层挑几段沿直街的三块墙，离别的地标远一点
func _make_houses() -> void:
	var taken: Array[Vector2i] = []
	for t: Dictionary in towers:
		taken.append(t["block"])
	for g: Dictionary in gatehouses:
		taken.append(g["block"])
	var spots: Array = []
	for t in TOP_TIER:
		spots.append([])
	for z in range(3, n - 3):
		for x in range(3, n - 3):
			if (x % 2 == 0) == (z % 2 == 0):
				continue
			var c := Vector2i(x, z)
			var along := Vector2i(0, 1) if x % 2 == 0 else Vector2i(1, 0)
			var perp := Vector2i(along.y, along.x)
			for face: Vector2i in [perp, -perp]:
				var f := c + face
				if kind[f.y][f.x] != FLOOR:
					continue
				var base: float = height[f.y][f.x]
				var t := int(base / TIER_H + 0.001)
				if t < TOP_TIER and _house_ok(c, along, face, base):
					spots[t].append([c, along, face, base])
	for t in TOP_TIER:
		_shuffle(spots[t])
		var made := 0
		for sp: Array in spots[t]:
			if made >= HOUSES_PER_TIER:
				break
			var c: Vector2i = sp[0]
			if not _far_from(c, taken, HOUSE_GAP):
				continue
			var along: Vector2i = sp[1]
			for k in [-1, 0, 1]:
				var q: Vector2i = c + along * k
				landmark[q.y][q.x] = true
				house[q.y][q.x] = true
			houses.append({"block": c, "along": along, "face": sp[2], "base": sp[3],
				"storeys": rng.randi_range(2, 3), "arches": 3 if rng.randf() < 0.5 else 5, "balcony": rng.randf() < 0.5})
			taken.append(c)
			made += 1


## 三块普通墙（不是矮墙、步道、拱廊墙、地标），朝街那面三块都是本层的平地（直街），周围安静
func _house_ok(c: Vector2i, along: Vector2i, face: Vector2i, base: float) -> bool:
	for k in [-1, 0, 1]:
		var q: Vector2i = c + along * k
		if kind[q.y][q.x] != WALL or walkway[q.y][q.x] or landmark[q.y][q.x] or arcade[q.y][q.x]:
			return false
		if not _quiet(q, base):   # 挡土墙、外圈墙旁边有高一层的地面或观景台，这一条就排除了
			return false
		var f: Vector2i = q + face
		if kind[f.y][f.x] != FLOOR or span[f.y][f.x] or doorway[f.y][f.x] or arch[f.y][f.x]:
			return false
		if not is_equal_approx(height[f.y][f.x], base):
			return false
	for r in courtyards:
		if r.grow(1).has_point(c):
			return false
	return true


func _far_from(p: Vector2i, others: Array[Vector2i], gap := LANDMARK_GAP) -> bool:
	for o in others:
		if maxi(absi(o.x - p.x), absi(o.y - p.y)) < gap:
			return false
	return true


func _shuffle(a: Array) -> void:
	for i in a.size():
		var j := rng.randi_range(i, a.size() - 1)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


## 周围 3×3 里没有楼梯、桥、深渊、观景台、小房间门口、飞桥，开放块都在本层地面上；不挨着房间
func _quiet(p: Vector2i, base: float) -> bool:
	if cemetery.grow(1).has_point(p):
		return false
	for room: Dictionary in rooms:
		if (room["rect"] as Rect2i).grow(2).has_point(p):
			return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := p.x + dx
			var z := p.y + dz
			var k: int = kind[z][x]
			if k == STAIR or k == BRIDGE or k == PLATFORM or k == VOID or k == TERRACE or doorway[z][x]:
				return false
			if k == FLOOR and not is_equal_approx(height[z][x], base):
				return false
			if not is_nan(overpass[z][x]):
				return false
	return true


## 塔楼：本层的墙角块，不在步道上，至少一面朝着平地（从街上看得见）
func _tower_ok(p: Vector2i, base: float) -> bool:
	if kind[p.y][p.x] != WALL or walkway[p.y][p.x] or landmark[p.y][p.x] or not _quiet(p, base):
		return false
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if kind[p.y + d.y][p.x + d.x] == FLOOR:
			return true
	return false


## 门楼：一条平地通道，顺着街前后各两块都是同高平地（直街），两侧墙角是普通墙
func _gatehouse_ok(p: Vector2i, base: float) -> bool:
	if kind[p.y][p.x] != FLOOR or arch[p.y][p.x] or span[p.y][p.x] or walkway[p.y][p.x]:
		return false
	if not _quiet(p, base):
		return false
	var along := Vector2i(1, 0) if p.x % 2 == 0 else Vector2i(0, 1)
	var perp := Vector2i(along.y, along.x)
	for k in [-2, -1, 1, 2]:
		var q: Vector2i = p + along * k
		if q.x < 1 or q.y < 1 or q.x >= n - 1 or q.y >= n - 1:
			return false
		if kind[q.y][q.x] != FLOOR or span[q.y][q.x] or doorway[q.y][q.x] or not is_equal_approx(height[q.y][q.x], base):
			return false
	for r in courtyards:
		if r.grow(1).has_point(p):
			return false
	for q: Vector2i in [p - perp, p + perp]:
		if kind[q.y][q.x] != WALL or walkway[q.y][q.x] or landmark[q.y][q.x]:
			return false
	return true


## 从 from 走到 to 要几步（按块计）；走不到返回 -1。
## 相邻开放块的高差不超过一块楼梯的升高就能走过去；飞桥两头也算连着
func path_length(from: Vector2i, to: Vector2i) -> int:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p == to:
			return dist[p]
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q := p + d
			if dist.has(q) or not is_open(q.x, q.y) or burial_plots.has(q):
				continue
			if absf(floor_height(q.x, q.y) - floor_height(p.x, p.y)) > STAIR_RISE + 0.01:
				continue
			dist[q] = dist[p] + 1
			queue.append(q)
		for q: Vector2i in jumps.get(p, []):
			if not dist.has(q):
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
			if kind[p.y][p.x] != TERRACE or arch[front.y][front.x] or cemetery.grow(5).has_point(p) or path_length(p, center) < 0:
				continue
			if kind[front.y][front.x] == WALL:
				kind[front.y][front.x] = PARAPET
				wall_top[front.y][front.x] = height[p.y][p.x] + PARAPET_H
			spawn = p
			return
