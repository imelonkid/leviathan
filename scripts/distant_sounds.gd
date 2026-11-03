extends Node
## 远处的动静：每隔一阵在某个方向放一声，告诉你这座迷宫里不只你一个。
## - 远处的金属：很远的地方有人拖动、敲了一下一块巨大的铁板，低沉、拖着长回响（60～150 米外，随机方向）；
## - 铁链：一串叮当加拖地声，附近有搭出来的房间时更常听到；
## - 门轴：附近某扇门慢慢吱呀一声，只在小楼和房间附近；
## - 低语：最少见。在不安的屋子里、或刚被黑光扫过之后，从背后传来几秒听不出字的气声；
## - 钟楼的钟：迷宫里的钟楼每隔几分钟真的敲几下，声音从那座钟楼传来，可以拿来认方向。
## 两声之间至少隔 MIN_GAP 秒；被黑光吸走声音时不放；大雨盖住一部分远处的声音；在屋里远处的声音发闷。
## 声音全部在代码里合成（开局在后台线程里合成，不卡画面），走 World 总线（跟着分区混响和“吸走”）。

const Synth = preload("res://scripts/synth.gd")
const RATE := Synth.RATE
const MIN_GAP := 20.0            # 两声之间至少隔多久（秒）
const MAX_GAP := 55.0
const BELL_MIN := 150.0          # 钟楼多久敲一次
const BELL_MAX := 300.0
const WHISPER_AFTER := 12.0      # 被黑光扫过之后多久之内可能听见低语
const DB := {"metal": -2.0, "chain": -8.0, "creak": -10.0, "whisper": -16.0, "bell": 2.0}

var player: Node3D               # main 注入
var maze: Node3D
var soundscape: Node             # 读 indoor、hush
var rain: Node                   # 读 level

var lib := {}                    # 种类 → [AudioStreamWAV]
var pool: Array[AudioStreamPlayer3D] = []
var next_t := 30.0
var bell_t := 60.0
var since_hush := 999.0
var rng := RandomNumberGenerator.new()
var ready_lib := false
var worker: Thread
var tolls: Array[Vector4] = []   # 还没敲的钟：(还剩几秒, x, y, z)
var synth_rng := RandomNumberGenerator.new()   # 合成用（后台线程）


func _ready() -> void:
	rng.randomize()
	synth_rng.randomize()
	for i in 4:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.max_distance = 0.0
		add_child(p)
		pool.append(p)
	worker = Thread.new()
	worker.start(_build_library)


func _exit_tree() -> void:
	if worker and worker.is_started():
		worker.wait_to_finish()


## 在后台线程里合成全部声音；合成用自己的随机数，不和主线程抢
func _build_library() -> void:
	var makers := [
		["metal", _metal_wav.bind(false)], ["metal", _metal_wav.bind(true)], ["metal", _metal_wav.bind(false)],
		["chain", _chain_wav], ["chain", _chain_wav],
		["creak", _creak_wav], ["creak", _creak_wav],
		["whisper", _whisper_wav], ["whisper", _whisper_wav],
		["bell", _bell_wav],
	]
	var out := {}
	for mk: Array in makers:
		var key: String = mk[0]
		if not out.has(key):
			out[key] = []
		out[key].append((mk[1] as Callable).call())
	_library_done.call_deferred(out)


func _library_done(out: Dictionary) -> void:
	lib = out
	ready_lib = true


func _process(delta: float) -> void:
	if not ready_lib or player == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var hush: float = soundscape.hush if soundscape else 0.0
	since_hush = 0.0 if hush > 0.3 else since_hush + delta
	if hush > 0.2:
		return
	for i in range(tolls.size() - 1, -1, -1):
		tolls[i].x -= delta
		if tolls[i].x <= 0.0:
			_play("bell", Vector3(tolls[i].y, tolls[i].z, tolls[i].w), 45.0)
			tolls.remove_at(i)
	bell_t -= delta
	if bell_t <= 0.0:
		bell_t = rng.randf_range(BELL_MIN, BELL_MAX)
		_toll(cam)
	next_t -= delta
	if next_t > 0.0:
		return
	next_t = rng.randf_range(MIN_GAP, MAX_GAP)
	_pick(cam)


