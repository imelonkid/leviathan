extends "res://scripts/rooms/room.gd"
## 病房：墙裙和地面铺着发黄的旧瓷砖，两排铁床靠墙，有的歪了、翻了、没床垫。
## 天花板上三盏灯：一盏昏暗地亮着，一盏一阵阵地闪（伴着镇流器的嗡嗡声），一盏早就灭了。

const TilesShader = preload("res://scripts/rooms/tiles.gdshader")

const WAINSCOT := 2.2            # 墙裙高度
const BED_L := 2.0
const BED_W := 0.9

var flicker_light: OmniLight3D
var flicker_glow: StandardMaterial3D
var buzz: AudioStreamPlayer3D
var flick_t := 0.0
var flick_on := true


func _build() -> void:
	var tiles := ShaderMaterial.new()
	tiles.shader = TilesShader
	var floor_tiles := ShaderMaterial.new()
	floor_tiles.shader = TilesShader
	floor_tiles.set_shader_parameter("tile_size", 0.3)
	floor_tiles.set_shader_parameter("missing", 0.05)
	floor_tiles.set_shader_parameter("tile_color", Color(0.4, 0.4, 0.36))

	box(Vector3(size.x, 0.04, size.z), Vector3(0, 0.02, 0), floor_tiles)
	for slot in wall_slots():
		var nrm: Vector3 = slot["normal"]
		var along: Vector3 = slot["along"]
		var sz := along.abs() * WALL_STEP + nrm.abs() * 0.05 + Vector3(0, WAINSCOT, 0)
		box(sz, slot["pos"] + nrm * 0.025 + Vector3(0, WAINSCOT / 2.0, 0), tiles)

	_beds()
	_lamps()


## 两排床：挑门少的一对对面墙，床头顶着墙
func _beds() -> void:
	var iron := mat(Color(0.2, 0.19, 0.18), 0.6, 0.7)
	var rust := mat(Color(0.32, 0.18, 0.1), 0.9, 0.3)
	var cloth := mat(Color(0.55, 0.52, 0.44), 0.95)
	var x_doors := 0
	for d in doors:
		if absf(d.x) > absf(d.z):
			x_doors += 1
	var nrms: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	if x_doors >= doors.size() - x_doors:
		nrms = [Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for slot in wall_slots():
		if not nrms.has(slot["normal"]):
			continue
		for off: float in [-1.2, 1.2]:
			var nrm: Vector3 = slot["normal"]
			var pos: Vector3 = slot["pos"] + slot["along"] * off + nrm * (BED_L / 2.0 + 0.1)
			var roll := rng.randf()
			var frame := rust if rng.randf() < 0.4 else iron
			if roll < 0.12:
				# 翻倒的床：侧躺在地上
				var rot := facing(nrm) * Basis(Vector3(0, 0, 1), deg_to_rad(95))
				_bed(pos + Vector3(0, 0.45, 0), rot, frame, null)
			else:
				var yaw := Basis(Vector3.UP, deg_to_rad(rng.randf_range(-7.0, 7.0)))
				_bed(pos, yaw * facing(nrm), frame, cloth if roll > 0.3 else null)


## 一张铁床：局部 +z 指向床尾，床头在 -z
func _bed(pos: Vector3, rot: Basis, frame: Material, mattress: Material) -> void:
	var bed := Node3D.new()
	bed.transform = Transform3D(rot, pos)
	add_child(bed)
	var hl := BED_L / 2.0
	var hw := BED_W / 2.0
	for sx: float in [-hw, hw]:
		for sz: float in [-hl, hl]:
			box(Vector3(0.05, 0.5, 0.05), Vector3(sx, 0.25, sz), frame, false, Basis.IDENTITY, bed)
		box(Vector3(0.05, 0.06, BED_L), Vector3(sx, 0.45, 0), frame, false, Basis.IDENTITY, bed)
		# 床头的两根立柱
		box(Vector3(0.05, 1.1, 0.05), Vector3(sx, 0.55, -hl), frame, false, Basis.IDENTITY, bed)
	for y: float in [0.75, 1.05]:
		box(Vector3(BED_W, 0.04, 0.04), Vector3(0, y, -hl), frame, false, Basis.IDENTITY, bed)
	for i in 5:
		box(Vector3(0.025, 0.3, 0.025), Vector3(-hw + BED_W * (i + 1) / 6.0, 0.9, -hl), frame, false, Basis.IDENTITY, bed)
	box(Vector3(BED_W, 0.04, 0.04), Vector3(0, 0.7, hl), frame, false, Basis.IDENTITY, bed)
	if mattress:
		box(Vector3(BED_W - 0.06, 0.16, BED_L - 0.1), Vector3(0, 0.56, 0), mattress, false, Basis.IDENTITY, bed)
	# 碰撞只要一个整块
	var shape := BoxShape3D.new()
	shape.size = Vector3(BED_W, 0.7, BED_L)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	cs.global_transform = bed.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.35, 0))


