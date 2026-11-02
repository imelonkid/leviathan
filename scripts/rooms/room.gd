extends Node3D
## 一间房的屋里：按种子挑一个配方（recipes.gd），从实体库（props.gd）里挑东西摆进来，再打光、配声音、洒血、加变异。
## maze.gd 在玩家走近时创建它、调用 build()，走远了拆掉；同一间房的种子不变，所以每次进来都长一样——
## 除了“会变的屋子”（SHIFT_CHANCE）：你出了门、背过身去，它就按新的种子整个重搭一遍，变过几次记在 maze 里。
## 坐标以房间地面中心为原点，x / z 是 ±size/2，y 从 0（地面）到 size.y（屋顶）。
##
## 屋里要暗：全局环境光很亮（走道靠它照明），屋里不能吃它。围墙、地面是整座迷宫共用的材质改不了，
## 所以贴一层“内衬”——同样的土墙着色器，但关掉环境光；道具的材质也都关掉环境光，屋里只靠自己的灯。
## （反射探针也能覆盖环境光，但 Godot 4.6 退出时会报贴图 RID 泄漏，所以用内衬）

const ArchMesh = preload("res://scripts/arch_mesh.gd")
const Props = preload("res://scripts/rooms/props.gd")
const Recipes = preload("res://scripts/rooms/recipes.gd")
const TilesShader = preload("res://scripts/rooms/tiles.gdshader")
const WeepShader = preload("res://scripts/rooms/weep.gdshader")

const VIS := 40.0                # 道具的可见距离、灯的淡出距离（米）
const WALL_STEP := 5.0           # 围墙一格的宽度：每面墙按 5 米分段，门占一段
const WALKWAY := 1.0             # 从每扇门到屋子正中留一条这么宽（半宽）的过道
const MOD_CHANCE := 0.3          # 不安的屋子加一种变异的概率
const MODIFIERS := ["inverted", "levitate", "repeat", "turning", "giant"]
const SHIFT_CHANCE := 0.25       # 会变的屋子的比例
const SHIFT_SEED := 7919         # 每变一次，种子加这么多
const GIANT := 6.0               # 变异“巨物”：玩偶放大的倍数
## 变异“转身”：你不看的时候会转过来对着你的东西
const TURNERS := ["chair", "stool", "wheelchair", "mannequin", "doll", "rocking_chair", "desk", "iv_stand"]

var size := Vector3(15, 6, 15)   # maze 注入：屋里的长、高、宽
var doors: Array[Vector3] = []   # maze 注入：门洞正中，贴在屋里那一面墙上（y = 0）
var seed_value := 0
var wall_shader: Shader          # maze 注入：土墙着色器，内衬用它的“不吃环境光”版本
var gate_shape := Vector2(1.7, 3.2)   # maze 注入：门洞拱的半宽、起拱高度
var visits := 0                  # maze 注入：会变的屋子已经变过几次
var on_shift: Callable           # maze 注入：变了一次，交给 maze 记下新的次数
var shifting := false

var rng := RandomNumberGenerator.new()
var recipe: Dictionary
var dread := 0.5
var modifier := ""
var props: Props
var placed: Array[Dictionary] = []   # [{node, place, rect: Rect2（地面占地，俯视）}]
var tickers: Array[Callable] = []
var t := 0.0
var dt := 0.0
# 进门事件用到的东西，实体在 props.gd 里登记进来
var watchers: Array[Node3D] = []     # 会转过来看着你的：玩偶的头、人台
var rockers: Array[Node3D] = []      # 会自己摇起来的摇椅
var drifters: Array[Node3D] = []     # 会自己滑开的轮椅
var lights: Array[Light3D] = []
var entered := false
var inside := false
var busy_slots: Array[Vector3] = []   # 被前墙的大件（黑板）占掉的墙段，不再往上挂、往下靠