## 按周围的情况挑一种：远处的金属总有份，附近有房间多些铁链和门轴，不安的屋里、黑光扫过后才可能有低语
func _pick(cam: Camera3D) -> void:
	var near_room := _near_room(cam.global_position)
	var near_house := _near_house(cam.global_position)
	var w := {"metal": 3.0, "chain": 1.0, "creak": 0.0, "whisper": 0.0}
	if near_room:
		w["chain"] += 2.0
		w["creak"] += 1.5
	if near_house != Vector3.INF:
		w["creak"] += 2.0
	if (near_room and near_room.get("dread") > 0.5) or since_hush < WHISPER_AFTER:
		w["whisper"] = 1.2
	var total := 0.0
	for k: String in w:
		total += w[k]
	var r := rng.randf() * total
	for k: String in w:
		r -= w[k]
		if r <= 0.0:
			_play_kind(k, cam, near_house)
			return


func _play_kind(kind: String, cam: Camera3D, near_house: Vector3) -> void:
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	match kind:
		"metal":
			var a := rng.randf() * TAU
			_play("metal", eye + Vector3(cos(a), 0.3, sin(a)) * rng.randf_range(60.0, 150.0), 30.0)
		"chain":
			var a := rng.randf() * TAU
			_play("chain", eye + Vector3(cos(a), 0.1, sin(a)) * rng.randf_range(8.0, 25.0), 6.0)
		"creak":
			var at := near_house + Vector3(0, 1.5, 0) if near_house != Vector3.INF \
				else eye + Vector3(rng.randf_range(-1, 1), 0.1, rng.randf_range(-1, 1)).normalized() * rng.randf_range(6.0, 14.0)
			_play("creak", at, 5.0)
		"whisper":
			# 从背后，偏一边，贴得很近
			var side := Vector3(-fwd.z, 0, fwd.x) * rng.randf_range(-0.8, 0.8)
			_play("whisper", eye - fwd * rng.randf_range(1.2, 2.0) + side + Vector3(0, -0.1, 0), 1.2)


## 钟楼：敲一到三下，隔三秒一下；没有钟楼就算了
func _toll(cam: Camera3D) -> void:
	if maze == null or maze.gen == null:
		return
	var bells: Array[Vector3] = []
	for t: Dictionary in maze.gen.towers:
		if t["kind"] == 0:
			var b: Vector2i = t["block"]
			bells.append(maze._block_to_world(b.x, b.y) + Vector3(0, t["base"] + 22.0, 0))
	if bells.is_empty():
		return
	# 离得近的那座更可能
	bells.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_to(cam.global_position) < b.distance_to(cam.global_position))
	var at: Vector3 = bells[0] if rng.randf() < 0.7 else bells[rng.randi_range(0, bells.size() - 1)]
	for i in rng.randi_range(1, 3):
		tolls.append(Vector4(i * 3.2, at.x, at.y, at.z))


func _play(kind: String, at: Vector3, unit: float) -> void:
	var p: AudioStreamPlayer3D = null
	for q in pool:
		if not q.playing:
			p = q
			break
	if p == null:
		return
	var streams: Array = lib[kind]
	p.stream = streams[rng.randi_range(0, streams.size() - 1)]
	p.unit_size = unit
	p.pitch_scale = rng.randf_range(0.9, 1.08)
	var db: float = DB[kind]
	var far := kind == "metal" or kind == "bell"
	var indoor: bool = soundscape != null and soundscape.indoor
	if far and rain:
		db -= clampf(rain.level, 0.0, 1.0) * 6.0        # 大雨盖住远处的声音
	if indoor and kind != "whisper":
		db -= 6.0
	p.volume_db = db
	p.attenuation_filter_cutoff_hz = 1200.0 if indoor and kind != "whisper" else 5000.0
	p.global_position = at
	p.play()


