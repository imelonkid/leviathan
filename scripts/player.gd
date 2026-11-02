extends CharacterBody3D
## 第一人称漫游：WASD 移动，鼠标或方向键转视角，Shift 奔跑，空格跳，F 开关提灯。
## 滑翔：空中按住空格往上升，松开后缓缓滑翔，都消耗能量；能量在地面行走时按走过的距离积攒，
## 用完就落回地面。升空高度以最近站过的地面为准，越得过层内的墙，翻不上一层的挡土墙。
## 拍照模式（菜单里打开）下 V 切换自由飞行：穿墙、无重力，空格上升、Ctrl 下降、Shift 加速。

const WALK_SPEED := 5.0
const RUN_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const FLY_SPEED := 15.0
const FLY_FAST_SPEED := 60.0
const RISE_SPEED := 6.0          # 升空时的上升速度（米/秒）
const RISE_COST := 0.25          # 升空每秒消耗的能量（满能量 1.0，约 4 秒）
const GLIDE_FALL := 2.0          # 滑翔时最快的下落速度（米/秒）
const GLIDE_SPEED := 9.0         # 滑翔的水平速度
const GLIDE_COST := 0.05         # 滑翔每秒消耗的能量（约 20 秒）
const CHARGE_PER_M := 1.0 / 50.0 # 地面每走一米积攒的能量：走 50 米充满
const LOOK_RAMP := 0.4           # 方向键按住多久转到全速（秒）：轻点一下转得慢，方便微调
const CEILING := 13.0            # 升空的上限（相对最近站过的地面）：层内墙 8～11 米，挡土墙 12 米加 2.4 米栏杆

var settings: Node               # 鼠标灵敏度从这里读，由 main 注入
var flying := false
var last_safe := Vector3.ZERO    # 最近一次站稳的位置，掉进深渊后回到这里
var maze: Node3D                 # main 注入：判断脚下是不是地面、迷宫边界
var energy := 1.0                # 滑翔能量 0～1，能量条读它
var gliding := false             # 这次离地后升过空：松开空格进入滑翔，落地结束
var rising := false
var ground_y := 0.0              # 所在层的地面高度（墙顶上不更新），升空上限以它为准
var space_was_down := false
var space_held := 0.0            # 空格按住了多久：从地面一直按着，跳起后接着升空
var look_held := 0.0             # 方向键按住了多久

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var head: Node3D
var cam: Camera3D
var lamp: SpotLight3D
var bob_t := 0.0
var collider: CollisionShape3D


func _ready() -> void:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	collider = CollisionShape3D.new()
	collider.shape = cap
	collider.position.y = 0.9
	add_child(collider)

	head = Node3D.new()
	head.position.y = 1.65
	add_child(head)

	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 2000.0
	head.add_child(cam)
	cam.make_current()

	lamp = SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 3.0
	lamp.spot_range = 30.0
	lamp.spot_angle = 26.0
	lamp.shadow_enabled = true
	lamp.visible = false
	cam.add_child(lamp)
	lamp.position = Vector3(0.25, -0.2, 0)

	floor_snap_length = 0.5          # 下楼梯时贴着坡面走，不会一蹦一蹦
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var sens: float = settings.get_value("mouse_sens")
		rotate_y(-mm.relative.x * sens)
		head.rotate_x(-mm.relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_F:
			lamp.visible = not lamp.visible
		elif key == KEY_V and settings.get_value("photo_mode"):
			set_flying(not flying)


## 方向键转视角：左右转身，上下抬头低头；速度在菜单里调
func _process(delta: float) -> void:
	var turn := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		turn.x = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
		turn.y = float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))
	if turn == Vector2.ZERO:
		look_held = 0.0
		return
	look_held += delta
	var speed: float = deg_to_rad(settings.get_value("key_look_speed")) * minf(0.3 + look_held / LOOK_RAMP, 1.0)
	rotate_y(-turn.x * speed * delta)
	head.rotate_x(turn.y * speed * 0.7 * delta)
	head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func set_flying(on: bool) -> void:
	flying = on
	collider.disabled = on
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	# 菜单打开时（鼠标未锁定）不响应移动
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if active:
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0

	if flying and not settings.get_value("photo_mode"):
		set_flying(false)
	if flying:
		_fly(input, active)
		return

	var space := active and Input.is_physical_key_pressed(KEY_SPACE)
	var pressed := space and not space_was_down
	space_was_down = space
	space_held = space_held + delta if space else 0.0

	if is_on_floor():
		gliding = false
		rising = false
		if space:
			velocity.y = JUMP_VELOCITY
	else:
		# 空中按下空格（或起跳后一直按着）：升空；按住就一直升，松开转入滑翔
		if (pressed or (space and space_held > 0.25)) and not rising and energy > 0.0:
			gliding = true
			rising = true
		if not space:
			rising = false
		if energy <= 0.0:
			gliding = false
			rising = false
		if rising:
			energy = maxf(energy - RISE_COST * delta, 0.0)
			# 接近上限时提前减速，停在上限处悬着
			var room := ground_y + CEILING - global_position.y
			var target := RISE_SPEED * clampf(room / 2.0, 0.0, 1.0)
			velocity.y = move_toward(velocity.y, target, 20.0 * delta)
		elif gliding:
			energy = maxf(energy - GLIDE_COST * delta, 0.0)
			velocity.y = maxf(velocity.y - gravity * delta, -GLIDE_FALL)
		else:
			velocity.y -= gravity * delta

	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := RUN_SPEED if active and Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var accel := 10.0 if is_on_floor() else 2.0
	if gliding:
		speed = GLIDE_SPEED
		accel = 3.0
	velocity.x = lerpf(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, accel * delta)
	var before := global_position
	move_and_slide()
	_keep_inside()

	if is_on_floor():
		last_safe = global_position
		var tier := _tier_floor()
		if not is_nan(tier):
			ground_y = tier
		# 在地面走动时积攒能量（按水平走过的距离）
		var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
		energy = minf(energy + moved * CHARGE_PER_M, 1.0)

	# 轻微的步伐晃动
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal > 0.5:
		bob_t += delta * horizontal * 1.4
	cam.position.y = sin(bob_t) * 0.04


## 脚下所在层的地面高度；站在墙顶上返回 NAN（不更新升空上限）
func _tier_floor() -> float:
	if maze == null:
		return global_position.y
	var b: Vector2 = maze.world_to_block(global_position)
	return maze.gen.tier_floor(int(floor(b.x)), int(floor(b.y)))


## 不让滑翔越过最外圈围墙
func _keep_inside() -> void:
	if maze == null:
		return
	var limit: float = maze.n * maze.block / 2.0 - maze.block
	var p := global_position
	if absf(p.x) > limit or absf(p.z) > limit:
		global_position = Vector3(clampf(p.x, -limit, limit), p.y, clampf(p.z, -limit, limit))
		if absf(p.x) > limit:
			velocity.x = 0.0
		if absf(p.z) > limit:
			velocity.z = 0.0


## 飞行：沿视线方向移动，不受碰撞和重力影响
func _fly(input: Vector2, active: bool) -> void:
	var look := cam.global_transform.basis
	var dir := look * Vector3(input.x, 0, input.y)
	if active and Input.is_physical_key_pressed(KEY_SPACE):
		dir.y += 1.0
	if active and Input.is_physical_key_pressed(KEY_CTRL):
		dir.y -= 1.0
	var speed := FLY_FAST_SPEED if active and Input.is_physical_key_pressed(KEY_SHIFT) else FLY_SPEED
	velocity = dir.normalized() * speed
	move_and_slide()
