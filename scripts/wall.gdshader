// 程序化的旧土墙：按世界坐标生成，不用 UV，缩放过的 MultiMesh 实例和程序生成的拱也能无缝贴上。
// 墙面是一层风化的灰泥 / 夯土：大块的明暗斑驳、细裂纹、竖向水渍、墙根积的土；
// 灰泥剥落的地方露出底下的土坯砖。朝上的面是踩实的土地，带碎石和浅坑。
// 用屏幕空间导数做凹凸，裂纹和剥落处真的有起伏。
// 下雨时朝上的面变湿变暗；地面（puddles = 1）的低洼处积起水洼：几乎是镜面，下雨时有涟漪，闪电时一亮。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 plaster_color : source_color = vec3(0.5, 0.46, 0.4);   // 灰泥 / 夯土
uniform vec3 brick_color : source_color = vec3(0.42, 0.34, 0.27);   // 剥落处露出的土坯
uniform vec3 dirt_color : source_color = vec3(0.24, 0.21, 0.18);    // 积土、水渍
uniform vec2 brick_size = vec2(0.42, 0.14);  // 土坯砖：长 × 高（米）
uniform float tier_h = 12.0;                 // 层高：墙根积土按“离本层地面多高”计算
uniform float peel = 0.45;                   // 灰泥剥落的多少，0 = 不剥落
uniform float crack = 0.6;                   // 裂纹强度
uniform float grime = 0.55;                  // 水渍和积土强度
uniform float bump = 1.4;                    // 凹凸强度
uniform float puddles = 0.0;                 // 会不会积水洼：地面 1，墙顶等 0
uniform vec3 puddle_sky : source_color = vec3(0.2, 0.24, 0.31);   // 水洼里倒映的天光（越斜着看越亮）
global uniform float wetness;                // 地面有多湿 0～1（rain.gd：下雨时慢慢变湿，停雨后更慢地变干）
global uniform float rain;                   // 当前雨量 0～1：水洼上的涟漪
global uniform float lightning;              // 闪电亮度（storm.gd）

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
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

// 沃罗诺伊网格到最近边界的距离：用来画龟裂纹
float cell_edge(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash2(i + o) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

// 水洼上的雨点涟漪：每 0.7 米一格，格里一个雨点，按各自的相位一圈圈扩散
float ripples(vec2 p) {
	vec2 g = p / 0.7;
	float h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = floor(g) + vec2(float(x), float(y));
			vec2 r = hash2(c);
			float t = fract(TIME * 0.8 + r.x * 7.0);
			float d = length(g - c - r) - t * 0.9;
			h += sin(d * 40.0) * exp(-abs(d) * 18.0) * (1.0 - t);
		}
	}
	return h;
}