## 三盏吊灯沿屋子中线：亮、闪、灭各一盏，顺序随机
func _lamps() -> void:
	var housing := mat(Color(0.25, 0.25, 0.23), 0.5, 0.6)
	var states := ["on", "flicker", "dead"]
	for i in 3:
		var j := rng.randi_range(i, 2)
		var tmp: String = states[i]
		states[i] = states[j]
		states[j] = tmp
	var cold := Color(0.78, 0.92, 0.86)
	for i in 3:
		var pos := Vector3(0, size.y - 0.6, (i - 1) * WALL_STEP)
		box(Vector3(0.02, 0.6, 0.02), pos + Vector3(-0.4, 0.3, 0), housing)
		box(Vector3(0.02, 0.6, 0.02), pos + Vector3(0.4, 0.3, 0), housing)
		box(Vector3(1.2, 0.1, 0.24), pos, housing)
		var tube := glow(cold, 0.0 if states[i] == "dead" else 2.5)
		box(Vector3(1.1, 0.04, 0.12), pos - Vector3(0, 0.07, 0), tube)
		match states[i]:
			"on":
				lamp(pos - Vector3(0, 0.3, 0), cold, 0.9, 9.0)
			"flicker":
				flicker_light = lamp(pos - Vector3(0, 0.3, 0), cold, 1.6, 10.0, true)
				flicker_glow = tube
				buzz = sound(_buzz_wav(), pos, -14.0, 2.0)


## 日光灯镇流器的嗡嗡声：100 Hz 的方波味道 + 一点噪声，一秒一循环
func _buzz_wav() -> AudioStreamWAV:
	var rate := 22050
	var s := PackedFloat32Array()
	s.resize(rate)
	for i in rate:
		var t := float(i) / rate
		var v := 0.5 * sin(TAU * 100.0 * t) + 0.25 * sin(TAU * 200.0 * t) + 0.15 * sin(TAU * 300.0 * t) \
			+ 0.08 * sin(TAU * 1200.0 * t)
		s[i] = (clampf(v * 1.6, -0.8, 0.8) + randf_range(-0.05, 0.05)) * 0.6
	return wav(s, rate, true)


## 闪的那盏：亮一阵、啪啪地闪几下、灭一会儿
func _process(delta: float) -> void:
	if flicker_light == null:
		return
	flick_t -= delta
	if flick_t <= 0.0:
		flick_on = not flick_on
		if flick_on:
			flick_t = rng.randf_range(0.03, 0.12) if rng.randf() < 0.6 else rng.randf_range(0.8, 3.0)
		else:
			flick_t = rng.randf_range(0.04, 0.2) if rng.randf() < 0.8 else rng.randf_range(0.6, 1.5)
	var v := 1.0 if flick_on else 0.0
	flicker_light.light_energy = 1.6 * v
	flicker_glow.emission_energy_multiplier = 2.5 * v + 0.05
	buzz.volume_db = -14.0 if flick_on else -30.0