func build() -> void:
	# 会不会变用单独的随机数定，不影响原来的种子序列：不会变的屋子和以前长得一样
	var fate := RandomNumberGenerator.new()
	fate.seed = seed_value
	shifting = fate.randf() < SHIFT_CHANCE
	rng.seed = seed_value + visits * SHIFT_SEED
	recipe = Recipes.pick(rng, size.x < WALL_STEP * 2.0)
	var normal: bool = recipe.get("normal", false)
	dread = 0.0 if normal else clampf(recipe["dread"] + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
	if not normal and dread >= 0.3 and rng.randf() < MOD_CHANCE:
		modifier = MODIFIERS[rng.randi_range(0, MODIFIERS.size() - 1)]
	props = Props.new(self, rng, dread)
	name = "Room_%s%s" % [recipe["id"], "_" + modifier if modifier else ""]

	_lining()
	_layout()
	if normal:
		_wrong_detail()
	_lighting()
	_sound()
	if not normal:
		_blood()
	_apply_modifier()


func _process(delta: float) -> void:
	t += delta
	dt = delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		var p := to_local(cam.global_position)
		inside = absf(p.x) < size.x / 2.0 - 0.3 and absf(p.z) < size.z / 2.0 - 0.3 and p.y > 0.0 and p.y < size.y
		if inside and not entered:
			entered = true
			_on_enter()
		elif shifting and entered and not inside and _turned_away(cam):
			_shift()
			return
	for f in tickers:
		f.call(t)


## 出了屋子、背对着它：离屋子中心够远，而且屋子在身后
func _turned_away(cam: Camera3D) -> bool:
	var to_room := global_position + Vector3(0, size.y / 2.0, 0) - cam.global_position
	if to_room.length() < size.x / 2.0 + 2.0:
		return false
	return (-cam.global_basis.z).dot(to_room.normalized()) < -0.2


## 整间屋子按新的种子重搭：拆掉屋里的一切，换配方、换摆设、换变异，进门事件重新来一遍
func _shift() -> void:
	visits += 1
	if on_shift.is_valid():
		on_shift.call(visits)
	for c in get_children():
		c.queue_free()
	placed.clear()
	tickers.clear()
	watchers.clear()
	rockers.clear()
	drifters.clear()
	lights.clear()
	busy_slots.clear()
	modifier = ""
	entered = false
	inside = false
	build()


# ---------- 进门事件 ----------

## 第一次走进这间屋子时发生的事，按不安程度挑；正常的屋子里，玩偶一定会转过头来
func _on_enter() -> void:
	var normal: bool = recipe.get("normal", false)
	if not watchers.is_empty() and (normal or modifier == "giant" or rng.randf() < 0.6):
		_watch()
	if modifier == "turning":
		_turn_when_unseen()
	for r in rockers:
		_rock(r)
	for d in drifters:
		if rng.randf() < 0.5:
			_drift(d)
	if normal:
		return
	if dread > 0.5 and rng.randf() < 0.4:
		_blackout()
	if dread > 0.6 and rng.randf() < 0.5:
		sound(stinger_wav(), Vector3(0, 2.0, 0), -6.0, 4.0)


## 它们慢慢转过来，一直对着你
func _watch() -> void:
	for w in watchers:
		var node := w
		tick(func(_tt: float) -> void:
			if not inside:
				return
			var cam := get_viewport().get_camera_3d()
			var d := cam.global_position - node.global_position
			var parent := node.get_parent() as Node3D
			var local := parent.global_transform.basis.inverse() * d
			var target := atan2(local.x, local.z)
			node.rotation.y = lerp_angle(node.rotation.y, target, minf(1.0, dt * 0.8)))


## 变异“转身”：椅子、人台、玩偶……你看不见的那些，转过来对着你
func _turn_when_unseen() -> void:
	var turners: Array[Node3D] = []
	for p in placed:
		if p.get("id", "") in TURNERS:
			turners.append(p["node"])
	tick(func(_tt: float) -> void:
		if not inside:
			return
		var cam := get_viewport().get_camera_3d()
		var fwd := -cam.global_basis.z
		for n in turners:
			var to := n.global_position - cam.global_position
			if fwd.dot(to.normalized()) < 0.2:
				n.basis = facing(to_local(cam.global_position) - n.position))


## 摇椅自己摇起来，越摇越慢，最后停下
func _rock(r: Node3D) -> void:
	var start := t
	tick(func(tt: float) -> void:
		var k := tt - start
		r.rotation.x = 0.14 * sin(k * 2.4) * exp(-k * 0.08))


## 轮椅自己往后滑开一小段
func _drift(d: Node3D) -> void:
	var from := d.position
	var to := from - d.basis.z * rng.randf_range(0.4, 0.9)
	var start := t + rng.randf_range(0.5, 2.0)
	tick(func(tt: float) -> void:
		var k := clampf((tt - start) / 3.0, 0.0, 1.0)
		d.position = from.lerp(to, k * k * (3.0 - 2.0 * k)))


## 灯全灭一下：一声闷响，过一会儿再亮
func _blackout() -> void:
	for l in lights:
		l.visible = false
	sound(thud_wav(), Vector3(0, 1.0, 0), -2.0, 4.0)
	var back := t + rng.randf_range(0.7, 1.4)
	var done := [false]
	tick(func(tt: float) -> void:
		if not done[0] and tt > back:
			done[0] = true
			for l in lights:
				l.visible = true)


func tick(f: Callable) -> void:
	tickers.append(f)


# ---------- 内衬 ----------

## 贴着四面墙（门洞留空）、地面、天花板的薄板，用不吃环境光的土墙着色器；瓷砖屋子再贴墙裙和地砖
func _lining() -> void:
	var dark := Shader.new()
	dark.code = wall_shader.code.replace("render_mode blend_mix,", "render_mode blend_mix, ambient_light_disabled,")
	var m := ShaderMaterial.new()
	m.shader = dark
	const T := 0.02
	box(Vector3(size.x, T, size.z), Vector3(0, T / 2.0 + 0.002, 0), m)
	box(Vector3(size.x, T, size.z), Vector3(0, size.y - T / 2.0 - 0.002, 0), m)
	for slot in wall_slots():
		var nrm: Vector3 = slot["normal"]
		var along: Vector3 = slot["along"]
		var sz := along.abs() * WALL_STEP + nrm.abs() * T + Vector3(0, size.y, 0)
		box(sz, slot["pos"] + nrm * (T / 2.0 + 0.002) + Vector3(0, size.y / 2.0, 0), m)
	# 门洞：一片同样拱形开口的薄板贴在门里侧，一直到屋顶
	var arch := ArchMesh.gate(WALL_STEP / 2.0, size.y, T, gate_shape.x, gate_shape.y)
	for d in doors:
		mesh_at(arch, Transform3D(facing(_door_normal(d)), d + _door_normal(d) * (T / 2.0 + 0.003)), m)

	if recipe["lining"] == "tiles":
		var tiles := ShaderMaterial.new()
		tiles.shader = TilesShader
		var floor_tiles := ShaderMaterial.new()
		floor_tiles.shader = TilesShader
		floor_tiles.set_shader_parameter("tile_size", 0.3)
		floor_tiles.set_shader_parameter("missing", 0.05 + dread * 0.05)
		floor_tiles.set_shader_parameter("tile_color", Color(0.4, 0.4, 0.36))
		box(Vector3(size.x, 0.04, size.z), Vector3(0, 0.02, 0), floor_tiles)
		var wh := minf(2.2, size.y - 1.0)
		for slot in wall_slots():
			var nrm: Vector3 = slot["normal"]
			var along: Vector3 = slot["along"]
			box(along.abs() * WALL_STEP + nrm.abs() * 0.05 + Vector3(0, wh, 0), slot["pos"] + nrm * 0.025 + Vector3(0, wh / 2.0, 0), tiles)


# ---------- 摆放 ----------

func _layout() -> void:
	var half := size.x / 2.0
	if modifier == "repeat":
		_repeat_grid()
	elif modifier == "giant":
		_giant()
	elif recipe["focal"] != "":
		_put(recipe["focal"], Vector3.ZERO, _toward_door(Vector3.ZERO), true)
	if modifier != "repeat" and recipe.get("grid", "") != "":
		_grid(recipe["grid"], recipe.get("front", ""))

	# 屋角：两边都不是门的角，一半概率放个立在角上的
	for corner: Vector3 in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		if rng.randf() > 0.5:
			continue
		if is_door(Vector3(corner.x * half, 0, corner.z * (half - WALL_STEP / 2.0))) \
				or is_door(Vector3(corner.x * (half - WALL_STEP / 2.0), 0, corner.z * half)):
			continue
		var id := _pick("corner")
		if id != "":
			var nrm := -Vector3(corner.x, 0, corner.z).normalized()
			_put(id, Vector3(corner.x * (half - 0.7), 0, corner.z * (half - 0.7)), nrm)

	if modifier != "repeat":
		if recipe["rows"] != "":
			_rows(recipe["rows"])
		for slot in wall_slots():
			if slot["pos"] in busy_slots:
				continue
			if rng.randf() < 0.55:
				var id := _pick("wall")
				if id != "":
					_put_on_wall(id, slot, rng.randf_range(-1.2, 1.2))
		var count := int(recipe["floor"] * size.x * size.z / 10.0 * rng.randf_range(0.6, 1.3))
		for i in count:
			var id := _pick("floor")
			if id == "":
				break
			for attempt in 15:
				var pos := Vector3(rng.randf_range(-half + 0.6, half - 0.6), 0, rng.randf_range(-half + 0.6, half - 0.6))
				if _put(id, pos, Vector3(0, 0, 1).rotated(Vector3.UP, rng.randf() * TAU)):
					break

	_hangings()
	for id: String in recipe["ceiling"]:
		for i in int(recipe["ceiling"][id]) * (2 if size.x > WALL_STEP else 1):
			var pos := Vector3(rng.randf_range(-half + 1.0, half - 1.0), size.y, rng.randf_range(-half + 1.0, half - 1.0))
			var n := props.make(id)
			n.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos)
			add_child(n)
			placed.append({"node": n, "place": "ceiling"})


