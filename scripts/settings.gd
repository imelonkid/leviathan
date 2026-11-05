extends Node
## 画质与操作设置：保存在 user://settings.cfg，改动后立即生效。
## 三档预设只是一组默认值，单项改过之后预设显示为“自定义”。

signal changed

const PATH := "user://settings.cfg"

const PRESETS := {
	"low": {
		"volumetric_fog": false, "ssao": false, "glow": true,
		"shadow_distance": 120.0, "render_scale": 0.67, "clouds": 0, "reflections": false,
	},
	"medium": {
		"volumetric_fog": true, "ssao": false, "glow": true,
		"shadow_distance": 180.0, "render_scale": 0.85, "clouds": 1, "reflections": false,
	},
	"high": {
		"volumetric_fog": true, "ssao": true, "glow": true,
		"shadow_distance": 250.0, "render_scale": 1.0, "clouds": 2, "reflections": true,
	},
}

const FRAME_LIMITS := [30, 60, 120, 0]
const RESOLUTION_LIMITS := [Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440), Vector2.ZERO]
const BACKGROUND_FPS := 15

var has_focus := true

var values := {
	"preset": "medium",
	"volumetric_fog": true,
	"ssao": false,
	"glow": true,
	"shadow_distance": 180.0,
	"render_scale": 0.85,
	"reflections": false,        # 水洼倒影：高档预设开启屏幕空间反射
	"clouds": 1,                 # 乌云质量：0 低（半分辨率、少步进、没有云环）/ 1 中 / 2 高
	"resolution_limit": 1,       # 900p / 1080p / 1440p / 原生；只约束 3D，UI 保持原生清晰度
	"fullscreen": false,
	"vsync": true,
	"frame_limit": 1,           # 30 / 60 / 120 / 不限，旧配置缺项时默认 60 FPS
	"mouse_sens": 0.0025,
	"key_look_speed": 120.0,     # 方向键转视角的速度（度/秒）
	"music_volume": 0.8,
	"ambience_volume": 0.8,      # 雨、利维坦低鸣、屋里的声音（World 总线）
	"photo_mode": false,         # V 键自由飞行（穿墙、无重力），截图和看全景用
}

var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in values:
			values[key] = cfg.get_value("settings", key, values[key])
		# 旧版本存的设置里没有后来加的项：按当时选的预设补上，免得预设变成“自定义”
		var preset: String = values["preset"]
		if PRESETS.has(preset):
			for key: String in PRESETS[preset]:
				if not cfg.has_section_key("settings", key):
					values[key] = PRESETS[preset][key]

	# 配置文件是外部输入；无效帧率档位回到节能的 60 FPS 默认值。
	if not (values["frame_limit"] is int) or values["frame_limit"] < 0 or values["frame_limit"] >= FRAME_LIMITS.size():
		values["frame_limit"] = 1
	if not (values["resolution_limit"] is int) or values["resolution_limit"] < 0 or values["resolution_limit"] >= RESOLUTION_LIMITS.size():
		values["resolution_limit"] = 1
	get_viewport().size_changed.connect(_apply_render_scale)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		has_focus = false
		_apply_frame_limit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		has_focus = true
		_apply_frame_limit()


func _apply_frame_limit() -> void:
	Engine.max_fps = FRAME_LIMITS[values["frame_limit"]] if has_focus else BACKGROUND_FPS


func render_scale_for(size: Vector2) -> float:
	var scale: float = values["render_scale"]
	var limit: Vector2 = RESOLUTION_LIMITS[values["resolution_limit"]]
	if limit != Vector2.ZERO:
		scale = minf(scale, minf(limit.x / size.x, limit.y / size.y))
	return scale


func _apply_render_scale() -> void:
	var vp := get_viewport()
	var scale := render_scale_for(vp.get_visible_rect().size)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if is_equal_approx(scale, 1.0) \
		else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = scale


func get_value(key: String) -> Variant:
	return values[key]


func set_value(key: String, value: Variant) -> void:
	values[key] = value
	if PRESETS["high"].has(key):
		values["preset"] = _matching_preset()
	_save()
	apply()


func set_preset(preset: String) -> void:
	values["preset"] = preset
	values.merge(PRESETS[preset], true)
	_save()
	apply()


func apply() -> void:
	_apply_frame_limit()
	if env:
		env.volumetric_fog_enabled = values["volumetric_fog"]
		env.ssao_enabled = values["ssao"]
		env.glow_enabled = values["glow"]
		env.ssr_enabled = values["reflections"]
		env.ssr_max_steps = 48
	if sun:
		sun.directional_shadow_max_distance = values["shadow_distance"]

	_apply_render_scale()

	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)

	for pair: Array in [["Music", "music_volume"], ["World", "ambience_volume"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		if idx >= 0:
			var v: float = values[pair[1]]
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)

	changed.emit()


func _matching_preset() -> String:
	for preset_name: String in PRESETS:
		var p: Dictionary = PRESETS[preset_name]
		var same := true
		for key: String in p:
			if values[key] != p[key]:
				same = false
				break
		if same:
			return preset_name
	return "custom"


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: String in values:
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)
