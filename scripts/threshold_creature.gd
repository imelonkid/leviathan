extends Node3D
## 胆小的量墙人和扶门者：沿通行空间躲避玩家，视野内不消失。
const Sounds = preload("res://scripts/threshold_sounds.gd")
const Materials = preload("res://scripts/creature_materials.gd")
const Budget = preload("res://scripts/creature_budget.gd")
const Gen = preload("res://scripts/maze_gen.gd")
const Space = preload("res://scripts/creature_space.gd")
const TEMPERAMENT = Space.Temperament.TIMID
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
var wall_gen: RefCounted
var cached_routes: Array[Dictionary] = []
var mirrored := false
var encounter_room := -1
var observed := 0.0
var wait_reason := "等待出场"
var body_space: RefCounted
var wall_position := 0.0
var flee_target := 0.0
var flee_probe := 0.0
var escape_route: Array[Vector3] = []
var occupied_room: Node3D
var moving := false
var flee_walked := 0.0


func _ready() -> void:
	# 在模型静态范围之外预留折尺、摆臂和侧弯动作的空间。
	var box := AABB(Vector3(-1.6, 0.08, -0.95), Vector3(3.2, 3.6, 1.9)) if kind == "surveyor" else AABB(Vector3(-1.05, 0.08, -0.6), Vector3(2.1, 3.3, 1.35))
	body_space = Space.new(self, player, box)
	sounds = Sounds.new()
	sounds.kind = kind
	add_child(sounds)
	rng.randomize()
	next_t = first_delay()
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
			next_t = first_delay()
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
	if model != null:
		idle += delta
		if idle > Budget.KEEP:
			_unload()
	if next_t > 0.0:
		if model == null and next_t < Budget.PREFETCH:
			budget.prefetch(path)
		return
	probe_t -= delta
	if probe_t > 0.0:
		return
	# 门口的可见窗口只有几秒，不能错过一次就再等 12 秒。
	probe_t = 0.5 if kind == "door_holder" else 1.0
	var site := find_encounter()
	if site.is_empty():
		return
	if model == null:
		var scene: PackedScene = budget.take(self, path)
		if scene == null:
			wait_reason = "等待加载名额"
			return
		_build(scene)
	start_pos = site["at"]
	direction = site["dir"] if kind == "surveyor" else site["face"]
	distance = 9.0 if kind == "surveyor" else 0.0
	if kind == "door_holder":
		exit_pos = site["exit"]
		mirrored = site["mirror"]
		encounter_room = site["room"]
	_begin()


func first_delay() -> float:
	return rng.randf_range(10.0, 18.0) if kind == "surveyor" else rng.randf_range(1.0, 3.0)


func debug_status() -> String:
	if active:
		return "躲避中" if retreat else "活动中"
	if player.frozen or watchman.state in [WATCH_CHASE, WATCH_HOLD]:
		return "追逐期间暂停"
	return "等待 %d 秒" % ceili(next_t) if next_t > 0 else wait_reason


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


func find_encounter() -> Dictionary:
	if kind == "surveyor":
		wait_reason = "视野内暂无可见墙顶"
		if soundscape != null and soundscape.indoor:
			return {}
		var candidates := wall_routes()
		candidates.shuffle()
		for route: Dictionary in candidates:
			var at: Vector3 = route["at"]
			var dist := player.global_position.distance_to(at)
			# 高处俯瞰同样能看见行列；遮挡由实际射线判定。
			if dist < 22 or dist > 60:
				continue
			if _seen(at + Vector3.UP * 2) and wall_move_clear(at, at + route.dir * 9.0, route.dir):
				return route
	else:
		wait_reason = "附近暂无可用房门"
		for slot: Dictionary in door_slots():
			var at: Vector3 = slot["at"]
			var dist := player.global_position.distance_to(at)
			if used_rooms.has(slot["room"]) or dist < 5.5 or dist > 24:
				continue
			if _seen(at + Vector3.UP * 1.6):
				return slot
	return {}


