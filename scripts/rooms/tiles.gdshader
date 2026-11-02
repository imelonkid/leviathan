// 病房的旧瓷砖：按世界坐标铺小方砖，灰缝发黑，砖面泛黄、有污渍，少数砖掉了露出底下的灰泥。
// 按面的朝向选平面（地面用 xz，墙用 xy / zy），不用 UV。
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, ambient_light_disabled;

uniform vec3 tile_color : source_color = vec3(0.5, 0.5, 0.45);
uniform vec3 grout_color : source_color = vec3(0.26, 0.24, 0.2);
uniform vec3 stain_color : source_color = vec3(0.3, 0.25, 0.16);
uniform vec3 bare_color : source_color = vec3(0.34, 0.3, 0.25);
uniform float tile_size = 0.15;
uniform float grout = 0.05;          // 灰缝占一块砖的比例
uniform float missing = 0.03;        // 掉砖的比例
uniform float stain = 0.85;

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
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 n = abs(world_nrm);
	vec2 p = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec2 cell = floor(p / tile_size);
	vec2 f = fract(p / tile_size);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float is_grout = 1.0 - smoothstep(grout * 0.5, grout * 0.5 + 0.02, edge);
	float h = hash(cell);

	vec3 col = tile_color * (0.9 + 0.12 * h);
	// 大片的污渍和水渍，越往下越重
	float s = noise(p * 0.8) * 0.6 + noise(p * 3.1) * 0.4;
	float low = n.y > 0.5 ? 0.5 : 1.0 - smoothstep(0.0, 2.0, fract(world_pos.y / 12.0) * 12.0);
	col = mix(col, stain_color, clamp((s - 0.45) * 2.0, 0.0, 1.0) * stain * (0.5 + 0.5 * low));
	col = mix(col, grout_color, is_grout);
	float rough = mix(0.45, 0.9, is_grout);

	if (hash(cell + 17.3) < missing) {
		col = bare_color * (0.7 + 0.3 * noise(p * 6.0));
		rough = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
}
