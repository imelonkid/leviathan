// 血迹：贴在地面或墙面上的一块方片，形状全由噪声算出来，不用贴图。
// kind = 0：地上的一摊，边缘不规则，周围溅着小血点；kind = 1：墙上往下淌的血痕，顶上一抹，往下拉出几道，末端积成血珠；
// kind = 2：墙上的血手印，手掌往下滑，拖出几道指痕；kind = 3：地上的拖痕，一头积着血，越拖越淡、断断续续；
// kind = 4：墙上用血划的计数，四竖一横一组，一组一组排下去。
// aspect = 方片的高 / 宽，形状按真实比例算，不会被拉扁。
// 湿的地方反光（粗糙度低），干的边缘发黑。屋里不吃环境光，和房间内衬一致。
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, ambient_light_disabled, shadows_disabled;

uniform float seed = 0.0;
uniform int kind = 0;
uniform float aspect = 1.0;
uniform vec3 wet : source_color = vec3(0.32, 0.015, 0.01);
uniform vec3 dry : source_color = vec3(0.13, 0.025, 0.018);

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

// p.x 0～1，p.y 0～aspect（往下）。顶上一抹不规则的血，往下拉出几道细细的血痕，末端一颗圆血珠
float drip(vec2 p) {
	// 顶上一抹：厚薄不匀，两头收尖
	float th = (0.02 + 0.07 * noise(vec2(p.x * 6.0, seed))) * smoothstep(0.08, 0.3, p.x) * smoothstep(0.92, 0.7, p.x);
	float top = 1.0 - smoothstep(th, th + 0.01, abs(p.y - 0.06 - 0.03 * noise(vec2(p.x * 3.0, seed + 1.0))));
	float streaks = 0.0;
	for (int i = 0; i < 6; i++) {
		float x = 0.15 + 0.7 * hash(vec2(float(i), seed + 0.5));
		float w = 0.004 + 0.008 * hash(vec2(seed, float(i)));
		float len = (0.2 + 0.75 * hash(vec2(float(i) + 9.0, seed))) * aspect;
		float wobble = 0.006 * sin(p.y * 20.0 + float(i));
		float line = (1.0 - smoothstep(w, w + 0.003, abs(p.x - x - wobble))) * (1.0 - step(len, p.y)) * step(0.03, p.y);
		float bead = 1.0 - smoothstep(w * 1.5, w * 1.5 + 0.003, length(vec2(p.x - x - wobble, p.y - len)));
		streaks = max(streaks, max(line, bead));
	}
	return max(top, streaks);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// 手印：p.x 0～1，p.y 0～aspect（往下）。手掌在上面，下面是往下滑出来的指痕
float hand(vec2 p) {
	vec2 palm = vec2(0.5, 0.42);
	float m = 1.0 - smoothstep(0.0, 0.02, length((p - palm) / vec2(0.21, 0.23)) - 1.0);
	for (int i = 0; i < 4; i++) {
		float x = 0.34 + 0.11 * float(i);
		float top = 0.1 + 0.05 * abs(float(i) - 1.4) + 0.03 * hash(vec2(float(i), seed));
		m = max(m, 1.0 - smoothstep(0.045, 0.055, segment(p, vec2(x, top), vec2(x + 0.01, 0.3))));
		// 往下滑出来的指痕：断断续续，越往下越细
		float len = 0.65 + 0.5 * hash(vec2(seed, float(i) + 2.0));
		float w = 0.035 * (1.0 - smoothstep(0.5, aspect, p.y));
		float trail = (1.0 - smoothstep(w, w + 0.01, abs(p.x - x - 0.01 - 0.01 * sin(p.y * 20.0 + float(i)))))
			* step(0.55, p.y) * step(p.y, len) * step(0.35, noise(vec2(x * 13.0, p.y * 9.0 + seed)));
		m = max(m, trail);
	}
	m = max(m, 1.0 - smoothstep(0.05, 0.06, segment(p, vec2(0.26, 0.5), vec2(0.12, 0.34))));
	// 掌纹里没沾上血的空隙
	m *= step(0.12, noise(p * 16.0 + seed));
	return m;
}

// 拖痕：p.x 0～1，p.y 0～aspect。开头一摊，往下拖出一道越来越淡的宽痕，带纵向的条纹
float drag(vec2 p) {
	float pool = 1.0 - smoothstep(0.0, 0.03, length((p - vec2(0.5, 0.45)) / vec2(0.42, 0.4)) - 1.0
		+ 0.25 * noise(p * 6.0 + seed));
	float fade = 1.0 - smoothstep(0.6, aspect - 0.2, p.y);
	float w = 0.28 + 0.1 * noise(vec2(p.y * 1.5, seed));
	float band = (1.0 - smoothstep(w - 0.04, w, abs(p.x - 0.5 - 0.06 * sin(p.y * 0.8 + seed))))
		* step(0.4, p.y);
	float streaks = noise(vec2(p.x * 40.0, p.y * 0.6 + seed));
	float broken = noise(vec2(p.y * 2.0, seed + 5.0));
	return max(pool, band * step(1.0 - fade * 0.9, streaks * 0.6 + broken * 0.6));
}

// 计数：p.x 0～1，p.y 0～aspect。四竖一斜一组，笔画抖动
float tally(vec2 p) {
	float m = 0.0;
	int groups = 3 + int(hash(vec2(seed, 1.0)) * 4.0);
	for (int g = 0; g < 7; g++) {
		if (g >= groups) {
			break;
		}
		float gx = 0.06 + float(g) * 0.135;
		for (int i = 0; i < 4; i++) {
			float x = gx + float(i) * 0.025;
			float j = 0.01 * (hash(vec2(float(g * 4 + i), seed)) - 0.5);
			m = max(m, 1.0 - smoothstep(0.004, 0.008, segment(p, vec2(x + j, aspect * 0.15), vec2(x - j, aspect * 0.85))));
		}
		m = max(m, 1.0 - smoothstep(0.004, 0.008, segment(p, vec2(gx - 0.015, aspect * 0.75), vec2(gx + 0.1, aspect * 0.25))));
	}
	return m * step(0.2, noise(p * 60.0 + seed));
}

void fragment() {
	vec2 p = vec2(UV.x, UV.y * aspect);
	float a = 0.0;
	if (kind == 0) {
		a = splat(UV);
	} else if (kind == 1) {
		a = drip(p);
	} else if (kind == 2) {
		a = hand(p);
	} else if (kind == 3) {
		a = drag(p);
	} else {
		a = tally(p);
	}
	if (a < 0.5) {
		discard;
	}
	float n = noise(UV * 14.0 + seed);
	ALBEDO = mix(dry, wet, smoothstep(0.3, 0.7, n));
	ROUGHNESS = mix(0.7, 0.35, smoothstep(0.3, 0.7, n));
	SPECULAR = 0.25;
}
