extends Node
## 声景：利维坦的低鸣（3D 定位，转头听得出它在哪），以及 World 总线的分区混响。
## 雨（rain.gd）、房间里的声音也走 World 总线。混响按周围有多开阔实时调整：
## 每 0.2 秒从镜头朝八个方向和头顶各打一条射线——窄走道回声短而亮，庭院大一些，
## 高处开阔的观景台几乎没有回声但远处的墙晚一点才回来，头顶有遮挡（门洞、隧道）和屋里小而闷。
## 黑光：Music / World / Ambience 继续播放，共同经过 Hearing 总线的低通，离开后快速恢复。
## 被守夜人抓住时仍保留 World 的失声和耳鸣；这与黑光的堵耳效果分开。

const Synth = preload("res://scripts/synth.gd")
const RATE := Synth.RATE
const PROBE_EVERY := 0.2
const PROBE_RANGE := 40.0
const HUM_UNIT := 140.0          # 利维坦低鸣的衰减尺度（米）：越大，远近差别越小
const HUM_DB := -8.0
const BEAM_IN := 0.12           # 黑光堵耳进入时间
const BEAM_OUT := 0.25          # 黑光离开后快速恢复，不跟随画面余效
const BEAM_CUTOFF := 850.0      # 保留低频和旋律，压掉高频细节
const BEAM_DB := -2.0           # 轻微衰减，不抽空环境和音乐
const HUSH_IN := 0.5             # 被吸走用多久（秒）
const HUSH_VOL_OUT := 1.5        # 守夜人抓住后醒来，环境音量恢复时间
const HUSH_LP_OUT := 3.5         # 高频多久回来（比音量慢）
const HUSH_DB := -30.0           # 吸到最空时 World 总线压低多少
const HUSH_CUTOFF := 220.0       # 吸到最空时低通截止频率（赫兹）
const RING_DB := -30.0           # 耳鸣、呼吸最响时的音量
const BREATH_DB := -22.0

var player: CharacterBody3D      # main 注入
var maze: Node3D
var lev: Node3D

var world_bus := -1
var reverb: AudioEffectReverb
var hush_lp: AudioEffectLowPassFilter
var hush_amp: AudioEffectAmplify
var ring: AudioStreamPlayer
var breath: AudioStreamPlayer
var beam := 0.0                 # 黑光实际曝光强度，独立于画面缓动
var beam_level := 0.0
var beam_lp: AudioEffectLowPassFilter
var beam_amp: AudioEffectAmplify
var hush := 0.0                  # 被守夜人抓住的程度 0～1，main 每帧设置
var hush_vol := 0.0              # 平滑过的：音量被压了多少
var hush_hi := 0.0               # 平滑过的：高频被吸走了多少（回来得比音量慢）
var hum: AudioStreamPlayer3D
var wet_level := 0.25
var probe_t := 0.0
var indoor := false              # 镜头在某间房里（rain.gd 也读它）
var openness := 0.5              # 周围有多开阔 0（屋里、头顶有遮挡、窄巷）～ 1（观景台），dust.gd 读它
var covered := false             # 头顶有遮挡（门洞、隧道、小楼的拱廊），rain.gd 读它：雨声收一半
var target := {"room": 0.6, "damp": 0.4, "wet": 0.25, "pre": 20.0}


func _ready() -> void:
	# AudioServer 总线只能发送到自己左侧，先把 Hearing 插在 Master 后面。
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, "Hearing")
	AudioServer.set_bus_send(1, "Master")
	beam_lp = AudioEffectLowPassFilter.new()
	beam_lp.cutoff_hz = 20000.0
	beam_lp.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(1, beam_lp)
	AudioServer.set_bus_effect_enabled(1, 0, false)
	beam_amp = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(1, beam_amp)
	for bus_name in ["Music", "Ambience"]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Hearing")
	world_bus = AudioServer.get_bus_index("World")
	if world_bus < 0:
		AudioServer.add_bus()
		world_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(world_bus, "World")
		AudioServer.set_bus_send(world_bus, "Master")
		var r := AudioEffectReverb.new()
		r.room_size = 0.6
		r.damping = 0.4
		r.wet = 0.25
		r.dry = 1.0
		r.hipass = 0.15
		r.predelay_msec = 20.0
		AudioServer.add_bus_effect(world_bus, r)
	AudioServer.set_bus_send(world_bus, "Hearing")
	reverb = AudioServer.get_bus_effect(world_bus, 0) as AudioEffectReverb
	hush_lp = AudioEffectLowPassFilter.new()
	hush_lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(world_bus, hush_lp)
	hush_amp = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(world_bus, hush_amp)
	ring = _quiet_player(_ring_wav())
	breath = _quiet_player(_breath_wav())

	hum = AudioStreamPlayer3D.new()
	hum.name = "LeviathanHum"
	hum.stream = _hum_wav()
	hum.bus = "World"
	hum.volume_db = HUM_DB
	hum.unit_size = HUM_UNIT
	hum.max_distance = 0.0
	hum.attenuation_filter_cutoff_hz = 20500.0   # 远处也别闷掉：低鸣本来就低
	hum.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(hum)
	hum.play()


