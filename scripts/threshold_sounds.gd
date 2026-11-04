extends Node
## CC0 录音拟音，按动画阶段触发；来源见 assets/audio/threshold/CREDITS.md。
const HINGE = [preload("res://assets/audio/threshold/hinge_01.wav"), preload("res://assets/audio/threshold/hinge_02.wav")]
const LATCH = preload("res://assets/audio/threshold/ruler_latch.wav")
const TAP = preload("res://assets/audio/threshold/measure_tap.wav")
const CLOTH = [preload("res://assets/audio/threshold/cloth_01.wav"), preload("res://assets/audio/threshold/cloth_02.wav")]
const RELEASE = preload("res://assets/audio/threshold/finger_release.wav")
const CREAK = preload("res://assets/audio/threshold/joint_creak.wav")
const STEP = [preload("res://assets/audio/watchman/step_stone_l1.ogg"), preload("res://assets/audio/watchman/step_stone_r1.ogg")]

var kind := "surveyor"
var voices: Array[AudioStreamPlayer3D] = []
var cursor := 0
var previous: Array[float] = [0.0, 0.0, 0.0]
var last_release := 0.0
var event_count := 0            # 专项检查读：每次相遇实际触发了几声
var flee_step := 0


func _ready() -> void:
	for i in 8:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "World"
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		voice.max_distance = 85.0 if kind == "surveyor" else 35.0
		add_child(voice)
		voices.append(voice)


func begin(at: Vector3) -> void:
	stop()
	previous = [0.0, 0.0, 0.0]
	last_release = 0.0
	event_count = 0
	flee_step = 0
	if kind == "door_holder":
		play(CLOTH[0], at + Vector3.UP * 1.8, -17.0, 0.8, 4.0)


func survey_tick(time: float, actors: Array[Node3D], stepping := true) -> void:
	for i in actors.size():
		var t := maxf(0.0, time - i * 0.32)
		var old := previous[i]
		var at := actors[i].global_position
		var walked := floorf(t / 6.0) * 2.4 + minf(fmod(t, 6.0), 4.0) * 0.6
		var before := floorf(old / 6.0) * 2.4 + minf(fmod(old, 6.0), 4.0) * 0.6
		if stepping and floori(walked / 0.6) > floori(before / 0.6):
			play(STEP[floori(walked / 0.6) % 2], at + Vector3.UP * 0.1, -17.0, 0.8, 3.0)
		if crossed(old, t, 4.05):
			play(HINGE[i % 2], at + Vector3.UP, -12.0, 0.72 + i * 0.04, 12.0)
		if crossed(old, t, 4.65):
			play(TAP, at + Vector3.UP * 0.15, -12.0, 0.85, 10.0)
		if crossed(old, t, 5.35):
			play(LATCH, at + Vector3.UP * 0.8, -13.0, 0.8, 12.0)
		previous[i] = t


func flee_tick(walked: float, actors: Array[Node3D]) -> void:
	var step := floori(walked / 0.6)
	if step > flee_step:
		for actor: Node3D in actors:
			play(STEP[step % 2], actor.global_position + Vector3.UP * 0.1, -17.0, 0.8, 3.0)
	flee_step = step


func holder_tick(time: float, release: float, at: Vector3) -> void:
	if previous[0] < 5.0 and time >= 5.0 and release == 0:
		play(CREAK, at + Vector3.UP * 2.0, -21.0, 0.65, 4.0)
	for phase in [0.05, 0.3, 0.55]:
		if last_release < phase and release >= phase:
			play(RELEASE, at + Vector3.UP * 2.1, -20.0, 0.65 + phase * 0.3, 4.0)
	if last_release < 0.7 and release >= 0.7:
		play(CLOTH[0], at + Vector3.UP * 1.6, -14.0, 0.8, 4.0)
	if last_release < 1.4 and release >= 1.4:
		play(CREAK, at + Vector3.UP, -18.0, 0.6, 4.0)
	if last_release < 2.1 and release >= 2.1:
		play(CLOTH[1], at + Vector3.UP, -14.0, 0.75, 4.0)
	previous[0] = time
	last_release = release


func crossed(old: float, now: float, phase: float) -> bool:
	return floori((now - phase) / 6.0) > floori((old - phase) / 6.0)


func play(stream: AudioStream, at: Vector3, db: float, pitch: float, unit: float) -> void:
	var voice := voices[cursor]
	cursor = (cursor + 1) % voices.size()
	voice.stream = stream
	voice.global_position = at
	voice.unit_size = unit
	voice.volume_db = db
	voice.pitch_scale = pitch
	voice.play()
	event_count += 1


func stop() -> void:
	for voice in voices:
		voice.stop()
