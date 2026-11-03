extends Node3D
## 落下的灰烬与碎屑。
## 灰烬：跟着镜头的一团炭灰、纸灰碎片（GPU 粒子，ash.gdshader），跟着同一阵风斜着慢慢往下落，大片的翻转。
## 不吃环境光和月光：暗处看不见，提灯照过去、闪电一亮才显形，背着亮天是黑色的剪影。
## 屋里、头顶有遮挡和窄巷更密，开阔处稀；露天下雨时被雨打下来。乌云低档时数量减半。
## 碎屑：每隔一阵，身边某段墙的墙头掉下几块碎石，落地扬起一小团尘，带一声轻响（声音在代码里合成）。

const MazeGen = preload("res://scripts/maze_gen.gd")
const AshShader = preload("res://scripts/ash.gdshader")

const RATE := 22050
const AMOUNT := 1500             # 灰烬片数；乌云低档减半
const BOX := Vector3(8, 4, 8)    # 灰烬在镜头周围多大一团（半宽、半高、半深，米）
const WIND := Vector3(0.35, -0.45, 0.12)   # 灰烬落下的速度和风向（米/秒）
const GRIT_MIN := 7.0            # 两次掉碎屑之间的间隔（秒）
const GRIT_MAX := 18.0
const GRIT_REACH := 4            # 在镜头周围几块以内找墙
const GRIT_DROP_MIN := 4.0       # 墙头至少比落点高这么多才掉（矮墙不掉）
const GRIT_DB := -10.0

var settings: Node               # main 注入
var maze: Node3D
var soundscape: Node             # 读 indoor、openness
var rain: Node                   # 读 level

var particles: GPUParticles3D
var density := 0.5               # 平滑过的灰尘浓度 0～1
var grit_t := 5.0
var grit_sounds: Array[AudioStreamWAV] = []
var stone_mat: StandardMaterial3D
var puff_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build_dust()
	stone_mat = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.5, 0.46, 0.4)
	stone_mat.roughness = 1.0
	puff_mat = StandardMaterial3D.new()
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.albedo_color = Color(0.55, 0.5, 0.44)
	puff_mat.proximity_fade_enabled = true
	puff_mat.proximity_fade_distance = 0.4
	for i in 3:
		grit_sounds.append(_grit_wav())
	if settings:
		settings.changed.connect(_apply_quality)
	_apply_quality()


