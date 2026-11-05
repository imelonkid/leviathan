extends SceneTree
## Godot --headless --audio-driver Dummy --path . --script res://tests/creature_budget.gd
## 注入帧时序测试调节策略；用真实加载验证降额不会删除已在场的怪物。
const Budget = preload("res://scripts/creature_budget.gd")
const Settings = preload("res://scripts/settings.gd")
const Main = preload("res://main.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func feed(budget: Node, fps: int, seconds: float, reference := 60.0, active := true) -> void:
	for frame in ceili(seconds * fps):
		budget.observe_frame(1.0 / fps, reference, active)


func warmed_budget() -> Node:
	var budget := Budget.new()
	budget.observe_frame(1.0 / 60.0, 60.0)
	budget.observe_frame(Budget.SETTLE + 1.0, 60.0)
	return budget


func loaded(budget: Node, who: Node) -> PackedScene:
	for frame in 300:
		var scene: PackedScene = budget.take(who, "res://assets/models/watchman.glb")
		if scene != null:
			return scene
		await process_frame
	check(false, "Model did not load through budget")
	return null


func run() -> void:
	var budget := warmed_budget()
	check(budget.limit == 3, "Initial budget must use baseline 3")
	budget.observe_frame(5.0, 60.0)
	feed(budget, 60, 3.0)
	check(budget.limit == 3, "One long stall reduced budget")
	feed(budget, 60, 22.0)
	check(budget.limit == 4, "Sustained healthy frames did not raise budget")
	feed(budget, 240, 60.0)
	check(budget.limit == 4, "Budget exceeded upper bound")
	feed(budget, 40, 2.0)
	check(budget.limit == 4, "Brief slowdown reduced budget")
	feed(budget, 40, 5.0)
	check(budget.limit == 2, "Sustained slowdown did not reduce budget to lower bound")
	feed(budget, 60, 20.0)
	check(budget.limit == 2, "Budget rebounded during recovery cooldown")
	feed(budget, 60, 55.0)
	check(budget.limit == 4, "Budget did not recover gradually")
	feed(budget, 5, 20.0)
	check(budget.limit == 2, "Budget fell below lower bound")
	budget.free()
	# 临界帧率不来回跳；30 FPS 档按 30 FPS 判断，不当成掉帧。
	budget = warmed_budget()
	feed(budget, 55, 60.0)
	check(budget.limit == 3, "Middle band caused budget oscillation")
	feed(budget, 30, 40.0, 30.0)
	check(budget.limit == 4, "30 FPS limit was mistaken for overload")
	feed(budget, 15, 30.0, 60.0, false)
	check(budget.limit == 4 and budget.good_windows == 0 and budget.slow_windows == 0, "Background or menu samples changed budget")
	feed(budget, 30, 7.0)
	check(budget.limit == 4, "Resume grace period was not respected")
	feed(budget, 30, 10.0)
	check(budget.limit == 2, "Resumed sustained overload was not detected")
	budget.free()
	budget = warmed_budget()
	var settings := Settings.new()
	budget.settings = settings
	settings.values.frame_limit = 2
	check(budget.reference_fps(60.0) == 60.0, "V-Sync refresh limit was ignored")
	settings.values.vsync = false
	check(budget.reference_fps(60.0) == 120.0, "Refresh incorrectly limited V-Sync-off reference")
	settings.values.frame_limit = 3
	check(budget.reference_fps(144.0) == 60.0, "Unlimited mode must use a sustainable 60 FPS reference")
	settings.values.vsync = true
	check(budget.reference_fps(30.0) == 30.0, "30 Hz display was mistaken for overload")
	# 三个真实加载名额降为两个时，已加载节点全部保留，只暂停新加载。
	Engine.max_fps = 0
	var actors: Array[Node3D] = []
	for i in 4:
		var actor := Node3D.new()
		root.add_child(actor)
		actors.append(actor)
	for actor: Node3D in actors.slice(0, 3):
		check(await loaded(budget, actor) != null, "Baseline slot unavailable")
	feed(budget, 30, 4.0)
	check(budget.limit == 2 and budget.holders.size() == 3, "Lowering budget forcibly removed loaded creatures")
	for actor: Node3D in actors.slice(0, 3):
		check(is_instance_valid(actor) and actor.visible, "Lowering budget hid or freed a creature")
	check(budget.take(actors[3], "res://assets/models/watchman.glb") == null, "New load exceeded reduced budget")
	budget.release(actors[0])
	check(budget.take(actors[3], "res://assets/models/watchman.glb") == null, "New load admitted before enough natural releases")
	budget.release(actors[1])
	check(await loaded(budget, actors[3]) != null, "Natural release did not make a slot available")
	budget.free()
	settings.free()
	for actor: Node3D in actors:
		actor.queue_free()
	# 真实主场景的注入、改设置清空旧样本、换图后的稳定期。
	var main := Main.instantiate()
	root.add_child(main)
	for node: Node in main.find_children("*", "Node", true, false):
		node.set_process(false)
		node.set_physics_process(false)
	main.set_process(false)
	main.set_physics_process(false)
	budget = main.get_node("CreatureBudget")
	check(budget.settings == main.settings and budget.maze == main.maze, "Runtime budget was not connected")
	budget.observe_frame(1.0 / 60.0, 60.0)
	main.settings.changed.emit()
	check(budget.settling == Budget.SETTLE and budget.sample_frames == 0, "Settings change retained old measurements")
	var original: RefCounted = main.maze.gen
	main.maze.gen = RefCounted.new()
	budget._process(0.0)
	check(budget.last_gen == main.maze.gen and budget.settling == Budget.SETTLE, "Maze replacement retained old measurements")
	main.maze.gen = original
	for audio_type: String in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	print("adaptive creature budget: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
