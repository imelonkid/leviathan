extends Node3D
## 雨：跟着镜头的一片雨丝（GPU 粒子），加上雨声——铺底的沙沙声（立体声循环）
## 和身边打在石头、铁栏杆上的雨点（3D，一声一声的）。雨的大小慢慢起伏。
## 走进屋里（soundscape.indoor）看不见雨，雨声变闷变小，身边的雨点停掉。
## 声音走 Rain 总线，Rain 再送进 World 总线，跟着分区混响走。

const RATE := 22050
const AMOUNT := 3000             # 雨丝数量；乌云低档时减到四成
const FALL := 22.0               # 雨丝下落速度（米/秒）
const TICK_RADIUS := 7.0         # 身边的雨点落在多远以内
const RAIN_DB := -10.0

var settings: Node               # main 注入
var soundscape: Node

var particles: GPUParticles3D
var bed: AudioStreamPlayer
var ticks: Array[AudioStreamWAV] = []
var metal: Array[AudioStreamWAV] = []
var pool: Array[AudioStreamPlayer3D] = []
var lp: AudioEffectLowPassFilter
var rain_bus := -1
var rng := RandomNumberGenerator.new()
var tick_t := 0.0
var level := 0.7                 # 雨的大小 0～1
var inside := 0.0                # 0 屋外 ～ 1 屋里，平滑过
var t := 0.0


func _ready() -> void:
	rng.randomize()
	rain_bus = AudioServer.get_bus_index("Rain")
	if rain_bus < 0:
		AudioServer.add_bus()
		rain_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(rain_bus, "Rain")
		AudioServer.set_bus_send(rain_bus, "World")
		AudioServer.add_bus_effect(rain_bus, AudioEffectLowPassFilter.new())
	lp = AudioServer.get_bus_effect(rain_bus, 0) as AudioEffectLowPassFilter
	lp.cutoff_hz = 20000.0

	_build_particles()

	bed = AudioStreamPlayer.new()
	bed.stream = _bed_wav()
	bed.bus = "Rain"
	bed.volume_db = RAIN_DB
	add_child(bed)
	bed.play()

	for i in 5:
		ticks.append(_tick_wav(false))
	for i in 3:
		metal.append(_tick_wav(true))
	for i in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Rain"
		p.unit_size = 2.5
		p.max_distance = 20.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		pool.append(p)

	if settings:
		settings.changed.connect(_apply_quality)
	_apply_quality()


func _build_particles() -> void:
	particles = GPUParticles3D.new()
	particles.amount = AMOUNT
	particles.lifetime = 1.0
	particles.preprocess = 1.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-24, -30, -24), Vector3(48, 40, 48))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(20, 0.5, 20)
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = FALL - 2.0
	pm.initial_velocity_max = FALL + 2.0
	pm.gravity = Vector3(0, -4, 0)
	particles.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.68, 0.8, 0.16)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	# 贴着镜头的雨丝会变成一根粗棍子：近处淡掉
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.2
	m.distance_fade_max_distance = 3.5
	q.material = m
	particles.draw_pass_1 = q
	add_child(particles)


func _apply_quality() -> void:
	var low: bool = settings != null and settings.get_value("clouds") == 0
	particles.amount = int(AMOUNT * (0.4 if low else 1.0))


func _process(delta: float) -> void:
	t += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 雨的大小：几分钟一个起伏，偶尔一阵大的
	level = clampf(0.55 + 0.25 * sin(t * 0.021) + 0.2 * sin(t * 0.0537 + 1.3), 0.15, 1.0)
	var target := 1.0 if soundscape and soundscape.indoor else 0.0
	inside = move_toward(inside, target, delta * 1.5)

	var fwd := -cam.global_basis.z
	particles.global_position = cam.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 8.0 + Vector3(0, 14, 0)
	particles.amount_ratio = level
	particles.visible = inside < 0.5

	lp.cutoff_hz = lerpf(20000.0, 650.0, inside)
	bed.volume_db = RAIN_DB + linear_to_db(maxf(level, 0.05)) - inside * 8.0

	if inside > 0.5:
		return
	tick_t -= delta
	if tick_t <= 0.0:
		tick_t = rng.randf_range(0.06, 0.3) / maxf(level, 0.2)
		_tick(cam.global_position)


## 身边一滴：落在镜头周围的地上、墙上或者栏杆上
func _tick(around: Vector3) -> void:
	for p in pool:
		if p.playing:
			continue
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, TICK_RADIUS)
		p.global_position = around + Vector3(cos(a) * r, rng.randf_range(-1.6, 1.5), sin(a) * r)
		var is_metal := rng.randf() < 0.25
		p.stream = metal[rng.randi_range(0, metal.size() - 1)] if is_metal else ticks[rng.randi_range(0, ticks.size() - 1)]
		p.pitch_scale = rng.randf_range(0.85, 1.2)
		p.volume_db = rng.randf_range(-14.0, -4.0) - (4.0 if is_metal else 0.0)
		p.play()
		return


# ---------- 合成 ----------

## 铺底的雨声：两个声道各自独立的沙沙声（宽），里面密密的细小雨点；
## 8 秒一循环，尾巴叠进开头，接缝听不出来
func _bed_wav() -> AudioStreamWAV:
	var n := RATE * 8
	var fade := RATE / 2
	var l := _bed_channel(n + fade)
	var r := _bed_channel(n + fade)
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		var a := l[i]
		var b := r[i]
		if i < fade:
			var k := float(i) / fade
			a = a * k + l[n + i] * (1.0 - k)
			b = b * k + r[n + i] * (1.0 - k)
		data.encode_s16(i * 4, int(clampf(a, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, int(clampf(b, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = true
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _bed_channel(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var drop := 0.0
	var drop_amp := 0.0
	var drop_decay := 0.0
	var hp_prev := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += (w - lp1) * 0.5
		lp2 += (lp1 - lp2) * 0.02
		var hiss := (lp1 - lp2) * 0.22
		if rng.randf() < 420.0 / RATE:
			drop = 1.0
			drop_amp = pow(rng.randf_range(0.15, 0.8), 2.0)
			drop_decay = exp(-1.0 / (RATE * rng.randf_range(0.0015, 0.005)))
		drop *= drop_decay
		var hp := w - hp_prev
		hp_prev = w
		out[i] = hiss + hp * drop * drop_amp * 0.6
	return out


## 一滴雨：打在石头上是一声短促的“嗒”；打在铁栏杆上是一声细细的“叮”
func _tick_wav(is_metal: bool) -> AudioStreamWAV:
	var n := int(RATE * (0.35 if is_metal else 0.08))
	var out := PackedFloat32Array()
	out.resize(n)
	var f := [rng.randf_range(1700.0, 2400.0), rng.randf_range(2900.0, 3600.0), rng.randf_range(4300.0, 5200.0)]
	var lp1 := 0.0
	var cut := rng.randf_range(0.3, 0.6)
	for i in n:
		var tt := float(i) / RATE
		lp1 += (rng.randf_range(-1.0, 1.0) - lp1) * cut
		var s := lp1 * exp(-tt * 300.0) * 0.9
		if is_metal:
			s += (sin(TAU * f[0] * tt) * 0.5 + sin(TAU * f[1] * tt) * 0.3 + sin(TAU * f[2] * tt) * 0.2) * exp(-tt * 14.0) * 0.35
		out[i] = s
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(out[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
