extends CharacterBody3D
## 第一人称漫游：WASD 移动，Shift 奔跑，空格跳，F 开关提灯。
## V 切换飞行模式（调试用）：穿墙、无重力，空格上升、Ctrl 下降。

const WALK_SPEED := 5.0
const RUN_SPEED := 10.0
const JUMP_VELOCITY := 5.0
const FLY_SPEED := 15.0
const FLY_FAST_SPEED := 60.0

var settings: Node               # 鼠标灵敏度从这里读，由 main 注入
var flying := false
var last_safe := Vector3.ZERO    # 最近一次站稳的位置，掉进深渊后回到这里

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
		elif key == KEY_V:
			set_flying(not flying)


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

	if flying:
		_fly(input, active)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif active and Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := RUN_SPEED if active and Input.is_physical_key_pressed(KEY_SHIFT) else WALK_SPEED
	var accel := 10.0 if is_on_floor() else 2.0
	velocity.x = lerpf(velocity.x, dir.x * speed, accel * delta)
	velocity.z = lerpf(velocity.z, dir.z * speed, accel * delta)
	move_and_slide()

	if is_on_floor():
		last_safe = global_position

	# 轻微的步伐晃动
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal > 0.5:
		bob_t += delta * horizontal * 1.4
	cam.position.y = sin(bob_t) * 0.04


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