## 一排靠墙的（病房的床、浴室的浴缸）：大屋子挑门少的一对对面墙，每段墙排两到三件
func _rows(id: String) -> void:
	var foot: Vector2 = Props.ENTITIES[id]["foot"]
	var x_walls := not _more_doors_on_x()
	for slot in wall_slots():
		var nrm: Vector3 = slot["normal"]
		if size.x > WALL_STEP and (absf(nrm.x) > 0.5) != x_walls:
			continue
		var step := foot.x + 0.7
		var k := int(WALL_STEP / step)
		for i in k:
			_put_on_wall(id, slot, (i - (k - 1) / 2.0) * step)


## 方阵（教室的课桌）：挑一面没有门的墙当前墙，前墙正中挂 front，课桌一排排朝着它
func _grid(id: String, front_id: String) -> void:
	var half := size.x / 2.0
	var dirs: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var front := dirs[rng.randi_range(0, 3)]
	for k in 4:
		var d := dirs[(dirs.find(front) + k) % 4]
		var free := true
		for door in doors:
			if door.dot(d) > half - 0.5:
				free = false
		if free:
			front = d
			break
	if front_id != "":
		var best: Dictionary = {}
		for slot in wall_slots():
			if (slot["normal"] as Vector3).dot(-front) > 0.9 and (best.is_empty() \
					or (slot["pos"] as Vector3).length() < (best["pos"] as Vector3).length()):
				best = slot
		if not best.is_empty():
			var nrm: Vector3 = best["normal"]
			var board := props.make(front_id)
			board.transform = Transform3D(facing(nrm), best["pos"] + Vector3(0, 1.7, 0) + nrm * 0.03)
			add_child(board)
			placed.append({"node": board, "place": "hang", "id": front_id})
			busy_slots.append(best["pos"])
	var foot: Vector2 = Props.ENTITIES[id]["foot"]
	var side := front.cross(Vector3.UP)
	var dist := half - 2.2 - foot.y / 2.0
	while dist > -half + foot.y / 2.0 + 0.4:
		var across := -half + 0.6 + foot.x / 2.0
		while across < half - 0.6 - foot.x / 2.0 + 0.01:
			var pos := front * dist + side * across
			if rng.randf() > 0.08:   # 偶尔空一个座位
				_put(id, pos, front)
			across += foot.x + 0.9
		dist -= foot.y + 0.9


