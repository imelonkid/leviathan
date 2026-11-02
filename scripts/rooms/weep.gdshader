// 渗血的墙：贴在墙面上的一块方片。顶上一道暗红的渗痕，从里面一道道往下渗，
// 每一道的长度随时间慢慢变长、到底后重新开始，表面一层湿亮的光顺着往下滑。
// UV.y = 0 在顶上。屋里不吃环境光，和房间内衬一致。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, ambient_light_disabled, shadows_disabled;

uniform float seed = 0.0;
uniform vec3 wet : source_color = vec3(0.34, 0.015, 0.01);
uniform vec3 dry : source_color = vec3(0.14, 0.025, 0.018);
uniform float aspect = 1.0;          // 方片的高 / 宽
uniform float speed = 0.03;          // 血痕往下伸长的速度（方片高度 / 秒）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float py = uv.y * aspect;   // 按真实比例的竖直坐标，血珠才是圆的
	// 顶上的渗痕：一条不规则的暗带
	float seam = 1.0 - smoothstep(0.02, 0.05 + 0.04 * noise(vec2(uv.x * 7.0, seed)), py);
	float a = seam * smoothstep(0.0, 0.05, uv.x) * smoothstep(1.0, 0.95, uv.x);
	float sheen = 0.0;
	for (int i = 0; i < 9; i++) {
		float fi = float(i);
		float x = 0.06 + 0.88 * hash(vec2(fi, seed));
		float w = 0.003 + 0.006 * hash(vec2(seed, fi));
		// 每道各自的周期：从顶上往下伸，伸到最长再从头来
		float period = 1.0 / (speed * (0.6 + 0.8 * hash(vec2(fi + 4.0, seed))));
		float t = fract(TIME / period + hash(vec2(fi, seed + 2.0)));
		float len = 0.1 + t * (0.5 + 0.45 * hash(vec2(fi + 9.0, seed)));
		float wobble = 0.008 * sin(uv.y * 25.0 + fi * 3.0);
		float dx = abs(uv.x - x - wobble);
		float line = (1.0 - smoothstep(w, w + 0.003, dx)) * (1.0 - step(len, uv.y));
		float bead = 1.0 - smoothstep(w * 1.5, w * 1.5 + 0.003, length(vec2(uv.x - x - wobble, (uv.y - len) * aspect)));
		float s = max(line, bead);
		a = max(a, s);
		// 一小段湿亮的光顺着这一道往下滑
		float glint = 1.0 - smoothstep(0.0, 0.06, abs(uv.y - fract(TIME * 0.15 + fi * 0.37) * len));
		sheen = max(sheen, s * glint);
	}
	if (a < 0.5) {
		discard;
	}
	float n = noise(uv * 18.0 + seed);
	ALBEDO = mix(dry, wet, smoothstep(0.25, 0.75, n) * 0.7 + sheen * 0.3);
	ROUGHNESS = mix(0.6, 0.15, sheen);
	SPECULAR = 0.25 + sheen * 0.4;
}
