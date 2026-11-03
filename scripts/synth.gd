extends RefCounted
## 合成声音共用的小工具：浮点采样打包成 16 位 WAV、尾部淡出、状态变量带通滤波。
## soundscape.gd、distant_sounds.gd、watchman_sounds.gd 都用它。

const RATE := 22050


## 采样（-1～1）→ 16 位单声道 WAV；loop 为真时整段循环
static func wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
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


## 整段按比例缩放，最响的一点正好是 peak（原地改）
static func normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0
	for x in s:
		m = maxf(m, absf(x))
	if m > 0.0:
		var k := peak / m
		for i in s.size():
			s[i] *= k
	return s


## 最后 seconds 秒线性淡出（原地改）
static func fade_out(s: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var m := int(seconds * RATE)
	for i in mini(m, s.size()):
		s[s.size() - 1 - i] *= float(i) / m
	return s


## 状态变量滤波器的带通输出；st 是两个元素的状态数组，调用方每路声音各留一份
static func bandpass(x: float, freq: float, q: float, st: Array) -> float:
	var f := 2.0 * sin(PI * freq / RATE)
	var low: float = st[0] + f * st[1]
	var high: float = x - low - st[1] / q
	var band: float = st[1] + f * high
	st[0] = low
	st[1] = band
	return band
