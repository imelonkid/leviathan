extends Node3D
## 量墙人和扶门者：只做氛围，无碰撞。按名额加载，换迷宫即取消当前相遇。
const Sounds = preload("res://scripts/threshold_sounds.gd")
const Materials = preload("res://scripts/creature_materials.gd")
const Budget = preload("res://scripts/creature_budget.gd")
const Gen = preload("res://scripts/maze_gen.gd")
const WATCH_CHASE := 3
const WATCH_HOLD := 5

var kind := "surveyor"
var player: Node3D
var maze: Node3D
var budget: Node
var watchman: Node
var soundscape: Node
var model: Node3D
var actors: Array[Node3D] = []
var rigs: Array[Skeleton3D] = []
var mats: Dictionary = {}
var rng := RandomNumberGenerator.new()
var next_t := 45.0
var idle := 0.0
var elapsed := 0.0
var active := false
var retreat := false
var alpha := 0.0
var start_pos := Vector3.ZERO
var direction := Vector3.ZERO
var distance := 0.0
var last_gen: RefCounted
var probe_t := 0.0
var sounds: Node
var used_rooms := {}
var exit_pos := Vector3.ZERO
var release_t := 0.0


func _ready() -> void:
	sounds = Sounds.new()
	sounds.kind = kind
	add_child(sounds)
	rng.randomize()
	next_t = rng.randf_range(45, 75) if kind == "surveyor" else rng.randf_range(25, 45)
	visible = false


func _process(delta: float) -> void:
	if maze == null or maze.gen == null or player == null:
		return
	if last_gen != maze.gen:
		var changed := last_gen != null
		last_gen = maze.gen
		used_rooms.clear()
		if changed:
			finish()
	var blocked: bool = player.frozen or (watchman != null and watchman.state in [WATCH_CHASE, WATCH_HOLD])
	if active:
		elapsed += delta
		if blocked:
			retreat = true
		_tick(delta)
		return
	if blocked:
		return
	next_t -= delta
	var path := "res://assets/models/" + kind + ".glb"
	if model == null:
		if next_t > Budget.PREFETCH:
			return
		var scene: PackedScene = budget.take(self, path)
		if scene == null:
			return
		_build(scene)
	else:
		idle += delta
		if idle > Budget.KEEP and next_t > Budget.PREFETCH:
			_unload()
			return
	if next_t > 0:
		return
	probe_t -= delta
	if probe_t > 0:
		return
	probe_t = 3.0
	if try_start():
		next_t = rng.randf_range(100, 170)
	else:
		# 没有合适相遇位置时立即还回名额，避免两只氛围怪占满后饿死守夜人。
		_unload()
		next_t = 12.0


func _build(scene: PackedScene) -> void:
	model = Node3D.new()
	add_child(model)
	mats = Materials.make({
		"skin": [Color(0.51, 0.43, 0.33), Color(0.72, 0.6, 0.66), 0.9, 0.6, 0.6, 0.0, false],
		"coat": [Color(0.43, 0.235, 0.08) if kind == "surveyor" else Color(0.105, 0.245, 0.195), Color(0.7, 0.62, 0.5), 1.6, 0.4, 0.95, 0.0, true],
		"cape": [Color(0.24, 0.12, 0.045) if kind == "surveyor" else Color(0.27, 0.1, 0.085), Color(0.7, 0.62, 0.5), 1.6, 0.4, 0.95, 0.0, true],
		"leather": [Color(0.13, 0.085, 0.055), Color(0.6, 0.5, 0.45), 2.0, 0.5, 0.8, 0.0, true],
		"brass": [Color(0.55, 0.32, 0.09), Color(0.6, 0.55, 0.5), 2.0, 0.2, 0.4, 0.8, false],
		"iron": [Color(0.2, 0.11, 0.06), Color(0.5, 0.42, 0.4), 1.2, 0.6, 0.75, 0.5, false],
		"glass": [Color(0.018, 0.009, 0.007), Color.WHITE, 1.0, 0.0, 0.8, 0.0, false],
		"bandage": [Color(0.56, 0.51, 0.39), Color(0.65, 0.55, 0.42), 3.0, 0.3, 0.95, 0.0, false],
	}, rng, ["glass"])
	for mat: StandardMaterial3D in mats.values():
		mat.vertex_color_use_as_albedo = true
	for i in (3 if kind == "surveyor" else 1):
		var actor: Node3D = scene.instantiate()
		model.add_child(actor)
		actors.append(actor)
		for sk: Skeleton3D in actor.find_children("*", "Skeleton3D", true, false):
			rigs.append(sk)
	Materials.apply(model, mats, "skin")
	idle = 0.0
	_set_alpha(0.0)


func _unload() -> void:
	model.queue_free()
	model = null
	actors.clear()
	rigs.clear()
	mats.clear()
	budget.release(self)


