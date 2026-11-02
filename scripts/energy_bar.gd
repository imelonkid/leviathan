extends CanvasLayer
## 滑翔能量条：屏幕下方正中一条细细的黄铜色条。满能量、没在用时慢慢淡出，用的时候才出现。

const WIDTH := 260.0
const HEIGHT := 5.0
const COLOR := Color(0.78, 0.6, 0.32)
const LOW_COLOR := Color(0.75, 0.22, 0.15)   # 能量见底时转红

var player: CharacterBody3D
var root: Control
var fill: ColorRect
var idle := 0.0                  # 满能量且没在空中多久了


func _ready() -> void:
	layer = 1
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -WIDTH / 2.0
	root.offset_right = WIDTH / 2.0
	root.offset_top = -48.0
	root.offset_bottom = -48.0 + HEIGHT
	add_child(root)

	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.45)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)

	fill = ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(WIDTH, HEIGHT)
	root.add_child(fill)


func _process(delta: float) -> void:
	var e: float = player.energy
	fill.size.x = WIDTH * e
	fill.color = LOW_COLOR.lerp(COLOR, smoothstep(0.1, 0.3, e))
	var busy: bool = e < 0.999 or player.gliding or player.flying
	idle = 0.0 if busy else idle + delta
	# 用的时候立刻出现；满了以后停 1.5 秒再慢慢淡出
	var target := 0.0 if idle > 1.5 or player.flying else 1.0
	root.modulate.a = move_toward(root.modulate.a, target, delta * (6.0 if target > 0.0 else 1.0))
