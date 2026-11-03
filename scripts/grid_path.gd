extends RefCounted
## 怪物在迷宫网格上找路：只读 MazeGen 的网格数据，不碰节点（和 maze_gen.gd 一样与引擎无关）。
## 能走的块：开放块，但不进房间（大房间、小房间和小房间的门——门洞只有 3.2 米高，守夜人钻不进去），
## 相邻两块的地面高差不超过一块楼梯的升高；飞桥那种要跳的不算。

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var gen: RefCounted
var blocked := {}                # 不让进的块（房间里、小房间的门）


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