func _build_dust() -> void:
	particles = GPUParticles3D.new()
	particles.amount = AMOUNT
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(-BOX - Vector3.ONE * 4.0, (BOX + Vector3.ONE * 4.0) * 2.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX
	# 全体跟着同一阵风斜着往下落，只带一点点晃，不各飘各的
	pm.direction = WIND.normalized()
	pm.spread = 8.0
	pm.initial_velocity_min = WIND.length() * 0.7
	pm.initial_velocity_max = WIND.length() * 1.2
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.005
	pm.turbulence_influence_max = 0.02
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	# 生出来和消失时都淡一下，不会一片片地蹦出来
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	particles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := ShaderMaterial.new()
	m.shader = AshShader
	q.material = m
	particles.draw_pass_1 = q
	add_child(particles)


func _apply_quality() -> void:
	var low: bool = settings != null and settings.get_value("clouds") == 0
	particles.amount = int(AMOUNT * (0.5 if low else 1.0))


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 往上风处偏一点：落到镜头这儿时正好在身边
	particles.global_position = cam.global_position - WIND * 4.0
	var indoor: bool = soundscape != null and soundscape.indoor
	var open: float = soundscape.openness if soundscape else 0.5
	var goal := lerpf(1.0, 0.25, open)
	if not indoor and rain:
		goal *= 1.0 - 0.75 * clampf(rain.level, 0.0, 1.0) * open
	density = move_toward(density, goal, delta * 0.3)
	particles.amount_ratio = density

	grit_t -= delta
	if grit_t <= 0.0:
		grit_t = rng.randf_range(GRIT_MIN, GRIT_MAX)
		if not indoor:
			_drop_grit(cam)


## 身边找一段高墙：墙头沿着朝向街道的那一面掉几块碎石，落地扬尘、一声轻响
func _drop_grit(cam: Camera3D) -> void:
	if maze == null or maze.gen == null:
		return
	var gen: RefCounted = maze.gen
	var here: Vector2 = maze.world_to_block(cam.global_position)
	var fwd := -cam.global_basis.z
	for attempt in 12:
		var x := int(here.x) + rng.randi_range(-GRIT_REACH, GRIT_REACH)
		var z := int(here.y) + rng.randi_range(-GRIT_REACH, GRIT_REACH)
		if x < 1 or z < 1 or x >= gen.n - 1 or z >= gen.n - 1:
			continue
		if gen.kind[z][x] != MazeGen.WALL or gen.landmark[z][x]:
			continue
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[rng.randi_range(0, 3)]
		var ox := x + d.x
		var oz := z + d.y
		if not gen.is_open(ox, oz) or gen.span[oz][ox] or not is_nan(gen.overpass[oz][ox]):
			continue
		var top: float = gen.wall_top[z][x]
		var floor_y: float = gen.floor_height(ox, oz)
		if top - floor_y < GRIT_DROP_MIN:
			continue
		var face: Vector3 = maze._block_to_world(x, z) + Vector3(d.x, 0, d.y) * (maze.block / 2.0 + 0.1)
		face += Vector3(d.y, 0, d.x) * rng.randf_range(-1.5, 1.5)
		# 落在看得见的那边：背后的不掉
		var to := face - cam.global_position
		if Vector2(to.x, to.z).normalized().dot(Vector2(fwd.x, fwd.z).normalized()) < 0.2:
			continue
		_grit(Vector3(face.x, top, face.z), floor_y, Vector3(d.x, 0, d.y))
		return


func _grit(from: Vector3, floor_y: float, out: Vector3) -> void:
	var fall := sqrt(2.0 * (from.y - floor_y) / 9.8)
	var stones := GPUParticles3D.new()
	stones.one_shot = true
	stones.amount = rng.randi_range(4, 8)
	stones.lifetime = fall + 0.05
	stones.explosiveness = 0.7
	stones.local_coords = false
	stones.visibility_aabb = AABB(Vector3(-3, floor_y - from.y - 2, -3), Vector3(6, from.y - floor_y + 4, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.4, 0.1, 0.4)
	pm.direction = out
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	stones.process_material = pm
	var chip := BoxMesh.new()
	chip.size = Vector3(0.08, 0.06, 0.07)
	chip.material = stone_mat
	stones.draw_pass_1 = chip
	stones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stones)
	stones.global_position = from + out * 0.2
	stones.emitting = true

	var land := Vector3(from.x, floor_y, from.z) + out * 0.5
	get_tree().create_timer(fall).timeout.connect(_landed.bind(land))
	get_tree().create_timer(fall + 3.0).timeout.connect(stones.queue_free)


## 落地：一小团慢慢散开、淡掉的尘，一声轻响
func _landed(at: Vector3) -> void:
	var puff := GPUParticles3D.new()
	puff.one_shot = true
	puff.amount = 14
	puff.lifetime = 2.5
	puff.explosiveness = 0.9
	puff.local_coords = false
	puff.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 90.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.05, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.2
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.45))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	puff.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.material = puff_mat
	puff.draw_pass_1 = q
	add_child(puff)
	puff.global_position = at + Vector3(0, 0.2, 0)
	puff.emitting = true
	get_tree().create_timer(3.5).timeout.connect(puff.queue_free)

	var p := AudioStreamPlayer3D.new()
	p.stream = grit_sounds[rng.randi_range(0, grit_sounds.size() - 1)]
	p.bus = "World"
	p.volume_db = GRIT_DB
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.pitch_scale = rng.randf_range(0.85, 1.15)
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


# ---------- 合成 ----------

## 碎屑落地：一下闷闷的着地声，紧跟着几颗小石子散开的“嗒嗒”，最后一点沙沙的尘
func _grit_wav() -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits: Array[Vector2] = [Vector2(0.0, 1.0)]   # (时间, 响度)
	for i in rng.randi_range(4, 7):
		hits.append(Vector2(rng.randf_range(0.03, 0.45), rng.randf_range(0.15, 0.5)))
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += (w - lp1) * 0.08
		lp2 += (w - lp2) * 0.5
		# 着地：低沉的一下
		var s := lp1 * 2.5 * exp(-t * 35.0)
		# 石子：每颗是一下很短的高频噪声
		for h in hits:
			if h.x > 0.0 and t >= h.x:
				s += (w - lp2) * h.y * exp(-(t - h.x) * 260.0)
		# 尘：一点渐弱的沙沙
		s += (lp2 - lp1) * 0.08 * exp(-t * 4.0)
		out[i] = s * 0.8
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	return wav
