extends CanvasLayer
## 调试信息（F3）与俯视小地图（M）。都默认关闭，不影响沉浸感。

var maze: Node3D
var player: CharacterBody3D
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
	minimap.visible = false
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


## 右上角的俯视图：墙块、玩家位置与朝向、中心广场
class Minimap extends Control:
	const SIZE := 280.0
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
		var n: int = maze.n
		var cell := SIZE / n
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		for z in n:
			for x in n:
				if maze.grid[z][x]:
					draw_rect(Rect2(x * cell, z * cell, cell, cell), Color(0.55, 0.6, 0.65, 0.85))
		var center := Vector2(n, n) * cell / 2.0
		draw_circle(center, cell * 1.2, Color(0.6, 0.75, 1.0, 0.8))

		var player: CharacterBody3D = hud.player
		var p: Vector2 = maze.world_to_block(player.global_position) * cell
		var fwd := -player.global_transform.basis.z
		var dir := Vector2(fwd.x, fwd.z).normalized()
		draw_line(p, p + dir * cell * 2.5, Color(1, 0.8, 0.4), 2.0)
		draw_circle(p, cell * 0.6, Color(1, 0.55, 0.3))