## 变异“巨物”：屋子正中坐着一个两人高的玩偶，一直看着你
func _giant() -> void:
	var n := props.make("doll")
	n.transform = Transform3D(facing(_toward_door(Vector3.ZERO)).scaled(Vector3.ONE * GIANT), Vector3.ZERO)
	props.solid(n, Vector3(0.3, 0.4, 0.3), Vector3(0, 0.2, 0))
	add_child(n)
	var r := 0.3 * GIANT / 2.0
	placed.append({"node": n, "place": "center", "rect": Rect2(-r, -r, r * 2.0, r * 2.0), "focal": true, "id": "doll"})


## 变异“重复”：同一件东西整整齐齐排满一屋子，全都朝着门
func _repeat_grid() -> void:
	var ids: Array[String] = ["chair", "bed", "doll", "cage", "bucket", "candles"]
	var id: String = ids[rng.randi_range(0, ids.size() - 1)]
	var foot: Vector2 = Props.ENTITIES[id]["foot"]
	var step := maxf(foot.x, foot.y) + 0.8
	var half := size.x / 2.0 - step / 2.0
	var x := -half
	while x <= half + 0.01:
		var z := -half
		while z <= half + 0.01:
			var pos := Vector3(x, 0, z)
			_put(id, pos, _toward_door(pos))
			z += step
		x += step


## 墙上挂的：每段墙按密度挂几件，高度错开，避开下面高大的家具
func _hangings() -> void:
	for slot in wall_slots():
		if slot["pos"] in busy_slots:
			continue
		var n := int(recipe["hang"] * rng.randf_range(0.5, 1.5) + rng.randf())
		var used: Array[Vector3] = []   # (沿墙位置, 高度, 半径)
		var nrm: Vector3 = slot["normal"]
		for i in n:
			var id := _pick("hang")
			if id == "":
				return
			for attempt in 10:
				var off := rng.randf_range(-1.8, 1.8)
				var y := rng.randf_range(1.5, size.y - 0.9)
				var r: float = Props.ENTITIES[id]["foot"].x / 2.0 + 0.1
				var ok := true
				for u in used:
					if absf(u.x - off) < u.z + r and absf(u.y - y) < u.z + r:
						ok = false
				var wpos: Vector3 = slot["pos"] + slot["along"] * off
				var probe := Vector2(wpos.x + nrm.x * 0.3, wpos.z + nrm.z * 0.3)
				for p in placed:
					if p["place"] == "wall" and (p["rect"] as Rect2).grow(0.2).has_point(probe) and y - r < 2.2:
						ok = false
				if not ok:
					continue
				used.append(Vector3(off, y, r))
				var node := props.make(id)
				node.transform = Transform3D(facing(nrm), wpos + Vector3(0, y, 0) + nrm * 0.03)
				add_child(node)
				placed.append({"node": node, "place": "hang"})
				break


## 靠墙放：背面贴着这段墙，沿墙偏移 off
func _put_on_wall(id: String, slot: Dictionary, off: float) -> bool:
	var foot: Vector2 = Props.ENTITIES[id]["foot"]
	var nrm: Vector3 = slot["normal"]
	var pos: Vector3 = slot["pos"] + slot["along"] * off + nrm * (foot.y / 2.0 + 0.06)
	return _put(id, pos, nrm)


## 在 pos 放一件朝 face 的东西；和已经放了的、门前过道、墙外冲突就放弃。force：焦点无视过道
func _put(id: String, pos: Vector3, face: Vector3, force := false) -> bool:
	var e: Dictionary = Props.ENTITIES[id]
	var foot: Vector2 = e["foot"]
	var basis := facing(face)
	# 俯视占地：转过去以后的外接矩形
	var ext := (basis.x * foot.x).abs() + (basis.z * foot.y).abs()
	var rect := Rect2(Vector2(pos.x, pos.z) - Vector2(ext.x, ext.z) / 2.0, Vector2(ext.x, ext.z))
	var half := size.x / 2.0
	if not Rect2(-half, -half, size.x, size.z).encloses(rect):
		return false
	for p in placed:
		if p.has("rect") and (p["rect"] as Rect2).grow(0.15).intersects(rect):
			return false
	if not force:
		for d in doors:
			if _seg_dist(Vector2(pos.x, pos.z), Vector2(d.x, d.z), Vector2.ZERO) < WALKWAY + maxf(rect.size.x, rect.size.y) * 0.5:
				return false
	var node := props.make(id)
	node.transform = Transform3D(basis, pos)
	add_child(node)
	placed.append({"node": node, "place": e["place"], "rect": rect, "focal": force, "id": id})
	return true


## 按配方的气质权重，从某种摆放方式的实体里挑一件
func _pick(place: String) -> String:
	var weights: Dictionary = recipe["tags"]
	var ids: Array[String] = []
	var ws: Array[float] = []
	var total := 0.0
	for id: String in Props.ENTITIES:
		var e: Dictionary = Props.ENTITIES[id]
		if e["place"] != place:
			continue
		var w := 0.0
		for tag: String in e["tags"]:
			w += weights.get(tag, 0.0)
		if w > 0.0:
			ids.append(id)
			ws.append(w)
			total += w
	if ids.is_empty():
		return ""
	var x := rng.randf() * total
	for i in ids.size():
		x -= ws[i]
		if x <= 0.0:
			return ids[i]
	return ids.back()


