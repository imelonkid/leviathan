extends Node3D
## 场景入口：环境、迷宫、利维坦、玩家、音频全部在代码里搭建，方便迭代。

const Maze = preload("res://scripts/maze.gd")
const Leviathan = preload("res://scripts/leviathan.gd")
const Player = preload("res://scripts/player.gd")
const Drone = preload("res://scripts/drone.gd")
const Settings = preload("res://scripts/settings.gd")
const Menu = preload("res://scripts/menu.gd")
const DebugHud = preload("res://scripts/debug_hud.gd")
const Storm = preload("res://scripts/storm.gd")
const BeamFx = preload("res://scripts/beam_fx.gd")
const EnergyBar = preload("res://scripts/energy_bar.gd")
const Soundscape = preload("res://scripts/soundscape.gd")
const Rain = preload("res://scripts/rain.gd")
const Dust = preload("res://scripts/dust.gd")
const DistantSounds = preload("res://scripts/distant_sounds.gd")
const Hauler = preload("res://scripts/hauler.gd")
const Watchman = preload("res://scripts/watchman.gd")
const Caught = preload("res://scripts/caught.gd")
const CreatureBudget = preload("res://scripts/creature_budget.gd")
const ThresholdCreature = preload("res://scripts/threshold_creature.gd")
const MUSIC = preload("res://assets/audio/liweitan.mp3")   # 背景音乐，导入设置里已开循环

const LEVIATHAN_HEIGHT := 250.0  # 中心高度；本体高 340 米，下尖离顶层广场约 40 米

var settings: Node
var env: Environment
var lev: Node3D
var drone: Node
var beam_fx: CanvasLayer
var caught: CanvasLayer
var soundscape: Node
var music: AudioStreamPlayer
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

	lev = Leviathan.new()
	lev.name = "Leviathan"
	add_child(lev)
	lev.position = Vector3(0, LEVIATHAN_HEIGHT, 0)

	player = Player.new()
	player.name = "Player"
	player.settings = settings
	player.maze = maze
	add_child(player)
	_spawn_player()

	drone = Drone.new()
	drone.name = "Drone"
	drone.music = true
	add_child(drone)

	_setup_music()

	soundscape = Soundscape.new()
	soundscape.name = "Soundscape"
	soundscape.player = player
	soundscape.maze = maze
	soundscape.lev = lev
	add_child(soundscape)

	var rain := Rain.new()
	rain.name = "Rain"
	rain.settings = settings
	rain.soundscape = soundscape
	add_child(rain)

	var dust := Dust.new()
	dust.name = "Dust"
	dust.settings = settings
	dust.maze = maze
	dust.soundscape = soundscape
	dust.rain = rain
	add_child(dust)

	var distant := DistantSounds.new()
	distant.name = "DistantSounds"
	distant.player = player
	distant.maze = maze
	distant.soundscape = soundscape
	distant.rain = rain
	add_child(distant)

	var budget := CreatureBudget.new()
	budget.name = "CreatureBudget"
	budget.settings = settings
	budget.maze = maze
	add_child(budget)

	var hauler := Hauler.new()
	hauler.name = "Hauler"
	hauler.player = player
	hauler.maze = maze
	hauler.soundscape = soundscape
	hauler.distant = distant
	hauler.budget = budget
	add_child(hauler)

	var watchman := Watchman.new()
	watchman.name = "Watchman"
	watchman.player = player
	watchman.maze = maze
	watchman.budget = budget
	add_child(watchman)

	for kind in ["surveyor", "door_holder"]:
		var creature := ThresholdCreature.new()
		creature.name = "Surveyors" if kind == "surveyor" else "DoorHolder"
		creature.kind = kind
		creature.player = player
		creature.maze = maze
		creature.budget = budget
		creature.watchman = watchman
		creature.soundscape = soundscape
		add_child(creature)

	var storm := Storm.new()
	storm.name = "Storm"
	storm.env = env
	storm.drone = drone
	storm.settings = settings
	storm.maze = maze
	storm.center = lev.position
	add_child(storm)

	_setup_hud()

	var debug := DebugHud.new()
	debug.maze = maze
	debug.player = player
	debug.watchman = watchman
	debug.budget = budget
	debug.encounters = [get_node("Surveyors"), get_node("DoorHolder")]
	add_child(debug)

	var bar := EnergyBar.new()
	bar.player = player
	add_child(bar)

	beam_fx = BeamFx.new()
	beam_fx.player = player
	add_child(beam_fx)

	caught = Caught.new()
	caught.player = player
	caught.watchman = watchman
	caught.maze = maze
	add_child(caught)

	var menu := Menu.new()
	menu.settings = settings
	add_child(menu)

	settings.apply()


