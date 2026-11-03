extends Node3D
## 守夜人的声音（挂在守夜人身上，跟着它走）：
## - 脚步：石头地上的真实脚步录音（CC0，见 README），左右脚交替、每步随机挑一条、音高稍微变一点；
## - 钥匙：左手那一大串钥匙，真实录音（CC0），每走一步晃一下——你往往先听见钥匙，后看见光；追你的时候每步都响、更响；
## - 火：提灯里那团火低低的呼呼声和偶尔的噼啪，离得很近才听得见；
## - 发现你：火猛地一窜（一声往上扫的呼），钥匙哗啦一抖；
## - 抓住你：钥匙在耳边哗啦作响、火声越来越大，最后一声闷响——这一声不走 World 总线，不会被“吸走”。
## 火、发现你的那一窜、抓住你那一声是合成的（开局在后台线程里合成好）。
## 走 World 总线（跟着分区混响），抓住你那一声直接进 Master。

const Synth = preload("res://scripts/synth.gd")
const RATE := Synth.RATE
const LANTERN_Y := 2.8           # 提灯离地多高
const STEPS_L := [preload("res://assets/audio/watchman/step_stone_l1.ogg"), preload("res://assets/audio/watchman/step_stone_l2.ogg"),
	preload("res://assets/audio/watchman/step_stone_l3.ogg")]
const STEPS_R := [preload("res://assets/audio/watchman/step_stone_r1.ogg"), preload("res://assets/audio/watchman/step_stone_r2.ogg"),
	preload("res://assets/audio/watchman/step_stone_r3.ogg")]
const KEYS := [preload("res://assets/audio/watchman/keys_01.ogg"), preload("res://assets/audio/watchman/keys_02.ogg"),
	preload("res://assets/audio/watchman/keys_03.ogg"), preload("res://assets/audio/watchman/keys_04.ogg"),
	preload("res://assets/audio/watchman/keys_05.ogg"), preload("res://assets/audio/watchman/keys_06.ogg"),
	preload("res://assets/audio/watchman/keys_07.ogg")]

var lib := {}                    # 种类 → [AudioStreamWAV]
var ready_lib := false
var worker: Thread
var rng := RandomNumberGenerator.new()
var synth_rng := RandomNumberGenerator.new()   # 合成用（后台线程）
var steps: AudioStreamPlayer3D
var keys: AudioStreamPlayer3D
var flame: AudioStreamPlayer3D
var sting: AudioStreamPlayer3D
var close: AudioStreamPlayer      # 抓住你那一声：不定位、不走 World
var close_keys: AudioStreamPlayer # 抓住你时耳边的钥匙声：同上
var burning := false
var left_foot := false


func _ready() -> void:
	rng.randomize()
	synth_rng.randomize()
	steps = _player(Vector3(0, 0.1, 0), 3.0, 45.0)
	keys = _player(Vector3(0.43, 0.7, 0.1), 2.5, 40.0)
	# 追的时候一步只有 0.25 秒，上一串钥匙还没响完：让它们叠着响，不要互相掐断
	steps.max_polyphony = 3
	keys.max_polyphony = 4
	flame = _player(Vector3(0, LANTERN_Y, 0.1), 0.8, 9.0)
	sting = _player(Vector3(0, LANTERN_Y, 0.1), 4.0, 50.0)
	close = AudioStreamPlayer.new()
	close.bus = "Master"
	add_child(close)
	close_keys = AudioStreamPlayer.new()
	close_keys.bus = "Master"
	close_keys.max_polyphony = 3
	add_child(close_keys)
	worker = Thread.new()
	worker.start(_build_library)


func _exit_tree() -> void:
	if worker and worker.is_started():
		worker.wait_to_finish()


