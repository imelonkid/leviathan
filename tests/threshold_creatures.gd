extends SceneTree
## Godot --path . --script res://tests/threshold_creatures.gd
## 验证真实场景中的骨架、墙顶支撑、房门候选、退场和换种子清理。
const Main = preload("res://main.tscn")
const Creature = preload("res://scripts/threshold_creature.gd")
const Gen = preload("res://scripts/maze_gen.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	var main := Main.instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var maze: Node3D = main.maze
	var survey: Node3D = main.get_node("Surveyors")
	var door: Node3D = main.get_node("DoorHolder")
	survey.set_process(false)
	door.set_process(false)
	main.get_node("Watchman").set_process(false)
	maze.set_process(false)
	var original: RefCounted = maze.gen
	for seed_value in [666, 1234, 9876]:
		var gen := Gen.new()
		gen.generate(seed_value)
		maze.gen = gen
		var routes: Array[Dictionary] = survey.wall_routes()
		check(not routes.is_empty(), "No wall routes for seed %d" % seed_value)
		for route: Dictionary in routes:
			for step in range(-1, 3):
				var b: Vector2 = maze.world_to_block(route.at + route.dir * maze.block * step)
				check(gen.kind[int(b.y)][int(b.x)] == Gen.WALL, "Unsupported wall route")
		print("seed ", seed_value, ": ", routes.size(), " supported wall routes")
	maze.gen = original
	# 实际摆出大房间，候选点必须避开生成出来的家具占地。
	for i in maze.gen.rooms.size():
		if not maze.gen.rooms[i]["small"] and not maze.room_nodes.has(i):
			maze.room_nodes[i] = maze._make_room(i)
	var slots: Array[Dictionary] = door.door_slots()
	check(not slots.is_empty(), "No door slots in actual scene")
	print("actual room slots: ", slots.size())
	for creature: Node3D in [survey, door]:
		var scene: PackedScene
		for attempt in 300:
			scene = creature.budget.take(creature, "res://assets/models/" + creature.kind + ".glb")
			if scene != null:
				break
			await process_frame
		check(scene != null and creature in creature.budget.holders, "Model was not loaded through budget")
		if scene == null:
			quit(1)
			return
		creature._build(scene)
		var colored_surfaces := 0
		for mesh: MeshInstance3D in creature.model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var src: Material = mesh.mesh.surface_get_material(surface)
				check(src != null and creature.mats.has(src.resource_name), "Unmapped material slot")
				if src != null and src.resource_name == "coat":
					colored_surfaces += 1
					check(mesh.get_surface_override_material(surface) == creature.mats["coat"], "Coat override lost")
		check(colored_surfaces > 0, "Model has no colored clothing")
		var coat: Color = creature.mats["coat"].albedo_color
		check(coat.r > coat.g * 1.5 if creature == survey else coat.g > coat.r * 2, "Clothing palette lost")
		check(creature.rigs.size() == (3 if creature.kind == "surveyor" else 1), "Missing skeleton")
		for sk: Skeleton3D in creature.rigs:
			for bone in ["body", "arm_l", "arm_r", "leg_l", "leg_r"]:
				check(sk.find_bone(bone) >= 0, "Missing bone " + bone)
		var route: Dictionary = survey.wall_routes()[0]
		creature.start_pos = route.at if creature == survey else slots[0].at
		creature.direction = route.dir if creature == survey else slots[0].face
		if creature == door:
			creature.exit_pos = slots[0]["exit"]
		creature.distance = 9.0 if creature == survey else 0.0
		creature._begin()
		if creature == door:
			var sk: Skeleton3D = creature.rigs[0]
			sk.force_update_all_bone_transforms()
			for side in ["l", "r"]:
				var at: Vector3 = creature.actors[0].to_local(sk.to_global(sk.get_bone_global_pose(sk.find_bone("palm_" + side)).origin))
				var expected := Vector3(0.58, 2.7, 0.605) if side == "l" else Vector3(0.62, 1.93, 0.605)
				check(at.distance_to(expected) < 0.025, "Palm rest pose changed: " + str(at))

		for frame in 120:
			creature.elapsed += 1.0 / 30.0
			creature._tick(1.0 / 30.0)
		check(creature.alpha > 0.9, "Creature failed to fade in")
		if creature == survey:
			for sk: Skeleton3D in creature.rigs:
				for bone in ["gauge", "gauge_tip", "gauge_line"]:
					check(sk.find_bone(bone) >= 0, "Missing measurement bone " + bone)
			check(is_equal_approx(survey.survey_distance(4.8), survey.survey_distance(5.3)), "Surveyor slides while measuring")
			check(survey.survey_distance(6.3) > survey.survey_distance(5.3), "Surveyor failed to resume walking")
			creature.elapsed = 3.0
			creature._pose()
			var first: Skeleton3D = creature.rigs[0]
			var joint := first.find_bone("gauge_tip")
			var rest := first.get_bone_rest(joint).basis.get_rotation_quaternion()
			check(first.get_bone_pose_rotation(joint).angle_to(rest) > 2.0, "Gauge is not folded during walk")
			creature.elapsed = 4.7
			creature._tick(0.0)
			check(first.get_bone_pose_rotation(joint).angle_to(rest) < 0.1, "Gauge failed to unfold")
			var last: Skeleton3D = creature.rigs[2]
			var last_joint := last.find_bone("gauge_tip")
			check(last.get_bone_pose_rotation(last_joint).angle_to(last.get_bone_rest(last_joint).basis.get_rotation_quaternion()) > 1.0, "Queue measurements are not staggered")

		if "--screenshots" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute("/tmp/leviathan-creatures")
			DirAccess.make_dir_recursive_absolute("/tmp/leviathan-surveyor-v3")
			DirAccess.make_dir_recursive_absolute("/tmp/leviathan-holder-v3")
			main.player.set_physics_process(false)
			var cam: Camera3D = main.player.cam
			cam.top_level = true
			if creature == survey:
				cam.global_position = creature.global_position + creature.direction.cross(Vector3.UP) * 12.0 + Vector3.UP * 3.5
			else:
				cam.global_position = creature.start_pos + creature.direction * 8.0 + creature.direction.cross(Vector3.UP) * 1.25 + Vector3.UP * 1.8
			cam.look_at(creature.global_position + Vector3.UP * 1.6)
			main.player.lamp.visible = true
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/leviathan-creatures/" + creature.kind + "_ingame.png")
			if creature == survey:
				var previous := cam.global_transform
				cam.global_position = creature.global_position + creature.direction * 3.5 + creature.direction.cross(Vector3.UP) + Vector3.UP * 1.9
				cam.look_at(creature.global_position + Vector3.UP * 1.8)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/leviathan-surveyor-v3/ingame_close.png")
				cam.global_transform = previous
			if creature == door:
				var previous := cam.global_transform
				cam.global_position = creature.start_pos + creature.direction * 3.8 + creature.direction.cross(Vector3.UP) + Vector3.UP * 1.7
				cam.look_at(creature.global_position + Vector3.UP * 1.6)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/leviathan-holder-v3/ingame_close.png")
				cam.global_transform = previous
		if creature == door:
			for slot: Dictionary in slots:
				for step in 6:
					check(door._room_space(slot.room, slot.at.lerp(slot.exit, step / 5.0)), "Exit path intersects furniture")
			for sk: Skeleton3D in creature.rigs:
				for side in ["l", "r"]:
					check(sk.find_bone("palm_" + side) >= 0, "Missing palm pivot")
					for finger in 4:
						check(sk.find_bone("finger_%d_%s" % [finger, side]) >= 0, "Missing finger pivot")
		creature.retreat = true
		for frame in 210:
			creature._tick(1.0 / 30.0)
			if creature == door and frame == 29:
				check(creature.alpha > 0.9, "Door holder faded before releasing its hands")
				var sk: Skeleton3D = creature.rigs[0]
				var finger := sk.find_bone("finger_0_l")
				check(sk.get_bone_pose_rotation(finger).angle_to(sk.get_bone_rest(finger).basis.get_rotation_quaternion()) > 0.5, "Finger failed to release")
			if creature == door and frame in [29, 65, 110] and "--screenshots" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/leviathan-creatures/door_holder_release_%d.png" % frame)
			if not creature.active:
				break
		if creature == door:
			check(creature.global_position.distance_to(creature.start_pos) > 1.3, "Door holder failed to withdraw")
		check(not creature.active and not creature.visible, "Creature failed to leave")
		creature.used_rooms[0] = true
		creature.last_gen = Gen.new()
		creature._process(0.01)
		check(creature.used_rooms.is_empty(), "Room history survived maze replacement")
		creature._unload()
		check(creature not in creature.budget.holders, "Budget slot leaked")
	await process_frame
	print("threshold creatures: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	for audio_type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