func _set_alpha(value: float) -> void:
	alpha = value
	for mat: StandardMaterial3D in mats.values():
		mat.albedo_color.a = value


func _clear(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _seen(at: Vector3) -> bool:
	return player.cam.is_position_in_frustum(at) and _clear(player.cam.global_position, at)


func try_start() -> bool:
	if model == null:
		return false
	if kind == "surveyor":
		if soundscape != null and soundscape.indoor:
			return false
		var candidates := wall_routes()
		candidates.shuffle()
		for route: Dictionary in candidates:
			var at: Vector3 = route["at"]
			var dist := player.global_position.distance_to(at)
			if dist < 25 or dist > 65 or player.cam.global_position.y > at.y - 2:
				continue
			if not _seen(at + Vector3.UP * 2):
				continue
			start_pos = at
			direction = route["dir"]
			distance = 9.0
			_begin()
			return true
	else:
		for slot: Dictionary in door_slots():
			var at: Vector3 = slot["at"]
			var dist := player.global_position.distance_to(at)
			if used_rooms.has(slot["room"]) or dist < 8 or dist > 23:
				continue
			if not _seen(at + Vector3.UP * 1.6):
				continue
			start_pos = at
			exit_pos = slot["exit"]
			direction = slot["face"]
			distance = 0.0
			used_rooms[slot["room"]] = true
			_begin()
			return true
	return false


## 只选真实连续、等高、没有房屋或地标的墙顶；队尾和终点均留在支撑面内。
func wall_routes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var g: RefCounted = maze.gen
	for z in range(1, g.n - 1):
		for x in range(1, g.n - 1):
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var ok := true
				var h: float = g.wall_top[z][x]
				for step in range(-1, 3):
					var p: Vector2i = Vector2i(x, z) + dir * step
					if p.x < 1 or p.y < 1 or p.x >= g.n - 1 or p.y >= g.n - 1:
						ok = false
						break
					if g.kind[p.y][p.x] != Gen.WALL or g.landmark[p.y][p.x] or g.house[p.y][p.x] or not is_equal_approx(g.wall_top[p.y][p.x], h):
						ok = false
						break
				if ok:
					out.append({"at": maze.block_center(x, z) + Vector3.UP * h, "dir": Vector3(dir.x, 0, dir.y)})
	return out


## 大房间内侧的门边；只选一扇门，保持门洞中央畅通。
func door_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in maze.gen.rooms.size():
		var room: Dictionary = maze.gen.rooms[i]
		if room["small"] or not maze.room_nodes.has(i):
			continue
		var rect: Rect2i = room["rect"]
		var center: Vector2 = Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) / 2.0
		for door: Vector2i in room["doors"]:
			var inward := Vector2(center - Vector2(door))
			inward = Vector2(signf(inward.x), 0) if absf(inward.x) > absf(inward.y) else Vector2(0, signf(inward.y))
			var forward := Vector3(inward.x, 0, inward.y)
			var side := forward.cross(Vector3.UP)
			var at: Vector3 = maze.block_center(door.x, door.y) + forward * (maze.block / 2.0 + 0.65) + side * 1.25 + Vector3.UP * float(room["base"])
			var end := at + side * 1.4
			var clear_path := true
			for step in 6:
				if not _room_space(i, at.lerp(end, step / 5.0)):
					clear_path = false
					break
			if clear_path and _clear(at + Vector3.UP, end + Vector3.UP) and _clear(at + Vector3.UP * 2.8, end + Vector3.UP * 2.8):
				out.append({"at": at, "exit": end, "face": -forward, "room": i})
	return out


func _room_space(index: int, at: Vector3) -> bool:
	var room: Node3D = maze.room_nodes[index]
	var local := room.to_local(at)
	var footprint := Rect2(Vector2(local.x, local.z) - Vector2.ONE * 0.5, Vector2.ONE)
	if not Rect2(Vector2(-room.size.x, -room.size.z) / 2.0, Vector2(room.size.x, room.size.z)).encloses(footprint):
		return false
	for prop: Dictionary in room.placed:
		if prop.has("rect") and (prop["rect"] as Rect2).grow(0.1).intersects(footprint):
			return false
	return true


func _begin() -> void:
	active = true
	retreat = false
	elapsed = 0.0
	release_t = 0.0
	visible = true
	idle = 0.0
	global_position = start_pos
	rotation.y = atan2(direction.x, direction.z)
	_set_alpha(0.0)
	sounds.begin(start_pos)
	_pose()