## 正常的屋子总有一处不对劲：一只玩偶坐在屋子正中（或桌上），直直地对着门
func _wrong_detail() -> void:
	var n := props.make("doll")
	var pos := Vector3.ZERO
	for p in placed:
		if p.get("focal", false):
			# 正常屋子的焦点是桌子：坐在桌面上；长餐桌正中是烛台，坐到一边去
			var table: Node3D = p["node"]
			pos = table.transform * (Vector3(0.6, 0.8, 0) if p["id"] == "long_table" else Vector3(0, 0.79, 0))
	n.transform = Transform3D(facing(_toward_door(pos)), pos)
	add_child(n)


# ---------- 变异 ----------

func _apply_modifier() -> void:
	match modifier:
		"inverted":
			# 地上的、靠墙的、正中的全部翻到天花板上，倒挂着
			var flip := Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, size.y, 0))
			for p in placed:
				if p["place"] in ["wall", "floor", "center", "corner"]:
					var n: Node3D = p["node"]
					n.transform = flip * n.transform
		"turning":
			# 屋里得有几件会转身的：不够就添几把椅子，背对着门
			var n := 0
			for p in placed:
				if p.get("id", "") in TURNERS:
					n += 1
			var half := size.x / 2.0
			for attempt in 30:
				if n >= 3:
					break
				var pos := Vector3(rng.randf_range(-half + 0.8, half - 0.8), 0, rng.randf_range(-half + 0.8, half - 0.8))
				if _put("chair", pos, -_toward_door(pos)):
					n += 1
		"levitate":
			# 东西离地悬着，慢慢上下浮动，各自的节奏不一样
			for p in placed:
				if p["place"] in ["wall", "floor", "center"]:
					var n: Node3D = p["node"]
					var base := n.position.y + rng.randf_range(0.25, 0.6)
					var phase := rng.randf() * TAU
					tick(func(tt: float) -> void: n.position.y = base + 0.06 * sin(tt * 0.8 + phase))


# ---------- 灯 ----------

func _lighting() -> void:
	var half := size.x / 2.0
	match recipe["light"]:
		"fluor":
			var n := int(size.z / WALL_STEP)
			for i in n:
				_fluor(Vector3(0, size.y - 0.6, (i - (n - 1) / 2.0) * WALL_STEP), i == 0)
		"bulb":
			_bulb(Color(1.0, 0.72, 0.42), 1.3)
		"warm":
			_bulb(Color(1.0, 0.78, 0.5), 2.0)
		"red":
			_bulb(Color(0.9, 0.12, 0.06), 1.4)
		"oculus":
			_oculus()
		"surgical":
			var spot := SpotLight3D.new()
			spot.light_color = Color(0.85, 0.92, 1.0)
			spot.light_energy = 6.0
			spot.spot_range = size.y + 1.0
			spot.spot_angle = 28.0
			spot.shadow_enabled = true
			_fade(spot)
			spot.position = Vector3(0, size.y - 0.4, 0)
			spot.rotation_degrees = Vector3(-90, 0, 0)
			add_child(spot)
			lights.append(spot)
			var lampshade := CylinderMesh.new()
			lampshade.top_radius = 0.2
			lampshade.bottom_radius = 0.45
			lampshade.height = 0.25
			mesh_at(lampshade, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 0.3, 0)), mat(Color(0.3, 0.32, 0.3), 0.4, 0.6))
			lamp(Vector3(0, size.y - 0.8, 0), Color(0.6, 0.7, 0.75), 0.5, size.x * 0.9)   # 手术灯以外一点冷的底光
	# 很不安的屋子里再加一层暗红的底光
	if dread > 0.7 and recipe["light"] != "red":
		lamp(Vector3(rng.randf_range(-half, half) * 0.5, 0.6, rng.randf_range(-half, half) * 0.5),
			Color(0.6, 0.05, 0.03), 0.7, size.x * 0.8)


## 日光灯：亮着、一阵阵地闪、早灭了，按不安程度挑；steady 的那盏一定稳稳亮着（屋里至少有一盏能看清）
func _fluor(pos: Vector3, steady := false) -> void:
	var housing := mat(Color(0.25, 0.25, 0.23), 0.5, 0.6)
	var cold := Color(0.78, 0.92, 0.86)
	box(Vector3(0.02, 0.6, 0.02), pos + Vector3(-0.4, 0.3, 0), housing)
	box(Vector3(0.02, 0.6, 0.02), pos + Vector3(0.4, 0.3, 0), housing)
	box(Vector3(1.2, 0.1, 0.24), pos, housing)
	var roll := 1.0 if steady else rng.randf()
	var dead := roll < dread * 0.3
	var flicker := not dead and roll < dread * 0.8
	var tube := glow(cold, 0.0 if dead else 2.5)
	box(Vector3(1.1, 0.04, 0.12), pos - Vector3(0, 0.07, 0), tube)
	if dead:
		return
	var l := lamp(pos - Vector3(0, 0.3, 0), cold, 1.2, 9.0, flicker)
	if not flicker:
		return
	var buzz := sound(buzz_wav(), pos, -14.0, 2.0)
	var state := {"on": true, "left": 0.0}
	tick(func(_tt: float) -> void:
		state["left"] -= dt
		if state["left"] <= 0.0:
			state["on"] = not state["on"]
			if state["on"]:
				state["left"] = rng.randf_range(0.03, 0.12) if rng.randf() < 0.6 else rng.randf_range(0.8, 3.0)
			else:
				state["left"] = rng.randf_range(0.04, 0.2) if rng.randf() < 0.8 else rng.randf_range(0.6, 1.5)
		var v := 1.0 if state["on"] else 0.0
		l.light_energy = 1.2 * v
		tube.emission_energy_multiplier = 2.5 * v + 0.05
		buzz.volume_db = -14.0 if state["on"] else -30.0)


