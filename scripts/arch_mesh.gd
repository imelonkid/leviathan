extends RefCounted
## 拱的网格，用 SurfaceTool 拼出来，在 maze.gd 里用 MultiMesh 成批摆放：
## - gate()：拱门。横跨走道的一段墙，下面开一个半圆拱门洞；
## - window()：盲拱窗。贴在墙面上的拱形窗框和窗台，中间是深色窗洞，看起来像一扇扇拱窗。
## 坐标约定：x 横向，y 向上，z 是厚度方向；材质由调用方给每个面设置。

const SEGS := 12                 # 半圆拱分几段


## 拱门：x 横跨走道（-half..half），y 从 0 到 height，z 厚度 -depth/2..depth/2。
## 门洞宽 2r，起拱高度 spring，拱顶高 spring + r。
static func gate(half: float, height: float, depth: float, r: float, spring: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zf := depth / 2.0
	var top := height - spring
	for side: float in [1.0, -1.0]:
		var z := zf * side
		var nrm := Vector3(0, 0, side)
		# 两侧门墩
		_quad(st, Vector3(-half, 0, z), Vector3(-r, 0, z), Vector3(-r, spring, z), Vector3(-half, spring, z), nrm)
		_quad(st, Vector3(r, 0, z), Vector3(half, 0, z), Vector3(half, spring, z), Vector3(r, spring, z), nrm)
		# 拱肩：从拱线到外框按角度切片；外框角点的角度也切一刀，保证每片落在同一条边上
		var angles := _angles(half, top)
		for i in angles.size() - 1:
			var a0: float = angles[i]
			var a1: float = angles[i + 1]
			var p0 := Vector3(r * cos(a0), spring + r * sin(a0), z)
			var p1 := Vector3(r * cos(a1), spring + r * sin(a1), z)
			var q0 := _box_hit(a0, half, top) + Vector3(0, spring, z)
			var q1 := _box_hit(a1, half, top) + Vector3(0, spring, z)
			_quad(st, p0, q0, q1, p1, nrm)
	# 门洞内侧：门墩内壁 + 拱腹
	_quad(st, Vector3(-r, 0, zf), Vector3(-r, 0, -zf), Vector3(-r, spring, -zf), Vector3(-r, spring, zf), Vector3.RIGHT)
	_quad(st, Vector3(r, 0, -zf), Vector3(r, 0, zf), Vector3(r, spring, zf), Vector3(r, spring, -zf), Vector3.LEFT)
	for i in SEGS:
		var a0 := PI * i / SEGS
		var a1 := PI * (i + 1) / SEGS
		var c0 := Vector3(r * cos(a0), spring + r * sin(a0), 0)
		var c1 := Vector3(r * cos(a1), spring + r * sin(a1), 0)
		var inward := -Vector3(cos((a0 + a1) / 2.0), sin((a0 + a1) / 2.0), 0)
		var dz := Vector3(0, 0, zf)
		_quad(st, c0 + dz, c1 + dz, c1 - dz, c0 - dz, inward)
	return st.commit()


## 盲拱窗：x 沿墙面，y 向上（0 是窗台顶面），z 朝墙外（0 是墙面）。
## 窗洞宽 2r，起拱高度 spring；frame 是窗框宽度，relief 是窗框凸出墙面的厚度。
## 返回两个面：0 = 窗框和窗台（石头），1 = 窗洞（深色）。
static func window(r: float, spring: float, frame: float, relief: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ro := r + frame
	var front := Vector3(0, 0, relief)
	# 窗台：比窗框宽一点、凸出多一点
	_box(st, Vector3(-ro - 0.12, -0.22, 0), Vector3(ro + 0.12, 0, relief + 0.1))
	# 两侧窗框
	_box(st, Vector3(-ro, 0, 0), Vector3(-r, spring, relief))
	_box(st, Vector3(r, 0, 0), Vector3(ro, spring, relief))
	# 拱圈：正面 + 外沿 + 内沿
	for i in SEGS:
		var a0 := PI * i / SEGS
		var a1 := PI * (i + 1) / SEGS
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var s := Vector3(0, spring, 0)
		var i0 := s + d0 * r
		var i1 := s + d1 * r
		var o0 := s + d0 * ro
		var o1 := s + d1 * ro
		var mid := (d0 + d1).normalized()
		_quad(st, i0 + front, o0 + front, o1 + front, i1 + front, Vector3.BACK)
		_quad(st, o0, o1, o1 + front, o0 + front, mid)
		_quad(st, i0 + front, i1 + front, i1, i0, -mid)
	var mesh := st.commit()

	# 窗洞：贴在墙面上的深色拱形面片
	var hole := SurfaceTool.new()
	hole.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := Vector3(0, 0, 0.01)
	_quad(hole, Vector3(-r, 0, 0) + z, Vector3(r, 0, 0) + z, Vector3(r, spring, 0) + z, Vector3(-r, spring, 0) + z, Vector3.BACK)
	for i in SEGS:
		var a0 := PI * i / SEGS
		var a1 := PI * (i + 1) / SEGS
		var c := Vector3(0, spring, 0) + z
		_tri(hole, c, c + Vector3(cos(a0), sin(a0), 0) * r, c + Vector3(cos(a1), sin(a1), 0) * r, Vector3.BACK)
	return hole.commit(mesh)


## 半圆上的切分角度，加上外框两个上角的角度，从 0 到 PI 排好序
static func _angles(half: float, top: float) -> Array[float]:
	var out: Array[float] = []
	for i in SEGS + 1:
		out.append(PI * i / SEGS)
	var corner := atan2(top, half)
	out.append(corner)
	out.append(PI - corner)
	out.sort()
	return out


## 从起拱点沿角度 a 发出的射线打到外框（x ∈ ±half，y ∈ 0..top）上的点
static func _box_hit(a: float, half: float, top: float) -> Vector3:
	var c := cos(a)
	var s := sin(a)
	var t := INF
	if absf(c) > 0.0001:
		t = half / absf(c)
	if s > 0.0001:
		t = minf(t, top / s)
	return Vector3(c * t, s * t, 0)


## 长方体（不含贴墙的背面）
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var p := func(x: float, y: float, z: float) -> Vector3:
		return Vector3(lerpf(lo.x, hi.x, x), lerpf(lo.y, hi.y, y), lerpf(lo.z, hi.z, z))
	_quad(st, p.call(0, 0, 1), p.call(1, 0, 1), p.call(1, 1, 1), p.call(0, 1, 1), Vector3.BACK)
	_quad(st, p.call(0, 1, 0), p.call(1, 1, 0), p.call(1, 1, 1), p.call(0, 1, 1), Vector3.UP)
	_quad(st, p.call(0, 0, 0), p.call(1, 0, 0), p.call(1, 0, 1), p.call(0, 0, 1), Vector3.DOWN)
	_quad(st, p.call(0, 0, 0), p.call(0, 0, 1), p.call(0, 1, 1), p.call(0, 1, 0), Vector3.LEFT)
	_quad(st, p.call(1, 0, 0), p.call(1, 0, 1), p.call(1, 1, 1), p.call(1, 1, 0), Vector3.RIGHT)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	_tri(st, a, b, c, nrm)
	_tri(st, a, c, d, nrm)


## Godot 以顺时针为正面：从法线方向看过去顶点要是顺时针，不对就交换
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v: Vector3 in [a, b, c]:
		st.set_normal(nrm)
		st.add_vertex(v)
