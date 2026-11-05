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
		maze.graves.crows.set_process(false)
		await physics_frame
		await physics_frame
		check(not is_instance_valid(previous), "Previous grave nodes survived maze replacement")
		var graves: Node3D = maze.graves
		check(graves.meshes.size() == 4 and graves.shapes.size() == 4, "Missing grave model or collision resource")
		check(graves.trees.size() == 3, "Missing cemetery dead trees")
		for tree: StaticBody3D in graves.trees:
			var ray := PhysicsRayQueryParameters3D.create(tree.global_position + Vector3(0, 1, 1), tree.global_position + Vector3(0, 1, -1))
			ray.collision_mask = Graves.COLLISION_LAYER
			var hit := graves.get_world_3d().direct_space_state.intersect_ray(ray)
			check(not hit.is_empty() and hit.collider == tree, "Dead tree trunk has no collision")
		check(maze.gen.cemetery.size != Vector2i.ZERO, "Missing cemetery")
		check(maze.gen.burial_plots.size() == 8, "Cemetery should contain eight paired burial plots")
		check(maze.gen.path_length(maze.gen.spawn, Vector2i(maze.gen.n / 2, maze.gen.n / 2)) >= 0, "Cemetery disconnected summit from spawn")
		for stair: Vector2i in maze.gen.stairs:
			check(maze.gen.path_length(maze.gen.spawn, stair) >= 0, "Cemetery disconnected a main staircase")
		for room: Dictionary in maze.gen.rooms:
			for door: Vector2i in room.doors:
				check(maze.gen.path_length(maze.gen.spawn, door) >= 0, "Cemetery disconnected a room entrance")
		var paths := preload("res://scripts/grid_path.gd").new(maze.gen)
		for plot: Vector2i in maze.gen.burial_plots:
			check(not paths.walkable(plot), "Monster navigation enters an occupied burial plot")
		var counts := {"grave_mound": 0, "grave_open": 0, "grave_wall": 0}
		for kind: String in ["grave_mound", "grave_open"]:
			var size: Vector3 = graves.bounds[kind].size
			check(size.z >= 3.0 and size.x >= 1.5 and size.y >= 1.0, "Burial lost adult proportions or cross silhouette")
		for i in graves.sites.size():
			var site: Dictionary = graves.sites[i]
			for j in range(i):
				var other: Dictionary = graves.sites[j]
				if absf(site.transform.origin.y - other.transform.origin.y) < 0.1:
					check(not graves.footprint(site.kind, site.transform).intersects(graves.footprint(other.kind, other.transform)), "Grave models overlap")
			counts[site.kind] += 1
			check(site.body.collision_layer & 1 != 0, "Grave does not collide with player/world layer")
			var cell_center: Vector3 = maze.block_center(site.block.x, site.block.y)
			var cell := Rect2(Vector2(cell_center.x, cell_center.z) - Vector2.ONE * maze.block / 2, Vector2.ONE * maze.block)
			check(cell.encloses(graves.footprint(site.kind, site.transform)), "Grave protrudes into neighboring cell")
			check(site.transform.origin.distance_to(maze.get_spawn_position()) >= Graves.SPAWN_GAP - 0.1, "Grave crowded spawn area")
			check(maze.gen.height[site.block.y][site.block.x] < maze.gen.TOP_TIER * maze.gen.TIER_H, "Grave intruded into giant patrol area")
			var start := Vector3(0, 0.3, 2.0)
			var end := Vector3(0, 0.3, 0.5)
			if site.kind == "grave_mound":
				start = Vector3(1.0, 0.25, 0.52)
				end = Vector3(0, 0.25, 0.52)
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
			var from := Vector3(1.8, 0.95, 0.52) if site.kind == "grave_mound" else Vector3(0, 0.95, 2.5)
			var to := Vector3(0, 0.95, 0.52) if site.kind == "grave_mound" else Vector3(0, 0.95, -0.1)
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
		# 验证实际通路碰撞：专用墓区外，每个开放格中心和邻接边保留 2.4 米宽体积。
		var space := graves.get_world_3d().direct_space_state
		var connections := 0
		for z in maze.gen.n:
			for x in maze.gen.n:
				if not maze.gen.is_open(x, z) or maze.gen.burial_plots.has(Vector2i(x, z)):
					continue
				var a: Vector3 = maze.block_center(x, z) + Vector3.UP * maze.gen.floor_height(x, z)
				var query := lane_query(a)
				check(space.intersect_shape(query, 1).is_empty(), "Grave blocked a walkable cell center")
				for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var q := Vector2i(x, z) + dir
					if not maze.gen.is_open(q.x, q.y) or maze.gen.burial_plots.has(q) or absf(maze.gen.floor_height(q.x, q.y) - a.y) > maze.gen.STAIR_RISE + 0.01:
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
			var court: Rect2i = maze.gen.cemetery
			var center: Vector3 = maze.block_center(court.get_center().x, court.get_center().y)
			center.y = maze.gen.height[court.position.y][court.position.x]
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 42.0
			camera.global_position = center + Vector3(0, 30, 0.01)
			camera.look_at(center)
			for frame in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/leviathan-graves/cemetery_ingame.png")
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			var long_axis := Vector3.RIGHT if court.size.x > court.size.y else Vector3.BACK
			camera.global_position = center - long_axis * 13.0 + Vector3.UP * 2.0
			camera.look_at(center + long_axis * 6.0 + Vector3.UP * 2.6)
			for frame in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/leviathan-graves/cemetery_walk_ingame.png")
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
