extends Node
## 声景：利维坦的低鸣（3D 定位，转头听得出它在哪），以及 World 总线的分区混响。
## 雨（rain.gd）、房间里的声音也走 World 总线。混响按周围有多开阔实时调整：
## 每 0.2 秒从镜头朝八个方向和头顶各打一条射线——窄走道回声短而亮，庭院大一些，
## 高处开阔的观景台几乎没有回声但远处的墙晚一点才回来，头顶有遮挡（门洞、隧道）和屋里小而闷。
## 声音全部在代码里合成，不用素材文件。

const RATE := 22050
const PROBE_EVERY := 0.2
const PROBE_RANGE := 40.0
const HUM_UNIT := 140.0          # 利维坦低鸣的衰减尺度（米）：越大，远近差别越小
const HUM_DB := -8.0

var player: CharacterBody3D      # main 注入
var maze: Node3D
var lev: Node3D

var world_bus := -1
var reverb: AudioEffectReverb
var hum: AudioStreamPlayer3D
var probe_t := 0.0
var indoor := false              # 镜头在某间房里（rain.gd 也读它）
var target := {"room": 0.6, "damp": 0.4, "wet": 0.25, "pre": 20.0}


func _ready() -> void:
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
	reverb = AudioServer.get_bus_effect(world_bus, 0) as AudioEffectReverb

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
	reverb.wet = lerpf(reverb.wet, target["wet"], k)
	reverb.predelay_msec = lerpf(reverb.predelay_msec, target["pre"], k)


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
	if indoor:
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
		target = {"room": 0.4, "damp": 0.5, "wet": 0.35, "pre": 8.0}
		return
	var o := clampf((total / 8.0 - 3.0) / 30.0, 0.0, 1.0)
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


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w