## 屋子正中一只吊着的灯泡；不安的会闪
func _bulb(color: Color, energy: float) -> void:
	box(Vector3(0.015, 1.2, 0.015), Vector3(0, size.y - 0.6, 0), mat(Color(0.03, 0.03, 0.03)))
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	var g := glow(color, 3.0)
	mesh_at(bulb, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 1.3, 0)), g)
	var l := lamp(Vector3(0, size.y - 1.4, 0), color, energy, size.x * 0.75 + 3.0)
	if dread > 0.6:
		tick(func(tt: float) -> void:
			var v := 1.0 if sin(tt * 23.0) * sin(tt * 3.7) > -0.85 else 0.15
			l.light_energy = energy * v
			g.emission_energy_multiplier = 3.0 * v)


## 天光：屋顶上一块发光的圆，一束冷光往下照，一小柱雾让光束显形
func _oculus() -> void:
	var sky := CylinderMesh.new()
	sky.top_radius = 1.1 if size.x > WALL_STEP else 0.6
	sky.bottom_radius = sky.top_radius
	sky.height = 0.04
	mesh_at(sky, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 0.02, 0)), glow(Color(0.55, 0.6, 0.68), 1.2))
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.75, 0.82, 0.95)
	spot.light_energy = 7.0
	spot.spot_range = size.y + 2.0
	spot.spot_angle = 16.0
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 4.0
	_fade(spot)
	spot.position = Vector3(0, size.y - 0.05, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	add_child(spot)
	lights.append(spot)
	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
	fog.size = Vector3(3.0, size.y, 3.0)
	var fm := FogMaterial.new()
	fm.density = 0.08
	fm.albedo = Color(0.8, 0.85, 0.9)
	fog.material = fm
	fog.position = Vector3(0, size.y / 2.0, 0)
	add_child(fog)
	lamp(Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.3), 0.9, 6.0)


# ---------- 声音 ----------

func _sound() -> void:
	match recipe["sound"]:
		"hum":
			sound(hum_wav(), Vector3(0, 2.5, 0), -6.0, 2.5)
		"tick":
			var tw := tick_wav()
			for slot in wall_slots():
				if rng.randf() > 0.7:
					continue
				var s := sound(tw, slot["pos"] + slot["normal"] * 0.3 + Vector3(0, 2.5, 0), -10.0, 2.0, false)
				var state := {"every": rng.randf_range(0.45, 1.4), "left": rng.randf()}
				tick(func(_tt: float) -> void:
					state["left"] -= dt
					if state["left"] <= 0.0:
						state["left"] += state["every"]
						s.pitch_scale = rng.randf_range(0.85, 1.25)
						s.play())
		"musicbox":
			sound(musicbox_wav(), Vector3(rng.randf_range(-1.0, 1.0), 1.0, rng.randf_range(-1.0, 1.0)), -8.0, 2.5)
		"drip":
			var dw := drip_wav()
			var half := size.x / 2.0
			for i in (2 if size.x > WALL_STEP else 1):
				var s := sound(dw, Vector3(rng.randf_range(-half, half), 0.2, rng.randf_range(-half, half)), -8.0, 2.0, false)
				var state := {"left": rng.randf_range(0.5, 3.0)}
				tick(func(_tt: float) -> void:
					state["left"] -= dt
					if state["left"] <= 0.0:
						state["left"] = rng.randf_range(0.7, 4.0)
						s.pitch_scale = rng.randf_range(0.8, 1.3)
						s.play())


# ---------- 血 ----------

