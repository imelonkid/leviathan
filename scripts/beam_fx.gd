extends CanvasLayer
## 被黑光扫中时的画面：抽掉颜色、从四周往中间压黑、画面微微扭动，再加一点镜头抖动。
## intensity 由 main 每帧根据镜头在不在光锥里给出，这里做平滑，进出都是渐变的。

var intensity := 0.0             # 目标强度（0～1）
var level := 0.0                 # 平滑后的实际强度
var player: CharacterBody3D      # 镜头抖动用
var rect: ColorRect
var mat: ShaderMaterial


func _ready() -> void:
	layer = 0                    # 在 HUD（第 1 层）下面：小地图、提示不被压黑
	mat = ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float level = 0.0;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	// 画面像被热浪一样扭动
	uv += vec2(sin(uv.y * 22.0 + TIME * 7.0), cos(uv.x * 18.0 - TIME * 6.0)) * 0.006 * level;
	// 越深越糊：取模糊一级的画面
	vec3 col = textureLod(screen_tex, uv, level * 1.2).rgb;
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), level * 0.85);
	// 从四周往中间压黑
	float r = length((SCREEN_UV - 0.5) * vec2(1.6, 1.0));
	float vignette = smoothstep(0.15, 0.95, r);
	col *= 1.0 - level * (0.35 + 0.55 * vignette);
	// 细碎的黑色颗粒
	col *= 1.0 - level * 0.25 * hash(SCREEN_UV * 900.0 + fract(TIME));
	COLOR = vec4(col, 1.0);
}
"""
	rect = ColorRect.new()
	rect.material = mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	add_child(rect)


func _process(delta: float) -> void:
	# 进入时快、离开时慢一点，像被压住后慢慢缓过来
	var speed := 4.0 if intensity > level else 1.5
	level = move_toward(level, intensity, speed * delta)
	rect.visible = level > 0.01
	mat.set_shader_parameter("level", level)
	if player:
		var shake := level * level * 0.06
		player.cam.h_offset = randf_range(-shake, shake)
		player.cam.v_offset = randf_range(-shake, shake)
