extends SceneTree
## 默认用明确的测试夹具，--require-private 验证本机授权模型；--benchmark 另做真实渲染采样。
const Main = preload("res://main.tscn")
const Hanged = preload("res://scripts/hanged_one.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func fixture() -> PackedScene:
	var node := Node3D.new()
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = Hanged.BODY_HEIGHT
	capsule.radius = Hanged.BODY_RADIUS
	mesh.mesh = capsule
	mesh.position = Hanged.BODY_CENTER
	node.add_child(mesh)
	mesh.owner = node
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	return packed


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var private := "--require-private" in args
	if "--public" in args:
		check(not ResourceLoader.exists(Hanged.MODEL_PATH), "Public export contains private licensed model")
		print("hanged_one public exclusion: ", failures == 0)
		quit(failures)
		return
	check(not private or ResourceLoader.exists(Hanged.MODEL_PATH), "Missing required local model")
	if failures > 0:
		quit(1)
		return
	var model: PackedScene = load(Hanged.MODEL_PATH) if private else fixture()
	var main := Main.instantiate()
	root.add_child(main)
	main.set_process(false)
	for node: Node in main.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	Engine.max_fps = 0
	main.player.cam.top_level = true
	await physics_frame
	await physics_frame
	if private:
		var initial: Node3D = main.maze.graves.hanged_one
		initial.clock = 1
		initial._physics_process(1)
		initial.set_physics_process(false)
		check(not initial.loading and initial.figures.size() == 3, "Normal threaded loading did not install figures")
		check(initial.find_children("*", "Node", true, false).size() + 1 == 16, "Unexpected runtime node cost")
	var triangles := 0
	if private:
		var kit := model.instantiate()
		var parts := kit.find_children("*", "MeshInstance3D", true, false)
		check(parts.size() == 1, "Model should have one shared mesh")
		for part: MeshInstance3D in parts:
			check(part.mesh.get_surface_count() == 1, "Model should have one material")
			check(part.transform.is_equal_approx(Transform3D.IDENTITY), "Model origin is not its suspension point")
			var box: AABB = part.mesh.get_aabb()
			check(box.end.y < 0.01 and box.position.y > -2.7 and box.position.y < -2.5, "Model hangs above pivot or lost adult scale")
			triangles += part.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
			var material: StandardMaterial3D = part.mesh.surface_get_material(0)
			for texture: Texture2D in [material.albedo_texture, material.normal_texture, material.roughness_texture]:
				check(texture != null and texture.get_width() == 1024 and texture.get_height() == 1024, "Model lost optimized PBR textures")
		check(triangles <= 12000, "Model exceeds triangle budget")
		check(kit.find_children("*", "Skeleton3D", true, false).is_empty(), "Unexpected runtime skeleton")
		kit.free()
	var figures: Node3D
	for seed_value: int in [666, 1234, 9876, 0, 1, 42, 2026, 65535]:
		var previous: Node3D = main.maze.graves.hanged_one
		main.maze.seed_value = seed_value
		main.maze.build()
		for node: Node in main.maze.find_children("*", "Node", true, false):
			node.set_process(false)
			node.set_physics_process(false)
		await physics_frame
		await physics_frame
		check(not is_instance_valid(previous), "Hanged figures survived map replacement")
		figures = main.maze.graves.hanged_one
		figures.install(model)
		figures.set_physics_process(false)
		await physics_frame
		await physics_frame
		check(figures.figures.size() == 3, "Missing clear branch positions, seed %d: %d" % [seed_value, figures.figures.size()])
		# 墓区开放格的通路保持 2.4 米宽、3.4 米高。
		var lane := PhysicsShapeQueryParameters3D.new()
		var clearance := BoxShape3D.new()
		clearance.size = Vector3(2.4, 3.4, 2.4)
		lane.shape = clearance
		lane.collision_mask = Hanged.COLLISION_LAYER
		var cemetery: Rect2i = main.maze.gen.cemetery
		for y in range(cemetery.position.y, cemetery.end.y):
			for x in range(cemetery.position.x, cemetery.end.x):
				if Vector2i(x, y) in main.maze.gen.burial_plots:
					continue
				lane.transform.origin = main.maze.block_center(x, y) + Vector3.UP * (main.maze.gen.height[y][x] + 1.72)
				check(main.get_world_3d().direct_space_state.intersect_shape(lane, 1).is_empty(), "Figure blocked cemetery lane")
		for figure: Dictionary in figures.figures:
			var body: AnimatableBody3D = figure.body
			check(body.collision_layer & 1 != 0, "Figure has no player collision")
			for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
				check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Figure added shadows")
			var anchor: Vector3 = figure.anchor
			var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(anchor - Vector3.UP * 0.03, anchor + Vector3.UP * 0.15, 2))
			check(not hit.is_empty() and hit.collider in main.maze.graves.trees, "Suspension point floats off branch")
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.get_child(1).shape
			query.collision_mask = 1
			query.exclude = [body.get_rid()]
			var resting_head: Vector3 = anchor + figure.basis * Hanged.HEAD_POINT
			var head_swing := 0.0
			for step in 180:
				figures.advance(figure, 0.1, false)
				check(body.global_position.is_equal_approx(anchor), "Suspension point moved")
				head_swing = maxf(head_swing, (body.global_transform * Hanged.HEAD_POINT).distance_to(resting_head))
				query.transform = body.global_transform * body.get_child(1).transform
				check(main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Swing body intersects wall/tree/grave")
			check(head_swing > 0.075 and head_swing < 0.095, "Head swing should be noticeable but stay within clearance")
			var pose := body.global_transform
			var phase: float = figure.phase
			for frame in 30:
				figures.advance(figure, Hanged.STEP, true)
			check(figure.phase == phase and body.global_transform == pose and figure.frozen, "Deadlight failed to freeze exact pose")
			figures.advance(figure, Hanged.STEP, false)
			check(not figure.frozen and figure.phase != phase, "Sway did not resume")
			check((body.global_transform * Hanged.HEAD_POINT).distance_to(pose * Hanged.HEAD_POINT) < 0.005, "Resume snapped to new pose")
		# 实际物理世界中，用玩家尺寸胶囊扫过实体。
		await physics_frame
		for figure: Dictionary in figures.figures:
			var query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.height = 1.8
			capsule.radius = 0.4
			query.shape = capsule
			query.collision_mask = Hanged.COLLISION_LAYER
			query.transform.origin = figure.anchor + Hanged.BODY_CENTER + Vector3.RIGHT * 2
			query.motion = Vector3.LEFT * 4
			check(main.get_world_3d().direct_space_state.cast_motion(query)[0] < 1, "Player-sized body passed through figure")
		if seed_value == 666 and not figures.figures.is_empty():
			await integration(main, figures)
			if "--benchmark" in args:
				await benchmark(main, figures, triangles)
	print("hanged_one: ", "PASS" if failures == 0 else "FAIL", "; private=", private, "; triangles=", triangles)
	main.drone.playback = null
	main.queue_free()
	await physics_frame
	await process_frame
	quit(0 if failures == 0 else 1)


func integration(main: Node3D, figures: Node3D) -> void:
	var figure: Dictionary = figures.figures[0]
	var phase: float = figure.phase
	main.player.cam.global_position = figure.anchor
	# 让真实死光的轴线穿过实体，而不是 mock beam_exposure。
	var beam: Node3D = main.lev.beams[0]
	var old := beam.global_basis
	var direction: Vector3 = (figure.anchor + Hanged.BODY_CENTER - main.lev.beam_pivot.global_position).normalized()
	beam.global_basis = Basis.looking_at(direction, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
	check(main.lev.beam_exposure(figure.anchor + Hanged.BODY_CENTER) > 0.9, "Test beam missed figure")
	figures.clock = 1
	main.settings.has_focus = true
	figures._physics_process(Hanged.STEP)
	check(figure.phase == phase and figure.frozen, "Real deadlight did not freeze sway")
	var other_basis: Basis = main.lev.beams[1].global_basis
	beam.global_basis = Basis.looking_at(-direction, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
	main.lev.beams[1].global_basis = beam.global_basis
	figures.clock = 1
	figures._physics_process(Hanged.STEP)
	check(figure.phase != phase and not figure.frozen, "Sway did not resume when real beam left")
	phase = figure.phase
	# 光锥边缘仅扫到头部时也要冻结；避免将世界坐标整体放大后取样。
	var origin: Vector3 = main.lev.beam_pivot.global_position
	var head_position: Vector3 = figure.body.global_transform * Hanged.HEAD_POINT
	main.lev.beam_pivot.global_position = head_position + Vector3(50, -8, 0)
	beam.global_basis = Basis.looking_at(Vector3.LEFT, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
	main.lev.beams[1].global_basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2)
	check(main.lev.beam_exposure(head_position) > 0.01 and main.lev.beam_exposure(figure.body.global_transform * Hanged.BODY_CENTER) < 0.01 and main.lev.beam_exposure(figure.anchor) < 0.01, "Test beam should expose only head")
	figures.clock = 1
	figures._physics_process(Hanged.STEP)
	check(figure.phase == phase and figure.frozen, "Head-only deadlight did not freeze sway")
	main.lev.beam_pivot.global_position = origin
	beam.global_basis = old
	main.lev.beams[1].global_basis = other_basis
	# 后台和远处仅休眠，不隐藏或删除实体。
	main.settings.has_focus = false
	figures.clock = 1
	figures._physics_process(1)
	check(figure.phase == phase and figure.body.visible, "Background sleep changed pose/visibility")
	main.settings.has_focus = true
	main.player.cam.global_position = Vector3.ONE * 10000
	figures.clock = 1
	figures._physics_process(1)
	check(figure.phase == phase and figure.body.visible and figures.interval == 1, "Distant figure moved or disappeared")


func median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]


func benchmark(main: Node3D, figures: Node3D, triangles: int) -> void:
	main.settings.values.fullscreen = false
	main.settings.values.vsync = false
	main.settings.values.frame_limit = 3
	main.settings.apply()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	Engine.max_fps = 0
	for particles: GPUParticles3D in main.find_children("*", "GPUParticles3D", true, false):
		particles.visible = false
	var anchor: Vector3 = figures.figures[0].anchor
	var out: Vector3 = figures.figures[0].basis * Vector3(Hanged.BRANCH.x, 0, Hanged.BRANCH.z).normalized()
	main.player.cam.global_position = anchor + out * 3.7 + Vector3.DOWN * 1.25
	main.player.cam.look_at(anchor + Hanged.BODY_CENTER)
	main.player.lamp.visible = true
	var times := {"off": [], "on": []}
	var draws := {"off": [], "on": []}
	for mode: String in ["off", "on", "on", "off"]:
		figures.visible = mode == "on"
		for frame in 20:
			await process_frame
			await RenderingServer.frame_post_draw
		for frame in 60:
			var begin := Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			times[mode].append(float(Time.get_ticks_usec() - begin) / 1000)
			draws[mode].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	figures.visible = true
	var cpu := []
	for i in 5000:
		var begin := Time.get_ticks_usec()
		for figure: Dictionary in figures.figures:
			figures.advance(figure, Hanged.STEP, false)
		cpu.append(float(Time.get_ticks_usec() - begin) / 1000)
	cpu.sort()
	var update_cpu := []
	for i in 5000:
		figures.clock = 1
		var begin := Time.get_ticks_usec()
		figures._physics_process(Hanged.STEP)
		update_cpu.append(float(Time.get_ticks_usec() - begin) / 1000)
	update_cpu.sort()
	var result := {"triangles_each": triangles, "figures": figures.figures.size(),
		"frame_ms_off": median(times.off), "frame_ms_on": median(times.on),
		"draw_calls_off": median(draws.off), "draw_calls_on": median(draws.on),
		"cpu_sway_median_ms": median(cpu), "cpu_sway_p95_ms": cpu[int(cpu.size() * 0.95)],
		"cpu_full_update_p95_ms": update_cpu[int(update_cpu.size() * 0.95)],
		"viewport": str(root.get_texture().get_size()), "window": str(DisplayServer.window_get_size()),
		"frame_limit": Engine.max_fps}
	DirAccess.make_dir_recursive_absolute("/tmp/leviathan-hanged-one")
	FileAccess.open("/tmp/leviathan-hanged-one/performance.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/leviathan-hanged-one/in-game.png")
	print(JSON.stringify(result))