## 越不安越多：地上几摊、一两道拖痕（从屋子中间拖向门或屋角）；墙上往下淌的血痕、手印、计数；
## 最不安的屋子里还有一两面墙在渗血
func _blood() -> void:
	if dread < 0.3:
		return
	var half := size.x / 2.0
	var area := size.x * size.z
	var layer := [0.03]   # 地上的血一层层略微抬高，免得互相闪烁
	var floor_at := func(x: float, z: float) -> Vector3:
		layer[0] += 0.0005
		return Vector3(x, layer[0], z)
	for i in int(dread * area / 18.0) + rng.randi_range(0, 2):
		props.blood(self, floor_at.call(rng.randf_range(-half + 0.5, half - 0.5), rng.randf_range(-half + 0.5, half - 0.5)),
			rng.randf_range(0.4, 1.5))
	for i in int(dread * 2.0 * (1.0 if size.x > WALL_STEP else 0.6)):
		# 拖痕：从屋子中间附近，朝一扇门或一个屋角拖过去
		var from := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0))
		var to: Vector3 = doors[rng.randi_range(0, doors.size() - 1)] if rng.randf() < 0.5 \
			else Vector3(signf(rng.randf() - 0.5), 0, signf(rng.randf() - 0.5)) * (half - 0.6)
		var dir := (to - from).normalized()
		var w := rng.randf_range(0.5, 0.75)
		var length := minf((to - from).length(), w * Props.BLOOD_ASPECT[Props.DRAG])
		var mid := from + dir * length / 2.0
		props.blood(self, floor_at.call(mid.x, mid.z), w, Props.DRAG, Vector3.UP, atan2(-dir.x, -dir.z) + PI)

	var slots := wall_slots()
	for i in int(dread * slots.size() * 0.8):
		var slot: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
		var y := rng.randf_range(1.0, size.y - 0.6)
		props.blood(self, slot["pos"] + slot["along"] * rng.randf_range(-1.8, 1.8) + slot["normal"] * 0.03
			+ Vector3(0, y, 0), rng.randf_range(0.6, 1.3), Props.DRIP, slot["normal"])
	for i in rng.randi_range(0, int(dread * 4.0)):
		# 手印：大约一人高，扶着墙往下滑
		var slot: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
		props.blood(self, slot["pos"] + slot["along"] * rng.randf_range(-2.0, 2.0) + slot["normal"] * 0.032
			+ Vector3(0, rng.randf_range(0.9, 1.4), 0), rng.randf_range(0.2, 0.26), Props.HAND, slot["normal"])
	if rng.randf() < dread * 0.6:
		var slot: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
		props.blood(self, slot["pos"] + slot["along"] * rng.randf_range(-1.0, 1.0) + slot["normal"] * 0.034
			+ Vector3(0, rng.randf_range(1.0, 1.7), 0), rng.randf_range(1.2, 2.0), Props.TALLY, slot["normal"])
	if dread > 0.75:
		for i in rng.randi_range(1, 2):
			_weep(slots[rng.randi_range(0, slots.size() - 1)])


## 一面墙在渗血：从屋顶下面一点开始，往下一直渗到接近地面
func _weep(slot: Dictionary) -> void:
	var q := QuadMesh.new()
	var h := size.y - 0.4
	q.size = Vector2(rng.randf_range(2.0, 4.0), h)
	var sm := ShaderMaterial.new()
	sm.shader = WeepShader
	sm.set_shader_parameter("seed", rng.randf() * 100.0)
	sm.set_shader_parameter("aspect", q.size.y / q.size.x)
	var nrm: Vector3 = slot["normal"]
	mesh_at(q, Transform3D(facing(nrm), slot["pos"] + slot["along"] * rng.randf_range(-0.5, 0.5) + nrm * 0.036
		+ Vector3(0, size.y - 0.2 - h / 2.0, 0)), sm)


# ---------- 几何工具 ----------

## 四面墙上的“段”：按 5 米分段，去掉门所在的段。
## 返回 [{pos: 段中心贴在墙面上（y = 0）, normal: 朝屋里, along: 沿墙方向}]
func wall_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := size.x / 2.0
	var segs := int(round(size.x / WALL_STEP))
	for nrm: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var along := Vector3(nrm.z, 0, -nrm.x)
		for k in segs:
			var pos := -nrm * half + along * ((k - (segs - 1) / 2.0) * WALL_STEP)
			if is_door(pos):
				continue
			out.append({"pos": pos, "normal": nrm, "along": along})
	return out


func is_door(pos: Vector3) -> bool:
	for d in doors:
		if Vector2(d.x - pos.x, d.z - pos.z).length() < 1.0:
			return true
	return false


func _door_normal(d: Vector3) -> Vector3:
	return -Vector3(signf(d.x) if absf(d.x) > absf(d.z) else 0.0, 0, signf(d.z) if absf(d.z) > absf(d.x) else 0.0)


## 从 pos 朝最近那扇门的方向（水平）
func _toward_door(pos: Vector3) -> Vector3:
	var best := Vector3(0, 0, 1)
	var bd := INF
	for d in doors:
		var v := Vector3(d.x - pos.x, 0, d.z - pos.z)
		if v.length() < bd and v.length() > 0.01:
			bd = v.length()
			best = v.normalized()
	return best


func _more_doors_on_x() -> bool:
	var x := 0
	for d in doors:
		if absf(d.x) > absf(d.z):
			x += 1
	return x >= doors.size() - x


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * k)


## 以 nrm 为朝向（局部 +z 指向 nrm）的基
func facing(nrm: Vector3) -> Basis:
	var z := Vector3(nrm.x, 0, nrm.z).normalized()
	if z.length() < 0.5:
		z = Vector3(0, 0, 1)
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


# ---------- 搭建工具（props.gd 也用） ----------

