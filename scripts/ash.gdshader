shader_type spatial;
// 落下的灰烬（dust.gd 的粒子）：不规则的炭灰、纸灰碎片，大小不一，大的慢慢翻转。
// 不吃环境光和平行光（月光、天光），只被提灯、房间里的灯、闪电落点的余光这类点光照亮，
// 闪电一亮整片显形；平时在暗处看不见，背着亮天是一片片黑色剪影。
render_mode blend_mix, depth_draw_never, cull_disabled, ambient_light_disabled, shadows_disabled;

global uniform float lightning;

uniform vec3 charcoal : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 paper : source_color = vec3(0.42, 0.39, 0.34);
uniform float big_chance = 0.08;      // 多少比例是指甲盖大的薄片
uniform float near_fade = 1.0;        // 贴着镜头的淡掉，不像飞虫糊在眼前

varying float seed;
varying float fade;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	seed = hash(float(INSTANCE_ID) + 0.37);
	fade = COLOR.a;
	float size = length(MODEL_MATRIX[0].xyz) * (hash(seed * 7.1) < big_chance ? 3.0 : 1.0);
	// 翻转：一条边绕着转，看过去宽度一会儿窄一会儿宽；小的转得快
	float spin = TIME * mix(0.6, 2.2, hash(seed * 3.3)) + seed * 40.0;
	vec2 v = VERTEX.xy * vec2(0.25 + 0.75 * abs(sin(spin)), mix(0.5, 1.0, hash(seed * 5.7)));
	float a = seed * 6.283 + TIME * 0.3 * (hash(seed * 9.1) - 0.5);
	v = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * v;
	// 朝向镜头（自己搭的公告板，好把翻转和旋转放进去）
	vec3 world = MODEL_MATRIX[3].xyz + (INV_VIEW_MATRIX[0].xyz * v.x + INV_VIEW_MATRIX[1].xyz * v.y) * size;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[2].xyz, 0.0)).xyz;
}

void fragment() {
	// 不规则的碎片：半径随角度起伏，边缘碎碎的，像撕开烧过的纸
	vec2 p = UV * 2.0 - 1.0;
	float ang = atan(p.y, p.x);
	float r = 0.6 + 0.1 * sin(ang * 2.0 + seed * 20.0) + 0.09 * sin(ang * 5.0 + seed * 41.0)
		+ 0.07 * sin(ang * 9.0 + seed * 7.0) + 0.05 * sin(ang * 17.0 + seed * 13.0);
	float shape = smoothstep(r, r - 0.12, length(p));
	if (shape < 0.05) {
		discard;
	}
	vec3 col = mix(charcoal, paper, hash(seed * 2.3) * hash(seed * 4.9));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// 闪电：整片一起显形
	EMISSION = col * vec3(0.8, 0.88, 1.0) * lightning * 6.0;
	float d = length(VERTEX);
	ALPHA = shape * fade * smoothstep(near_fade * 0.5, near_fade * 2.0, d) * 0.9;
}

// 只算点光、聚光（提灯、屋里的灯、余光）；薄片两面都受光
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.35 + 0.65 * abs(dot(NORMAL, LIGHT))) * 1.5;
	}
}
