extends Node3D
## 倒吊者：共享静态模型，以绳端为轴摇摆。授权资源可选，仅安装在本机。
const MODEL_PATH := "res://assets/private/hanged_one.glb"
const BRANCH := Vector3(-1.185, 5.75, -1.425)
const STEP := 1.0 / 30.0
const ACTIVE_DISTANCE := 70.0
const COLLISION_LAYER := 4
const BODY_CENTER := Vector3(0, -1.65, 0)
const HEAD_POINT := Vector3(0, -2.6, 0)
const BODY_HEIGHT := 1.98
const BODY_RADIUS := 0.29
const SWAY_X := 0.0315 # 主摆约 1.8°、横摆约 1.0°；较初版放大 50%。
const SWAY_Z := 0.018

var maze: Node3D
var trees: Array[StaticBody3D] = []
var figures: Array[Dictionary] = []
var clock := 0.0
var interval := 1.0
var loading := false


func build(supports: Array[StaticBody3D]) -> void:
	trees = supports
	if not ResourceLoader.exists(MODEL_PATH):
		print("倒吊者：未安装本地授权模型，跳过实体；见 docs/hanged-one.md。")
		set_physics_process(false)
		return
	var error := ResourceLoader.load_threaded_request(MODEL_PATH)
	if error != OK:
		push_error("倒吊者：无法加载本地模型：%s" % error_string(error))
		set_physics_process(false)
		return
	loading = true


func install(model: PackedScene) -> void:
	var space := get_world_3d().direct_space_state
	for tree: StaticBody3D in trees:
		var ideal := tree.global_transform * BRANCH
		var ray := PhysicsRayQueryParameters3D.create(ideal - Vector3.UP * 0.3, ideal + Vector3.UP * 0.3)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.collider != tree:
			push_warning("倒吊者：树枝悬挂点缺失，跳过此位置。")
			continue
		var anchor: Vector3 = hit.position
		# 身体完整摇摆包络；绳端与树枝的预期接触另行检查。
		var volume := BoxShape3D.new()
		volume.size = Vector3(0.8, 2.15, 0.8)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = volume
		query.transform = Transform3D(tree.global_basis, anchor + Vector3.DOWN * 1.65)
		query.collision_mask = 1
		if not space.intersect_shape(query, 1).is_empty():
			push_warning("倒吊者：摇摆空间受阻，跳过此位置。")
			continue
		var rope_space := BoxShape3D.new()
		rope_space.size = Vector3(0.3, 0.6, 0.3)
		query.shape = rope_space
		query.transform.origin = anchor + Vector3.DOWN * 0.5
		if not space.intersect_shape(query, 1).is_empty():
			push_warning("倒吊者：绳索空间受阻，跳过此位置。")
			continue
		var body := AnimatableBody3D.new()
		body.name = "倒吊者%d" % (figures.size() + 1)
		body.collision_layer = 1 | COLLISION_LAYER
		body.collision_mask = 0
		body.sync_to_physics = false # 本节点只在物理帧更新。
		add_child(body)
		body.global_transform = Transform3D(tree.global_basis, anchor)
		var visual := model.instantiate()
		body.add_child(visual)
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height = BODY_HEIGHT
		capsule.radius = BODY_RADIUS
		shape.shape = capsule
		shape.position = BODY_CENTER
		body.add_child(shape)
		var rope := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.24, 0.82, 0.2)
		rope.shape = box
		rope.position = Vector3(0, -0.41, 0)
		body.add_child(rope)
		figures.append({"body": body, "anchor": anchor, "basis": tree.global_basis,
			"phase": figures.size() * 2.1, "frozen": false})
	loading = false
	interval = STEP
	set_physics_process(not figures.is_empty())


func _physics_process(delta: float) -> void:
	clock += delta
	if clock < interval:
		return
	clock = 0.0
	if loading:
		var status := ResourceLoader.load_threaded_get_status(MODEL_PATH)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			install(ResourceLoader.load_threaded_get(MODEL_PATH))
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			push_error("倒吊者：本地模型导入失败：" + MODEL_PATH)
			set_physics_process(false)
		return
	var main: Node3D = maze.get_parent()
	var viewer := get_viewport().get_camera_3d()
	if viewer == null or not main.settings.has_focus:
		interval = 1.0
		return
	var nearby := false
	for figure: Dictionary in figures:
		if viewer.global_position.distance_squared_to(figure.anchor) <= ACTIVE_DISTANCE * ACTIVE_DISTANCE:
			nearby = true
			var center: Vector3 = figure.body.global_transform * BODY_CENTER
			var exposure: float = main.lev.beam_exposure(center)
			exposure = maxf(exposure, main.lev.beam_exposure(figure.anchor))
			exposure = maxf(exposure, main.lev.beam_exposure(figure.body.global_transform * HEAD_POINT))
			advance(figure, STEP, exposure > 0.01)
	interval = STEP if nearby else 1.0


func advance(figure: Dictionary, delta: float, exposed: bool) -> void:
	figure.frozen = exposed
	if exposed:
		return
	figure.phase = fmod(figure.phase + delta * 0.6, TAU)
	var tilt := Vector3(sin(figure.phase) * SWAY_X, 0, sin(figure.phase * 2.0) * SWAY_Z)
	figure.body.global_transform = Transform3D(figure.basis * Basis.from_euler(tilt), figure.anchor)