func _near_room(at: Vector3) -> Node:
	if maze == null:
		return null
	for r: Node in maze.room_nodes.values():
		if (r as Node3D).global_position.distance_to(at) < 25.0:
			return r
	return null


func _near_house(at: Vector3) -> Vector3:
	if maze == null or maze.gen == null:
		return Vector3.INF
	for h: Dictionary in maze.gen.houses:
		var b: Vector2i = h["block"]
		var f := Vector3(h["face"].x, 0, h["face"].y)
		var porch: Vector3 = maze._block_to_world(b.x, b.y) + Vector3(0, h["base"], 0) + f * 1.5
		if porch.distance_to(at) < 30.0:
			return porch
	return Vector3.INF


# ---------- 合成 ----------

## 远处的金属：一块巨大的铁板，几个不成谐和的低频分音慢慢衰减，开头一下闷击；
## drag = 拖动：先是一段粗糙的刮擦，再落下那一下
func _metal_wav(drag: bool) -> AudioStreamWAV:
	var dur := 6.5 if drag else 5.0
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var f0 := synth_rng.randf_range(38.0, 55.0)
	var ratios := [1.0, 1.73, 2.41, 3.37, 4.62, 6.1]
	var amps := [1.0, 0.7, 0.5, 0.35, 0.22, 0.12]
	var decays := [0.9, 1.1, 1.4, 1.9, 2.6, 3.4]
	var hit := 1.6 if drag else 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		if t >= hit:
			var th := t - hit
			for k in ratios.size():
				var f: float = f0 * ratios[k] * (1.0 + 0.004 * sin(TAU * 0.3 * th + k))
				s += sin(TAU * f * th) * amps[k] * exp(-th * decays[k])
			var w := synth_rng.randf_range(-1.0, 1.0)
			lp += (w - lp) * 0.06
			s += lp * 3.0 * exp(-th * 18.0)                        # 落下那一下的闷击
		if drag and t < hit + 0.2:
			# 刮擦：低通过的噪声，粗糙地一顿一顿
			var w2 := synth_rng.randf_range(-1.0, 1.0)
			lp2 += (w2 - lp2) * 0.12
			var grit := 0.6 + 0.4 * sin(TAU * 7.0 * t + sin(TAU * 1.3 * t) * 3.0)
			var env := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(hit - 0.1, hit + 0.2, t))
			s += lp2 * grit * env * 1.6 + sin(TAU * f0 * 2.3 * t) * 0.15 * env
		out[i] = s * 0.32
	return _wav(_fade_out(out, 0.4))


## 铁链：一串短促的金属叮当（高频分音、很快衰减），节奏一阵密一阵疏，底下一点拖地的沙沙
func _chain_wav() -> AudioStreamWAV:
	var dur := synth_rng.randf_range(1.6, 2.4)
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var hits: Array[Vector3] = []   # (时间, 响度, 基频)
	var t := 0.05
	while t < dur - 0.3:
		hits.append(Vector3(t, synth_rng.randf_range(0.3, 1.0), synth_rng.randf_range(1800.0, 3400.0)))
		t += synth_rng.randf_range(0.02, 0.12) * (1.0 + 2.0 * sin(t * 3.0) ** 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / RATE
		var s := 0.0
		for h in hits:
			if tt >= h.x and tt < h.x + 0.25:
				var d := tt - h.x
				s += (sin(TAU * h.z * d) + 0.6 * sin(TAU * h.z * 1.47 * d) + 0.4 * sin(TAU * h.z * 2.13 * d)) * h.y * exp(-d * 28.0)
		var w := synth_rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.15
		s += lp * 0.25 * sin(PI * tt / dur)
		out[i] = s * 0.22
	return _wav(_fade_out(out, 0.15))


## 门轴：粘滞—滑动的吱呀声。一个低音高的锯齿波，音高慢慢往上走又落下，振幅一顿一顿地抖
func _creak_wav() -> AudioStreamWAV:
	var dur := synth_rng.randf_range(1.6, 2.6)
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var base := synth_rng.randf_range(170.0, 260.0)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var f := base * (1.0 + 0.6 * sin(PI * u)) * (1.0 + 0.03 * sin(TAU * 11.0 * t))
		phase = fmod(phase + f / RATE, 1.0)
		var saw := phase * 2.0 - 1.0
		# 粘滞—滑动：振幅按一个不规则的节拍一跳一跳
		var stick := 0.5 + 0.5 * sin(TAU * (18.0 + 10.0 * u) * t + 2.0 * sin(TAU * 3.0 * t))
		stick = stick * stick
		var env := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.75, 1.0, u))
		var s := saw * stick * env
		hp = 0.9 * (hp + s - prev)                                 # 去掉最低的一截，声音细一点
		prev = s
		out[i] = hp * 0.35
	return _wav(out)