void fragment() {
	vec3 n = abs(world_nrm);
	bool up = n.y > max(n.x, n.z);
	vec2 uv;
	if (up) {
		uv = world_pos.xz;
	} else if (n.x > n.z) {
		uv = vec2(world_pos.z, world_pos.y);
	} else {
		uv = vec2(world_pos.x, world_pos.y);
	}

	float h;            // 凹凸用的高度
	vec3 col;
	float rough = 0.97;
	float spec = 0.2;
	vec3 emit = vec3(0.0);
	if (up) {
		// 踩实的土地：大块深浅、零星碎石、积土的浅坑
		float mottle = fbm(uv * 0.25) * 0.6 + fbm(uv * 1.7) * 0.4;
		float gravel = smoothstep(0.72, 0.8, noise(uv * 7.0 + 3.7)) * smoothstep(0.4, 0.6, fbm(uv * 0.9));
		float pit = smoothstep(0.55, 0.75, fbm(uv * 0.6 + 7.3));
		col = mix(plaster_color * 0.85, dirt_color * 1.3, mottle * 0.9);
		col = mix(col, dirt_color, pit * 0.5);
		col *= 1.0 - gravel * 0.3;
		h = mottle * 0.4 - pit * 0.6 + gravel * 0.4 + fbm(uv * 6.0) * 0.12;

		// 湿了：整体变暗、没那么糙；低洼处积水
		col *= 1.0 - wetness * 0.35;
		rough = mix(0.97, 0.6, wetness);
		float low = fbm(uv * 0.15 + 17.0) * 0.75 + fbm(uv * 0.6 + 7.3) * 0.25;
		float t = mix(0.8, 0.56, wetness);
		float water = smoothstep(t, t + 0.025, low) * step(0.02, wetness) * puddles;
		float rim = smoothstep(t - 0.07, t, low) * wetness * puddles;   // 水边一圈湿泥
		col *= 1.0 - rim * 0.25;
		col = mix(col, col * 0.2, water);
		rough = mix(rough, 0.03, water);
		spec = mix(spec, 0.5, water);
		h = mix(h, ripples(uv) * 0.25 * rain, water);
		// 倒映的天：天空是自定义着色器，引擎的环境反射几乎为零，这里按菲涅耳自己加一层天光；
		// 开了屏幕空间反射时，墙和利维坦的倒影叠在上面
		vec3 up_v = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(up_v, VIEW), 0.0, 1.0), 3.0);
		emit = (puddle_sky * (0.25 + fres * 0.9) + vec3(0.5, 0.55, 0.7) * lightning * 0.5) * water;
	} else {
		// 灰泥层：大块斑驳 + 细颗粒
		float mottle = fbm(uv * 0.18) * 0.55 + fbm(uv * 1.1) * 0.45;
		float grain = fbm(uv * 7.0);
		col = plaster_color * (0.72 + mottle * 0.55) * (0.93 + grain * 0.12);

		// 剥落：低频噪声超过阈值的地方，灰泥掉了，露出错缝土坯砖
		float flake = fbm(uv * 0.45 + 3.1) + (fbm(uv * 3.0) - 0.5) * 0.25;
		float exposed = smoothstep(1.0 - peel * 0.62, 1.0 - peel * 0.55, flake);
		vec2 g = uv / brick_size;
		g.x += mod(floor(g.y), 2.0) * 0.5;
		vec2 f = fract(g);
		vec2 edge = min(f, 1.0 - f) * brick_size;
		float joint = smoothstep(0.008, 0.02, min(edge.x, edge.y));
		vec3 brick = brick_color * (0.8 + hash(floor(g)) * 0.35) * mix(0.55, 1.0, joint);
		col = mix(col, brick, exposed);
		// 剥落边缘一圈更暗，像灰泥的断面
		float rim = smoothstep(1.0 - peel * 0.66, 1.0 - peel * 0.6, flake) - exposed;
		col *= 1.0 - rim * 0.35;

		// 龟裂纹：只在灰泥上，而且只在一部分区域出现，不然整面墙像绗缝的被子
		float c = cell_edge(uv * 1.4 + fbm(uv * 2.0) * 0.8);
		float crack_zone = smoothstep(0.5, 0.62, fbm(uv * 0.35 + 11.0));
		float cracks = (1.0 - smoothstep(0.0, 0.02, c)) * crack * crack_zone * (1.0 - exposed);
		col *= 1.0 - cracks * 0.55;

		// 竖向水渍，从墙顶往下流
		float streak = fbm(vec2(uv.x * 1.6, world_pos.y * 0.06));
		col = mix(col, dirt_color, grime * 0.6 * smoothstep(0.45, 0.8, streak));
		// 墙根积土：离本层地面 0～2 米越低越脏
		float above = mod(world_pos.y + 0.01, tier_h);
		col = mix(col, dirt_color, grime * (1.0 - smoothstep(0.0, 2.2, above)) * (0.6 + noise(uv * 2.0) * 0.4));

		h = mottle * 0.5 - exposed * 0.5 - cracks * 0.6 - (1.0 - joint) * exposed * 0.3 + grain * 0.12;
	}

	// 屏幕空间导数做凹凸：不需要切线
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * 0.05);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = emit;
}
