extends RefCounted
## 怪物在迷宫网格上找路：只读 MazeGen 的网格数据，不碰节点（和 maze_gen.gd 一样与引擎无关）。
## 能走的块：开放块，但不进房间（大房间、小房间和小房间的门——门洞只有 3.2 米高，守夜人钻不进去），
## 相邻两块的地面高差不超过一块楼梯的升高；飞桥那种要跳的不算。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var gen: RefCounted
var blocked := {}                # 不让进的块（房间里、小房间的门）
var connected := {}              # 从出生点走得到的块（找醒来的地方用，第一次用到时才算）


func _init(g: RefCounted) -> void:
	gen = g
	for r: Dictionary in gen.rooms:
		var rect: Rect2i = r["rect"]
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				blocked[Vector2i(x, z)] = true
		for d: Vector2i in r.get("doors", []):
			blocked[d] = true
	for z in gen.n:
		for x in gen.n:
			if gen.doorway[z][x]:
				blocked[Vector2i(x, z)] = true


func walkable(p: Vector2i) -> bool:
	return gen.is_open(p.x, p.y) and not blocked.has(p)


func _step_ok(p: Vector2i, q: Vector2i) -> bool:
	return walkable(q) and absf(gen.floor_height(q.x, q.y) - gen.floor_height(p.x, p.y)) <= gen.STAIR_RISE + 0.01


## 从 from 出发、最多走 max_steps 步能到的块：块 → 步数
func reach(from: Vector2i, max_steps: int) -> Dictionary:
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if dist[p] >= max_steps:
			continue
		for d in DIRS:
			var q := p + d
			if not dist.has(q) and _step_ok(p, q):
				dist[q] = dist[p] + 1
				queue.append(q)
	return dist


## from 到 to 的一条最短路（含两头）；走不到返回空
func path(from: Vector2i, to: Vector2i, max_steps := 60) -> Array[Vector2i]:
	var prev := {from: from}
	var steps := {from: 0}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p == to:
			var out: Array[Vector2i] = [p]
			while p != from:
				p = prev[p]
				out.push_front(p)
			return out
		if steps[p] >= max_steps:
			continue
		for d in DIRS:
			var q := p + d
			if not prev.has(q) and _step_ok(p, q):
				prev[q] = p
				steps[q] = steps[p] + 1
				queue.append(q)
	return []


## p 本身能走就是 p，否则在 radius 块以内找一块离它最近、能走的；都没有返回 (-1, -1)
func nearest(p: Vector2i, radius := 2) -> Vector2i:
	if walkable(p):
		return p
	var best := Vector2i(-1, -1)
	var best_d := INF
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var q := p + Vector2i(dx, dz)
			var d := Vector2(dx, dz).length()
			if d < best_d and walkable(q):
				best = q
				best_d = d
	return best


## 被抓后醒来的地方：地面高度为 floor_y 的那一层里、从出生点走得到的普通地面块，离 avoid 至少 min_gap 块；
## 优先死胡同（三面是墙）。返回 {block, out: 朝开口的方向}；找不到返回空
func wake_spot(floor_y: float, avoid: Vector2i, min_gap: int, rng: RandomNumberGenerator) -> Dictionary:
	if connected.is_empty():
		connected = reach(gen.spawn, 100000)
	var ends: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for p: Vector2i in connected:
		if gen.kind[p.y][p.x] != gen.FLOOR or absf(gen.height[p.y][p.x] - floor_y) > 0.5:
			continue
		if absi(p.x - avoid.x) + absi(p.y - avoid.y) < min_gap:
			continue
		var exits: Array[Vector2i] = []
		for d in DIRS:
			if _step_ok(p, p + d):
				exits.append(d)
		if exits.is_empty():
			continue
		var spot := {"block": p, "out": exits[rng.randi() % exits.size()]}
		(ends if exits.size() == 1 else others).append(spot)
	var pool := ends if not ends.is_empty() else others
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else {}