## 低语：气声（噪声）通过两三个共振峰滤波器，共振峰一段一段地换，像是在说话——但不是任何一种语言，听不出字
func _whisper_wav() -> AudioStreamWAV:
	var dur := synth_rng.randf_range(2.6, 3.8)
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var vowels := [Vector2(700, 1200), Vector2(400, 2000), Vector2(550, 900), Vector2(300, 2300), Vector2(600, 1700)]
	var bp1 := [0.0, 0.0, 0.0, 0.0]
	var bp2 := [0.0, 0.0, 0.0, 0.0]
	var syl := 0.0
	var syl_len := 0.2
	var cur: Vector2 = vowels[0]
	var target: Vector2 = vowels[1]
	var amp := 0.0
	for i in n:
		var t := float(i) / RATE
		syl += 1.0 / RATE
		if syl >= syl_len:
			syl = 0.0
			syl_len = synth_rng.randf_range(0.12, 0.3)
			target = vowels[synth_rng.randi_range(0, vowels.size() - 1)]
			amp = synth_rng.randf_range(0.3, 1.0) if synth_rng.randf() > 0.2 else 0.05   # 偶尔停一下，像换气
		cur = cur.lerp(target, 0.0015)
		var w := synth_rng.randf_range(-1.0, 1.0)
		var a := _bandpass(w, cur.x, 6.0, bp1) + 0.7 * _bandpass(w, cur.y, 8.0, bp2)
		var syl_env := sin(PI * clampf(syl / syl_len, 0.0, 1.0))
		var whole := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(dur - 0.5, dur, t))
		out[i] = a * syl_env * amp * whole * 0.3
	return _wav(out)


## 钟楼的钟：钟的几个特征分音（低一个八度的哼音、基音、小三度、五度、八度），衰减很长，有一点拍音
func _bell_wav() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var f0 := 196.0
	var parts := [[0.5, 0.8, 0.25], [1.0, 1.0, 0.45], [1.2, 0.6, 0.6], [1.5, 0.4, 0.8], [2.0, 0.5, 0.7], [2.5, 0.2, 1.2], [3.0, 0.15, 1.6]]
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for p: Array in parts:
			var f: float = f0 * p[0]
			s += sin(TAU * f * t) * (1.0 + 0.15 * sin(TAU * 0.7 * t * p[0])) * p[1] * exp(-t * p[2])
		var w := synth_rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.2
		s += lp * exp(-t * 40.0) * 2.0                                # 钟锤敲上去那一下
		out[i] = s * 0.28
	return _wav(_fade_out(out, 1.0))


## 二阶带通（状态变量形式），st 是滤波器状态（low, band）
func _bandpass(x: float, freq: float, q: float, st: Array) -> float:
	return Synth.bandpass(x, freq, q, st)


func _fade_out(s: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	return Synth.fade_out(s, seconds)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	return Synth.wav(samples)
