extends CanvasLayer
## 被守夜人抓住：你动不了，不由自主地抬头看着那盏灯；画面发灰、发糊，周围的声音被吸走，只剩耳鸣，接着一黑。
## 黑了一会儿，你在低一层的某个死胡同里醒来——躺在地上，眼前一道拖痕一直拖向巷口；画面慢慢亮回来，
## 你慢慢站起来。已经在最低一层就丢到同一层远处。没有血量、没有死亡，代价是丢了爬上来的高度。
## 醒来后守夜人隔 RESPITE 秒才会再出现。

const BloodShader = preload("res://scripts/rooms/blood.gdshader")
const DRAG := 3                  # blood.gdshader 的血迹种类：拖痕（同 props.gd 的 DRAG）
const DRAG_ASPECT := 8.0         # 拖痕方片的长 / 宽（同 props.gd 的 BLOOD_ASPECT）
const DARKEN := 0.9              # 黑下去用多久（秒）
const BLACK := 2.5               # 黑着多久
const WAKE := 3.0                # 醒过来：画面亮回来、站起来
const RESPITE := 90.0            # 醒来后多久守夜人再出现
const LIE_H := 0.35              # 躺在地上时眼睛离地多高
const STAND_H := 1.65            # 和 player.gd 里头的高度一致
const MIN_GAP := 12              # 醒来的地方离被抓的地方至少隔多少块（同一层时有用）

var player: CharacterBody3D      # main 注入
var watchman: Node3D
var maze: Node3D
var hush := 0.0                  # main 读：叠到 soundscape.hush 上（声音被吸走）
var blur := 0.0                  # main 读：叠到 beam_fx.intensity 上（发灰、发糊、四周压黑）
var rect: ColorRect
var rng := RandomNumberGenerator.new()
var t := -1.0                    # 进行到第几秒；-1 = 没在进行
var moved := false
var look_from := 0.0
var look_to := 0.0
var yaw_from := 0.0
var yaw_to := 0.0


func _ready() -> void:
	layer = 5                    # 盖住 HUD
	rng.randomize()
	rect = ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	watchman.caught.connect(start)


func start() -> void:
	if t >= 0.0:
		return
	t = 0.0
	moved = false
	player.frozen = true
	# 转过身、抬头看着那盏灯
	var eye: Vector3 = player.cam.global_position
	var lantern: Vector3 = watchman.lamp.global_position
	var flat := Vector2(lantern.x - eye.x, lantern.z - eye.z)
	look_from = player.head.rotation.x
	look_to = clampf(atan2(lantern.y - eye.y, maxf(flat.length(), 0.3)), 0.0, deg_to_rad(70))
	yaw_from = player.rotation.y
	yaw_to = atan2(-flat.x, -flat.y)


func _process(delta: float) -> void:
	if t < 0.0:
		return
	t += delta
	if t < DARKEN:
		var k := t / DARKEN
		var e := smoothstep(0.0, 1.0, minf(k * 1.6, 1.0))
		player.head.rotation.x = lerp_angle(look_from, look_to, e)
		player.rotation.y = lerp_angle(yaw_from, yaw_to, e)
		rect.color.a = k * k
		blur = k
		hush = k
	elif not moved:
		moved = true
		rect.color.a = 1.0
		_move()
	elif t < DARKEN + BLACK:
		rect.color.a = 1.0
	elif t < DARKEN + BLACK + WAKE:
		var k := (t - DARKEN - BLACK) / WAKE
		rect.color.a = 1.0 - smoothstep(0.0, 0.8, k)
		blur = 1.0 - k
		hush = 0.0               # 声音按 soundscape 自己的节奏慢慢回来
		player.head.position.y = lerpf(LIE_H, STAND_H, smoothstep(0.35, 1.0, k))
		player.head.rotation.x = lerpf(-0.15, 0.0, smoothstep(0.35, 1.0, k))
	else:
		t = -1.0
		rect.color.a = 0.0
		blur = 0.0
		player.head.position.y = STAND_H
		player.frozen = false


## 黑着的时候：把你挪到低一层的死胡同里，躺着，脸朝巷口；地上一道拖痕从你脚边拖向巷口
func _move() -> void:
	var gen: RefCounted = maze.gen
	var b: Vector2 = maze.world_to_block(player.global_position)
	var here := Vector2i(floori(b.x), floori(b.y))
	var tier_h: float = gen.TIER_H
	var floor_y := floorf(player.global_position.y / tier_h + 0.001) * tier_h
	var spot: Dictionary = watchman.paths.wake_spot(maxf(floor_y - tier_h, 0.0), here, MIN_GAP, rng)
	if spot.is_empty():
		spot = watchman.paths.wake_spot(floor_y, here, MIN_GAP, rng)
	watchman.retreat(RESPITE)
	if spot.is_empty():
		player.global_position = maze.get_spawn_position()
		return
	var blk: Vector2i = spot["block"]
	var out := Vector3(spot["out"].x, 0, spot["out"].y)
	var ground: float = gen.floor_height(blk.x, blk.y)
	var pos: Vector3 = maze.block_center(blk.x, blk.y) + Vector3(0, ground, 0) - out * 1.2
	player.set_flying(false)
	player.velocity = Vector3.ZERO
	player.global_position = pos + Vector3(0, 0.1, 0)
	player.last_safe = pos
	player.ground_y = ground
	player.look_at(pos + out, Vector3.UP)
	player.head.position.y = LIE_H
	player.head.rotation.x = -0.15
	# 拖痕：从脚边一直拖向巷口
	var q := QuadMesh.new()
	var w := 0.65
	q.size = Vector2(w, w * DRAG_ASPECT)
	var sm := ShaderMaterial.new()
	sm.shader = BloodShader
	sm.set_shader_parameter("seed", rng.randf() * 100.0)
	sm.set_shader_parameter("kind", DRAG)
	sm.set_shader_parameter("aspect", DRAG_ASPECT)
	var mark := MeshInstance3D.new()
	mark.mesh = q
	mark.material_override = sm
	var mid := pos + out * (0.4 + q.size.y / 2.0) + Vector3(0, 0.03, 0)
	mark.transform = Transform3D(Basis(Vector3.UP, atan2(-out.x, -out.z) + PI) * Basis(Vector3.RIGHT, -PI / 2.0), mid)
	maze.add_child(mark)
