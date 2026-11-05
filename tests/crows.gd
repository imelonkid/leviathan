extends SceneTree
## --headless --audio-driver Dummy --script res://tests/crows.gd
## 有窗口时加 -- --benchmark：固定视角 A/B 渲染采样并保存截图。
const Main = preload("res://main.tscn")
const Crows = preload("res://scripts/crows.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	root.size = Vector2i(1280, 720)
	var main := Main.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	for node: Node in main.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	Engine.max_fps = 0
	await physics_frame
	await physics_frame
	var flock: Node3D = main.maze.graves.crows
	check(flock.birds.size() == 4 and flock.perches.size() == 6, "Incorrect crow/perch budget")
	check(flock.get_child_count() == 4, "Flock exceeded three render nodes and one audio node")
	check(flock.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decorative crows added physics bodies")
	check(flock.find_children("*", "Skeleton3D", true, false).is_empty(), "Crow added a skeleton")
	var triangles := 0
	for batch: MultiMeshInstance3D in flock.batches.values():
		check(batch.multimesh.mesh.get_surface_count() == 1, "Crow mesh added material draws")
		check(batch.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Crow added shadow passes")
		check(batch.visibility_range_end == Crows.ACTIVE_DISTANCE, "Crow lost distance culling")
		if batch.name == "crow_body":
			check(batch.multimesh.mesh.get_aabb().size.x < 0.3, "Wing feathers were baked into the fixed torso")
		var colors: PackedColorArray = batch.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		check(not colors.is_empty() and colors[0].r < 0.15, "Crow exported without dark feather colors")
		triangles += batch.multimesh.mesh.surface_get_array_index_len(0) / 3 * batch.multimesh.instance_count
	check(triangles <= 5000, "Crow geometry exceeded 5000 triangles for the whole flock")
	check(Crows.Caw.get_length() < 1.0, "Crow call expanded into long background playback")
	for perch: Vector3 in flock.perches:
		var ray := PhysicsRayQueryParameters3D.create(perch + Vector3.UP * 0.1, perch - Vector3.UP * 0.2)
		check(not main.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Crow perch is not on a real branch")
	flock._set_awake(true)
	var bird: Dictionary = flock.birds[0]
	var start: Vector3 = bird.position
	flock.advance(0.1, start - Vector3.UP * 2, false, main.lev.global_position)
	check(flock.flying_count() > 0 and flock.flying_count() <= 2, "Approach did not startle one or two crows")
	var flight_time: float = bird.time
	var frozen: Vector3 = bird.position
	flock._sound(Crows.Caw, start, -18, 1)
	flock.advance(0.1, start, true, main.lev.global_position)
	check(flock.silenced and not flock.voice.playing, "Deadlight did not silence crows")
	check(bird.time == flight_time and bird.position == frozen, "Crow kept moving under deadlight")
	flock.advance(0.5, start, false, main.lev.global_position)
	check(bird.time == flight_time and flock.recovery > 0, "Crows resumed before deadlight recovery")
	flock.advance(2, start, false, main.lev.global_position)
	for frame in 240:
		flock.advance(1.0 / 30, Vector3.ONE * 1000, false, main.lev.global_position)
	check(flock.flying_count() == 0, "Crow failed to land at its reserved perch")
	for crow: Dictionary in flock.birds:
		check(crow.position.distance_to(flock.perches[crow.perch]) < 0.01, "Crow disappeared or landed in empty space")
	flock.call_timer = 0
	flock.voice.stop()
	flock.advance(0.1, Vector3.ONE * 1000, false, main.lev.global_position)
	check(flock.voice.playing and flock.voice.stream == Crows.Caw and flock.voice.bus == "World", "Missing sparse spatial crow call")
	main.player.cam.top_level = true
	main.player.cam.global_position = flock.center + Vector3.ONE * 1000
	var resting_time: float = bird.time
	flock.clock = 1
	flock._process(1)
	check(not flock.awake and not flock.voice.playing and bird.time == resting_time, "Distant crows kept animating or calling")
	main.player.cam.global_position = flock.center
	main.settings.has_focus = false
	flock.clock = 1
	flock._process(1)
	check(not flock.awake and bird.time == resting_time, "Background crows kept updating")
	main.settings.has_focus = true
	# 墓地外单独放一堵墙，飞行弧线必须拒绝穿过它。
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 20, 20)
	collider.shape = shape
	wall.add_child(collider)
	main.add_child(wall)
	wall.global_position = Vector3(1010, 5, 1000)
	await physics_frame
	await physics_frame
	check(flock._flight_route(Vector3(1000, 1, 1000), Vector3(1020, 1, 1000), Vector3.ZERO, Vector3.ZERO).is_empty(), "Crow flight crossed a wall")
	wall.queue_free()
	if "--benchmark" in OS.get_cmdline_user_args():
		await benchmark(main, flock, triangles)
	for seed_value: int in [1234, 9876, 0, 1, 42, 2026, 65535]:
		var previous := flock
		main.maze.seed_value = seed_value
		main.maze.build()
		flock = main.maze.graves.crows
		flock.set_process(false)
		await physics_frame
		await physics_frame
		check(not is_instance_valid(previous), "Previous crow flock survived map replacement")
		check(flock.birds.size() == 4, "Seed lost the crow flock")
		for perch: Vector3 in flock.perches:
			var ray := PhysicsRayQueryParameters3D.create(perch + Vector3.UP * 0.1, perch - Vector3.UP * 0.2)
			check(not main.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Seed placed a crow off the branch")
		flock.advance(0.1, flock.birds[0].position - Vector3.UP * 2, false, main.lev.global_position)
		check(flock.flying_count() > 0 and flock.flying_count() <= 2, "Seed blocked all crow escape routes")
	print("crows: ", "PASS" if failures == 0 else "FAIL", "; triangles=", triangles, "; render batches=", flock.batches.size())
	for audio_type: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	main.queue_free()
	await physics_frame
	await process_frame
	quit(0 if failures == 0 else 1)


func median(values: Array) -> float:
	values.sort()
	return values[values.size() / 2]


func benchmark(main: Node3D, flock: Node3D, triangles: int) -> void:
	# 只改测试内存，不保存玩家配置；固定窗口并关闭 GPU 天气，排除粒子显隐噪声。
	main.settings.values.fullscreen = false
	main.settings.values.vsync = false
	main.settings.values.frame_limit = 3
	main.settings.apply()
	for particles: GPUParticles3D in main.find_children("*", "GPUParticles3D", true, false):
		particles.visible = false
	DisplayServer.window_set_size(Vector2i(1280, 720))
	Engine.max_fps = 0
	main.player.cam.global_position = flock.birds[0].position + flock.perch_out[0] * 1.5 + flock.perch_out[0].cross(Vector3.UP) * 0.8 + Vector3.UP * 0.7
	main.player.cam.look_at(flock.birds[0].position + Vector3.UP * 0.2)
	main.player.lamp.visible = true
	var samples := {"off": [], "on": []}
	var draws := {}
	var primitives := {}
	var draw_samples := {"off": [], "on": []}
	var primitive_samples := {"off": [], "on": []}
	for mode: String in ["off", "on", "on", "off"]:
		flock._set_awake(mode == "on")
		for frame in 20:
			await process_frame
			await RenderingServer.frame_post_draw
		for frame in 60:
			var begin := Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			samples[mode].append(float(Time.get_ticks_usec() - begin) / 1000)
			draw_samples[mode].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			primitive_samples[mode].append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		draws[mode] = median(draw_samples[mode])
		primitives[mode] = median(primitive_samples[mode])
	flock._set_awake(true)
	var cpu: Array[float] = []
	flock.call_timer = 100000
	for i in 5000:
		var begin := Time.get_ticks_usec()
		flock.advance(Crows.REST_STEP, Vector3.ONE * 1000, false, main.lev.global_position)
		cpu.append(float(Time.get_ticks_usec() - begin) / 1000)
	cpu.sort()
	var result := {"flock_triangles": triangles, "nodes": 5, "draw_calls": draws, "render_primitives": primitives,
		"frame_median_ms_off": median(samples.off),
		"frame_median_ms_on": median(samples.on),
		"cpu_update_median_ms": median(cpu), "cpu_update_p95_ms": cpu[int(cpu.size() * 0.95)]}
	var begin := Time.get_ticks_usec()
	flock._startle(flock.birds[0], flock.birds[0].position)
	result["startle_planning_ms"] = float(Time.get_ticks_usec() - begin) / 1000
	var flight_cpu: Array[float] = []
	for frame in 30:
		begin = Time.get_ticks_usec()
		flock.advance(Crows.FLIGHT_STEP, Vector3.ONE * 1000, false, main.lev.global_position)
		flight_cpu.append(float(Time.get_ticks_usec() - begin) / 1000)
	flight_cpu.sort()
	result["cpu_flight_p95_ms"] = flight_cpu[int(flight_cpu.size() * 0.95)]
	result["window_size"] = str(DisplayServer.window_get_size())
	result["engine_frame_limit"] = Engine.max_fps
	# 复位到栖息状态拍照，之后再演示一次真实飞行。
	for crow: Dictionary in flock.birds:
		crow.position = flock.perches[crow.perch]
		crow.route = PackedVector3Array()
		crow.destination = crow.perch
	flock._draw_birds()
	DirAccess.make_dir_recursive_absolute("/tmp/leviathan-crows")
	var file := FileAccess.open("/tmp/leviathan-crows/performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result))
	main.player.cam.global_position = flock.birds[0].position + flock.perch_out[0] * 0.75 + flock.perch_out[0].cross(Vector3.UP) * 0.4 + Vector3.UP * 0.3
	main.player.cam.look_at(flock.birds[0].position + Vector3.UP * 0.17)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/leviathan-crows/perched.png")
	flock._startle(flock.birds[0], flock.birds[0].position)
	for frame in 20:
		flock.advance(Crows.FLIGHT_STEP, Vector3.ONE * 1000, false, main.lev.global_position)
	main.player.cam.global_position = flock.birds[0].position + Vector3(1.5, 0.7, -2.0)
	main.player.cam.look_at(flock.birds[0].position + Vector3.UP * 0.2)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/leviathan-crows/flying.png")