func _tick(delta: float) -> void:
	var near := player.global_position.distance_to(global_position) < (17.0 if kind == "surveyor" else 4.5)
	retreat = retreat or near or elapsed > (22.0 if kind == "surveyor" else 14.0)
	if kind == "surveyor":
		_set_alpha(move_toward(alpha, 0.0 if retreat else 1.0, delta / 2.0))
	if kind == "surveyor":
		# 每六秒停下测量两秒，三个人的步态依次延迟。
		var walked := survey_distance(elapsed)
		global_position = start_pos + direction * walked
	else:
		# 松指 → 收臂 → 沿已经检查过的空地退到门框后。
		if retreat:
			release_t += delta
		var slide := smoothstep(1.4, 3.6, release_t)
		global_position = start_pos.lerp(exit_pos, slide)
		_set_alpha(move_toward(alpha, 1.0, delta / 2.0))
		if release_t >= 3.6:
			var eye: Vector3 = player.cam.global_position
			var covered := true
			for height in [0.5, 1.6, 2.4]:
				if _clear(eye, global_position + Vector3.UP * height):
					covered = false
					break
			if covered:
				finish()
				return
			# 玩家跟进屋内时仍可能看见它，此时停在空地，再短暂淡出。
			if release_t > 5.0:
				_set_alpha(clampf(1.0 - (release_t - 5.0), 0.0, 1.0))
	_pose()
	if kind == "surveyor":
		sounds.survey_tick(elapsed, actors)
	else:
		sounds.holder_tick(elapsed, release_t, global_position)
	if retreat and alpha <= 0:
		finish()


func _pose() -> void:
	for i in actors.size():
		var actor := actors[i]
		var actor_time := maxf(0.0, elapsed - i * 0.32)
		actor.position = Vector3(0, 0, -i * 1.7 + survey_distance(actor_time) - survey_distance(elapsed)) if kind == "surveyor" else Vector3.ZERO
		actor.scale = Vector3.ONE * (1.0 - i * 0.08)
		if i >= rigs.size():
			continue
		var sk := rigs[i]
		var phase := actor_time * 3.0
		for side in ["l", "r"]:
			var sign_side := 1.0 if side == "l" else -1.0
			var walking := kind == "surveyor" and fmod(actor_time, 6.0) < 4.0
			_turn(sk, "leg_" + side, Vector3.RIGHT, sin(phase) * sign_side * 0.22 if walking else 0.0)
			_turn(sk, "arm_" + side, Vector3.RIGHT, -sin(phase) * sign_side * 0.12 if walking else (1.0 - alpha) * 0.35 if retreat else 0.0)
		if kind == "door_holder":
			var fold := smoothstep(0.65, 1.8, release_t)
			for side in ["l", "r"]:
				_turn(sk, "arm_" + side, Vector3.RIGHT, -fold * 0.65)
				_turn(sk, "hand_" + side, Vector3.FORWARD, -fold * 1.0)
				for finger in 4:
					var curl := smoothstep(finger * 0.1, 0.65 + finger * 0.1, release_t)
					_turn(sk, "finger_%d_%s" % [finger, side], Vector3.RIGHT, -curl * 0.9)
			_turn(sk, "body", Vector3.FORWARD, fold * 0.12)
			_turn(sk, "buried_head", Vector3.UP, sin(elapsed * 0.5) * 0.035)
		else:
			var measure := survey_measure(actor_time)
			# 左手把量尺扶正，铰接段展开，头部转向刻度；队尾稍晚执行。
			_turn(sk, "arm_l", Vector3.FORWARD, measure * 0.14)
			_turn(sk, "gauge", Vector3.FORWARD, -measure * 0.14 - (1.0 - measure) * 0.35)
			_turn(sk, "gauge_tip", Vector3.FORWARD, (1.0 - measure) * 2.3)
			_turn(sk, "instruments", Vector3.UP, measure * 0.75)
			var head := sk.find_bone("instruments")
			var pitch_axis := (sk.get_bone_global_rest(head).basis.inverse() * Vector3.RIGHT).normalized()
			sk.set_bone_pose_rotation(head, sk.get_bone_pose_rotation(head) * Quaternion(pitch_axis, measure * 0.25))
			_turn(sk, "body", Vector3.FORWARD, sin(actor_time * 0.65) * 0.015 * (1.0 - measure))
			sk.set_bone_pose_scale(sk.find_bone("gauge_line"), Vector3(1, maxf(0.02, measure), 1))


func survey_distance(time: float) -> float:
	return minf(distance, floorf(time / 6.0) * 2.4 + minf(fmod(time, 6.0), 4.0) * 0.6)


func survey_measure(time: float) -> float:
	var cycle := fmod(time, 6.0)
	return smoothstep(4.0, 4.65, cycle) * (1.0 - smoothstep(5.25, 6.0, cycle))


func _turn(sk: Skeleton3D, bone: String, world_axis: Vector3, angle: float) -> void:
	var index := sk.find_bone(bone)
	if index < 0:
		return
	var axis := (sk.get_bone_global_rest(index).basis.inverse() * world_axis).normalized()
	sk.set_bone_pose_rotation(index, sk.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(axis, angle))


func finish() -> void:
	sounds.stop()
	active = false
	visible = false
	retreat = false
	next_t = rng.randf_range(75, 140)
	idle = 0.0
	_set_alpha(0.0)
