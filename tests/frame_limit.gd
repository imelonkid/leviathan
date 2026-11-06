extends SceneTree
## 静音运行：Godot --headless --audio-driver Dummy --path . --script res://tests/frame_limit.gd
const Settings = preload("res://scripts/settings.gd")
const Menu = preload("res://scripts/menu.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	root.size = Vector2i(1600, 900)
	var settings := Settings.new()
	check(settings.values.frame_limit == 1, "New or missing setting must default to 60 FPS")
	check(settings.values.preset == "medium" and settings.values.resolution_limit == 1, "Fresh settings must default to medium / 1080p")
	for key: String in Settings.PRESETS.medium:
		check(settings.values[key] == Settings.PRESETS.medium[key], "Medium default differs from preset: " + key)
	root.add_child(settings)
	settings.values.fullscreen = false
	var original_scale: float = settings.values.render_scale
	var original_limit: int = settings.values.resolution_limit
	settings.values.render_scale = 1.0
	settings.values.resolution_limit = 1
	check(is_equal_approx(settings.render_scale_for(Vector2(3840, 2160)), 0.5), "4K must cap to 1080p")
	check(is_equal_approx(settings.render_scale_for(Vector2(3024, 1898)), 1080.0 / 1898.0), "Retina aspect ratio must be preserved")
	check(is_equal_approx(settings.render_scale_for(Vector2(5120, 1440)), 1920.0 / 5120.0), "Ultrawide width must stay within limit")
	check(is_equal_approx(settings.render_scale_for(Vector2(1280, 720)), 1.0), "Small windows must not upscale")
	for index in 3:
		settings.values.resolution_limit = index
		var limit: Vector2 = Settings.RESOLUTION_LIMITS[index]
		var actual := Vector2(3840, 2160) * settings.render_scale_for(Vector2(3840, 2160))
		check(actual.is_equal_approx(limit), "Resolution choice did not apply")
	settings.values.resolution_limit = 1
	settings.values.render_scale = 0.4
	check(is_equal_approx(settings.render_scale_for(Vector2(3840, 2160)), 0.4), "Lower manual scale must be respected")
	settings.values.resolution_limit = 3
	settings.values.render_scale = 0.95
	check(is_equal_approx(settings.render_scale_for(Vector2(3840, 2160)), 0.95), "Native choice must preserve manual scale")
	settings.values.resolution_limit = 1
	settings.values.render_scale = 1.0
	settings.apply()
	root.size = Vector2i(3840, 2160)
	await process_frame
	await process_frame
	check(is_equal_approx(root.scaling_3d_scale, 0.5), "Resize did not update 3D rendering budget")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "Render budget must not scale the UI viewport")
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	check(is_equal_approx(root.scaling_3d_scale, 1.0), "Shrinking window left a stale render scale")
	settings.values.render_scale = original_scale
	settings.values.resolution_limit = original_limit
	# 只在内存里切档，不写玩家的配置文件。
	for index in Settings.FRAME_LIMITS.size():
		settings.values.frame_limit = index
		settings.apply()
		check(Engine.max_fps == Settings.FRAME_LIMITS[index], "Foreground cap not applied")
		settings.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(Engine.max_fps == 15, "Background must be capped at 15 FPS")
		settings.apply()
		check(Engine.max_fps == 15, "Changing settings must retain background cap")
		settings.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		check(Engine.max_fps == Settings.FRAME_LIMITS[index], "Focus must restore selected cap")
	settings.values.frame_limit = 1
	settings.apply()
	check(Engine.max_fps == 60, "Default cap not applied")
	var menu := Menu.new()
	menu.settings = settings
	root.add_child(menu)
	menu.open()
	await process_frame
	await process_frame
	check(menu.controls.frame_limit.selected == 1, "Frame choice does not reflect setting")
	check(menu.controls.resolution_limit.selected == original_limit, "Resolution choice does not reflect setting")
	check(menu.panel.get_combined_minimum_size().y <= 900, "Menu is taller than default window")
	print("menu minimum: ", menu.panel.get_combined_minimum_size())
	menu.queue_free()
	settings.queue_free()
	await process_frame
	print("frame limit: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
