// 血迹：贴在地面或墙面上的一块方片，形状全由噪声算出来，不用贴图。
// kind = 0：地上的一摊，边缘不规则，周围溅着小血点；kind = 1：墙上往下淌的血痕，顶上一抹，往下拉出几道，末端积成血珠。
// 湿的地方反光（粗糙度低），干的边缘发黑。屋里不吃环境光，和房间内衬一致。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, ambient_light_disabled, shadows_disabled;

uniform float seed = 0.0;
uniform int kind = 0;
uniform vec3 wet : source_color = vec3(0.2, 0.008, 0.006);
uniform vec3 dry : source_color = vec3(0.07, 0.02, 0.015);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float splat(vec2 uv) {
	vec2 p = uv - 0.5;
	float a = atan(p.y, p.x);
	float r = length(p);
	float edge = 0.27 + 0.09 * noise(vec2(a * 2.0 + seed, seed)) + 0.05 * noise(vec2(a * 7.0, seed * 3.1));
	float body = 1.0 - smoothstep(edge - 0.01, edge + 0.01, r);
	// 周围的小血点
	float drops = 0.0;
	for (int i = 0; i < 9; i++) {
		vec2 h = vec2(hash(vec2(float(i), seed)), hash(vec2(seed, float(i) + 3.7)));
		float ang = h.x * 6.2832;
		float dist = 0.3 + h.y * 0.17;
		vec2 c = vec2(cos(ang), sin(ang)) * dist;
		float s = 0.008 + 0.02 * hash(vec2(seed + float(i), 1.3));
		drops = max(drops, 1.0 - smoothstep(s - 0.004, s + 0.004, length(p - c)));
	}
	return max(body, drops);
}

float drip(vec2 uv) {
	// uv.y = 0 在顶上
	float top = (1.0 - smoothstep(0.12, 0.2 + 0.08 * noise(vec2(uv.x * 9.0, seed)), uv.y))
		* smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x);
	float streaks = 0.0;
	for (int i = 0; i < 6; i++) {
		float x = 0.1 + 0.8 * hash(vec2(float(i), seed + 0.5));
		float w = 0.008 + 0.018 * hash(vec2(seed, float(i)));
		float len = 0.3 + 0.65 * hash(vec2(float(i) + 9.0, seed));
		float wobble = 0.01 * sin(uv.y * 30.0 + float(i));
		float line = 1.0 - smoothstep(w, w + 0.004, abs(uv.x - x - wobble));
		line *= 1.0 - step(len, uv.y);
		float bead = 1.0 - smoothstep(w * 1.6, w * 1.6 + 0.004, length(vec2(uv.x - x - wobble, (uv.y - len) * 0.6)));
		streaks = max(streaks, max(line, bead));
	}
	return max(top, streaks);
}

void fragment() {
	float a = kind == 0 ? splat(UV) : drip(UV);
	if (a < 0.5) {
		discard;
	}
	float n = noise(UV * 14.0 + seed);
	ALBEDO = mix(dry, wet, smoothstep(0.3, 0.7, n));
	ROUGHNESS = mix(0.7, 0.35, smoothstep(0.3, 0.7, n));
	SPECULAR = 0.25;
}
