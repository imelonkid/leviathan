extends Node
## 画质与操作设置：保存在 user://settings.cfg，改动后立即生效。
## 三档预设只是一组默认值，单项改过之后预设显示为“自定义”。

signal changed

const PATH := "user://settings.cfg"

const PRESETS := {
	"low": {
		"volumetric_fog": false, "ssao": false, "glow": true,
		"shadow_distance": 120.0, "render_scale": 0.67,
	},
	"medium": {
		"volumetric_fog": true, "ssao": false, "glow": true,
		"shadow_distance": 180.0, "render_scale": 0.85,
	},
	"high": {
		"volumetric_fog": true, "ssao": true, "glow": true,
		"shadow_distance": 250.0, "render_scale": 1.0,
	},
}

var values := {
	"preset": "high",
	"volumetric_fog": true,
	"ssao": true,
	"glow": true,
	"shadow_distance": 250.0,
	"render_scale": 1.0,
	"fullscreen": false,
	"vsync": true,
	"mouse_sens": 0.0025,
	"music_volume": 0.8,
	"photo_mode": false,         # V 键自由飞行（穿墙、无重力），截图和看全景用
}

var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in values:
			values[key] = cfg.get_value("settings", key, values[key])


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
	if env:
		env.volumetric_fog_enabled = values["volumetric_fog"]
		env.ssao_enabled = values["ssao"]
		env.glow_enabled = values["glow"]
	if sun:
		sun.directional_shadow_max_distance = values["shadow_distance"]

	var vp := get_viewport()
	var scale: float = values["render_scale"]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if is_equal_approx(scale, 1.0) \
		else Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = scale

	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if values["vsync"] else DisplayServer.VSYNC_DISABLED)

	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		var v: float = values["music_volume"]
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(music_bus, v <= 0.001)

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
