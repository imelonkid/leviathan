// 缠绕利维坦的云环：一个包住利维坦周围的大盒子里做光线步进的体积云。
// 盒子只画背面（镜头在里面也画得出来），关掉深度测试，自己读场景深度来决定走到哪为止，
// 所以挡在利维坦前面的云会遮住它，后面的云被它挡住。
// 云的分布是一个环：贴着本体的内圈薄、腰部最厚、往外和上下都散开；整体绕竖轴缓慢盘旋。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled, fog_disabled;

global uniform float lightning;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 center = vec3(0.0, 250.0, 0.0);
uniform float r_inner = 50.0;          // 云环内径：本体腰部半宽 42 米
uniform float r_outer = 380.0;         // 包围盒的半宽；云在 r_fade 处就散尽，离盒壁留足余量
uniform float r_fade = 250.0;
uniform float half_h = 180.0;          // 包围盒上下的半高；云在 h_fade 处就散尽
uniform float h_fade = 110.0;
uniform float y_bias = 30.0;
uniform float coverage = 0.56;
uniform float scale = 0.006;
uniform float swirl = 0.025;           // 盘旋的角速度（弧度/秒）
uniform vec3 light_dir = vec3(-0.45, 0.42, -0.78);
uniform vec3 light_color : source_color = vec3(0.26, 0.29, 0.35);
uniform vec3 ambient_color : source_color = vec3(0.065, 0.075, 0.1);
uniform vec3 shadow_color : source_color = vec3(0.015, 0.018, 0.028);
uniform vec3 flash_color : source_color = vec3(0.65, 0.72, 1.0);
uniform int steps = 40;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

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
		p = p * 2.03 + vec3(3.1, 7.7, 1.3);
		a *= 0.5;
	}
	return v;
}

float density(vec3 p, bool detail) {
	vec3 q = p - center;
	q.y -= y_bias;
	float r = length(q.xz);
	if (r > r_fade || abs(q.y) > h_fade) {
		return 0.0;
	}
	// 环形的轮廓：腰部最厚，往上下、往外逐渐散开；外缘用噪声扰动，不留规整的边
	float edge_n = fbm3(q * 0.012, 2) - 0.5;
	float ring = smoothstep(r_inner, r_inner + 35.0, r) * (1.0 - smoothstep(r_fade * 0.35, r_fade, r + edge_n * 90.0));
	float vert = 1.0 - smoothstep(h_fade * 0.15, h_fade, abs(q.y) + (r - r_inner) * 0.18 + edge_n * 40.0);
	// 盘旋：绕竖轴转，越靠内转得越快，高处多转一点，像漩涡
	float ang = TIME * swirl * (1.6 - r / r_outer) + q.y * 0.004;
	float c = cos(ang);
	float s = sin(ang);
	vec3 w = vec3(c * q.x - s * q.z, q.y, s * q.x + c * q.z);
	float shape = fbm3(w * scale, 4);
	float d = (shape - (1.0 - coverage)) * ring * vert;
	if (d <= 0.0) {
		return 0.0;
	}
	if (detail) {
		d -= (fbm3(w * scale * 4.0, 2) - 0.4) * 0.12;
	}
	return clamp(d * 5.0, 0.0, 1.0);
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize(world_pos - cam);

	// 光线和云环包围盒的交点
	vec3 bmin = center + vec3(-r_outer, -half_h + y_bias, -r_outer);
	vec3 bmax = center + vec3(r_outer, half_h + y_bias, r_outer);
	vec3 inv = 1.0 / dir;
	vec3 t0 = (bmin - cam) * inv;
	vec3 t1 = (bmax - cam) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float t_near = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float t_far = min(min(tmax.x, tmax.y), tmax.z);

	// 场景深度：走到挡住视线的东西（利维坦、墙）为止
	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene = length(view.xyz / view.w);
	t_far = min(t_far, scene);
	if (t_far <= t_near) {
		discard;
	}

	vec3 ld = normalize(light_dir);
	float dt = (t_far - t_near) / float(steps);
	float t = t_near + dt * fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);
	float trans = 1.0;
	vec3 col = vec3(0.0);
	float phase = 0.5 + 1.4 * pow(max(dot(dir, ld), 0.0), 4.0);
	for (int i = 0; i < steps; i++) {
		vec3 p = cam + dir * t;
		float d = density(p, true);
		if (d > 0.005) {
			float occ = density(p + ld * 25.0, false) + density(p + ld * 60.0, false);
			float lit = exp(-occ * 1.2);
			float hf = clamp((p.y - center.y + half_h) / (2.0 * half_h), 0.0, 1.0);
			vec3 c = mix(shadow_color, ambient_color, hf * 0.8 + 0.15);
			c += light_color * phase * lit * 0.6;
			c += flash_color * lightning * (0.35 + 0.6 * (1.0 - lit));
			float a = 1.0 - exp(-d * dt * 0.035);
			col += trans * a * c;
			trans *= 1.0 - a;
			if (trans < 0.03) {
				break;
			}
		}
		t += dt;
	}
	ALBEDO = col / max(1.0 - trans, 0.001);
	ALPHA = 1.0 - trans;
}