## 收到关窗口请求后等音频线程放掉生成器再退出（见 drone.gd）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		await get_tree().create_timer(0.2).timeout
		get_tree().quit()


## 黑光改变听感但音乐不停；守夜人抓住时单独处理失声和音乐压低
func _process(_delta: float) -> void:
	var e: float = lev.beam_exposure(player.cam.global_position)
	beam_fx.intensity = maxf(e, caught.blur)
	drone.pressure = e
	soundscape.beam = e
	soundscape.hush = caught.hush
	music.volume_db = linear_to_db(1.0 - caught.blur * 0.75)


## 背景音乐走自己的 Music 总线，音量在 Esc 菜单里调
func _setup_music() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	music = AudioStreamPlayer.new()
	music.name = "Music"
	var stream: AudioStreamMP3 = MUSIC
	stream.loop = true           # 导入设置里也开了循环，这里再保证一次
	music.stream = stream
	music.bus = "Music"
	add_child(music)
	music.play()


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


## 出生在最外一圈观景台上（离中心约 100 米），正对矮墙“观景窗”和远处的利维坦，满能量
func _spawn_player() -> void:
	player.set_flying(false)
	player.velocity = Vector3.ZERO
	var spawn: Vector3 = maze.get_spawn_position()
	player.global_position = spawn
	player.last_safe = spawn
	player.ground_y = spawn.y
	player.energy = 1.0
	player.look_at(Vector3(0, spawn.y, 0), Vector3.UP)
	player.head.rotation.x = deg_to_rad(28)


## 截图存到 user://screenshots/，文件名带时间
func _screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://screenshots/leviathan-%s.png" % stamp
	get_viewport().get_texture().get_image().save_png(path)
	print("截图已保存：", ProjectSettings.globalize_path(path))


## 天空在 storm.gd 里换成风暴云（BG_SKY）
func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.018, 0.022)

	# 主光照不进 5 米宽的走道，走道里全靠环境光；颜色按 sRGB 转线性后很暗，
	# 再经 ACES 和对比度压暗部。墙面是浅色灰泥（wall.gdshader），2 左右走道就看得清又不至于像白天
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.4)
	env.ambient_light_energy = 2.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1

	# 远处的整体雾：让利维坦成为半隐半现的剪影
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.14, 0.17)
	env.fog_density = 0.0018     # 太浓会把远处的利维坦和整座迷宫洗成一片灰
	env.fog_sky_affect = 0.0      # 天上的乌云自己处理地平线的雾霭（sky.gdshader），不再叠一层雾

	# 近处的体积雾：光束、提灯在雾里显形
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.7)
	env.volumetric_fog_emission = Color(0.01, 0.012, 0.015)
	# 雾也吃一份环境光：走道里的雾略亮，黑光柱在亮雾里更显黑
	env.volumetric_fog_ambient_inject = 1.0
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

	# 很弱的竖直天光：只照朝上的面（地面、墙顶），让走道地面比墙略亮、能看清路；
	# 不投影、不进体积雾，黑光周围的雾亮度不受影响
	var sky_fill := DirectionalLight3D.new()
	sky_fill.name = "SkyFill"
	sky_fill.light_color = Color(0.6, 0.68, 0.82)
	sky_fill.light_energy = 0.35
	sky_fill.light_volumetric_fog_energy = 0.0
	add_child(sky_fill)
	sky_fill.rotation_degrees = Vector3(-90, 0, 0)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.text = "WASD 移动 · 方向键 转视角 · Shift 奔跑 · 空格 跳跃，空中按住升空、松开滑翔 · F 提灯 · M 地图 · Esc 菜单"
	label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85, 0.85))
	label.add_theme_font_size_override("font_size", 18)
	label.position = Vector2(24, 20)
	layer.add_child(label)
	var tw := create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(label, "modulate:a", 0.0, 3.0)
