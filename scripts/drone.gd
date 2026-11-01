extends AudioStreamPlayer
## 程序化环境音：持续的低频嗡鸣 + 周期性的号角 + 闪电后的雷声（storm.gd 调用 thunder()）
## + 被黑光扫中时的低频压迫声（main 设置 pressure）。
## 号角按摩斯电码拼出 "GOD"（--. --- -..），致敬原片配乐的彩蛋。

const RATE := 11025.0
const UNIT := 0.35            # 摩斯电码的一个"点"时长（秒）
const HORN_FREQ := 49.0

var playback: AudioStreamGeneratorPlayback
var t := 0.0
var pattern: Array = []       # [[开始, 结束], ...]
var cycle := 0.0
var thunder_at := -1.0           # 雷声开始的时刻（音频时间）；< 0 表示没有
var thunder_gain := 0.0
var brown := 0.0                 # 布朗噪声的状态：白噪声积分，低沉的轰隆声
var rumble := 0.0
var pressure := 0.0              # 被黑光照到的程度（0～1），main 每帧设置
var pressure_s := 0.0            # 逐个采样平滑过的值，免得音量跳变出爆音


func _ready() -> void:
	_build_pattern()

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	stream = gen
	volume_db = -4.0

	# 给主总线加一点大空间混响
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.95
	reverb.damping = 0.3
	reverb.wet = 0.45
	reverb.dry = 0.8
	AudioServer.add_bus_effect(0, reverb)

	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback


## 关窗口时先停播放、放掉 playback 的引用，否则退出时报 ObjectDB 泄漏。
## 音频线程要几帧才真正释放它，所以 main 会晚一点再退出。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()
		playback = null


## 预约一声雷：delay 秒后开始，strength 0～1.2
func thunder(delay: float, strength: float) -> void:
	thunder_at = t + delay
	thunder_gain = strength


func _build_pattern() -> void:
	var tt := 5.0
	for letter: String in ["--.", "---", "-.."]:
		for ch in letter:
			var dur := UNIT * (3.0 if ch == "-" else 1.0)
			pattern.append([tt, tt + dur])
			tt += dur + UNIT
		tt += UNIT * 2.0
	cycle = tt + 20.0   # 每轮之间留 20 秒寂静


func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames := playback.get_frames_available()
	for i in frames:
		var s := _sample()
		playback.push_frame(Vector2(s, s))
		t += 1.0 / RATE


func _sample() -> float:
	var lfo := 0.6 + 0.4 * sin(TAU * 0.05 * t)
	var drone := (sin(TAU * 36.7 * t) * 0.5
		+ sin(TAU * 55.0 * t + sin(TAU * 0.2 * t)) * 0.3
		+ sin(TAU * 73.4 * t) * 0.12) * lfo

	var horn := 0.0
	var env := _horn_env(fmod(t, cycle))
	if env > 0.0:
		for h in range(1, 7):
			horn += sin(TAU * HORN_FREQ * h * t * (1.0 + 0.002 * h)) / h
		horn *= env * 0.45

	var boom := 0.0
	if thunder_at >= 0.0 and t >= thunder_at:
		var k := t - thunder_at
		if k > 6.0:
			thunder_at = -1.0
		else:
			# 先一声炸响，再拖出几秒忽强忽弱的滚雷
			brown = (brown + randf_range(-1.0, 1.0) * 0.06) * 0.995
			rumble = lerpf(rumble, brown, 0.08)
			var swell := (1.0 - exp(-k * 25.0)) * exp(-k * 0.7) * (0.7 + 0.3 * sin(k * 5.3) * sin(k * 2.1))
			boom = rumble * swell * thunder_gain * 2.2

	# 黑光：一记很低的嗡声，带着搏动，混一点滚动的噪声；同时把平常的嗡鸣压下去
	pressure_s = lerpf(pressure_s, pressure, 0.0005)
	var press := 0.0
	if pressure_s > 0.001:
		var throb := 0.6 + 0.4 * sin(TAU * 1.7 * t)
		press = (sin(TAU * 27.5 * t) * 0.6 + sin(TAU * 41.0 * t + sin(TAU * 0.5 * t)) * 0.3 + rumble * 2.0) \
			* throb * pressure_s * 0.7

	return clampf(drone * 0.35 * (1.0 - pressure_s * 0.6) + horn + boom + press, -1.0, 1.0)


func _horn_env(x: float) -> float:
	for p: Array in pattern:
		var s: float = p[0]
		var e: float = p[1]
		if x >= s and x < e:
			return minf((x - s) / 0.08, 1.0) * minf((e - x) / 0.15, 1.0)
	return 0.0
