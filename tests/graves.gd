extends SceneTree
## Godot --headless --audio-driver Dummy --path . --script res://tests/graves.gd
## -- --screenshots 可在有渲染窗口时输出实际场景截图，音频仍用 Dummy。
const Main = preload("res://main.tscn")
const Graves = preload("res://scripts/graves.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func lane_query(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(Graves.CLEAR_WIDTH, 3.4, Graves.CLEAR_WIDTH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = at + Vector3.UP * 1.72
	query.collision_mask = Graves.COLLISION_LAYER
	query.margin = 0.01
	return query


func signature(sites: Array[Dictionary]) -> Array:
	var out := []
	for site: Dictionary in sites:
		out.append([site.kind, site.block, site.wall, site.transform])
	return out


func run() -> void:
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
	var maze: Node3D = main.maze
	var seeds := [666, 1234, 9876, 0, 1, 42, 2026, 65535]
	if "--screenshots" in OS.get_cmdline_user_args():
		seeds = [666]
	for seed_value: int in seeds:
		var previous: Node3D = maze.graves
		maze.seed_value = seed_value
		maze.build()
		maze.set_process(false)
		maze.graves.set_process(false)
		await physics_frame
		await physics_frame
		check(not is_instance_valid(previous), "Previous grave nodes survived maze replacement")
		var graves: Node3D = maze.graves
		check(graves.meshes.size() == 3 and graves.shapes.size() == 3, "Missing grave model or collision resource")
		var counts := {"grave_mound": 0, "grave_open": 0, "grave_wall": 0}
		for site: Dictionary in graves.sites:
			counts[site.kind] += 1
			check(site.body.collision_layer & 1 != 0, "Grave does not collide with player/world layer")
			var cell_center: Vector3 = maze.block_center(site.block.x, site.block.y)
			var cell := Rect2(Vector2(cell_center.x, cell_center.z) - Vector2.ONE * maze.block / 2, Vector2.ONE * maze.block)
			check(cell.encloses(graves.footprint(site.kind, site.transform)), "Grave protrudes into neighboring cell")
			check(site.transform.origin.distance_to(maze.get_spawn_position()) >= Graves.SPAWN_GAP - 0.1, "Grave crowded spawn area")
			check(maze.gen.height[site.block.y][site.block.x] < maze.gen.TOP_TIER * maze.gen.TIER_H, "Grave intruded into giant patrol area")
			var start := Vector3(0, 0.15, 1.6)
			var end := Vector3(0, 0.15, 0.0)
			if site.kind == "grave_mound":
				start = Vector3(0.4, 0.55, 0.52)
				end = Vector3(-1.4, 0.55, 0.52)
			elif site.kind == "grave_wall":
				start = Vector3(0, 1.2, 1.6)
				end = Vector3(0, 1.2, -0.1)
			var ray := PhysicsRayQueryParameters3D.create(site.transform * start, site.transform * end)
			ray.collision_mask = Graves.COLLISION_LAYER
			var hit := graves.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider == site.body, "Grave's visible solid has no physical collision: " + site.kind)
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.4
			capsule.height = 1.8
			var approach := PhysicsShapeQueryParameters3D.new()
			approach.shape = capsule
			approach.collision_mask = Graves.COLLISION_LAYER
			var from := Vector3(2.3, 0.95, 0.52) if site.kind == "grave_mound" else Vector3(0, 0.95, 1.8)
			var to := Vector3(-1.5, 0.95, 0.52) if site.kind == "grave_mound" else Vector3(0, 0.95, -0.1)
			approach.transform.origin = site.transform * from
			approach.motion = site.transform.basis * (to - from)
			check(graves.get_world_3d().direct_space_state.cast_motion(approach)[0] < 1.0, "Player-sized body passed through grave: " + site.kind)
		for i in Graves.KINDS.size():
			var kind: String = Graves.KINDS[i]
			check(counts[kind] > 0 and counts[kind] <= Graves.QUOTAS[i], "Missing or excessive graves: %s seed %d" % [kind, seed_value])
			var varied := false
			var mesh: Mesh = graves.meshes[kind]
			for surface in mesh.get_surface_count():
				var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				check(not colors.is_empty(), "Grave lost weathering vertex colors")
				for color: Color in colors:
					varied = varied or color.r < 0.8
				check(mesh.surface_get_material(surface).vertex_color_use_as_albedo, "Grave material ignored weathering")
			check(varied, "Grave weathering exported as plain white")
		# 验证真实碰撞，而非只重算摆放矩形：每个开放格中心和每条邻接边保留 2.4 米宽体积。
		var space := graves.get_world_3d().direct_space_state
		var connections := 0
		for z in maze.gen.n:
			for x in maze.gen.n:
				if not maze.gen.is_open(x, z):
					continue
				var a: Vector3 = maze.block_center(x, z) + Vector3.UP * maze.gen.floor_height(x, z)
				var query := lane_query(a)
				check(space.intersect_shape(query, 1).is_empty(), "Grave blocked a walkable cell center")
				for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var q := Vector2i(x, z) + dir
					if not maze.gen.is_open(q.x, q.y) or absf(maze.gen.floor_height(q.x, q.y) - a.y) > maze.gen.STAIR_RISE + 0.01:
						continue
					var b: Vector3 = maze.block_center(q.x, q.y) + Vector3.UP * maze.gen.floor_height(q.x, q.y)
					query.motion = b - a
					check(space.cast_motion(query)[0] >= 1.0, "Grave narrowed or blocked an existing connection")
					connections += 1
		seed(17)
		var first: Array[Dictionary] = graves.plan()
		seed(8888)
		check(signature(first) == signature(graves.plan()) and signature(first) == signature(graves.sites), "Grave layout depended on global RNG or changed on reload")
		print("seed ", seed_value, ": ", counts, "; clear connections=", connections)
		if "--screenshots" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute("/tmp/leviathan-graves")
			var camera: Camera3D = main.player.cam
			camera.top_level = true
			main.player.lamp.visible = true
			for kind: String in Graves.KINDS:
				for site: Dictionary in graves.sites:
					if site.kind != kind:
						continue
					camera.global_position = site.transform * Vector3(2.0, 1.9, 3.8)
					camera.look_at(site.transform * Vector3(0, 1.1 if kind == "grave_wall" else 0.5, 0.5))
					for frame in 6:
						await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("/tmp/leviathan-graves/" + kind + "_ingame.png")
					break
	# 靠近会停声，远处不会每具石棺都同时发声。
	var graves: Node3D = maze.graves
	var crypt: Dictionary = {}
	for site: Dictionary in graves.sites:
		if site.kind == "grave_wall":
			crypt = site
			break
	assert(not crypt.is_empty(), "Missing crypt audio fixture")
	main.player.cam.top_level = true
	main.player.cam.global_position = crypt.transform * Vector3(0, 1.5, 12)
	graves.sound_timer = 0.0
	graves._process(0.0)
	check(graves.voice.playing and graves.voice.bus == "World", "Crypt knocking did not use spatial world audio")
	main.player.cam.global_position = graves.voice.global_position + Vector3(0, 0.3, 2)
	graves._process(0.1)
	check(not graves.voice.playing and graves.sound_timer > 0.0, "Crypt did not fall silent on approach")
	main.player.cam.global_position = Vector3.ONE * 10000
	graves.sound_timer = 0.0
	graves._process(0.0)
	check(not graves.voice.playing, "Distant crypt started inaudible background playback")
	print("ruined graves: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	for audio_type: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await physics_frame
	await process_frame
	quit(0 if failures == 0 else 1)