## 方块：collide 时在同一个父节点下挂一个同样大小的碰撞盒
func box(sz: Vector3, pos: Vector3, material: Material, collide := false, rot := Basis.IDENTITY,
		parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := mesh_at(mesh, Transform3D(rot, pos), material, parent)
	if collide:
		props.solid(parent if parent else self, sz, pos)
	return mi


func mesh_at(mesh: Mesh, xf: Transform3D, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	mi.visibility_range_end = VIS
	mi.visibility_range_end_margin = 5.0
	(parent if parent else self).add_child(mi)
	return mi


func mat(color: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.disable_ambient_light = true
	return m


func glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_ambient_light = true
	return m


func _fade(l: Light3D) -> void:
	l.distance_fade_enabled = true
	l.distance_fade_begin = VIS - 10.0
	l.distance_fade_length = 10.0


## 点光源：离远了淡出，默认不投影（灯多，投影太贵）
func lamp(pos: Vector3, color: Color, energy: float, radius: float, shadows := false, parent: Node3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = shadows
	_fade(l)
	l.position = pos
	(parent if parent else self).add_child(l)
	lights.append(l)
	return l


## 3D 声音，走 Ambience 总线（带混响）；max_distance 外听不见
func sound(stream: AudioStream, pos: Vector3, volume_db := 0.0, unit := 3.0, autoplay := true,
		parent: Node3D = null) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	s.stream = stream
	s.volume_db = volume_db
	s.unit_size = unit
	s.max_distance = 24.0
	s.bus = "Ambience"
	s.position = pos
	(parent if parent else self).add_child(s)
	if autoplay:
		s.play()
	return s


## 把采样（-1～1）打包成 16 位单声道的 AudioStreamWAV
func wav(samples: PackedFloat32Array, rate := 22050, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


## 日光灯镇流器的嗡嗡声：100 Hz 的方波味道 + 一点噪声，一秒一循环
func buzz_wav() -> AudioStreamWAV:
	var rate := 22050
	var s := PackedFloat32Array()
	s.resize(rate)
	for i in rate:
		var tt := float(i) / rate
		var v := 0.5 * sin(TAU * 100.0 * tt) + 0.25 * sin(TAU * 200.0 * tt) + 0.15 * sin(TAU * 300.0 * tt) \
			+ 0.08 * sin(TAU * 1200.0 * tt)
		s[i] = (clampf(v * 1.6, -0.8, 0.8) + rng.randf_range(-0.05, 0.05)) * 0.6
	return wav(s, rate, true)


## 低沉的嗡鸣：55 Hz 加泛音，两个频率差一点点，像在缓慢地呼吸；4 秒一循环
func hum_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 4
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var v := 0.5 * sin(TAU * 55.0 * tt) + 0.3 * sin(TAU * 55.5 * tt) \
			+ 0.18 * sin(TAU * 110.0 * tt) + 0.08 * sin(TAU * 165.25 * tt)
		s[i] = v * (0.75 + 0.25 * sin(TAU * tt / 4.0)) * 0.7
	return wav(s, rate, true)


## 一声滴答：短促的噪声 + 一点高频的金属声，30 毫秒
func tick_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		s[i] = (rng.randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 2600.0 * tt) * 0.5) * exp(-tt * 180.0) * 0.8
	return wav(s, rate, false)


## 八音盒：一段原创的小调旋律，叮叮当当，音准一点点跑偏，越往后越慢，像发条快走完了；约 9 秒一循环
func musicbox_wav() -> AudioStreamWAV:
	var rate := 22050
	var melody := [0, 3, 7, 12, 10, 7, 8, 7, 3, 5, 2, -2, 0, 3, 2, -5]
	var notes: Array[Vector2] = []   # (开始时间, 频率)
	var at := 0.0
	for i in melody.size():
		var semis: float = melody[i]
		notes.append(Vector2(at, 659.25 * pow(2.0, semis / 12.0) * (1.0 + 0.012 * sin(i * 1.7))))
		at += 0.42 + i * 0.018
	var n := int(rate * (at + 1.0))
	var s := PackedFloat32Array()
	s.resize(n)
	for note in notes:
		var start := int(note.x * rate)
		for i in range(start, mini(n, start + int(rate * 1.4))):
			var tt := float(i - start) / rate
			var v := sin(TAU * note.y * tt) + 0.35 * sin(TAU * note.y * 2.0 * tt) + 0.15 * sin(TAU * note.y * 4.1 * tt)
			s[i] += v * exp(-tt * 4.0) * 0.25
	return wav(s, rate, true)


## 不和谐的低音慢慢涌上来又退下去，2.5 秒
func stinger_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var noise := 0.0
	for i in n:
		var tt := float(i) / rate
		var env := smoothstep(0.0, 1.2, tt) * (1.0 - smoothstep(1.6, 2.5, tt))
		noise = noise * 0.97 + rng.randf_range(-1.0, 1.0) * 0.03
		var v := sin(TAU * 55.0 * tt) + 0.8 * sin(TAU * 58.3 * tt) + 0.5 * sin(TAU * 82.4 * tt) + 0.4 * sin(TAU * 116.5 * tt)
		s[i] = (v * 0.25 + noise * 2.0) * env * 0.7
	return wav(s, rate, false)


## 一声闷响：50 Hz 往下沉的重击，0.5 秒
func thud_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var tt := float(i) / rate
		phase += TAU * lerpf(70.0, 35.0, tt / 0.5) / rate
		s[i] = (sin(phase) + rng.randf_range(-0.2, 0.2) * exp(-tt * 30.0)) * exp(-tt * 7.0) * 0.9
	return wav(s, rate, false)


## 一滴水（或血）落地：音高往下滑的短“噗”声，120 毫秒
func drip_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var tt := float(i) / rate
		phase += TAU * lerpf(1400.0, 500.0, tt / 0.12) / rate
		s[i] = sin(phase) * exp(-tt * 40.0) * 0.6
	return wav(s, rate, false)
