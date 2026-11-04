extends SceneTree
## Godot --headless --audio-driver Dummy --path . --script res://tests/audio_perception.gd [-- --preview]
## 静音验证真实音频总线，并可导出实际混音试听文件。
const Main = preload("res://main.tscn")
const Synth = preload("res://scripts/synth.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	var main := Main.instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var sc: Node = main.soundscape
	sc.set_process(false)
	var music_bus := AudioServer.get_bus_index("Music")
	var world_bus := AudioServer.get_bus_index("World")
	var hearing := AudioServer.get_bus_index("Hearing")
	for bus_name in ["World", "Music", "Ambience"]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus_name)) == "Hearing", "Missing filter route: " + bus_name)
	# 等过场景同步初始化的首个长帧，再测真实播放进度。
	await create_timer(0.2).timeout
	# 真正把镜头放进光束，检查 main 的接线没有再用画面余效压低音乐。
	var camera: Camera3D = main.player.cam
	var previous_transform := camera.global_transform
	camera.top_level = true
	var light: Node3D = main.lev.beams[0]
	camera.global_position = main.lev.beam_pivot.global_position - light.global_basis.y * 100.0
	main._process(1.0 / 60.0)
	check(sc.beam > 0.99 and sc.hush == 0.0 and is_zero_approx(main.music.volume_db), "Main still silences music on beam exposure")
	main.caught.hush = 1.0
	main.caught.blur = 1.0
	main._process(1.0 / 60.0)
	check(sc.hush == 1.0 and main.music.volume_db < -11.0, "Watchman capture audio changed")
	main.caught.hush = 0.0
	main.caught.blur = 0.0
	camera.global_transform = previous_transform
	main._process(1.0 / 60.0)
	var music_volume := AudioServer.get_bus_volume_db(music_bus)
	var start: float = main.music.get_playback_position()
	sc.beam = 1.0
	for frame in 15:
		sc._hush(1.0 / 120.0)
	check(is_equal_approx(sc.beam_level, 1.0), "Blacklight attack too slow")
	check(is_equal_approx(sc.beam_lp.cutoff_hz, 850.0), "Wrong blocked-ear cutoff")
	check(sc.beam_amp.volume_db >= -2.01 and is_zero_approx(sc.hush_amp.volume_db), "Blacklight silences ambience")
	await create_timer(0.25).timeout
	print("music playhead: ", start, " -> ", main.music.get_playback_position())
	check(main.music.playing and main.music.get_playback_position() > start + 0.1, "Music stopped or restarted")
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_volume), "Blacklight overwrote user music volume")
	sc.beam = 0.0
	for frame in 31:
		sc._hush(1.0 / 120.0)
	check(is_zero_approx(sc.beam_level) and sc.beam_lp.cutoff_hz > 19999.0, "Blacklight recovery exceeds 0.26 seconds")
	check(is_zero_approx(sc.beam_amp.volume_db), "Blacklight gain did not recover")
	check(not AudioServer.is_bus_effect_enabled(hearing, 0), "Filter remains active after blacklight")
	# 混响湿度不应在每次调用时继续相乘下降。
	sc.hush = 0.3
	sc._hush(2.0)
	var wet: float = sc.reverb.wet
	for frame in 120:
		sc._hush(1.0 / 120.0)
	check(is_equal_approx(sc.reverb.wet, wet), "Reverb is being multiplied down every frame")
	sc.hush = 0.0
	sc._hush(4.0)
	# 用真实混音捕获比较 125 Hz 与 4 kHz；低频保留，高频衰减。
	main.music.stop()
	AudioServer.set_bus_volume_db(world_bus, -80.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), -80.0)
	AudioServer.set_bus_volume_db(music_bus, 0.0)
	var probe := AudioStreamPlayer.new()
	probe.bus = "Music"
	var samples := PackedFloat32Array()
	samples.resize(Synth.RATE * 4)
	for i in samples.size():
		samples[i] = 0.1 * (sin(TAU * 125.0 * i / Synth.RATE) + sin(TAU * 4000.0 * i / Synth.RATE))
	probe.stream = Synth.wav(samples, true)
	root.add_child(probe)
	var capture := AudioEffectCapture.new()
	AudioServer.add_bus_effect(hearing, capture)
	probe.play()
	await create_timer(0.25).timeout
	var clean := capture.get_buffer(capture.get_frames_available())
	sc.beam = 1.0
	sc._hush(0.12)
	await create_timer(0.15).timeout
	capture.clear_buffer()
	await create_timer(0.2).timeout
	var blocked := capture.get_buffer(capture.get_frames_available())
	check(not clean.is_empty() and not blocked.is_empty(), "No actual audio captured")
	if not clean.is_empty() and not blocked.is_empty():
		var bass := level(blocked, 125.0) / level(clean, 125.0)
		var treble := level(blocked, 4000.0) / level(clean, 4000.0)
		check(bass > 0.65, "Blocked-ear filter removed the low-frequency signal")
		check(treble < 0.08, "Blocked-ear filter did not muffle high frequencies")
		print("actual mix: bass ratio=", bass, ", treble ratio=", treble)
	probe.stop()
	probe.queue_free()
	if "--preview" in OS.get_cmdline_user_args():
		sc.beam = 0.0
		sc._hush(1.0)
		main.music.play()
		capture.clear_buffer()
		var output := PackedFloat32Array()
		var clock := 0.0
		var previous := Time.get_ticks_usec()
		while clock < 9.0:
			await create_timer(0.02).timeout
			var now := Time.get_ticks_usec()
			var delta := (now - previous) / 1000000.0
			previous = now
			clock += delta
			sc.beam = 1.0 if clock >= 2.0 and clock < 6.0 else 0.0
			sc._hush(delta)
			for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
				output.append((sample.x + sample.y) * 0.5)
		var wav: AudioStreamWAV = Synth.wav(output)
		wav.mix_rate = AudioServer.get_mix_rate()
		check(wav.save_to_wav("/tmp/leviathan-blacklight-audio.wav") == OK, "Failed to save preview")
	for audio_type in ["AudioStreamPlayer", "AudioStreamPlayer3D"]:
		for audio: Node in main.find_children("*", audio_type, true, false):
			audio.stop()
	main.drone.playback = null
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	print("audio perception: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)


func level(samples: PackedVector2Array, hz: float) -> float:
	var real := 0.0
	var imaginary := 0.0
	var rate := float(AudioServer.get_mix_rate())
	for i in samples.size():
		var value := (samples[i].x + samples[i].y) * 0.5
		real += value * cos(TAU * hz * i / rate)
		imaginary += value * sin(TAU * hz * i / rate)
	return 2.0 * sqrt(real * real + imaginary * imaginary) / samples.size()