func _player(at: Vector3, unit: float, reach: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "World"
	p.position = at
	p.unit_size = unit
	p.max_distance = reach
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	return p


## ---------- 守夜人调用 ----------

## 落了一步：左右脚交替的脚步声，钥匙晃一下（追的时候每步都响、更响）
func step(chasing: bool) -> void:
	left_foot = not left_foot
	_play(steps, STEPS_L if left_foot else STEPS_R, -5.0 if chasing else -10.0)
	if chasing or rng.randf() < 0.7:
		_play(keys, KEYS, -6.0 if chasing else -12.0)


## 出场 / 退下：火声开关
func burn(on: bool) -> void:
	burning = on
	if not ready_lib:
		return
	if on and not flame.playing:
		flame.stream = lib["flame"][0]
		flame.volume_db = -8.0
		flame.play()
	elif not on and flame.playing:
		flame.stop()


## 发现你：火一窜，钥匙哗啦一抖
func alert() -> void:
	_play(keys, KEYS, -3.0)
	if ready_lib:
		_play(sting, lib["alert"], 0.0)


## 抓住你：钥匙在耳边越晃越响（0.9 秒里晃三下），火声越来越大，最后一声闷响
func caught() -> void:
	if ready_lib:
		close.stream = lib["caught"][0]
		close.volume_db = -4.0
		close.play()
	for i in 3:
		get_tree().create_timer(i * 0.3).timeout.connect(func() -> void:
			close_keys.stream = KEYS[rng.randi() % KEYS.size()]
			close_keys.volume_db = -12.0 + i * 4.0
			close_keys.pitch_scale = rng.randf_range(0.95, 1.05)
			close_keys.play())


func _play(p: AudioStreamPlayer3D, list: Array, db: float) -> void:
	p.stream = list[rng.randi() % list.size()]
	p.volume_db = db + rng.randf_range(-1.5, 1.5)
	p.pitch_scale = rng.randf_range(0.94, 1.06)
	p.play()


## ---------- 合成 ----------

func _build_library() -> void:
	var out := {"flame": [], "alert": [], "caught": []}
	out["flame"].append(_flame_wav())
	out["alert"].append(_alert_wav())
	out["caught"].append(_caught_wav())
	_library_done.call_deferred(out)


func _library_done(out: Dictionary) -> void:
	lib = out
	ready_lib = true
	if burning:
		burn(true)


## 火：低低的呼呼声（低通噪声，慢慢起伏）加偶尔的噼啪；首尾交叉淡化，循环起来没有接缝
func _flame_wav() -> AudioStreamWAV:
	var dur := 3.0
	var xf := int(RATE * 0.5)
	var n := int(RATE * dur)
	var raw := PackedFloat32Array()
	raw.resize(n + xf)
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		var w := synth_rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.04
		lp2 += (lp - lp2) * 0.08
		var swell := 0.7 + 0.3 * sin(t * 2.3) * sin(t * 0.9 + 1.0)
		raw[i] = lp2 * 6.0 * swell
		if synth_rng.randf() < 0.0004:          # 噼啪
			for k in mini(160, raw.size() - i):
				raw[i + k] += synth_rng.randf_range(-1.0, 1.0) * 0.5 * exp(-k / 25.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = raw[i]
		if i < xf:
			var a := float(i) / xf
			out[i] = raw[i] * a + raw[n + i] * (1.0 - a)
	return Synth.wav(Synth.normalize(out, 0.6), true)


## 发现你：火猛地一窜——带通噪声从低往高扫、涨起来再落下（钥匙那一抖用录音）
func _alert_wav() -> AudioStreamWAV:
	var dur := 1.6
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var st := [0.0, 0.0]
	for i in n:
		var t := float(i) / RATE
		var env := smoothstep(0.0, 0.25, t) * exp(-maxf(t - 0.25, 0.0) * 2.5)
		var freq := 180.0 + 1100.0 * smoothstep(0.0, 0.35, t)
		out[i] += Synth.bandpass(synth_rng.randf_range(-1.0, 1.0), freq, 0.9, st) * env * 1.4
	return Synth.wav(Synth.fade_out(Synth.normalize(out, 0.85), 0.3))


## 抓住你：0.9 秒里火声越来越大，最后一声闷响（正好赶上画面黑下去；钥匙声用录音另放）
func _caught_wav() -> AudioStreamWAV:
	var dur := 2.4
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var st := [0.0, 0.0]
	var thump := int(RATE * 0.9)
	for i in n:
		var t := float(i) / RATE
		if i < thump:
			var k := t / 0.9
			out[i] += Synth.bandpass(synth_rng.randf_range(-1.0, 1.0), 300.0 + 900.0 * k, 0.8, st) * k * k * 1.6
		else:
			var d := t - 0.9
			out[i] = sin(TAU * 48.0 * d) * exp(-d * 4.0) * 0.9 + sin(TAU * 31.0 * d) * exp(-d * 2.5) * 0.5
	return Synth.wav(Synth.fade_out(Synth.normalize(out, 0.9), 0.4))
