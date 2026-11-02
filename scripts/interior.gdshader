// 窗后的屋子（假室内）：盲拱窗的窗洞面片上，沿视线算进一间并不存在的毛坯房——
// 两侧墙、地面、天花板、后墙按真实的透视画出来，走动时角度跟着变，看上去就像窗后真有一间屋。
// 屋里离窗 1.2 / 2.2 / 3 米各有一层家具剪影（倒下的椅子、翻过来的桌子、靠墙的床垫、柜子、碎屑堆），
// 墙角挂着蜘蛛网；最前面是窗本身：脏玻璃、碎了一角、钉着木板或装着铁栏杆。
// 屋里自己发光（EMISSION），大多只有窗外透进去的一点冷光；少数亮着一盏灯泡，极少数是暗红的。
// 每扇窗按自己的位置取种子，所以扇扇不同、同一扇每次看都一样。
// 窗洞的局部坐标：x 横向、y 向上（0 = 窗台）、z 朝外（窗洞面在 z = 0.01，屋子在 z < 0）。
shader_type spatial;
render_mode blend_mix, cull_back;

uniform float detail = 1.0;          // 0 = 只画屋子本身，不画家具、蜘蛛网（实测整扇窗贴脸也只多 0.1 毫秒，暂不分档）
uniform float brightness = 1.0;      // 屋里整体亮度
uniform float figure_near = 15.0;    // 屋里的人影：走到这么近就看不见了（米）

varying vec3 lp;
varying vec3 cam_l;
varying vec3 seed3;

