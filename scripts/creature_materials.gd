extends RefCounted
## 怪物共用的材质（hauler.gd、watchman.gd）：颜色上叠一层噪声（斑驳、污渍、褪色），法线上叠一层（起皱、粗糙的布纹），
## 三平面映射，不用展 UV。都用抖动透明，淡入淡出不用排序；布料双面画（衣服是单层的）。
## 噪声纹理所有怪物共用：斑块颜色相同的槽共用一张颜色噪声，凹凸只有两张（皮肤一张、其余一张），
## 生成一次就留着，以后加再多怪物也不再多占显存。

const TEX_SIZE := 256

static var _albedo := {}         # 斑块颜色 → 颜色噪声纹理
static var _bump := {}           # "skin" / "cloth" → 凹凸法线纹理


## spec：槽 → [底色, 斑块颜色（乘在底色上）, 纹理密度, 凹凸, 粗糙度, 金属度, 双面]；
## plain 里的槽只要纯色（玻璃、火这类，特殊效果由调用的地方再加）。返回 槽 → 材质
static func make(spec: Dictionary, _rng: RandomNumberGenerator, plain: Array = []) -> Dictionary:
	var out := {}
	for k: String in spec:
		var a: Array = spec[k]
		var m := StandardMaterial3D.new()
		m.albedo_color = a[0]
		m.roughness = a[4]
		m.metallic = a[5]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		if a[6]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if k not in plain:
			m.albedo_texture = _albedo_tex(a[1])
			m.normal_enabled = true
			m.normal_texture = _bump_tex(k == "skin")
			m.normal_scale = a[3]
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * a[2] * 0.25
		if k == "skin":
			# 发湿的皮：边上一圈微亮，雾里也读得出轮廓
			m.rim_enabled = true
			m.rim = 0.35
			m.rim_tint = 0.4
		out[k] = m
	return out


## 斑块颜色 spot 的颜色噪声：噪声从 spot 过渡到白，乘在底色上
static func _albedo_tex(spot: Color) -> NoiseTexture2D:
	var key := spot.to_html(false)
	if not _albedo.has(key):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		noise.seed = key.hash()
		var g := Gradient.new()
		g.set_color(0, spot)
		g.set_color(1, Color(1, 1, 1))
		var tex := NoiseTexture2D.new()
		tex.width = TEX_SIZE
		tex.height = TEX_SIZE
		tex.seamless = true
		tex.noise = noise
		tex.color_ramp = g
		_albedo[key] = tex
	return _albedo[key]


## 凹凸：皮肤是细胞状的（起皱、毛孔），其余是平滑噪声（布纹、锈、皮革）
static func _bump_tex(skin: bool) -> NoiseTexture2D:
	var key := "skin" if skin else "cloth"
	if not _bump.has(key):
		var bump := NoiseTexture2D.new()
		bump.width = TEX_SIZE
		bump.height = TEX_SIZE
		bump.seamless = true
		bump.as_normal_map = true
		bump.bump_strength = 6.0
		var bn := FastNoiseLite.new()
		bn.noise_type = FastNoiseLite.TYPE_CELLULAR if skin else FastNoiseLite.TYPE_SIMPLEX
		bn.frequency = 0.06
		bump.noise = bn
		_bump[key] = bump
	return _bump[key]


## 把模型里每个面按材质槽的名字换成 by_slot 里的材质
static func apply(root: Node, by_slot: Dictionary, fallback: String) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, by_slot.get(src.resource_name if src else fallback, by_slot[fallback]))
