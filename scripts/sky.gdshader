// 风暴天空：低垂的乌云盖满整个天空，云层缓慢翻滚，闪电时整片云被照亮。
// 云按“投到头顶一个平面上”的坐标计算，越靠近地平线越扁、越密，像真的云层。
shader_type sky;

global uniform float lightning;

uniform vec3 zenith : source_color = vec3(0.07, 0.09, 0.14);
uniform vec3 horizon : source_color = vec3(0.15, 0.18, 0.24);
uniform vec3 cloud_dark : source_color = vec3(0.03, 0.04, 0.06);
uniform vec3 cloud_lit : source_color = vec3(0.32, 0.38, 0.5);
uniform vec3 flash_color : source_color = vec3(0.7, 0.78, 1.0);
uniform float drift = 0.006;

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
	for (int i = 0; i < 6; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.7, d.y));
	float dens = 0.0;
	float lit = 0.0;
	if (d.y > -0.1) {
		vec2 uv = d.xz / (max(d.y, 0.0) + 0.12) * 2.8;
		vec2 t = vec2(TIME * drift, TIME * drift * 0.6);
		// 两层扭曲的噪声：大团的云 + 翻卷的边
		float warp = fbm(uv * 0.8 + t);
		float n = fbm(uv * 1.3 + warp * 1.6 - t * 0.5);
		dens = smoothstep(0.32, 0.7, n);
		// 云团朝上的一侧被天光照亮一些，形成层次
		lit = smoothstep(0.45, 0.85, fbm(uv * 1.9 + warp * 2.2 + 4.0));
		vec3 c = mix(cloud_dark, cloud_lit, lit * lit);
		col = mix(col, c, dens * smoothstep(-0.1, 0.08, d.y));
	}
	col += flash_color * lightning * (0.08 + dens * 0.45 + lit * 0.35);
	COLOR = col;
}
