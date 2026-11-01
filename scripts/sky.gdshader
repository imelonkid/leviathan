// 风暴天空：光线步进的体积乌云。
// 从镜头沿视线穿过一层高空云层（cloud_bottom～cloud_top），一步步累加密度；
// 每一步再朝“云后的亮处”（light_dir）探几步，算出这里被遮了多少，于是云有了明暗和体积，
// 背光的边缘透出银白的亮边，像电影里翻滚的雷暴云墙。
// 反射用的环境贴图不做步进，只给大致颜色，省下大头的开销。
// 闪电时（全局参数 lightning）整片云从内部被照亮。
shader_type sky;

global uniform float lightning;

uniform vec3 zenith : source_color = vec3(0.06, 0.08, 0.13);
uniform vec3 horizon : source_color = vec3(0.16, 0.2, 0.28);
uniform vec3 glow_color : source_color = vec3(0.55, 0.62, 0.75);  // 云后亮处的天光
uniform vec3 light_dir = vec3(-0.45, 0.42, -0.78);               // 亮处的方向（左上、利维坦后方）
uniform vec3 light_color : source_color = vec3(0.95, 1.0, 1.1);
uniform vec3 shadow_color : source_color = vec3(0.02, 0.026, 0.045);  // 云底、云心最暗处
uniform vec3 ambient_color : source_color = vec3(0.22, 0.27, 0.36);  // 云顶接到的天光
uniform vec3 flash_color : source_color = vec3(0.65, 0.72, 1.0);
uniform float coverage = 0.76;          // 云量：越大越密
uniform float cloud_bottom = 420.0;     // 云层底和顶（米，相对镜头）
uniform float cloud_top = 2400.0;
uniform float scale = 0.0011;           // 云的尺度：越小云团越大
uniform float wind = 6.0;               // 云飘动的速度（米/秒）
uniform int steps = 48;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm3(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * noise3(p);
		p = p * 2.02 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// 某一点的云密度：大团的形状 + 细节侵蚀；底部平、顶部圆，像积雨云
float density(vec3 p, bool detail) {
	float h = (p.y - cloud_bottom) / (cloud_top - cloud_bottom);
	if (h < 0.0 || h > 1.0) {
		return 0.0;
	}
	vec3 q = p * scale + vec3(TIME * wind * scale, 0.0, TIME * wind * scale * 0.4);
	float shape = fbm3(q, 4);
	float profile = smoothstep(0.0, 0.08, h) * smoothstep(1.0, 0.45, h);
	float d = (shape - (1.0 - coverage)) * profile;
	if (d <= 0.0) {
		return 0.0;
	}
	if (detail) {
		d -= (fbm3(q * 5.0, 3) - 0.35) * 0.18;
	}
	return clamp(d * 6.0, 0.0, 1.0);
}

vec4 march(vec3 dir) {
	if (dir.y < 0.02) {
		return vec4(0.0);
	}
	vec3 ld = normalize(light_dir);
	float t0 = cloud_bottom / dir.y;
	float t1 = min(cloud_top / dir.y, t0 + 3500.0);
	float dt = (t1 - t0) / float(steps);
	// 起点抖动一点，消掉分层的条纹
	float t = t0 + dt * fract(sin(dot(dir.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float trans = 1.0;
	vec3 col = vec3(0.0);
	// 朝亮处看时云边更亮（前向散射）
	float phase = 0.5 + 1.6 * pow(max(dot(dir, ld), 0.0), 4.0);
	for (int i = 0; i < steps; i++) {
		vec3 p = dir * t;
		float d = density(p, true);
		if (d > 0.005) {
			float occ = 0.0;
			for (int j = 1; j <= 3; j++) {
				occ += density(p + ld * 55.0 * float(j), false);
			}
			float lit = exp(-occ * 0.9);
			// 天光：越往云顶越亮，底部压暗，云团才有上下的体积感
			float hf = (p.y - cloud_bottom) / (cloud_top - cloud_bottom);
			vec3 c = mix(shadow_color, ambient_color, clamp(hf * 1.4 + 0.1, 0.0, 1.0));
			// 主光：朝亮处的一面被照亮，背光的边缘透出亮边
			c += light_color * phase * lit * 0.8;
			// 闪电从云里面照亮
			c += flash_color * lightning * (0.25 + 0.5 * (1.0 - lit));
			float a = 1.0 - exp(-d * dt * 0.02);
			col += trans * a * c;
			trans *= 1.0 - a;
			if (trans < 0.03) {
				break;
			}
		}
		t += dt;
	}
	// 越远越淡进地平线的雾霭
	float haze = 1.0 - exp(-t0 * 0.00012);
	col = mix(col, horizon * (1.0 - trans), haze);
	return vec4(col, 1.0 - trans);
}

vec3 background(vec3 dir) {
	vec3 col = mix(horizon, zenith, smoothstep(0.0, 0.6, dir.y));
	// 云后亮处的一片天光，只有在云缝里看得见
	float g = pow(max(dot(dir, normalize(light_dir)), 0.0), 8.0);
	col += glow_color * g * 0.8;
	return col + flash_color * lightning * 0.15;
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		// 反射用的环境贴图：不做步进，给个大致的颜色就行
		COLOR = background(EYEDIR) * 0.6;
	} else {
		vec4 c = march(EYEDIR);
		COLOR = background(EYEDIR) * (1.0 - c.a) + c.rgb;
	}
}
