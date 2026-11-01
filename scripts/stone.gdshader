// 程序化石材：按世界坐标铺砌的浅色方石。
// 墙面是错缝砌筑的条石（每一皮错开半块），朝上的面是方形铺地石。
// 砖缝压暗、每块石头颜色略有差异，墙面带竖向的水渍。
// 不用 UV，所以缩放过的 MultiMesh 实例和程序生成的拱也能无缝贴上。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 stone_color : source_color = vec3(0.6, 0.59, 0.55);
uniform vec2 block_size = vec2(1.8, 0.9);   // 墙面条石：长 × 高（米）
uniform float paving_size = 1.6;           // 铺地石边长（米）
uniform float mortar = 0.016;              // 砖缝宽度（米）
uniform float variation = 0.26;            // 石块之间的明暗差异
uniform float grime = 0.4;                 // 水渍强度

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
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

	vec2 bsize = up ? vec2(paving_size) : block_size;
	vec2 g = uv / bsize;
	if (!up) {
		g.x += mod(floor(g.y), 2.0) * 0.5;   // 错缝
	}
	vec2 id = floor(g);
	vec2 f = fract(g);
	vec2 edge = min(f, 1.0 - f) * bsize;     // 到最近砖缝的距离（米）
	float joint = smoothstep(mortar, mortar * 2.0, min(edge.x, edge.y));   // 0 = 砖缝

	float tone = 1.0 + (hash(id) - 0.5) * variation;
	float detail = 0.74 + fbm(uv * 2.5) * 0.3 + fbm(uv * 0.35) * 0.26;
	vec3 col = stone_color * tone * detail;

	// 竖向水渍：沿水平方向变化、竖直方向拉长；铺地上弱一些
	float streak = fbm(vec2(uv.x * 1.3 + id.x * 0.1, world_pos.y * 0.07));
	col *= 1.0 - grime * smoothstep(0.42, 0.78, streak) * (up ? 0.3 : 1.0);
	// 石块边缘略暗，像风化后的倒角
	col *= mix(0.82, 1.0, smoothstep(0.0, 0.1, min(edge.x, edge.y)));
	col *= mix(0.6, 1.0, joint);

	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.86, joint);
	SPECULAR = 0.3;
}
