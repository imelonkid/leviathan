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
	root.add_child(settings)
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
	check(menu.panel.get_combined_minimum_size().y <= 900, "Menu is taller than default window")
	print("menu minimum: ", menu.panel.get_combined_minimum_size())
	menu.queue_free()
	settings.queue_free()
	await process_frame
	print("frame limit: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	quit(0 if failures == 0 else 1)