void vertex() {
	lp = VERTEX;
	cam_l = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	seed3 = MODEL_MATRIX[3].xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rnd(float s, float k) {
	return fract(sin((s * 13.17 + k) * 91.345) * 47453.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

float box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// ---------- 屋子的表面 ----------

// 墙：灰泥大片剥落露出砖，竖向水渍，霉斑
vec3 wall_col(vec2 uv, float s) {
	float n = fbm(uv * 1.3 + s * 10.0);
	vec3 plaster = mix(vec3(0.36, 0.34, 0.3), vec3(0.24, 0.23, 0.2), n);
	float peel = smoothstep(0.52, 0.56, fbm(uv * 0.6 + s * 7.0 + 3.0));
	vec2 b = uv * vec2(4.0, 8.0);
	b.x += step(1.0, mod(b.y, 2.0)) * 0.5;
	vec2 f = fract(b);
	float mortar = step(0.07, f.x) * step(0.12, f.y);
	vec3 brick = mix(vec3(0.1, 0.09, 0.08), vec3(0.3, 0.16, 0.11) * (0.7 + 0.5 * hash(floor(b))), mortar);
	vec3 c = mix(plaster, brick, peel);
	float stain = fbm(vec2(uv.x * 3.0, uv.y * 0.35) + s * 3.0);
	c *= 1.0 - 0.5 * smoothstep(0.5, 0.75, stain);
	float mold = smoothstep(0.62, 0.8, fbm(uv * 2.5 + s * 5.0 + 9.0));
	c = mix(c, vec3(0.08, 0.09, 0.06), mold * 0.7);
	return c;
}

// 地面：落满灰的水泥地，碎屑和纸片
vec3 floor_col(vec2 uv, float s) {
	float n = fbm(uv * 1.7 + s * 4.0);
	vec3 c = mix(vec3(0.26, 0.25, 0.23), vec3(0.17, 0.16, 0.15), n);
	float grit = step(0.86, hash(floor(uv * 22.0) + s));
	c = mix(c, vec3(0.1, 0.09, 0.08), grit * 0.8);
	vec2 pc = floor(uv * 2.5);
	vec2 pf = fract(uv * 2.5);
	float paper = step(0.88, hash(pc + s * 2.0)) * step(box(rot(pf - 0.5, hash(pc) * 3.0), vec2(0.0), vec2(0.18, 0.13)), 0.0);
	c = mix(c, vec3(0.42, 0.4, 0.34), paper);
	return c;
}

// 天花板：发黑的灰泥，一大片水渍
vec3 ceil_col(vec2 uv, float s) {
	float n = fbm(uv * 1.1 + s * 6.0);
	vec3 c = mix(vec3(0.22, 0.21, 0.19), vec3(0.12, 0.11, 0.1), n);
	c *= 1.0 - 0.5 * smoothstep(0.45, 0.7, fbm(uv * 0.5 + s));
	return c;
}

// 墙角的蜘蛛网：以 corner 为圆心的一把扇子，放射的丝和一圈圈横丝，微微飘动
float web(vec2 p, vec2 corner, float radius, float s) {
	vec2 q = abs(p - corner);
	q += vec2(sin(TIME * 1.3 + s * 20.0), cos(TIME * 1.1 + s * 9.0)) * 0.006 * length(q);
	float r = length(q);
	if (r > radius) {
		return 0.0;
	}
	float a = atan(q.y, q.x);
	float spokes = 7.0;
	float da = abs(fract(a / 1.5708 * spokes + 0.5) - 0.5) * 1.5708 / spokes * r;
	float radial = 1.0 - smoothstep(0.002, 0.006, da);
	float k = r * 16.0 + 0.4 * sin(a * spokes * 2.0 + s);
	float dr = abs(fract(k + 0.5) - 0.5) / 16.0;
	float ring = (1.0 - smoothstep(0.002, 0.005, dr)) * step(0.05, r);
	// 有几处断开，垂下来
	float torn = step(0.3, noise(vec2(a * 6.0, r * 4.0) + s * 11.0));
	return max(radial, ring * torn) * (1.0 - smoothstep(radius * 0.7, radius, r)) * 0.55;
}

// ---------- 家具剪影 ----------

// 椅子的侧影：原点在地面，座面 0.45 米高，靠背在 -x
float chair(vec2 q) {
	float d = box(q, vec2(0.0, 0.45), vec2(0.22, 0.025));
	d = min(d, box(q, vec2(0.2, 0.225), vec2(0.02, 0.225)));
	d = min(d, box(q, vec2(-0.2, 0.47), vec2(0.022, 0.47)));
	d = min(d, box(q, vec2(-0.2, 0.78), vec2(0.03, 0.12)));
	return d;
}

// 一件家具，kind：0 立着的椅子、1 倒下的椅子、2 四脚朝天的桌子、3 靠墙的床垫、4 柜子、5 桌子、6 碎屑堆
float item(int kind, vec2 q, float s) {
	if (kind == 0) {
		return chair(q);
	} else if (kind == 1) {
		return chair(rot(q - vec2(0.0, 0.24), 1.45 + 0.2 * s) + vec2(0.0, 0.45));
	} else if (kind == 2) {
		float d = box(q, vec2(0.0, 0.035), vec2(0.7, 0.035));
		d = min(d, box(q, vec2(-0.62, 0.4), vec2(0.03, 0.36)));
		d = min(d, box(rot(q - vec2(0.62, 0.07), -0.35), vec2(0.0, 0.3), vec2(0.03, 0.3)));
		return d;
	} else if (kind == 3) {
		vec2 k = q;
		k.x -= q.y * 0.12;
		return box(k, vec2(0.0, 0.9), vec2(0.45, 0.9)) - 0.03;
	} else if (kind == 4) {
		return box(q, vec2(0.0, 0.9), vec2(0.5, 0.9));
	} else if (kind == 5) {
		float d = box(q, vec2(0.0, 0.75), vec2(0.7, 0.03));
		d = min(d, box(q, vec2(-0.62, 0.37), vec2(0.03, 0.37)));
		d = min(d, box(q, vec2(0.62, 0.37), vec2(0.03, 0.37)));
		return d;
	}
	float h = 0.3 * max(1.0 - (q.x / 0.9) * (q.x / 0.9), 0.0) + 0.06 * noise(vec2(q.x * 9.0, s * 7.0));
	return max(q.y - h, abs(q.x) - 0.95);
}

vec3 item_col(int kind, vec2 q, float s) {
	if (kind == 3) {
		vec3 c = vec3(0.2, 0.18, 0.15) * (0.8 + 0.3 * noise(q * 6.0 + s));
		c *= 0.75 + 0.25 * step(0.5, fract(q.x * 4.0));   // 床垫的绗缝
		return mix(c, vec3(0.09, 0.05, 0.03), smoothstep(0.5, 0.7, fbm(q * 2.0 + s * 3.0)));
	} else if (kind == 4) {
		// 柜门半开：一边是黑洞洞的柜膛
		float open = step(0.05, q.x) * step(abs(q.y - 0.95), 0.75) * step(q.x, 0.45);
		return mix(vec3(0.13, 0.09, 0.06), vec3(0.01), open);
	} else if (kind == 6) {
		return vec3(0.16, 0.15, 0.13) * (0.6 + 0.6 * noise(q * 14.0));
	}
	return vec3(0.15, 0.1, 0.07) * (0.8 + 0.3 * noise(vec2(q.x * 30.0, q.y * 3.0)));
}

// 屋里的人影：头、肩、身子、腿，模糊的边
float figure(vec2 q) {
	float d = length(q - vec2(0.0, 1.62)) - 0.11;
	d = min(d, box(q, vec2(0.0, 1.15), vec2(0.2, 0.33)) - 0.04);
	d = min(d, box(q, vec2(-0.08, 0.42), vec2(0.06, 0.42)));
	d = min(d, box(q, vec2(0.08, 0.42), vec2(0.06, 0.42)));
	return d;
}

void fragment() {
	float s = fract(sin(dot(floor(seed3 * 4.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float W = mix(1.4, 2.2, rnd(s, 1.0));
	float D = mix(3.0, 4.2, rnd(s, 2.0));
	float y0 = -1.0;
	float y1 = 3.1;
	bool boarded = rnd(s, 3.0) < 0.15;
	bool bars = !boarded && rnd(s, 3.0) < 0.25;
	bool broken = rnd(s, 4.0) < 0.3;
	float lk = rnd(s, 5.0);
	bool has_figure = rnd(s, 6.0) < 0.034;
	bool bulb = lk < 0.1 || has_figure;
	bool red = lk >= 0.1 && lk < 0.13;

	vec3 ro = lp;
	vec3 rd = normalize(lp - cam_l);
	rd.z = min(rd.z, -0.0005);
	vec3 safe = vec3(abs(rd.x) < 1e-4 ? 1e-4 : rd.x, abs(rd.y) < 1e-4 ? 1e-4 : rd.y, rd.z);
	float tx = (sign(safe.x) * W - ro.x) / safe.x;
	float ty = ((safe.y > 0.0 ? y1 : y0) - ro.y) / safe.y;
	float tz = (-D - ro.z) / safe.z;
	float t = min(min(tx, ty), tz);
	vec3 hit = ro + rd * t;

	// 灯：窗外透进来的冷光越往里越暗；灯泡在天花板下，偶尔闪一下
	vec3 bulb_pos = vec3((rnd(s, 7.0) - 0.5) * W, y1 - 0.75, -D * 0.55);
	float flick = 1.0 - 0.8 * step(0.94, hash(vec2(floor(TIME * 9.0), s * 31.0)));
	vec3 bulb_col = red ? vec3(0.8, 0.07, 0.04) : vec3(1.0, 0.68, 0.38);

	vec3 col;
	vec3 nrm;
	if (t == tz) {
		col = wall_col(hit.xy + vec2(s * 20.0, 0.0), s);
		nrm = vec3(0.0, 0.0, 1.0);
		if (detail > 0.5) {
			float w = max(web(hit.xy, vec2(-W, y1), 0.7, s), web(hit.xy, vec2(W, y1), 0.55, s + 1.0) * step(0.5, rnd(s, 8.0)));
			col = mix(col, vec3(0.5, 0.5, 0.48), w);
		}
	} else if (t == tx) {
		col = wall_col(vec2(hit.z * sign(hit.x), hit.y) + vec2(s * 30.0, 0.0), s);
		nrm = vec3(-sign(hit.x), 0.0, 0.0);
		if (detail > 0.5) {
			col = mix(col, vec3(0.5, 0.5, 0.48), web(vec2(hit.z, hit.y), vec2(-D, y1), 0.6, s + 2.0) * step(0.4, rnd(s, 9.0)));
		}
	} else if (rd.y < 0.0) {
		col = floor_col(hit.xz, s);
		nrm = vec3(0.0, 1.0, 0.0);
	} else {
		col = ceil_col(hit.xz, s);
		nrm = vec3(0.0, -1.0, 0.0);
		// 天花板正中吊下来的电线
		vec2 wq = hit.xz - bulb_pos.xz;
		col *= 1.0 - 0.8 * (1.0 - smoothstep(0.015, 0.03, length(wq)));
	}
	// 屋角压暗
	float e = 9.0;
	if (t != tx) { e = min(e, W - abs(hit.x)); }
	if (t != ty) { e = min(e, min(hit.y - y0, y1 - hit.y)); }
	if (t != tz) { e = min(e, hit.z + D); }
	float ao = 0.35 + 0.65 * smoothstep(0.0, 0.7, e);

	vec3 light = vec3(0.012, 0.013, 0.016);
	light += vec3(0.6, 0.65, 0.78) * exp(-max(-hit.z, 0.0) * 0.95) * (0.6 + 0.4 * max(nrm.z, 0.0) + 0.3 * max(nrm.y, 0.0));
	if (bulb || red) {
		vec3 L = bulb_pos - hit;
		float d2 = dot(L, L);
		light += bulb_col * 1.6 * flick * max(dot(nrm, normalize(L)), 0.0) / (1.0 + d2 * 1.2);
	}
	vec3 inside = col * light * ao;

	// 家具：近的挡住远的
	if (detail > 0.5) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float zl = min(1.2 + fi * 0.95, D - 0.25);
			if (rnd(s, 20.0 + fi) < 0.25) {
				continue;
			}
			float tp = (-zl - ro.z) / rd.z;
			if (tp >= t) {
				continue;
			}
			vec3 hp = ro + rd * tp;
			int kind = int(rnd(s, 30.0 + fi) * 7.0);
			float xoff = (rnd(s, 40.0 + fi) - 0.5) * (W * 2.0 - 1.4);
			vec2 q = vec2(hp.x - xoff, hp.y - y0);
			if (rnd(s, 50.0 + fi) < 0.5) {
				q.x = -q.x;
			}
			if (item(kind, q, s + fi) < 0.0) {
				vec3 fl = vec3(0.012) + vec3(0.6, 0.65, 0.78) * exp(-zl * 0.95) * 0.7;
				if (bulb || red) {
					fl += bulb_col * 1.2 * flick / (1.0 + dot(bulb_pos - hp, bulb_pos - hp) * 1.2);
				}
				inside = item_col(kind, q, s) * fl;
				t = tp;
				break;
			}
		}
	}
	// 人影：只在远处看得见，走近了就不在了
	if (has_figure) {
		float tp = (-2.0 - ro.z) / rd.z;
		if (tp < t) {
			vec3 hp = ro + rd * tp;
			float dist = length(cam_l - vec3(0.0, 1.0, 0.0));
			float vis = smoothstep(figure_near, figure_near + 4.0, dist);
			float f = 1.0 - smoothstep(-0.02, 0.03, figure(vec2(hp.x - (rnd(s, 60.0) - 0.5) * W, hp.y - y0)));
			inside = mix(inside, vec3(0.004), f * vis);
		}
	}
	inside *= brightness;

	// ---------- 窗本身 ----------
	vec2 g = ro.xy;
	vec3 alb = vec3(0.0);
	float opaque = 0.0;
	float dirt = fbm(g * 3.0 + s * 17.0) * (0.55 + 0.6 * smoothstep(1.2, 0.0, g.y));
	if (broken) {
		// 碎掉的一角：没有玻璃、没有灰，边上一圈裂纹
		vec2 c = vec2((rnd(s, 10.0) < 0.5 ? -0.75 : 0.75), rnd(s, 11.0) * 1.6);
		float hole = length((g - c) * vec2(1.0, 0.8)) - (0.32 + 0.12 * noise(vec2(atan(g.y - c.y, g.x - c.x) * 3.0, s)));
		dirt *= step(0.0, hole);
		float a = atan(g.y - c.y, g.x - c.x);
		float crack = (1.0 - smoothstep(0.0, 0.012, abs(fract(a * 1.6 + s) - 0.5) * length(g - c)))
			* step(0.0, hole) * step(hole, 0.4);
		alb = mix(alb, vec3(0.02), crack);
		opaque = max(opaque, crack);
	}
	if (detail > 0.5 && rnd(s, 12.0) < 0.4) {
		float w = web(g, vec2(rnd(s, 13.0) < 0.5 ? -0.75 : 0.75, 0.0), 0.45, s + 3.0);
		alb = mix(alb, vec3(0.45, 0.45, 0.43), w);
		opaque = max(opaque, w);
	}
	if (bars) {
		float bx = abs(fract(g.x / 0.2 + 0.5) - 0.5) * 0.2;
		float bar = 1.0 - smoothstep(0.012, 0.016, bx);
		bar = max(bar, 1.0 - smoothstep(0.015, 0.02, abs(g.y - 1.05)));
		alb = mix(alb, vec3(0.08, 0.07, 0.06), bar);
		opaque = max(opaque, bar);
	}
	if (boarded) {
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float a = (rnd(s, 70.0 + fi) - 0.5) * 0.5;
			float yc = 0.25 + fi * 0.62 + (rnd(s, 80.0 + fi) - 0.5) * 0.2;
			vec2 k = rot(g - vec2(0.0, yc), a);
			float plank = 1.0 - smoothstep(0.1, 0.11, abs(k.y));
			if (plank > 0.0) {
				vec3 wood = vec3(0.2, 0.14, 0.09) * (0.7 + 0.4 * noise(vec2(k.x * 2.0, k.y * 40.0) + fi * 7.0));
				alb = mix(alb, wood, plank);
				opaque = max(opaque, plank);
			}
		}
	}
	// 脏玻璃：一层灰，透过去的光被吃掉一些
	float glass = clamp(dirt * 0.75, 0.0, 0.8) * (1.0 - opaque);
	ALBEDO = mix(alb, vec3(0.16, 0.15, 0.14), glass);
	EMISSION = inside * (1.0 - opaque) * (1.0 - glass * 0.85);
	ROUGHNESS = mix(0.95, 0.4, (1.0 - opaque) * (1.0 - glass));
	SPECULAR = mix(0.2, 0.5, (1.0 - opaque) * (1.0 - glass));
}
