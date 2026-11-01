// 利维坦本体：旧黄铜，表面刻满几何纹样。
// 按模型自身坐标计算，每个三角面上用两个量定位：
//   a = 沿面水平方向的位置（米），e = 到最近斜棱的距离（米），y = 高度（米）。
// 纹样：沿棱的两道边框、每 34 米一道横带、带子里的回纹（电路一样的折线）、腰部的圆形徽章。
// 尺度要大：从几百米外看也得认得出纹样，不然只是一层噪点。
// 刻槽是暗色、粗糙、凹下去的；铜面有磨亮和发暗的斑块。
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx, fog_disabled;   // 远景雾会把它洗成一团灰

uniform float half_width = 42.0;     // 腰部到棱的距离，与 leviathan.gd 的 HALF_WIDTH 一致
uniform float half_height = 170.0;
uniform vec3 brass : source_color = vec3(0.5, 0.38, 0.21);
uniform vec3 tarnish : source_color = vec3(0.13, 0.11, 0.08);
uniform vec3 groove_color : source_color = vec3(0.04, 0.035, 0.03);
uniform float groove_w = 0.45;       // 刻槽半宽（米）
uniform float band_period = 34.0;    // 横带间距（米）
uniform float cell = 7.0;            // 回纹格子（米）
uniform float bump = 0.5;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

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

// 离一条线 d（到线的距离）有多近：1 = 在槽里
float line(float d) {
	return 1.0 - smoothstep(groove_w * 0.6, groove_w, abs(d));
}

void fragment() {
	vec3 p = local_pos;
	float y = p.y;
	float taper = 1.0 - abs(y) / half_height;
	// 所在的面由 x、z 的符号决定；a 沿着这一面的水平棱
	float sx = p.x >= 0.0 ? 1.0 : -1.0;
	float sz = p.z >= 0.0 ? 1.0 : -1.0;
	float a = (sz * p.z - sx * p.x) * 0.7071;
	float half_len = half_width * taper * 0.7071;
	float e = half_len - abs(a);
	// 面的编号，让四个面的纹样各不相同
	float face = (sx > 0.0 ? 0.0 : 2.0) + (sz > 0.0 ? 0.0 : 1.0);

	float g = 0.0;
	// 沿两条斜棱的边框
	g = max(g, line(e - 2.5));
	g = max(g, line(e - 5.5));
	bool inner = e > 7.5;
	if (inner) {
		// 横带：一道粗线夹两道细线
		float band = (fract(y / band_period + 0.5) - 0.5) * band_period;
		g = max(g, line(band));
		g = max(g, line(abs(band) - 2.0) * step(abs(band), 2.6));

		// 腰部徽章：两道圆环 + 放射线
		vec2 c = vec2(a, y);
		float r = length(c);
		float medal = 0.0;
		if (r < 26.0) {
			medal = max(line(r - 13.0), line(r - 21.0));
			medal = max(medal, line(r - 23.5));
			float ang = atan(c.y, c.x);
			float spoke = abs(fract(ang / (3.14159 / 8.0) + 0.5) - 0.5) * (3.14159 / 8.0) * r;
			medal = max(medal, line(spoke) * step(13.0, r) * step(r, 21.0));
			medal = max(medal, line(r - 5.0));
			// 内圈一个菱形，呼应本体的形状
			medal = max(medal, line(abs(c.x) * 1.8 + abs(c.y) - 10.0));
			g = max(g, medal);
		} else if (abs(band) > 3.5) {
			// 回纹：一格一格随机画一段竖线、横线或拐角，连起来像电路
			vec2 id = floor(vec2(a, y) / cell);
			vec2 f = fract(vec2(a, y) / cell) * cell - cell * 0.5;
			float h = hash(id + face * 17.0);
			float v_line = line(f.x) * step(h, 0.35);
			float h_line = line(f.y) * step(0.35, h) * step(h, 0.65);
			float corner = step(0.65, h) * step(h, 0.85)
				* max(line(f.x) * step(0.0, f.y), line(f.y) * step(0.0, f.x));
			g = max(g, max(v_line, max(h_line, corner)));
		}
	}

	// 铜面：大块发暗、局部磨亮，越往下越脏
	float wear = fbm(vec2(a, y) * 0.03 + face * 3.0);
	float dark = smoothstep(0.28, 0.62, fbm(vec2(a, y) * 0.05 + 9.0));
	vec3 col = mix(brass * (0.75 + wear * 0.45), tarnish, dark * 0.75);
	col = mix(col, tarnish, smoothstep(0.2, -1.0, y / half_height) * 0.5);
	col = mix(col, groove_color, g);

	// 刻槽凹下去：屏幕空间导数做凹凸
	float hgt = -g * 0.6 + fbm(vec2(a, y) * 0.6) * 0.3;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * bump * 0.05);

	ALBEDO = col;
	// 一点自发光：天空很暗，不然整体沉进背景里；刻槽不发光，纹样更清楚
	EMISSION = col * 0.05 * (1.0 - g);
	METALLIC = mix(0.6, 0.2, g);   // 不调太高：天空很暗，全金属会只反射一片黑
	ROUGHNESS = mix(0.32 + dark * 0.35 + wear * 0.1, 1.0, g);
	SPECULAR = mix(0.5, 0.0, g);   // 刻槽不反光，否则槽壁会亮成一道道白线
}