## 只选真实连续、等高、没有房屋或地标的墙顶；队尾和终点均留在支撑面内。
func wall_routes() -> Array[Dictionary]:
	if wall_gen == maze.gen:
		return cached_routes
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
	wall_gen = maze.gen
	cached_routes = out
	return cached_routes


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
			for sign_side: float in [-1.0, 1.0]:
				var side: Vector3 = forward.cross(Vector3.UP) * sign_side
				var at: Vector3 = maze.block_center(door.x, door.y) + forward * (maze.block / 2.0 + 0.85) + side * 1.25 + Vector3.UP * float(room["base"])
				var end: Vector3 = at + side * 1.4
				var clear_path := true
				for step in 6:
					if not _room_space(i, at.lerp(end, step / 5.0)):
						clear_path = false
						break
				if clear_path and body_space.can_move(Transform3D(Basis.looking_at(forward), at), Transform3D(Basis.looking_at(forward), end)):
					out.append({"at": at, "exit": end, "face": -forward, "room": i, "mirror": sign_side < 0.0})
	return out


func _room_space(index: int, at: Vector3) -> bool:
	var room: Node3D = maze.room_nodes[index]
	var local := room.to_local(at)
	var footprint := Rect2(Vector2(local.x, local.z) - Vector2.ONE * 0.8, Vector2.ONE * 1.6)
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
	observed = 0.0
	wall_position = 0.0
	flee_target = 0.0
	flee_probe = 0.0
	flee_walked = 0.0
	escape_route.clear()
	if kind == "door_holder":
		occupied_room = maze.room_nodes[encounter_room]
		occupied_room.residents += 1
	visible = true
	idle = 0.0
	global_position = start_pos
	rotation.y = atan2(direction.x, direction.z)
	# 房门的可见窗口可能只有转角前的一瞬，不能等透明淡入后才看得见。
	_set_alpha(1.0)
	sounds.begin(start_pos)
	_pose()


func wall_move_clear(a: Vector3, b: Vector3, forward: Vector3) -> bool:
	var basis := Basis.looking_at(-forward)
	for i in 3:
		var offset := forward * -i * 1.7
		if not body_space.can_move(Transform3D(basis, a + offset), Transform3D(basis, b + offset)):
			return false
		# 三人都要留在等高支撑面上，不能从墙头走到空中。
		for x: float in [body_space.bounds.position.x, body_space.bounds.end.x]:
			for z: float in [body_space.bounds.position.z, body_space.bounds.end.z]:
				var point: Vector3 = b + offset + basis * Vector3(x, 0, z)
				var block_at: Vector2 = maze.world_to_block(point)
				var p := Vector2i(floori(block_at.x), floori(block_at.y))
				if p.x < 0 or p.y < 0 or p.x >= maze.gen.n or p.y >= maze.gen.n or maze.gen.kind[p.y][p.x] != Gen.WALL or absf(maze.gen.wall_top[p.y][p.x] - point.y) > 0.01:
					return false
	return true


func _move_wall(target: float) -> void:
	var destination := start_pos + direction * target
	moving = wall_move_clear(global_position, destination, direction) and global_position.distance_to(destination) > 0.0001
	if moving:
		if retreat:
			flee_walked += global_position.distance_to(destination)
		global_position = destination
		wall_position = target


func room_escape() -> Array[Vector3]:
	# 在已搭好的屋内按米寻路，每条边同时检查家具占地和身体体积。
	var origin := global_position
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var parent := {Vector2i.ZERO: Vector2i.ZERO}
	var best := Vector2i.ZERO
	var current_distance := origin.distance_to(player.global_position)
	var best_score := current_distance
	var index := 0
	while index < queue.size():
		var p := queue[index]
		index += 1
		var at := origin + Vector3(p.x, 0, p.y)
		var d := at.distance_to(player.global_position)
		var score := d + (4.0 if not _clear(player.cam.global_position, at + Vector3.UP * 1.6) else 0.0)
		if d > current_distance + 0.5 and score > best_score:
			best = p
			best_score = score
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var q := p + dir
			if parent.has(q):
				continue
			var to := origin + Vector3(q.x, 0, q.y)
			if _room_space(encounter_room, to) and body_space.can_move(Transform3D(global_basis, at), Transform3D(global_basis, to)):
				parent[q] = p
				queue.append(q)
	var result: Array[Vector3] = []
	while best != Vector2i.ZERO:
		result.push_front(origin + Vector3(best.x, 0, best.y))
		best = parent[best]
	return result