func _process(delta: float) -> void:
	if lev:
		hum.global_position = lev.global_position
	probe_t -= delta
	if probe_t <= 0.0:
		probe_t = PROBE_EVERY
		_probe()
	var k := minf(delta * 1.5, 1.0)
	reverb.room_size = lerpf(reverb.room_size, target["room"], k)
	reverb.damping = lerpf(reverb.damping, target["damp"], k)
	wet_level = lerpf(wet_level, target["wet"], k)
	reverb.predelay_msec = lerpf(reverb.predelay_msec, target["pre"], k)
	_hush(delta)


## 黑光只改听感；守夜人抓住时才压空 World，并加入耳鸣和呼吸
func _hush(delta: float) -> void:
	beam_level = move_toward(beam_level, beam, delta / (BEAM_IN if beam > beam_level else BEAM_OUT))
	beam_lp.cutoff_hz = 20000.0 * pow(BEAM_CUTOFF / 20000.0, beam_level)
	beam_amp.volume_db = BEAM_DB * beam_level
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Hearing"), 0, beam_level > 0.0)
	hush_vol = move_toward(hush_vol, hush, delta / (HUSH_IN if hush > hush_vol else HUSH_VOL_OUT))
	hush_hi = move_toward(hush_hi, hush, delta / (HUSH_IN if hush > hush_hi else HUSH_LP_OUT))
	hush_lp.cutoff_hz = 20000.0 * pow(HUSH_CUTOFF / 20000.0, hush_hi)
	hush_amp.volume_db = HUSH_DB * hush_vol
	reverb.wet = wet_level * (1.0 - hush_vol)
	var quiet := hush_vol * hush_vol
	for p: AudioStreamPlayer in [ring, breath]:
		var db := (RING_DB if p == ring else BREATH_DB) + linear_to_db(maxf(quiet, 0.0001))
		p.volume_db = db
		if quiet > 0.01 and not p.playing:
			p.play()
		elif quiet <= 0.01 and p.playing:
			p.stop()


## 耳鸣、呼吸：不走 World（不然自己也被吸走），直接进 Master
func _quiet_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	p.volume_db = -80.0
	add_child(p)
	return p


## 量一下周围：屋里、头顶有遮挡、或者按水平方向平均多远碰到墙
func _probe() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	indoor = false
	if maze:
		for r: Node in maze.room_nodes.values():
			if r.get("inside"):
				indoor = true
	covered = false
	if indoor:
		openness = 0.0
		target = {"room": 0.3, "damp": 0.7, "wet": 0.3, "pre": 4.0}
		return
	var space := player.get_world_3d().direct_space_state
	var origin := cam.global_position
	var ex: Array[RID] = [player.get_rid()]
	var total := 0.0
	for i in 8:
		var a := TAU * i / 8.0
		total += _ray(space, origin, Vector3(cos(a), 0.0, sin(a)), PROBE_RANGE, ex)
	var up := _ray(space, origin, Vector3.UP, 12.0, ex)
	if up < 10.0:
		openness = 0.0
		covered = true
		target = {"room": 0.4, "damp": 0.5, "wet": 0.35, "pre": 8.0}
		return
	var o := clampf((total / 8.0 - 3.0) / 30.0, 0.0, 1.0)
	openness = o
	target = {"room": lerpf(0.45, 0.9, o), "damp": lerpf(0.25, 0.5, o),
		"wet": lerpf(0.32, 0.12, o), "pre": lerpf(15.0, 60.0, o)}


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float, ex: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length)
	q.exclude = ex
	var hit := space.intersect_ray(q)
	return from.distance_to(hit["position"]) if hit else length


# ---------- 合成 ----------

## 利维坦的低鸣：8 秒一循环（每个频率在 8 秒里都是整数个周期，接缝无声），
## 底下是很低的三个音，上面一层金属似的泛音让耳朵分得出方向
func _hum_wav() -> AudioStreamWAV:
	var n := RATE * 8
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var beat := 0.65 + 0.35 * sin(TAU * 0.125 * t)
		var low := sin(TAU * 36.75 * t) * 0.5 + sin(TAU * 55.0 * t) * 0.32 + sin(TAU * 73.375 * t) * 0.14
		var shimmer := (sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 220.125 * t) * 0.3 + sin(TAU * 330.25 * t) * 0.12) \
			* (0.5 + 0.5 * sin(TAU * 0.25 * t + 1.0))
		out[i] = (low * beat + shimmer * 0.35) * 0.6
	return _wav(out, true)


## 耳鸣：两个很近的高音，2 秒一循环（都是整数个周期），差拍成一下下的颤
func _ring_wav() -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 6200.0 * t) + sin(TAU * 6203.0 * t) * 0.8) * 0.25
	return _wav(out, true)


## 呼吸：4 秒一循环，吸气一声、呼气一声，都是滤过的噪声，首尾都静下来，接缝听不出
func _breath_wav() -> AudioStreamWAV:
	var n := RATE * 4
	var out := PackedFloat32Array()
	out.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var lo := 0.0
	var lo2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := r.randf_range(-1.0, 1.0)
		lo += (w - lo) * 0.35
		lo2 += (lo - lo2) * 0.08
		var air := lo - lo2   # 去掉最低的一截，留下气声
		var inhale := sin(PI * clampf(t / 1.3, 0.0, 1.0)) if t < 1.3 else 0.0
		var exhale := sin(PI * clampf((t - 1.8) / 1.7, 0.0, 1.0)) * 0.7 if t > 1.8 and t < 3.5 else 0.0
		out[i] = air * (inhale * inhale + exhale * exhale) * 1.4
	return _wav(out, true)


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	return Synth.wav(samples, loop)
