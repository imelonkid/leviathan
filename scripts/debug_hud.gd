extends CanvasLayer
## 调试信息（F3，默认关闭）与俯视小地图（M，默认显示，迷宫太大，没有它完全没头绪）。

var maze: Node3D
var player: CharacterBody3D
var watchman: Node3D             # 守夜人：只在调试信息打开时画在小地图上，平时不剧透
var info: Label
var minimap: Control


func _ready() -> void:
	info = Label.new()
	info.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 4)
	info.add_theme_font_size_override("font_size", 15)
	info.position = Vector2(24, 60)
	info.visible = false
	add_child(info)

	minimap = Minimap.new()
	minimap.hud = self
	minimap.visible = true
	add_child(minimap)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F3:
				info.visible = not info.visible
			KEY_M:
				minimap.visible = not minimap.visible


func _process(_delta: float) -> void:
	if info.visible:
		var p := player.global_position
		info.text = "FPS %d  ·  绘制调用 %d  ·  图元 %dk\n位置 (%.1f, %.1f, %.1f)  ·  种子 %d%s" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			p.x, p.y, p.z, maze.seed_value,
			"  ·  飞行模式" if player.flying else "",
		]
	if minimap.visible:
		minimap.queue_redraw()


## 右上角的俯视图：地面按高度由暗到亮，楼梯橙色，桥和平台浅蓝，观景台褐色，房间暗红，深渊全黑
class Minimap extends Control:
	const SIZE := 280.0
	const MazeGen = preload("res://scripts/maze_gen.gd")
	var hud: CanvasLayer

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor_left = 1.0
		anchor_right = 1.0
		offset_left = -SIZE - 24.0
		offset_right = -24.0
		offset_top = 24.0
		offset_bottom = 24.0 + SIZE

	func _draw() -> void:
		var maze: Node3D = hud.maze
		var gen: RefCounted = maze.gen
		var n: int = maze.n
		var cell := SIZE / n
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		for z in n:
			for x in n:
				var color: Color
				match gen.kind[z][x]:
					MazeGen.WALL:
						color = Color(0.55, 0.6, 0.65, 0.9)
						if gen.arcade[z][x]:
							color = Color(0.7, 0.66, 0.55, 0.9)
					MazeGen.PARAPET:
						color = Color(0.4, 0.42, 0.45, 0.9)
					MazeGen.TERRACE:
						color = Color(0.45, 0.38, 0.32, 0.9)
					MazeGen.FLOOR:
						var t: float = gen.height[z][x] / (MazeGen.TOP_TIER * MazeGen.TIER_H)
						color = Color(0.1, 0.12, 0.14).lerp(Color(0.3, 0.34, 0.38), t)
					MazeGen.STAIR:
						color = Color(0.75, 0.5, 0.25)
					MazeGen.BRIDGE, MazeGen.PLATFORM:
						color = Color(0.5, 0.7, 0.9)
					_:
						continue
				if gen.walkway[z][x]:
					color = Color(0.85, 0.78, 0.55, 0.95)   # 墙顶步道（含跨过通道的桥面）
				draw_rect(Rect2(x * cell, z * cell, cell, cell), color)
		# 地标：塔楼和门楼画成亮白的小方块，方便认路
		for t: Dictionary in gen.towers:
			var b: Vector2i = t["block"]
			draw_rect(Rect2(Vector2(b) * cell - Vector2(cell, cell) * 0.5, Vector2(cell, cell) * 2.0), Color(0.95, 0.92, 0.85))
		for g: Dictionary in gen.gatehouses:
			var b: Vector2i = g["block"]
			draw_rect(Rect2(Vector2(b) * cell - Vector2(cell, cell) * 0.5, Vector2(cell, cell) * 2.0), Color(0.85, 0.8, 0.95))
		# 小楼：沿墙一条三块长的白条
		for hs: Dictionary in gen.houses:
			var b := Vector2(hs["block"]) + Vector2(0.5, 0.5)
			var al := Vector2(hs["along"])
			draw_line((b - al * 1.5) * cell, (b + al * 1.5) * cell, Color(0.95, 0.92, 0.85), cell * 1.4)
		# 房间：暗红色的方块
		for room: Dictionary in gen.rooms:
			var r: Rect2i = room["rect"]
			draw_rect(Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell), Color(0.45, 0.16, 0.12, 0.95))
		# 飞桥：压在下层街道上面的一条细线，悬空楼梯那段是楼梯色
		for o: Dictionary in gen.overpasses:
			var a := (Vector2(o["root"]) + Vector2(0.5, 0.5)) * cell
			var f := Vector2(o["out"])
			var level: float = o["level"] + 0.5
			draw_line(a, a + f * level * cell, Color(0.85, 0.78, 0.55, 0.95), cell * 0.6)
			if o["stair"] > 0:
				draw_line(a + f * level * cell, a + f * (level + o["stair"]) * cell, Color(0.75, 0.5, 0.25), cell * 0.6)
		for pb: Dictionary in gen.plaza_bridges:
			var a := (Vector2(pb["start"]) + Vector2(0.5, 0.5)) * cell
			draw_line(a, a + Vector2(pb["dir"]) * (pb["span"] + 1) * cell, Color(0.85, 0.78, 0.55, 0.95), cell * 0.6)
			var at := (Vector2(pb["stair_at"]) + Vector2(0.5, 0.5)) * cell
			draw_line(at, at + Vector2(pb["stair_dir"]) * MazeGen.PLAZA_STAIR_BLOCKS * cell, Color(0.75, 0.5, 0.25), cell * 0.6)
		var center := Vector2(n, n) * cell / 2.0
		draw_circle(center, cell * 1.2, Color(0.6, 0.75, 1.0, 0.8))

		var player: CharacterBody3D = hud.player
		var p: Vector2 = maze.world_to_block(player.global_position) * cell
		var fwd := -player.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		draw_line(p, p + dir * cell * 2.5, Color(1, 0.8, 0.4), 2.0)
		draw_circle(p, cell * 0.6, Color(1, 0.55, 0.3))
		var w: Node3D = hud.watchman
		if w and w.visible and hud.info.visible:
			var wp: Vector2 = maze.world_to_block(w.global_position) * cell
			var wf := w.global_transform.basis.z
			draw_line(wp, wp + Vector2(wf.x, wf.z).normalized() * cell * 2.5, Color(0.7, 0.85, 1.0), 2.0)
			draw_circle(wp, cell * 0.6, Color(0.75, 0.87, 1.0))
