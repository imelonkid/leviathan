extends Node3D
## 场景入口：环境、迷宫、利维坦、玩家、音频全部在代码里搭建，方便迭代。

const Maze = preload("res://scripts/maze.gd")
const Leviathan = preload("res://scripts/leviathan.gd")
const Player = preload("res://scripts/player.gd")
const Drone = preload("res://scripts/drone.gd")
const Settings = preload("res://scripts/settings.gd")
const Menu = preload("res://scripts/menu.gd")
const DebugHud = preload("res://scripts/debug_hud.gd")

const LEVIATHAN_HEIGHT := 170.0

var settings: Node
var maze: Node3D
var player: CharacterBody3D


func _ready() -> void:
	get_tree().auto_accept_quit = false
	settings = Settings.new()
	settings.name = "Settings"
	add_child(settings)

	_setup_environment()

	maze = Maze.new()
	maze.name = "Maze"
	add_child(maze)
	maze.build()

	var lev := Leviathan.new()
	lev.name = "Leviathan"
	add_child(lev)
	lev.position = Vector3(0, LEVIATHAN_HEIGHT, 0)

	player = Player.new()
	player.name = "Player"
	player.settings = settings
	add_child(player)
	_spawn_player()

	var drone := Drone.new()
	drone.name = "Drone"
	add_child(drone)

	_setup_hud()

	var debug := DebugHud.new()
	debug.maze = maze
	debug.player = player
	add_child(debug)

	var menu := Menu.new()
	menu.settings = settings
	add_child(menu)

	settings.apply()


## 收到关窗口请求后等音频线程放掉生成器再退出（见 drone.gd）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()


## 掉进深渊：回到最近站稳的位置
func _physics_process(_delta: float) -> void:
	if player.global_position.y < maze.KILL_Y and not player.flying:
		player.velocity = Vector3.ZERO
		player.global_position = player.last_safe


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_R:
			# 换一座迷宫：随机种子，玩家回到出生点
			maze.seed_value = randi_range(1, 99999)
			maze.build()
			_spawn_player()
		KEY_F12:
			_screenshot()


func _spawn_player() -> void:
	player.set_flying(false)
	player.velocity = Vector3.ZERO
	player.global_position = maze.get_spawn_position()
	player.last_safe = player.global_position
	# 出生时面朝迷宫中心
	player.look_at(Vector3(0, player.global_position.y, 0), Vector3.UP)


## 截图存到 user://screenshots/，文件名带时间
func _screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://screenshots/leviathan-%s.png" % stamp
	get_viewport().get_texture().get_image().save_png(path)
	print("截图已保存：", ProjectSettings.globalize_path(path))


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.022)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.4)
	env.ambient_light_energy = 0.2

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1

	# 远处的整体雾：让利维坦成为半隐半现的剪影
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.14, 0.17)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.6

	# 近处的体积雾：光束、提灯在雾里显形
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.7)
	env.volumetric_fog_emission = Color(0.01, 0.012, 0.015)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 120.0

	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05

	env.adjustment_enabled = true
	env.adjustment_saturation = 0.55
	env.adjustment_contrast = 1.1

	settings.env = env

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 冷色、低角度的主光，从高处斜射进迷宫
	var sun := DirectionalLight3D.new()
	sun.name = "ColdLight"
	sun.light_color = Color(0.7, 0.78, 0.92)
	sun.light_energy = 0.7
	sun.light_volumetric_fog_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)
	sun.rotation_degrees = Vector3(-62, 35, 0)
	settings.sun = sun


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "WASD 移动 · Shift 奔跑 · 空格 跳跃 · F 提灯 · Esc 菜单与设置"
	label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85, 0.85))
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(24, 20)
	layer.add_child(label)
	var tw := create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(label, "modulate:a", 0.0, 3.0)
