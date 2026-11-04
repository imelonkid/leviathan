extends SceneTree
## Godot --headless --audio-driver Dummy --path . --script res://tests/creature_behaviors.gd
## 真实碰撞场景：扫掠、转弯、追击、独立巡游、胆小避让和被堵后的可见性。
const Main = preload("res://main.tscn")
const Space = preload("res://scripts/creature_space.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func solid(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	parent.add_child(body)
	body.global_position = at
	return body


func model(creature: Node3D, path: String) -> void:
	var scene: PackedScene
	for attempt in 300:
		scene = creature.budget.take(creature, path)
		if scene != null:
			break
		await process_frame
	assert(scene != null, "Test model failed to load: " + path)
	creature._build(scene)


func run() -> void:
	seed(666)
	var main := Main.instantiate()
	root.add_child(main)
	main.set_process(false)
	for node: Node in main.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	Engine.max_fps = 0
	await physics_frame
	await physics_frame
	var maze: Node3D = main.maze
	var watch: Node3D = main.get_node("Watchman")
	var hauler: Node3D = main.get_node("Hauler")
	var survey: Node3D = main.get_node("Surveyors")
	var door: Node3D = main.get_node("DoorHolder")
	check(watch.TEMPERAMENT == Space.Temperament.DANGEROUS, "Watchman must be dangerous")
	check(hauler.TEMPERAMENT == Space.Temperament.NEUTRAL, "Hauler must be neutral")
	check(survey.TEMPERAMENT == Space.Temperament.TIMID and door.TEMPERAMENT == Space.Temperament.TIMID, "Threshold creatures must be timid")
	# 隔离的物理墙：中心射线能通过的擦边、一次跨过整墙、起点重叠、旋转扫墙。
	var arena := Vector3(1000, 0, 1000)
	var wall := solid(main, arena + Vector3(5, 3, 0), Vector3(1, 6, 10))
	await physics_frame
	await physics_frame
	var volume := Space.new(main, main.player, AABB(Vector3(-0.7, 0.1, -0.7), Vector3(1.4, 3, 1.4)))
	check(volume.fits(arena), "Empty start must fit")
	check(not volume.can_move(Transform3D(Basis.IDENTITY, arena), Transform3D(Basis.IDENTITY, arena + Vector3(10, 0, 0))), "Fast move tunneled through wall")
	var edge := arena + Vector3(0, 0, 5.4)
	check(not volume.can_move(Transform3D(Basis.IDENTITY, edge), Transform3D(Basis.IDENTITY, edge + Vector3(10, 0, 0))), "Body edge clipped wall while center ray was clear")
	check(not volume.can_move(Transform3D(Basis.IDENTITY, arena + Vector3.RIGHT * 5), Transform3D(Basis.IDENTITY, arena)), "Initial overlap was ignored")
	var long_body := Space.new(main, main.player, AABB(Vector3(-0.3, 0.1, -3), Vector3(0.6, 3, 6)))
	var turn := Transform3D(Basis.IDENTITY, arena + Vector3.RIGHT * 3)
	var turned := Transform3D(Basis(Vector3.UP, PI), turn.origin)
	check(long_body.fits(turn.origin, turn.basis) and long_body.fits(turned.origin, turned.basis), "Rotation fixture endpoints must fit")
	check(not long_body.can_move(turn, turned), "Turning body swept through wall")
	wall.queue_free()
	await physics_frame
	# 守夜人：即使误给一条跨墙路线，最后的移动边界仍会挡住；重规划保留当前段。
	await model(watch, watch.MODEL)
	var pair: Array[Vector2i] = []
	var straight: Array[Vector2i] = []
	for z in range(2, maze.gen.n - 2):
		for x in range(2, maze.gen.n - 2):
			var p := Vector2i(x, z)
			if not watch.paths.walkable(p) or not watch.body_space.fits(watch._center(p)):
				continue
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var q := p + dir * 2
				if pair.is_empty() and maze.gen.kind[z + dir.y][x + dir.x] == maze.gen.WALL and watch.paths.walkable(q) and is_equal_approx(watch._center(p).y, watch._center(q).y):
					pair = [p, q]
				if straight.is_empty() and watch.paths.walkable(p + dir) and watch.paths.walkable(q) and watch.body_space.can_move(Transform3D(Basis.IDENTITY, watch._center(p)), Transform3D(Basis.IDENTITY, watch._center(q))):
					straight = [p, p + dir, q]
	assert(not pair.is_empty() and not straight.is_empty(), "Missing watchman fixture")
	watch.global_position = watch._center(pair[0])
	var original: Vector3 = watch.global_position
	watch.route.clear()
	watch.route.append(pair[1])
	watch.seg_t = 1.0
	watch._follow(100.0, 1.0)
	check(watch.global_position.is_equal_approx(original), "Watchman crossed a physical wall")
	watch._approach(watch._center(pair[1]), 100.0, 1.0)
	check(watch.global_position.is_equal_approx(original), "Direct approach crossed a physical wall")
	watch.seg_from = watch._center(straight[0])
	watch.seg_to = watch._center(straight[1])
	watch.seg_t = 0.6
	watch.global_position = watch.seg_from.lerp(watch.seg_to, 0.6)
	var segment_end: Vector3 = watch.seg_to
	watch._go(straight[2])
	check(is_equal_approx(watch.seg_t, 0.6) and watch.seg_to == segment_end, "Replanning discarded active segment")
	watch.global_position = watch._center(straight[0])
	watch.seg_t = 1.0
	watch.route.clear()
	main.player.global_position = watch._center(straight[2]) + Vector3.UP * 0.1
	main.player.lamp.visible = true
	watch.state = watch.CHASE
	watch.sight_t = 0.0
	var before: float = watch.global_position.distance_to(main.player.global_position)
	watch._process(0.2)
	check(watch.global_position.distance_to(main.player.global_position) < before, "Dangerous creature failed to chase")
	watch.retreat(watch.FIRST)
	watch._unload()
	# 巨人：三张真实地图都至少有一处容得下身体和拖板的巡游场地。
	for seed_value in [666, 1234, 9876]:
		maze.seed_value = seed_value
		maze.build()
		await physics_frame
		await physics_frame
		hauler._process(0.0)
		var sites: Array[Dictionary] = hauler.patrol_routes()
		check(not sites.is_empty(), "No collision-free giant patrol for seed %d" % seed_value)
		print("seed ", seed_value, ": ", sites.size(), " giant patrol sites")
	var sites: Array[Dictionary] = hauler.patrol_routes()
	assert(not sites.is_empty(), "Missing giant patrol fixture")
	# 在真实场地朝向巨人，通过正常计时、按需加载和选点逻辑出场。
	main.player.global_position = sites[0].center + Vector3(0, 0.1, 12)
	main.player.cam.look_at(sites[0].center + Vector3.UP * 13)
	hauler.next_t = 0.0
	for attempt in 300:
		hauler._process(0.1)
		if hauler.walking:
			break
		await physics_frame
	check(hauler.walking and hauler in hauler.budget.holders, "Neutral creature failed to appear through normal loading and placement")
	assert(hauler.model != null, "Missing naturally loaded giant model")
	hauler.rng.seed = 123
	hauler.start_patrol(sites[0])
	main.player.global_position = hauler.global_position + Vector3(0, 0.1, 5)
	main.player.cam.look_at(hauler.global_position + Vector3.UP * 13)
	main.soundscape.indoor = false
	hauler._walk(0.5, main.player.cam)
	var first: Transform3D = hauler.global_transform
	check(hauler.walking and hauler.alpha > 0.8 and hauler.travelled > 0.5, "Giant vanished or stopped near player")
	hauler.rng.seed = 123
	hauler.start_patrol(sites[0])
	main.player.global_position += Vector3.RIGHT * 20
	main.soundscape.indoor = true
	hauler._walk(0.5, main.player.cam)
	check(first.is_equal_approx(hauler.global_transform), "Neutral patrol reacted to player position or entering a room")
	for step in 240:
		hauler._walk(0.1, main.player.cam)
		check(hauler.body_space.fits(hauler.global_position, hauler.global_basis), "Giant body intersected geometry")
		check(hauler.plate_space.fits(hauler.plate.global_position, hauler.plate.global_basis), "Dragged plate intersected geometry")
	check(hauler.walking and is_equal_approx(hauler.alpha, 1.0), "Giant faded after patrol timer")
	main.player.global_position = hauler.global_position + Vector3(0, 3, 150)
	main.player.cam.look_at(hauler.global_position + Vector3.UP * 13)
	hauler._walk(0.0, main.player.cam)
	check(hauler.walking and hauler.visible, "Watched distant giant disappeared")
	main.player.cam.look_at(main.player.cam.global_position + Vector3.BACK)
	hauler._walk(0.0, main.player.cam)
	check(not hauler.walking and not hauler.visible, "Distant off-screen giant was not reclaimed")
	hauler._unload()
	# 胆小怪物：接近后真实移动；插入堵路墙后仍须保持可见且不穿墙。
	main.soundscape.indoor = false
	for i in maze.gen.rooms.size():
		if not maze.gen.rooms[i].small and not maze.room_nodes.has(i):
			maze.room_nodes[i] = maze._make_room(i)
	await physics_frame
	await physics_frame
	for creature: Node3D in [survey, door]:
		await model(creature, "res://assets/models/" + creature.kind + ".glb")
		creature.last_gen = maze.gen
		if creature == survey:
			var route: Dictionary = {}
			for candidate: Dictionary in survey.wall_routes():
				if survey.wall_move_clear(candidate.at, candidate.at + candidate.dir * 9, candidate.dir):
					route = candidate
					break
			assert(not route.is_empty(), "Missing supported surveyor fixture")
			creature.start_pos = route.at
			creature.direction = route.dir
			creature.distance = 9.0
		else:
			var slots: Array[Dictionary] = door.door_slots()
			assert(not slots.is_empty(), "Missing holder fixture")
			creature.start_pos = slots[0].at
			creature.exit_pos = slots[0].exit
			creature.direction = slots[0].face
			creature.mirrored = slots[0].mirror
			creature.encounter_room = slots[0].room
		creature._begin()
		if creature == door:
			var room: Node3D = creature.occupied_room
			check(room.residents == 1, "Active holder did not retain its room")
			main.player.global_position = creature.start_pos + Vector3.RIGHT * 100
			main.player.cam.look_at(main.player.cam.global_position + Vector3.RIGHT)
			var visits: int = room.visits
			room.shifting = true
			room.entered = true
			room._process(0.0)
			maze.room_check = 0.0
			maze._process(0.0)
			check(room.visits == visits and maze.room_nodes.has(creature.encounter_room), "Occupied room was rebuilt or unloaded under holder")
		main.player.global_position = creature.start_pos + (creature.direction * -3.0 if creature == survey else creature.direction * 6.0) + Vector3.UP * 0.1
		main.player.cam.look_at(creature.start_pos + Vector3.UP * 1.6)
		before = creature.global_position.distance_to(main.player.global_position)
		for frame in 45:
			creature.elapsed += 0.1
			creature._tick(0.1)
		check(creature.retreat, "Timid creature failed to notice nearby player")
		check(creature.global_position.distance_to(main.player.global_position) > before + 0.3, "Timid creature did not move away")
		var blocker := solid(main, creature.global_position + creature.direction * 1.3 + Vector3.UP * 1.7, Vector3(0.2, 3.4, 0.2))
		await physics_frame
		await physics_frame
		for frame in 150:
			var previous: Transform3D = creature.global_transform
			creature.elapsed += 0.1
			creature._tick(0.1)
			check(creature.active and creature.visible and is_equal_approx(creature.alpha, 1.0), "Blocked timid creature disappeared")
			if creature == survey:
				if not creature.wall_move_clear(previous.origin, creature.global_position, creature.direction):
					check(false, "Surveyors crossed obstruction or lost support")
					break
			else:
				check(creature.body_space.fits(creature.global_position, creature.global_basis), "Holder crossed an obstruction")
		blocker.queue_free()
		await physics_frame
		creature.finish()
		if creature == door:
			check(maze.room_nodes[creature.encounter_room].residents == 0, "Holder did not release its room")
		creature._unload()
	print("creature behaviors: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	for audio_type: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
