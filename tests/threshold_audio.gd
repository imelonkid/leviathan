extends SceneTree
## --headless --audio-driver Dummy --path . --script res://tests/threshold_audio.gd [-- --preview]
const Sounds = preload("res://scripts/threshold_sounds.gd")
const Synth = preload("res://scripts/synth.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, "World")
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 1.6, 4)
	camera.look_at(Vector3.UP)
	camera.make_current()
	var actors: Array[Node3D] = []
	for i in 3:
		var actor := Node3D.new()
		scene.add_child(actor)
		actor.position.x = (i - 1) * 1.7
		actors.append(actor)
	for kind in ["surveyor", "door_holder"]:
		var sound := Sounds.new()
		sound.kind = kind
		scene.add_child(sound)
		for stream in sound.HINGE + sound.CLOTH + [sound.LATCH, sound.TAP, sound.RELEASE, sound.CREAK]:
			check(stream.get_length() > 0.1, "Missing recorded sample")
			check(stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Unexpected looping SFX")
		sound.begin(Vector3.ZERO)
		for frame in 650:
			var t := (frame + 1) / 100.0
			if kind == "surveyor":
				sound.survey_tick(t, actors)
			else:
				sound.holder_tick(t, minf(t, 2.5), Vector3.ZERO)
		var count := sound.event_count
		check(count == (21 if kind == "surveyor" else 7), "Wrong animation sound event count: " + kind + "=" + str(count))
		if kind == "surveyor":
			sound.survey_tick(6.5, actors)
		else:
			sound.holder_tick(6.5, 2.5, Vector3.ZERO)
		check(sound.event_count == count, "Stationary animation retriggered SFX")
		if kind == "surveyor":
			sound.begin(Vector3.ZERO)
			sound.survey_tick(3.9, actors, false)
			check(sound.event_count == 0, "Stopped surveyors still made footsteps")
			sound.flee_tick(0.7, actors)
			check(sound.event_count == 3, "Fleeing surveyors did not make movement footsteps")
			sound.flee_tick(0.7, actors)
			check(sound.event_count == 3, "Blocked escape retriggered footsteps")
		sound.stop()
		for voice: AudioStreamPlayer3D in sound.voices:
			check(not voice.playing and voice.bus == "World", "SFX leaked after encounter")
		if "--preview" in OS.get_cmdline_user_args():
			var capture := AudioEffectCapture.new()
			AudioServer.add_bus_effect(0, capture)
			await create_timer(0.2).timeout
			capture.clear_buffer()
			sound.begin(Vector3.ZERO)
			var output := PackedFloat32Array()
			var t := 0.0
			var previous := Time.get_ticks_usec()
			var length := 6.7 if kind == "surveyor" else 4.8
			while t < length:
				await create_timer(0.02).timeout
				var now := Time.get_ticks_usec()
				t += (now - previous) / 1000000.0
				previous = now
				if kind == "surveyor":
					sound.survey_tick(t, actors)
				else:
					sound.holder_tick(t, maxf(t - 1.0, 0.0), Vector3.ZERO)
				for sample: Vector2 in capture.get_buffer(capture.get_frames_available()):
					output.append((sample.x + sample.y) * 0.5)
			var wav: AudioStreamWAV = Synth.wav(output)
			wav.mix_rate = AudioServer.get_mix_rate()
			check(wav.save_to_wav("/tmp/leviathan-" + kind + "-audio.wav") == OK, "Failed SFX preview")
			sound.stop()
			AudioServer.remove_bus_effect(0, 0)
		sound.queue_free()
		await process_frame
	scene.queue_free()
	await process_frame
	print("threshold audio: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