func _flee_room(delta: float) -> void:
	release_t += delta
	var destination := global_position
	if release_t < 3.6:
		destination = start_pos.lerp(exit_pos, smoothstep(1.4, 3.6, release_t))
	else:
		flee_probe -= delta
		if escape_route.is_empty() and flee_probe <= 0.0:
			flee_probe = 2.0
			escape_route = room_escape()
		if not escape_route.is_empty():
			destination = global_position.move_toward(escape_route[0], delta * 1.8)
			if destination.distance_to(escape_route[0]) < 0.01:
				escape_route.pop_front()
	if _room_space(encounter_room, destination) and body_space.can_move(Transform3D(global_basis, global_position), Transform3D(global_basis, destination)):
		moving = destination.distance_to(global_position) > 0.0001
		flee_walked += destination.distance_to(global_position)
		global_position = destination
	else:
		escape_route.clear()


func _tick(delta: float) -> void:
	moving = false
	var near := player.global_position.distance_to(global_position) < (16.0 if kind == "surveyor" else 7.0)
	retreat = retreat or (near and _clear(player.cam.global_position, global_position + Vector3.UP * 1.6))
	# 靠近、计时结束和逃路被堵都不能使模型在眼前消失。
	if kind == "surveyor":
		if retreat:
			flee_probe -= delta
			if flee_probe <= 0.0:
				flee_probe = 1.0
				var a := start_pos + direction * -3.0
				var b := start_pos + direction * 11.5
				flee_target = -3.0 if a.distance_to(player.global_position) > b.distance_to(player.global_position) else 11.5
			_move_wall(move_toward(wall_position, flee_target, delta * 1.8))
		else:
			_move_wall(survey_distance(elapsed))
	elif retreat:
		_flee_room(delta)
	_pose()
	if kind == "door_holder" and alpha > 0.5 and _seen(global_position + Vector3.UP * 1.6):
		observed += delta
		if observed >= 1.0:
			used_rooms[encounter_room] = true
	if kind == "surveyor" and not retreat:
		sounds.survey_tick(elapsed, actors, moving)
	elif kind == "door_holder":
		sounds.holder_tick(elapsed, release_t, global_position)
	if retreat:
		sounds.flee_tick(flee_walked, actors)
	if elapsed > 22.0 and player.global_position.distance_to(global_position) > 45.0:
		var on_screen := false
		for actor: Node3D in actors:
			if body_space.on_screen(actor.global_position, actor.global_basis, player.cam):
				on_screen = true
				break
		if not on_screen:
			finish()


func _pose() -> void:
	for i in actors.size():
		var actor := actors[i]
		var actor_time := maxf(0.0, elapsed - i * 0.32)
		actor.position = Vector3(0, 0, -i * 1.7) if kind == "surveyor" else Vector3.ZERO
		actor.rotation.y = PI if kind == "surveyor" and retreat and flee_target < wall_position else 0.0
		actor.scale = Vector3.ONE * (1.0 - i * 0.08)
		if kind == "door_holder" and mirrored:
			actor.scale.x = -actor.scale.x
		if i >= rigs.size():
			continue
		var sk := rigs[i]
		var phase := flee_walked / 0.6 * PI if retreat else actor_time * 3.0
		for side in ["l", "r"]:
			var sign_side := 1.0 if side == "l" else -1.0
			var walking := moving
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
			var measure := 0.0 if retreat else survey_measure(actor_time)
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
	if is_instance_valid(occupied_room):
		occupied_room.residents -= 1
		occupied_room = null
	sounds.stop()
	active = false
	visible = false
	retreat = false
	next_t = rng.randf_range(60, 100)
	idle = 0.0
	_set_alpha(0.0)
