extends SceneTree
## 固定地图和随机数，沿可通行格子模拟步行；保留物理墙体和视线判定。
## 不直接调用怪物 _begin，不指定怪物位置。逻辑时间加速，不代表真人试玩。
## Godot --headless --audio-driver Dummy --path . --script res://tests/encounter_walk.gd
const Main = preload("res://main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func path(g: RefCounted, start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var parent := {start: start}
	var index := 0
	while index < queue.size():
		var p := queue[index]
		index += 1
		if p == end:
			break
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var q := p + dir
			if not parent.has(q) and g.is_open(q.x, q.y) and absf(g.floor_height(q.x, q.y) - g.floor_height(p.x, p.y)) <= g.STAIR_RISE + 0.01:
				parent[q] = p
				queue.append(q)
	if not parent.has(end):
		return []
	var result: Array[Vector2i] = [end]
	while result[0] != start:
		result.push_front(parent[result[0]])
	return result


func run() -> void:
	seed(666)
	var main := Main.instantiate()
	root.add_child(main)
	# 停止自动推进，保留物理碰撞；由测试统一推进逻辑时间。
	main.set_process(false)
	main.set_physics_process(false)
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
	var holder: Node3D = main.get_node("DoorHolder")
	for creature: Node3D in [watch, hauler, survey, holder]:
		creature.rng.seed = 666
	# 抬头没有候选点时，只检查条件，不占用模型名额。
	main.player.head.rotation.x = PI / 2.0
	for creature: Node3D in [survey, holder]:
		creature.next_t = 0.0
		creature._process(0.0)
		check(creature.model == null and creature not in creature.budget.holders, "No eligible site must not reserve a model")
		creature.next_t = creature.first_delay()
		creature.probe_t = 0.0
	main.player.head.rotation.x = 0.0
	seed(666)
	var from: Vector2i = maze.gen.spawn
	var goals: Array[Vector2i] = []
	for room: Dictionary in maze.gen.rooms:
		if not room.small:
			goals.append(room.rect.position + room.rect.size / 2)
	goals.append(Vector2i(maze.gen.n / 2, maze.gen.n / 2))
	var route: Array[Vector2i] = []
	for goal: Vector2i in goals:
		var segment := path(maze.gen, from, goal)
		check(not segment.is_empty(), "Walk target is unreachable")
		route.append_array(segment)
		from = goal
	var seen := {"watchman": 0, "surveyor": 0, "holder": 0}
	for point: Vector2i in route:
		var to: Vector3 = maze.block_center(point.x, point.y) + Vector3.UP * (maze.gen.floor_height(point.x, point.y) + 0.1)
		await physics_frame
		var old: Vector3 = main.player.global_position
		for step in 5:
			main.player.global_position = old.lerp(to, (step + 1) / 5.0)
			var look := to - old
			if Vector2(look.x, look.z).length() > 0.01:
				main.player.rotation.y = atan2(-look.x, -look.z)
			main.player.head.rotation.x = 0.0
			main.player.cam.rotation = Vector3.ZERO
			maze._process(0.25)
			main.soundscape._process(0.25)
			watch._process(0.25)
			main.caught._process(0.25)
			hauler._process(0.25)
			survey._process(0.25)
			holder._process(0.25)
			if watch.state != watch.HIDDEN and watch._player_sees_me():
				seen.watchman += 1
			if survey.active and survey.alpha > 0.5 and survey._seen(survey.global_position + Vector3.UP * 2):
				seen.surveyor += 1
			if holder.active and holder.alpha > 0.5 and holder._seen(holder.global_position + Vector3.UP * 1.6):
				seen.holder += 1
			await process_frame
	for kind: String in seen:
		check(seen[kind] > 0, kind + " was never visible during the walk")
	print("walk: ", route.size() * 1.25, " simulated seconds; visible quarter-seconds: ", seen)
	# 真正重建迷宫，验证旧寻路和房间记录不再残留。
	var old_gen: RefCounted = maze.gen
	maze.seed_value = 1234
	maze.build()
	await physics_frame
	await physics_frame
	watch._process(0.0)
	check(watch.paths.gen == maze.gen and maze.gen != old_gen, "Watchman retained old path grid")
	check(watch.state == watch.HIDDEN and watch.route.is_empty(), "Watchman retained old route")
	for creature: Node3D in [survey, holder]:
		creature._process(0.0)
		check(not creature.active and creature.used_rooms.is_empty(), "Old encounter survived maze replacement")
		check(creature.next_t <= 18.0, "Maze replacement delayed the first encounter")
	survey.wall_routes()
	check(survey.wall_gen == maze.gen, "Wall route cache retained old maze")
	print("encounter walk: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	for audio_type: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
