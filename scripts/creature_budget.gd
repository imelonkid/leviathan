extends Node
## 怪物加载名额按实际前台帧率，在基准值上下各浮动一个。
## 怪物平时只是一个没有模型的空节点（只有计时和行为），快出场时（PREFETCH 秒前）在后台线程里加载模型，
## 出场时向这里要一个名额：名额满了、或者模型还没加载完，就晚一点再试；退场后过了 KEEP 秒（而且不会马上又出来）
## 把模型释放、还回名额。模型路径用字符串，不用 preload——preload 会让模型一直留在内存里。

const Settings = preload("res://scripts/settings.gd")
const BASE_LOADED := 3
const MIN_LOADED := BASE_LOADED - 1
const MAX_LOADED := BASE_LOADED + 1
const SETTLE := 8.0             # 开局、换图、改画质、恢复前台后的稳定时间
const SLOW_WINDOWS := 3         # 连续三个一秒窗口低于目标的 85% 才减额
const GOOD_WINDOWS := 20        # 连续二十个窗口达到目标的 97% 才增额
const RECOVERY := 30.0          # 减额后至少三十秒不增额
const PREFETCH := 6.0            # 出场前多久开始在后台加载（秒）
const KEEP := 30.0               # 退场后模型再留多久才释放（马上又要出来就不用重新加载）

var settings: Node
var maze: Node3D
var limit := BASE_LOADED
var holders: Array[Node] = []    # 正占着名额的怪物
var requested := {}              # 已经在后台加载的模型路径
var target_fps := 0.0
var measured_fps := 0.0
var settling := SETTLE
var recovery := 0.0
var good_windows := 0
var slow_windows := 0
var sample_time := 0.0
var sample_frames := 0
var last_tick := 0
var last_gen: RefCounted


func _ready() -> void:
	last_tick = Time.get_ticks_usec()
	last_gen = maze.gen
	settings.changed.connect(reset_sampling)
	# 无窗口测试没有显示帧率，不能用它推断实际渲染性能。
	set_process(DisplayServer.get_name() != "headless")


func reset_sampling() -> void:
	sample_time = 0.0
	sample_frames = 0
	good_windows = 0
	slow_windows = 0
	measured_fps = 0.0
	settling = SETTLE
	last_tick = Time.get_ticks_usec()


func reference_fps(refresh_hz: float) -> float:
	var selected: int = Settings.FRAME_LIMITS[settings.get_value("frame_limit")]
	var fps := float(selected if selected > 0 else 60)
	if settings.get_value("vsync") and refresh_hz > 0:
		fps = minf(fps, refresh_hz)
	return fps


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var seconds := (now - last_tick) / 1000000.0
	last_tick = now
	if last_gen != maze.gen:
		last_gen = maze.gen
		reset_sampling()
		return
	var active: bool = settings.has_focus and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var refresh := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	observe_frame(seconds, reference_fps(refresh), active)


func observe_frame(seconds: float, reference: float, active := true) -> void:
	if not active or not is_equal_approx(reference, target_fps):
		reset_sampling()
		target_fps = reference
		return
	if settling > 0.0:
		settling -= seconds
		return
	recovery = maxf(0.0, recovery - seconds)
	sample_time += seconds
	sample_frames += 1
	if sample_time < 1.0:
		return
	measured_fps = sample_frames / sample_time
	sample_time = 0.0
	sample_frames = 0
	# 再长的一次停顿也只算一个坏窗口，不把单次加载当作持续掉帧。
	slow_windows = slow_windows + 1 if measured_fps < target_fps * 0.85 else 0
	good_windows = good_windows + 1 if measured_fps >= target_fps * 0.97 and recovery <= 0.0 else 0
	if slow_windows >= SLOW_WINDOWS and limit > MIN_LOADED:
		limit -= 1
		recovery = RECOVERY
		slow_windows = 0
		good_windows = 0
	elif good_windows >= GOOD_WINDOWS and limit < MAX_LOADED:
		limit += 1
		good_windows = 0


## 快要出场了：在后台线程里先把模型读进来
func prefetch(path: String) -> void:
	if not requested.has(path):
		requested[path] = true
		ResourceLoader.load_threaded_request(path)


## 出场：拿名额和模型。名额满了或者还没加载完返回 null（晚一点再试）；拿到以后由怪物自己实例化
func take(who: Node, path: String) -> PackedScene:
	if who not in holders and holders.size() >= limit:
		return null
	prefetch(path)
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		return null
	var scene: PackedScene = ResourceLoader.load_threaded_get(path)
	requested.erase(path)
	if who not in holders:
		holders.append(who)
	return scene


## 模型释放了：还回名额
func release(who: Node) -> void:
	holders.erase(who)
