// 乌云团：始终面向镜头的大面片（MultiMesh 里每个实例一团），
// 用扭曲的噪声画出蓬松的轮廓，上边亮、下边暗，缓慢翻滚；闪电时被照亮。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float lightning;

uniform vec3 dark : source_color = vec3(0.035, 0.045, 0.065);
uniform vec3 lit : source_color = vec3(0.24, 0.29, 0.38);
uniform vec3 flash_color : source_color = vec3(0.7, 0.78, 1.0);
uniform float opacity = 0.92;

varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	seed = float(INSTANCE_ID) * 0.618034;
	// 面向镜头，保留实例的缩放
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 offset = vec2(fract(seed * 13.1), fract(seed * 7.3)) * 40.0;
	vec2 q = UV * 2.6 + offset + vec2(TIME * 0.012, TIME * 0.004);
	float warp = fbm(q * 0.9);
	float n = fbm(q + warp * 1.5);
	// 外圈淡出，中间实；噪声决定边缘的蓬松形状
	float falloff = 1.0 - smoothstep(0.25, 1.0, length(p * vec2(1.0, 1.25)));
	float dens = smoothstep(0.3, 0.7, n * 0.6 + falloff * 0.6) * falloff;
	// UV 的 y 向下：p.y < 0 是上边，上边亮
	float shade = clamp(0.55 - p.y * 0.45 + (n - 0.5) * 0.8, 0.0, 1.0);
	vec3 col = mix(dark, lit, shade * shade);
	col += flash_color * lightning * (0.12 + shade * 0.5);
	ALBEDO = col;
	ALPHA = dens * opacity;
}
