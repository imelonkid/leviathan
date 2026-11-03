# 房间道具，按参数生成，导出成 assets/models/room_props.glb。
# 第一批：铁床、摇椅、婴儿床、轮椅、瓷娃娃、人台；第二批（医疗类）：手术台、推床、输液架、推车、洗手池、浴缸、铁皮柜、柜子；
# 第三批（家具）：椅子、凳子、桌子（加一套餐具）、长餐桌、课桌、长椅、架子（三套瓶罐）、木箱、落地钟、挂钟、表盘。
# 每个物体一件（或一件的一个活动部分），按名字取；材质槽名字对应 scripts/rooms/props.gd 里的材质：
#   frame（铁或锈，游戏里按不安程度挑；铁皮柜是漆过的铁）、wood、cloth、porcelain、black、skin、steel、brass、glass
#   （wood、glass、black 等槽在游戏里也可能被换掉：柜子有深浅两种木头，输液袋、浴缸和洗手池里的水不安时是血）
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/room_props.py -- assets/models/room_props.glb [预览图目录]
#
# 坐标约定：脚本里直接按 Godot 写（y 向上，+z 是道具的正面），落到 Blender 时换成 (x, -z, y)，导出时 glTF 再换回来。
# 尺寸、原点和 props.gd 里原来用方块拼的版本一致：活动部分（娃娃的头、人台的身子、摇椅）的原点就是它转动的轴心。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SLOTS = ["frame", "wood", "cloth", "porcelain", "black", "skin", "steel", "brass", "glass", "dark_wood", "face", "wax",
         "flame", "jar_dark"]
COLORS = {
    "frame": ((0.2, 0.19, 0.18), 0.6, 0.7),
    "wood": ((0.24, 0.16, 0.1), 0.75, 0.0),
    "cloth": ((0.52, 0.49, 0.42), 0.95, 0.0),
    "porcelain": ((0.62, 0.62, 0.58), 0.3, 0.0),
    "black": ((0.03, 0.03, 0.03), 0.4, 0.3),
    "skin": ((0.62, 0.55, 0.5), 0.6, 0.0),
    "steel": ((0.5, 0.5, 0.5), 0.3, 0.9),
    "brass": ((0.55, 0.42, 0.22), 0.35, 0.9),
    "glass": ((0.25, 0.27, 0.28), 0.08, 0.95),
    "dark_wood": ((0.12, 0.08, 0.05), 0.7, 0.0),
    "face": ((0.7, 0.66, 0.55), 0.6, 0.0),
    "wax": ((0.62, 0.56, 0.45), 0.7, 0.0),
    "flame": ((1.0, 0.62, 0.28), 0.5, 0.0),
    "jar_dark": ((0.2, 0.08, 0.06), 0.1, 0.5),
}


def V(x, y, z):
    return Vector((x, y, z))


class Part:
    """按 Godot 坐标攒顶点和面，最后一次性落成 Blender 网格"""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []      # (顶点下标, 材质槽, 平滑)

    def v(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def f(self, idx, slot, smooth=False):
        self.faces.append((idx, SLOTS.index(slot), smooth))

    # ---------- 基本形 ----------

    def box(self, c, size, slot, rot=None):
        rot = rot or Matrix.Identity(3)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        ids = [self.v(Vector(c) + rot @ V(sx * hx, sy * hy, sz * hz))
               for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.f([ids[i] for i in q], slot)

    def sweep(self, pts, slot, profile, close_path=False, caps=True, smooth=True, up=None):
        """沿折线扫出一根管子 / 板条。profile 是截面上的二维点（法向 n、副法向 b 方向），按逆时针给"""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        rings = []
        prev_n = None
        for i, p in enumerate(pts):
            if close_path:
                t = (pts[(i + 1) % n] - pts[i - 1]).normalized()
            elif i == 0:
                t = (pts[1] - pts[0]).normalized()
            elif i == n - 1:
                t = (pts[-1] - pts[-2]).normalized()
            else:
                t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
            ref = up or (prev_n if prev_n is not None else (V(0, 1, 0) if abs(t.y) < 0.9 else V(1, 0, 0)))
            nn = (ref - t * ref.dot(t)).normalized()
            if nn.length < 1e-6:
                nn = V(1, 0, 0)
            b = t.cross(nn)
            prev_n = nn
            # 折角处把截面撑大一点，管子粗细看上去不变
            scale = 1.0
            if 0 < i < n - 1 and not close_path:
                d = (pts[i + 1] - pts[i]).normalized().dot((pts[i] - pts[i - 1]).normalized())
                scale = 1.0 / max(math.sqrt((1 + d) / 2), 0.5)
            rings.append([self.v(p + (nn * u + b * w) * scale) for u, w in profile])
        k = len(profile)
        segs = n if close_path else n - 1
        for i in range(segs):
            a, c = rings[i], rings[(i + 1) % n]
            for j in range(k):
                self.f([a[j], a[(j + 1) % k], c[(j + 1) % k], c[j]], slot, smooth)
        if caps and not close_path:
            self.f(list(reversed(rings[0])), slot)
            self.f(rings[-1], slot)

    def tube(self, pts, r, slot, seg=8, **kw):
        prof = [(r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]
        self.sweep(pts, slot, prof, **kw)

    def bar(self, pts, w, h, slot, **kw):
        """截面 w（副法向）× h（法向）的扁板条"""
        prof = [(-h / 2, -w / 2), (h / 2, -w / 2), (h / 2, w / 2), (-h / 2, w / 2)]
        kw.setdefault("smooth", False)
        self.sweep(pts, slot, prof, **kw)

    def lathe(self, profile, slot, seg=16, xf=None, smooth=True, closed=False):
        """绕本地 y 轴旋转出来的回转体。profile：[(半径, 高)]；半径 0 的点收成一个极点。closed：截面首尾相接（圆环）"""
        xf = xf or Matrix.Identity(4)
        rings = []
        for r, y in profile:
            if r < 1e-5 and not closed:
                rings.append([self.v(xf @ V(0, y, 0))])
            else:
                rings.append([self.v(xf @ V(r * math.sin(2 * math.pi * i / seg), y, r * math.cos(2 * math.pi * i / seg)))
                              for i in range(seg)])
        m = len(rings)
        for i in range(m if closed else m - 1):
            a, b = rings[i], rings[(i + 1) % m]
            if len(a) == 1 and len(b) == 1:
                continue
            for j in range(seg):
                if len(a) == 1:
                    self.f([a[0], b[(j + 1) % seg], b[j]], slot, smooth)
                elif len(b) == 1:
                    self.f([a[j], a[(j + 1) % seg], b[0]], slot, smooth)
                else:
                    self.f([a[j], a[(j + 1) % seg], b[(j + 1) % seg], b[j]], slot, smooth)
        if not closed:
            if len(rings[0]) > 1:
                self.f(list(reversed(rings[0])), slot)
            if len(rings[-1]) > 1:
                self.f(rings[-1], slot)

    def ball(self, c, r, slot, seg=12, scale=(1, 1, 1)):
        prof = [(r * math.sin(math.pi * i / 6), -r * math.cos(math.pi * i / 6)) for i in range(7)]
        xf = Matrix.Translation(Vector(c)) @ Matrix.Diagonal((*scale, 1.0))
        self.lathe(prof, slot, seg, xf)

    def torus(self, c, axis_rot, R, r, slot, seg=24, rseg=6):
        prof = [(R + r * math.cos(2 * math.pi * i / rseg), r * math.sin(2 * math.pi * i / rseg)) for i in range(rseg)]
        xf = Matrix.Translation(Vector(c)) @ axis_rot
        self.lathe(prof, slot, seg, xf, closed=True)

    def slab(self, c, w, d, t, slot, fn=None, nx=8, nz=8, rot=None):
        """一块软垫 / 布：底平，顶面按 fn(u, v)（u、v 在 -1～1）起伏，四边往下收圆"""
        rot = rot or Matrix.Identity(3)
        c = Vector(c)
        top, bot = [], []
        for j in range(nz + 1):
            for i in range(nx + 1):
                u, v = -1 + 2 * i / nx, -1 + 2 * j / nz
                edge = max(abs(u), abs(v))
                round_off = t * 0.35 * max(0.0, (edge - 0.75) / 0.25) ** 2
                h = t / 2 - round_off + (fn(u, v) if fn else 0.0)
                top.append(self.v(c + rot @ V(u * w / 2, h, v * d / 2)))
                bot.append(self.v(c + rot @ V(u * w / 2, -t / 2 + (fn(u, v) * 0.6 if fn else 0.0), v * d / 2)))
        idx = lambda i, j: j * (nx + 1) + i
        for j in range(nz):
            for i in range(nx):
                q = [idx(i, j), idx(i, j + 1), idx(i + 1, j + 1), idx(i + 1, j)]
                self.f([top[k] for k in q], slot, True)
                self.f([bot[k] for k in reversed(q)], slot, True)
        ring = [idx(i, 0) for i in range(nx)] + [idx(nx, j) for j in range(nz)] + \
               [idx(i, nz) for i in range(nx, 0, -1)] + [idx(0, j) for j in range(nz, 0, -1)]
        for a, b in zip(ring, ring[1:] + ring[:1]):
            self.f([top[a], top[b], bot[b], bot[a]], slot, True)

    def loft(self, rings, slot, cap_bottom=True, cap_top=True, corner=6, smooth=True, xf=None):
        """一圈圈圆角矩形连起来：rings = [(高, 半宽 a, 半深 b, 圆角半径 r)]，从下往上（或从外壁绕到内壁）"""
        xf = xf or Matrix.Identity(4)
        ids = []
        for y, a, b, r in rings:
            ring = []
            for cx, cz, a0 in ((a - r, b - r, 0.0), (-(a - r), b - r, 0.5), (-(a - r), -(b - r), 1.0), (a - r, -(b - r), 1.5)):
                for k in range(corner + 1):
                    t = math.pi * (a0 + 0.5 * k / corner)
                    ring.append(self.v(xf @ V(cx + r * math.cos(t), y, cz + r * math.sin(t))))
            ids.append(ring)
        k = len(ids[0])
        for a, b in zip(ids, ids[1:]):
            for j in range(k):
                self.f([a[j], a[(j + 1) % k], b[(j + 1) % k], b[j]], slot, smooth)
        if cap_bottom:
            self.f(list(reversed(ids[0])), slot)
        if cap_top:
            self.f(ids[-1], slot)

    def sheet(self, xs, zs, fn, t, slot):
        """一张有厚度的布：顶面高度 fn(x, z)，底面往下 t；xs、zs 是网格坐标"""
        top = [[self.v(V(x, fn(x, z), z)) for x in xs] for z in zs]
        bot = [[self.v(V(x, fn(x, z) - t, z)) for x in xs] for z in zs]
        for j in range(len(zs) - 1):
            for i in range(len(xs) - 1):
                q = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
                self.f([top[b][a] for a, b in q], slot, True)
                self.f([bot[b][a] for a, b in reversed(q)], slot, True)
        nx, nz = len(xs) - 1, len(zs) - 1
        edge = [(i, 0) for i in range(nx)] + [(nx, j) for j in range(nz)] + \
               [(i, nz) for i in range(nx, 0, -1)] + [(0, j) for j in range(nz, 0, -1)]
        for (a0, b0), (a1, b1) in zip(edge, edge[1:] + edge[:1]):
            self.f([top[b0][a0], top[b1][a1], bot[b1][a1], bot[b0][a0]], slot, True)

    # ---------- 落成物体 ----------

    def build(self):
        bm = bmesh.new()
        bv = [bm.verts.new((p.x, -p.z, p.y)) for p in self.verts]
        for idx, mi, smooth in self.faces:
            try:
                face = bm.faces.new([bv[i] for i in idx])
            except ValueError:
                continue
            face.material_index = mi
            face.smooth = smooth
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for s in SLOTS:
            mesh.materials.append(bpy.data.materials[s])
        o = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(o)
        return o


def rx(a):
    return Matrix.Rotation(a, 3, "X")


def arc(p0, p1, rise, n=8):
    """p0 到 p1 之间往上拱起 rise 的弧线"""
    p0, p1 = Vector(p0), Vector(p1)
    return [p0.lerp(p1, i / n) + V(0, rise * math.sin(math.pi * i / n), 0) for i in range(n + 1)]


# ---------- 铁床：床头（-z）顶着墙，床头床尾是弯管栏杆；床垫单独一件（有的床没有床垫） ----------

def bed():
    p = Part("bed_frame")
    hw, hl = 0.45, 1.0
    for z, top, rails, bars in ((-hl, 1.12, (0.62, 1.0), 7), (hl, 0.82, (0.45, 0.72), 5)):
        for sx in (-hw, hw):
            p.tube([V(sx, 0.04, z), V(sx, top, z)], 0.022, "frame")
            p.ball(V(sx, top + 0.02, z), 0.032, "frame", 10)
            p.ball(V(sx, 0.03, z), 0.035, "black", 8)            # 脚轮
        lo, hi = rails
        p.tube(arc(V(-hw, hi, z), V(hw, hi, z), 0.08), 0.014, "frame")
        p.tube([V(-hw, lo, z), V(hw, lo, z)], 0.014, "frame")
        for i in range(bars):
            x = -hw + 2 * hw * (i + 1) / (bars + 1)
            yt = hi + 0.08 * math.sin(math.pi * (x + hw) / (2 * hw))
            p.tube([V(x, lo, z), V(x, yt, z)], 0.009, "frame", 6)
    for sx in (-hw + 0.02, hw - 0.02):                            # 角铁边框
        p.box(V(sx, 0.43, 0), (0.035, 0.035, 2 * hl), "frame")
    for k in range(9):                                            # 床绷：横着的钢丝，中间往下坠一点
        z = -hl + 0.1 + k * (2 * hl - 0.2) / 8
        sag = 0.025 * math.sin(math.pi * (k + 0.5) / 9)
        p.tube([V(-hw + 0.03, 0.44, z), V(0, 0.44 - sag, z), V(hw - 0.03, 0.44, z)], 0.005, "frame", 4)
    p.tube([V(0, 0.43, -hl), V(0, 0.42, 0), V(0, 0.43, hl)], 0.005, "frame", 4)
    p.build()

    m = Part("bed_mattress")
    # 中间睡塌了一点，有几处鼓包
    m.slab(V(0, 0.56, 0), 0.84, 1.9, 0.16, "cloth",
           lambda u, v: -0.012 * (1 - u * u) * (1 - v * v) + 0.006 * math.sin(u * 5 + v * 7) * math.sin(v * 3),
           nx=10, nz=16)
    m.slab(V(0, 0.665, -0.72), 0.55, 0.32, 0.07, "cloth", lambda u, v: 0.01 * (1 - u * u) * (1 - v * v), 6, 4)   # 枕头
    m.build()


# ---------- 摇椅：原点在两条摇杆的弧心正下方，整件绕原点前后摇 ----------

def rocking_chair():
    p = Part("rocking_chair")
    for sx in (-0.25, 0.25):
        rocker = [V(sx, 0.9 - math.cos(a) * 0.88, math.sin(a) * 0.9)
                  for a in [-0.6 + i * 0.1 for i in range(13)]]
        p.bar(rocker, 0.03, 0.05, "wood", up=V(0, 1, 0))
        # 前腿：车削的圆腿
        p.lathe([(0.016, 0.0), (0.02, 0.05), (0.026, 0.12), (0.018, 0.2), (0.022, 0.3), (0.017, 0.4), (0.0, 0.41)],
                "wood", 10, Matrix.Translation(V(sx, 0.04, 0.2)))
        # 后腿一直伸上去当靠背的立柱，往后仰
        p.tube([V(sx, 0.04, -0.2), V(sx, 0.45, -0.24), V(sx * 0.96, 1.08, -0.42)], 0.018, "wood", 10)
        p.ball(V(sx * 0.96, 1.1, -0.425), 0.026, "wood", 10)
        # 扶手：一条弯的板，前头搭在一根小立柱上
        p.bar([V(sx * 1.06, 0.66, -0.29), V(sx * 1.1, 0.68, -0.05), V(sx * 1.08, 0.665, 0.22), V(sx * 1.05, 0.65, 0.27)],
              0.05, 0.022, "wood", up=V(0, 1, 0))
        p.lathe([(0.012, 0.0), (0.016, 0.06), (0.011, 0.12), (0.014, 0.19), (0.0, 0.2)], "wood", 8,
                Matrix.Translation(V(sx * 1.03, 0.46, 0.21)))
        p.tube([V(sx, 0.2, -0.21), V(sx, 0.2, 0.2)], 0.011, "wood", 6)      # 腿间横档
    p.tube([V(-0.25, 0.2, 0.0), V(0.25, 0.2, 0.0)], 0.011, "wood", 6)
    # 座面：微微下凹
    p.slab(V(0, 0.45, -0.01), 0.52, 0.48, 0.035, "wood", lambda u, v: -0.008 * (1 - u * u) * (1 - v * v), 6, 6)
    # 靠背：上、中两道弯梁，中间一排竖档
    for y, z in ((1.0, -0.4), (0.66, -0.31)):
        p.bar([V(-0.24, y, z), V(0, y + 0.02, z - 0.04), V(0.24, y, z)], 0.035, 0.06, "wood", up=V(0, 1, 0))
    for i in range(5):
        x = -0.16 + i * 0.08
        p.tube([V(x, 0.47, -0.23), V(x, 0.66, -0.32), V(x * 1.02, 0.99, -0.42)], 0.009, "wood", 6)
    p.build()


# ---------- 婴儿床：车削的四根角柱，两长两短的栏杆，薄床垫，皱成一团的小毯子 ----------

def crib():
    p = Part("crib")
    hx, hz = 0.62, 0.34
    post = [(0.022, 0.0), (0.026, 0.04), (0.02, 0.1), (0.024, 0.3), (0.019, 0.62), (0.024, 0.9),
            (0.02, 0.96), (0.018, 1.0), (0.032, 1.03), (0.03, 1.06), (0.0, 1.08)]
    for sx in (-hx, hx):
        for sz in (-hz, hz):
            p.lathe(post, "wood", 10, Matrix.Translation(V(sx, 0, sz)))
    for y, h in ((0.33, 0.05), (0.95, 0.04)):
        for sz in (-hz, hz):
            p.box(V(0, y, sz), (2 * hx - 0.03, h, 0.035), "wood")
        for sx in (-hx, hx):
            p.box(V(sx, y, 0), (0.035, h, 2 * hz - 0.03), "wood")
    for sz in (-hz, hz):
        for i in range(12):
            if sz > 0 and i == 4:
                p.tube([V(-hx + 0.1 + i * 0.094, 0.35, sz), V(-hx + 0.1 + i * 0.094 + 0.01, 0.58, sz + 0.02)], 0.009, "wood", 6)
                continue                                                  # 断了一根，只剩半截
            x = -hx + 0.1 + i * 0.094
            p.tube([V(x, 0.35, sz), V(x, 0.93, sz)], 0.009, "wood", 6)
    for sx in (-hx, hx):
        for i in range(5):
            z = -hz + 0.12 + i * 0.11
            p.tube([V(sx, 0.35, z), V(sx, 0.93, z)], 0.009, "wood", 6)
    p.box(V(0, 0.33, 0), (2 * hx - 0.05, 0.02, 2 * hz - 0.05), "wood")        # 床板
    p.slab(V(0, 0.38, 0), 1.18, 0.62, 0.07, "cloth", lambda u, v: -0.005 * (1 - u * u), 8, 6)
    # 小毯子：一角掀起来，皱成几道
    p.slab(V(0.2, 0.43, 0.02), 0.6, 0.5, 0.025, "cloth",
           lambda u, v: 0.025 * math.sin(u * 7.0 + v * 2.0) * (0.5 + 0.5 * u) + 0.04 * max(0.0, u - 0.3) * max(0.0, -v),
           10, 8, rx(0.05))
    p.build()


# ---------- 轮椅：两个大辐条轮、两个前脚轮，弯管车架，帆布座和靠背往下坠 ----------

def wheelchair():
    p = Part("wheelchair")
    ax = Matrix.Rotation(math.pi / 2, 4, "Z")      # 圆环绕 x 轴
    for s in (-1, 1):
        x = 0.3 * s
        c = V(x, 0.3, -0.1)
        p.torus(c, ax, 0.285, 0.016, "black", 28, 6)                  # 轮胎
        p.torus(c, ax, 0.265, 0.008, "frame", 28, 4)                  # 轮圈
        p.torus(c + V(0.03 * s, 0, 0), ax, 0.25, 0.006, "frame", 24, 4)   # 手推圈
        p.lathe([(0.0, -0.03), (0.03, -0.03), (0.03, 0.03), (0.0, 0.03)], "frame", 10,
                Matrix.Translation(c) @ ax)                           # 轮毂
        for k in range(16):
            a = 2 * math.pi * k / 16
            off = 0.02 if k % 2 else -0.02
            p.tube([c + V(off, 0, 0), c + V(0, math.cos(a) * 0.26, math.sin(a) * 0.26)], 0.0025, "frame", 3, caps=False)
        for k in range(3):                                            # 手推圈的连接片
            a = 2 * math.pi * k / 3 + 0.4
            q = c + V(0, math.cos(a) * 0.25, math.sin(a) * 0.25)
            p.tube([q, q + V(0.03 * s, 0, 0)], 0.005, "frame", 4)
        # 前脚轮：叉子 + 小轮
        fx = 0.22 * s
        p.torus(V(fx, 0.07, 0.36), ax, 0.06, 0.014, "black", 14, 5)
        p.tube([V(fx, 0.07, 0.36), V(fx, 0.16, 0.33), V(fx, 0.25, 0.33)], 0.009, "frame", 6)
        # 侧车架：从前脚轮往上、沿座面往后、立成靠背杆、弯出推把
        sx = 0.235 * s
        p.tube([V(sx, 0.25, 0.33), V(sx, 0.5, 0.33), V(sx, 0.5, -0.2), V(sx, 0.96, -0.27), V(sx, 0.98, -0.38)],
               0.012, "frame", 8)
        p.tube([V(sx, 0.98, -0.32), V(sx, 0.98, -0.42)], 0.017, "black", 8)            # 推把手套
        p.tube([V(sx, 0.25, 0.33), V(sx, 0.25, -0.1), V(sx, 0.5, -0.2)], 0.011, "frame", 8)
        p.tube([V(x - 0.02 * s, 0.3, -0.1), V(sx, 0.3, -0.1)], 0.012, "frame", 6)     # 车轴
        # 扶手
        p.tube([V(sx, 0.5, -0.18), V(sx * 1.05, 0.7, -0.15), V(sx * 1.05, 0.7, 0.18), V(sx, 0.5, 0.22)], 0.01, "frame", 6)
        p.box(V(sx * 1.05, 0.715, 0.01), (0.05, 0.03, 0.3), "black")
        # 脚踏
        p.tube([V(sx, 0.5, 0.33), V(sx * 0.8, 0.14, 0.44)], 0.01, "frame", 6)
        p.box(V(sx * 0.55, 0.13, 0.46), (0.15, 0.012, 0.12), "frame", rx(0.15))
    # 座下的交叉撑
    p.tube([V(-0.23, 0.25, 0.02), V(0.23, 0.49, 0.02)], 0.01, "frame", 6)
    p.tube([V(0.23, 0.25, 0.02), V(-0.23, 0.49, 0.02)], 0.01, "frame", 6)
    # 帆布座和靠背：中间往下 / 往后坠
    p.slab(V(0, 0.505, 0.06), 0.47, 0.52, 0.012, "cloth", lambda u, v: -0.03 * (1 - u * u), 8, 6)
    p.slab(V(0, 0.74, -0.235), 0.47, 0.42, 0.012, "cloth", lambda u, v: -0.025 * (1 - u * u), 8, 6,
           rx(-math.pi / 2 + 0.15))
    p.build()


# ---------- 瓷娃娃：坐在地上，蓬裙、细胳膊细腿；头单独一件，原点在头中心（会转过来看你） ----------

def doll():
    p = Part("doll_body")
    # 蓬裙（坐着摊开在地上）+ 上身
    p.lathe([(0.0, 0.012), (0.13, 0.012), (0.125, 0.04), (0.09, 0.09), (0.05, 0.15), (0.042, 0.19), (0.03, 0.205),
             (0.0, 0.205)], "cloth", 16, Matrix.Diagonal((1.0, 1.0, 0.85, 1.0)))
    p.lathe([(0.0, 0.0), (0.05, 0.0), (0.035, 0.015), (0.0, 0.02)], "cloth", 12, Matrix.Translation(V(0, 0.2, 0)))   # 领子
    p.tube([V(0, 0.2, 0), V(0, 0.235, 0)], 0.016, "porcelain", 8)                                                 # 脖子
    for s in (-1, 1):
        # 腿从裙下伸到前面，脚尖朝上
        p.tube([V(0.035 * s, 0.035, 0.08), V(0.045 * s, 0.03, 0.17)], 0.018, "porcelain", 8)
        p.ball(V(0.047 * s, 0.035, 0.185), 0.024, "black", 8, (0.9, 0.9, 1.3))
        # 胳膊垂在身边，手搭在裙子上
        p.tube([V(0.045 * s, 0.185, 0.0), V(0.07 * s, 0.13, 0.02), V(0.075 * s, 0.085, 0.05)], 0.012, "porcelain", 6)
        p.ball(V(0.076 * s, 0.075, 0.055), 0.016, "porcelain", 8)
    p.build()

    h = Part("doll_head")
    h.ball(V(0, 0, 0), 0.068, "porcelain", 16, (0.95, 1.0, 0.92))
    # 头发：后脑勺和头顶罩一层，前面露出额头
    h.ball(V(0, 0.012, -0.014), 0.071, "black", 14, (1.0, 1.0, 0.95))
    for s in (-1, 1):
        h.ball(V(0.023 * s, 0.006, 0.06), 0.009, "black", 8, (1.0, 0.9, 0.5))      # 黑洞洞的眼睛
    h.ball(V(0, -0.03, 0.058), 0.006, "black", 6, (1.6, 0.7, 0.5))                # 小嘴
    h.build()


# ---------- 人台：黑色圆底座、钢杆；身子单独一件（会转），没有脸 ----------

def mannequin():
    p = Part("mannequin_stand")
    p.lathe([(0.0, 0.0), (0.18, 0.0), (0.18, 0.02), (0.12, 0.035), (0.03, 0.05), (0.0, 0.05)], "black", 20)
    p.tube([V(0, 0.04, 0), V(0, 0.82, 0)], 0.014, "steel", 8)
    p.build()

    b = Part("mannequin_body")
    torso = [(0.0, 0.76), (0.1, 0.78), (0.16, 0.86), (0.165, 0.94), (0.125, 1.03), (0.13, 1.1), (0.17, 1.2),
             (0.168, 1.3), (0.155, 1.38), (0.11, 1.44), (0.055, 1.47), (0.045, 1.5), (0.045, 1.56), (0.0, 1.565)]
    b.lathe(torso, "skin", 24, Matrix.Diagonal((1.0, 1.0, 0.64, 1.0)))
    # 头：光秃秃的蛋形，没有五官
    b.lathe([(0.0, 1.55), (0.06, 1.565), (0.092, 1.62), (0.1, 1.68), (0.09, 1.75), (0.06, 1.8), (0.0, 1.82)],
            "skin", 20, Matrix.Translation(V(0, 0, 0.01)) @ Matrix.Diagonal((0.88, 1.0, 1.0, 1.0)))
    b.lathe([(0.0, 0.0), (0.03, 0.0), (0.03, 0.03), (0.0, 0.03)], "steel", 8, Matrix.Translation(V(0, 0.74, 0)))   # 杆头
    b.build()


# ======================= 第二批：医疗类 =======================

def caster(p, c, slot="black"):
    """一只小脚轮：叉子 + 轮子（轮子绕 x 轴）"""
    p.torus(c, Matrix.Rotation(math.pi / 2, 4, "Z"), 0.03, 0.012, slot, 10, 4)
    p.tube([c, c + V(0, 0.06, -0.02)], 0.007, "frame", 4)


# ---------- 手术台：车削的立柱底座、三段台面（铁框 + 黑皮垫）、头枕；台面顶在 0.84 ----------

def optable():
    p = Part("optable")
    p.loft([(0.0, 0.32, 0.42, 0.08), (0.06, 0.32, 0.42, 0.08), (0.08, 0.28, 0.38, 0.06)], "steel")       # 底盘
    p.lathe([(0.11, 0.08), (0.11, 0.14), (0.075, 0.2), (0.07, 0.62), (0.09, 0.66), (0.09, 0.72), (0.0, 0.72)],
            "steel", 16)                                                                              # 液压立柱
    for z0, z1 in ((-1.0, -0.36), (-0.33, 0.33), (0.36, 1.0)):
        zc, half = (z0 + z1) / 2, (z1 - z0) / 2
        p.loft([(0.74, 0.37, half, 0.03), (0.78, 0.375, half, 0.03)], "steel", corner=3,
               xf=Matrix.Translation(V(0, 0, zc)))                                                      # 铁框
        p.loft([(0.78, 0.35, half - 0.02, 0.05), (0.825, 0.35, half - 0.02, 0.05), (0.84, 0.335, half - 0.035, 0.04)],
               "black", corner=4, xf=Matrix.Translation(V(0, 0, zc)))                                    # 皮垫
    for sx in (-0.39, 0.39):                                                                          # 两侧导轨
        p.box(V(sx, 0.76, 0), (0.015, 0.03, 1.9), "steel")
    p.box(V(0, 0.73, 0), (0.5, 0.03, 1.6), "steel")
    p.loft([(0.84, 0.2, 0.15, 0.08), (0.9, 0.19, 0.14, 0.07), (0.92, 0.16, 0.11, 0.05)], "cloth",
           xf=Matrix.Translation(V(0, 0, -0.85)))                                                     # 头枕
    for sx in (-0.38, 0.38):                                                                          # 台边的绑带扣
        for z in (-0.4, 0.2, 0.7):
            p.box(V(sx, 0.8, z), (0.03, 0.05, 0.05), "steel")
    p.build()


# ---------- 停尸推床：铁框四脚带脚轮、浅边的不锈钢台面、两头推把；白布单独一件，盖着一个人形的起伏 ----------

def gurney():
    p = Part("gurney")
    for sx in (-0.32, 0.32):
        for sz in (-0.9, 0.9):
            p.tube([V(sx, 0.09, sz), V(sx, 0.76, sz)], 0.016, "frame", 8)
            caster(p, V(sx, 0.03, sz + 0.02))
        p.tube([V(sx, 0.25, -0.9), V(sx, 0.25, 0.9)], 0.012, "frame", 6)                                # 下层横杆
    for sz in (-0.9, 0.9):
        p.tube([V(-0.32, 0.25, sz), V(0.32, 0.25, sz)], 0.012, "frame", 6)
        p.tube([V(-0.3, 0.78, sz * 1.04), V(-0.3, 0.9, sz * 1.1), V(0.3, 0.9, sz * 1.1), V(0.3, 0.78, sz * 1.04)],
               0.013, "frame", 8)                                                                     # 推把
    p.loft([(0.76, 0.35, 1.0, 0.04), (0.78, 0.35, 1.0, 0.04)], "steel", corner=3)
    p.loft([(0.78, 0.35, 1.0, 0.04), (0.81, 0.35, 1.0, 0.04), (0.81, 0.335, 0.985, 0.03), (0.785, 0.335, 0.985, 0.03)],
           "steel", cap_bottom=False, cap_top=True, corner=3)                                         # 一圈浅边
    p.build()

    def body(x, z):
        """布下面的人形：头、肩、胸腹、两条腿、脚尖朝上——都是圆滑的起伏，看不出细节"""
        h = 0.0
        h = max(h, 0.15 * math.exp(-((x / 0.11) ** 2 + ((z + 0.8) / 0.12) ** 2)))                      # 头
        h = max(h, 0.19 * math.exp(-((x / 0.2) ** 4 + ((z + 0.25) / 0.38) ** 4)))                      # 躯干
        for s in (-1, 1):
            h = max(h, 0.12 * math.exp(-(((x - 0.1 * s) / 0.075) ** 2 + ((z - 0.5) / 0.4) ** 6)))      # 腿
            h = max(h, 0.17 * math.exp(-(((x - 0.1 * s) / 0.06) ** 2 + ((z - 0.88) / 0.05) ** 2)))     # 脚尖
        return h

    def drape(x, z):
        top = 0.815
        ex = max(0.0, abs(x) - 0.36)
        ez = max(0.0, abs(z) - 1.01)
        if ex > 0 or ez > 0:
            # 从台边垂下去，下摆有几道褶
            e = max(ex, ez)
            return top - min(0.45, e * 3.2) - 0.012 * math.sin(z * 23.0 + x * 17.0) * min(1.0, e * 10)
        # 布绷在身体上，到台面上慢慢过渡
        return top + body(x, z) * 0.95 + 0.004 * math.sin(x * 31.0) * math.sin(z * 13.0)

    sh = Part("gurney_sheet")
    xs = [-0.5 + i * 0.025 for i in range(41)]
    zs = [-1.13 + i * 0.03 for i in range(76)]
    sh.sheet(xs, zs, drape, 0.008, "cloth")
    sh.build()


# ---------- 输液架：钢杆、五脚带轮的底座、顶上两只弯钩；吊瓶单独一件（袋子 + 垂下来的管子） ----------

def iv_stand():
    p = Part("iv_stand")
    p.tube([V(0, 0.08, 0), V(0, 1.86, 0)], 0.011, "steel", 8)
    p.lathe([(0.0, 0.06), (0.03, 0.06), (0.03, 0.12), (0.016, 0.14), (0.0, 0.14)], "steel", 10)
    p.lathe([(0.0, 1.0), (0.018, 1.0), (0.018, 1.05), (0.0, 1.05)], "steel", 8)                       # 调节箍
    for i in range(5):
        a = 2 * math.pi * i / 5
        d = V(math.sin(a), 0, math.cos(a))
        p.tube([V(0, 0.09, 0), d * 0.3 + V(0, 0.06, 0)], 0.01, "steel", 6)
        caster(p, d * 0.3 + V(0, 0.0, 0))
    for s in (-1, 1):
        hook = [V(0, 1.86, 0), V(0.08 * s, 1.88, 0), V(0.14 * s, 1.88, 0), V(0.16 * s, 1.85, 0), V(0.15 * s, 1.82, 0),
                V(0.13 * s, 1.83, 0)]
        p.tube(hook, 0.006, "steel", 6)
    p.build()

    b = Part("iv_bag")
    # 袋子：扁扁的软袋，底下窄一点，挂在右边的钩子上
    b.loft([(1.6, 0.03, 0.012, 0.01), (1.63, 0.06, 0.022, 0.02), (1.72, 0.07, 0.028, 0.026),
            (1.79, 0.065, 0.02, 0.019), (1.81, 0.04, 0.008, 0.007)], "glass", corner=4,
           xf=Matrix.Translation(V(0.15, 0, 0)))
    b.tube([V(0.15, 1.81, 0), V(0.15, 1.83, 0)], 0.004, "steel", 4)
    b.tube([V(0.15, 1.6, 0), V(0.15, 1.5, 0)], 0.008, "glass", 6)                                         # 滴壶
    tube = [V(0.15, 1.5, 0)]
    for i in range(1, 12):
        t = i / 11
        tube.append(V(0.15 + 0.12 * math.sin(t * 2.5), 1.5 - t * 0.95, 0.06 * math.sin(t * 4.0)))
    b.tube(tube, 0.003, "glass", 4)
    b.build()


# ---------- 手术推车：四根立柱带脚轮、两层带边的托盘、一头一根推把；上层托盘顶面在 0.89 ----------

def cart():
    p = Part("cart")
    for sx in (-0.27, 0.27):
        for sz in (-0.42, 0.42):
            p.tube([V(sx, 0.08, sz), V(sx, 0.9, sz)], 0.012, "frame", 8)
            caster(p, V(sx, 0.03, sz))
    for y in (0.29, 0.875):
        p.loft([(y, 0.3, 0.45, 0.03), (y + 0.015, 0.3, 0.45, 0.03)], "steel", corner=3)
        p.loft([(y + 0.015, 0.3, 0.45, 0.03), (y + 0.045, 0.3, 0.45, 0.03), (y + 0.045, 0.29, 0.44, 0.025),
                (y + 0.016, 0.29, 0.44, 0.025)], "steel", cap_bottom=False, cap_top=True, corner=3)
    p.tube([V(-0.27, 0.92, -0.42), V(-0.27, 0.97, -0.5), V(0.27, 0.97, -0.5), V(0.27, 0.92, -0.42)], 0.011, "frame", 8)
    p.build()


# ---------- 洗手池：车削的立柱、圆角台盆、后挡板、冷热两个十字把手和鹅颈龙头；盆里的水单独一件 ----------

def sink():
    p = Part("sink")
    p.lathe([(0.13, 0.0), (0.13, 0.03), (0.09, 0.06), (0.07, 0.35), (0.08, 0.62), (0.13, 0.72), (0.0, 0.72)],
            "porcelain", 16, Matrix.Translation(V(0, 0, -0.05)))
    # 台盆：外壁往上张开，翻过盆沿，再沿内壁下去到盆底
    p.loft([(0.7, 0.2, 0.15, 0.12), (0.8, 0.28, 0.2, 0.15), (0.88, 0.3, 0.225, 0.15), (0.9, 0.3, 0.225, 0.15),
            (0.905, 0.26, 0.185, 0.13), (0.85, 0.24, 0.16, 0.12), (0.78, 0.19, 0.12, 0.1)],
           "porcelain", cap_bottom=True, cap_top=True, xf=Matrix.Translation(V(0, 0, 0.02)))
    p.box(V(0, 0.98, -0.2), (0.6, 0.16, 0.05), "porcelain")                                                  # 后挡板
    for s in (-1, 1):
        x = 0.15 * s
        p.tube([V(x, 0.9, -0.16), V(x, 0.95, -0.16)], 0.012, "steel", 8)
        p.box(V(x, 0.955, -0.16), (0.07, 0.012, 0.012), "steel")
        p.box(V(x, 0.955, -0.16), (0.012, 0.012, 0.07), "steel")
    spout = [V(0, 0.9, -0.17), V(0, 1.02, -0.17), V(0, 1.06, -0.12), V(0, 1.04, -0.06), V(0, 1.0, -0.05)]
    p.tube(spout, 0.012, "steel", 8)
    p.build()

    w = Part("sink_fill")
    w.loft([(0.855, 0.22, 0.145, 0.11), (0.86, 0.22, 0.145, 0.11)], "black", xf=Matrix.Translation(V(0, 0, 0.02)))
    w.build()


# ---------- 浴缸：卷边的铸铁浴缸、四只爪形铜脚；缸里的水单独一件 ----------

def bathtub():
    p = Part("bathtub")
    # 外壁从缸底往上张开、在顶上卷一道边，再沿内壁下去
    p.loft([(0.17, 0.3, 0.72, 0.28), (0.3, 0.35, 0.8, 0.32), (0.58, 0.385, 0.84, 0.35), (0.64, 0.4, 0.86, 0.36),
            (0.68, 0.395, 0.855, 0.355), (0.69, 0.37, 0.83, 0.34), (0.66, 0.34, 0.8, 0.31), (0.45, 0.31, 0.75, 0.28),
            (0.28, 0.25, 0.66, 0.22), (0.24, 0.2, 0.58, 0.18)], "porcelain", corner=8)
    for sx in (-0.26, 0.26):
        for sz in (-0.6, 0.6):
            # 爪形脚：弯下去的腿，底下一只抓地的爪
            d = V(math.copysign(1, sx), 0, math.copysign(1, sz))
            top = V(sx, 0.24, sz)
            p.tube([top, top + d * 0.03 + V(0, -0.08, 0), top + d * 0.07 + V(0, -0.17, 0)], 0.028, "brass", 8)
            foot = top + d * 0.08 + V(0, -0.2, 0)
            p.ball(foot, 0.04, "brass", 10, (1.0, 0.7, 1.0))
            for k in (-1, 0, 1):
                toe = foot + (d + V(-d.z, 0, d.x) * k * 0.8).normalized() * 0.04
                p.ball(toe + V(0, -0.015, 0), 0.016, "brass", 6, (1.0, 0.8, 1.3))
    # 排水口和一根竖着的老式水管
    p.lathe([(0.0, 0.0), (0.025, 0.0), (0.025, 0.01), (0.0, 0.01)], "brass", 8, Matrix.Translation(V(0, 0.245, -0.55)))
    p.tube([V(0, 0.0, -0.95), V(0, 0.75, -0.95), V(0, 0.8, -0.9), V(0, 0.78, -0.8)], 0.014, "brass", 8)
    p.build()

    w = Part("bathtub_fill")
    w.loft([(0.53, 0.33, 0.78, 0.3), (0.54, 0.33, 0.78, 0.3)], "black", corner=8)
    w.build()


# ---------- 一排铁皮柜：三格的柜体、底座、顶檐；门单独一件（原点在合页，往 -x 伸），上面有百叶缝和把手 ----------

def lockers():
    p = Part("lockers_body")
    p.box(V(0, 0.95, 0.0), (1.4, 1.9, 0.48), "frame")
    p.box(V(0, 0.04, 0.0), (1.42, 0.08, 0.5), "black")                                                       # 底座
    p.box(V(0, 1.91, 0.0), (1.44, 0.03, 0.5), "frame")                                                       # 顶檐
    for x in (-0.69, -0.23, 0.23, 0.69):                                                                     # 门框立边
        p.box(V(x, 0.97, 0.235), (0.02, 1.84, 0.02), "frame")
    p.build()

    d = Part("locker_door")
    d.box(V(-0.21, 0.97, 0), (0.42, 1.84, 0.02), "frame")
    for row in (1.62, 0.35):                                                                                 # 上下两组百叶缝
        for k in range(5):
            d.box(V(-0.21, row + k * 0.045, 0.012), (0.24, 0.012, 0.008), "black")
    d.box(V(-0.38, 1.0, 0.02), (0.025, 0.12, 0.03), "steel")                                                 # 把手
    d.box(V(-0.21, 1.3, 0.012), (0.08, 0.05, 0.005), "steel")                                                # 号牌
    for y in (0.3, 1.6):                                                                                     # 合页
        d.tube([V(-0.005, y, 0.0), V(-0.005, y + 0.08, 0.0)], 0.008, "steel", 6)
    d.build()


# ---------- 柜子：带顶冠和踢脚的木柜；两扇门各一件（原点在合页），门上嵌一块凸起的门板和铜把手 ----------

def cabinet():
    p = Part("cabinet")
    p.box(V(0, 0.98, 0), (0.96, 1.8, 0.48), "wood")
    p.box(V(0, 0.04, 0.01), (1.0, 0.08, 0.5), "wood")                                                        # 踢脚
    p.loft([(1.88, 0.5, 0.25, 0.01), (1.9, 0.52, 0.27, 0.01), (1.95, 0.53, 0.28, 0.01), (1.98, 0.5, 0.26, 0.01)],
           "wood", corner=1)                                                                               # 顶冠线脚
    p.build()

    for side, name in ((1, "cabinet_door_r"), (-1, "cabinet_door_l")):
        d = Part(name)
        cx = -side * 0.245
        d.box(V(cx, 1.0, 0), (0.48, 1.8, 0.03), "wood")
        for y0, y1 in ((0.2, 0.95), (1.05, 1.8)):                                                            # 两块凸起的门板
            d.box(V(cx, (y0 + y1) / 2, 0.02), (0.36, y1 - y0, 0.015), "wood")
            d.box(V(cx, (y0 + y1) / 2, 0.03), (0.3, y1 - y0 - 0.06, 0.01), "wood")
        d.box(V(-side * 0.44, 1.0, 0.035), (0.02, 0.14, 0.02), "brass")
        d.ball(V(-side * 0.44, 1.07, 0.04), 0.015, "brass", 8)
        d.build()


# ======================= 第三批：家具 =======================

def turned_leg(p, x, z, y0, y1, r, slot="wood", seg=8):
    """车削的桌椅腿：上方一段方榫（这里用粗一点的圆段代替），中间收细，脚下收一点"""
    h = y1 - y0
    prof = [(r * 0.8, 0.0), (r, 0.03 * h), (r * 0.85, 0.12 * h), (r * 0.7, 0.55 * h), (r * 0.95, 0.78 * h),
            (r * 1.05, 0.82 * h), (r, 1.0 * h), (0.0, 1.0 * h)]
    p.lathe(prof, slot, seg, Matrix.Translation(V(x, y0, z)))


# ---------- 椅子：车削腿、略带圆角的座面、两根靠背立柱、弯的顶梁和一块竖背板、腿间横档 ----------

def chair():
    p = Part("chair")
    for sx in (-0.2, 0.2):
        for sz in (-0.2, 0.2):
            if sz < 0:
                p.tube([V(sx, 0.0, sz), V(sx, 0.45, sz), V(sx, 0.95, sz - 0.05)], 0.02, "wood", 8)   # 后腿连靠背立柱
                p.ball(V(sx, 0.96, sz - 0.052), 0.024, "wood", 8)
            else:
                turned_leg(p, sx, sz, 0.0, 0.44, 0.022)
        p.box(V(sx, 0.15, 0), (0.025, 0.025, 0.4), "wood")                                                 # 侧横档
    p.box(V(0, 0.2, 0.2), (0.4, 0.025, 0.025), "wood")
    p.loft([(0.435, 0.23, 0.23, 0.03), (0.47, 0.235, 0.235, 0.035), (0.48, 0.225, 0.225, 0.03)], "wood", corner=3)
    p.bar([V(-0.2, 0.89, -0.245), V(0, 0.9, -0.27), V(0.2, 0.89, -0.245)], 0.03, 0.08, "wood", up=V(0, 1, 0))
    p.bar([V(0, 0.5, -0.215), V(0, 0.86, -0.25)], 0.12, 0.02, "wood", up=V(0, 0, 1))                          # 竖背板
    p.build()


# ---------- 三脚凳：车削的圆座面、三条外撇的腿、一圈横档 ----------

def stool():
    p = Part("stool")
    p.lathe([(0.0, 0.46), (0.16, 0.46), (0.172, 0.475), (0.168, 0.495), (0.0, 0.5)], "wood", 18)
    for i in range(3):
        a = 2 * math.pi * i / 3
        d = V(math.cos(a), 0, math.sin(a))
        p.tube([d * 0.1 + V(0, 0.46, 0), d * 0.17 + V(0, 0.0, 0)], 0.016, "wood", 8)
    ring = [V(math.cos(2 * math.pi * k / 3) * 0.14, 0.17, math.sin(2 * math.pi * k / 3) * 0.14) for k in range(3)]
    p.tube(ring, 0.009, "wood", 6, close_path=True)
    p.build()


# ---------- 桌子：桌面、四面牙板、收细的车削腿；餐具（两只盘子、两把刀）单独一件 ----------

def table():
    p = Part("table")
    p.loft([(0.735, 0.7, 0.4, 0.02), (0.775, 0.7, 0.4, 0.02), (0.785, 0.69, 0.39, 0.015)], "wood", corner=2)
    p.loft([(0.64, 0.63, 0.33, 0.01), (0.735, 0.63, 0.33, 0.01)], "wood", corner=1)                           # 牙板
    for sx in (-0.64, 0.64):
        for sz in (-0.34, 0.34):
            turned_leg(p, sx, sz, 0.0, 0.735, 0.03)
    p.build()

    s = Part("table_setting")
    for sx in (-0.35, 0.35):
        s.lathe([(0.0, 0.785), (0.08, 0.785), (0.1, 0.79), (0.12, 0.8), (0.11, 0.8), (0.085, 0.792), (0.0, 0.792)],
                "porcelain", 20, Matrix.Translation(V(sx, 0, 0)))
        s.box(V(sx + 0.16, 0.788, 0), (0.015, 0.004, 0.18), "steel")
    s.build()


# ---------- 长餐桌：深色桌面、垂到两边的桌布、八套盘子、正中一座三头烛台（蜡烛和火苗在里面，灯光在游戏里打） ----------

def long_table():
    p = Part("long_table")
    p.loft([(0.735, 1.3, 0.5, 0.03), (0.785, 1.3, 0.5, 0.03)], "dark_wood", corner=2)
    for sx in (-1.2, 1.2):
        for sz in (-0.42, 0.42):
            turned_leg(p, sx, sz, 0.0, 0.735, 0.035, "dark_wood")
    p.box(V(0, 0.12, 0), (2.4, 0.04, 0.04), "dark_wood")                                                    # 底下一根长撑
    for sx in (-1.2, 1.2):
        p.box(V(sx, 0.12, 0), (0.04, 0.04, 0.84), "dark_wood")

    def drape(x, z):
        top = 0.792
        ex, ez = max(0.0, abs(x) - 1.31), max(0.0, abs(z) - 0.51)
        e = max(ex, ez)
        if e <= 0:
            return top
        return top - min(0.32, e * 5.0) - 0.01 * math.sin(x * 19.0 + z * 23.0) * min(1.0, e * 12)

    xs = [-1.4 + i * 0.05 for i in range(57)]
    zs = [-0.6 + i * 0.04 for i in range(31)]
    p.sheet(xs, zs, drape, 0.006, "cloth")
    plates = [(x, z * 0.55) for x in (-0.85, 0.0, 0.85) for z in (0.75, -0.75)] + [(1.24, 0.0), (-1.24, 0.0)]
    for x, z in plates:
        p.lathe([(0.0, 0.792), (0.08, 0.792), (0.1, 0.797), (0.12, 0.807), (0.11, 0.807), (0.085, 0.8), (0.0, 0.8)],
                "porcelain", 18, Matrix.Translation(V(x, 0, z)))
    # 烛台
    p.lathe([(0.0, 0.792), (0.09, 0.792), (0.09, 0.81), (0.04, 0.84), (0.025, 0.9), (0.035, 0.95), (0.02, 1.0),
             (0.03, 1.06), (0.0, 1.07)], "brass", 14)
    p.tube([V(-0.13, 1.1, 0), V(-0.12, 1.06, 0), V(0, 1.05, 0), V(0.12, 1.06, 0), V(0.13, 1.1, 0)], 0.008, "brass", 6)
    for sx in (-0.13, 0.0, 0.13):
        y0 = 1.07 if sx == 0 else 1.1
        p.lathe([(0.0, y0), (0.028, y0), (0.022, y0 + 0.02), (0.0, y0 + 0.02)], "brass", 10, Matrix.Translation(V(sx, 0, 0)))
        p.lathe([(0.0, 0.0), (0.014, 0.0), (0.014, 0.13), (0.011, 0.14), (0.0, 0.14)], "wax", 10,
                Matrix.Translation(V(sx, y0 + 0.02, 0)))
        p.ball(V(sx, y0 + 0.18, 0), 0.008, "flame", 8, (1.0, 2.6, 1.0))
    p.build()


# ---------- 课桌连椅：斜桌面、桌肚、铁架和两根落地的滑脚，后面连着一把小椅子 ----------

def desk():
    p = Part("desk")
    p.box(V(0, 0.72, 0.25), (0.7, 0.03, 0.45), "wood", rx(0.08))
    p.box(V(0, 0.64, 0.25), (0.66, 0.1, 0.4), "dark_wood")
    p.box(V(0, 0.585, 0.25), (0.6, 0.01, 0.36), "black")                                                    # 桌肚里黑的
    p.box(V(0.25, 0.745, 0.14), (0.06, 0.01, 0.012), "black")                                                # 笔槽
    for sx in (-0.3, 0.3):
        p.tube([V(sx, 0.03, 0.42), V(sx, 0.03, -0.42)], 0.016, "frame", 6)                                  # 滑脚
        p.tube([V(sx, 0.03, 0.3), V(sx, 0.6, 0.27)], 0.016, "frame", 6)
        p.tube([V(sx * 0.7, 0.03, -0.3), V(sx * 0.7, 0.42, -0.3), V(sx * 0.7, 0.77, -0.48)], 0.014, "frame", 6)
        p.tube([V(sx, 0.03, 0.0), V(sx * 0.85, 0.3, 0.12), V(sx, 0.58, 0.18)], 0.01, "frame", 4)
    p.box(V(0, 0.43, -0.3), (0.44, 0.03, 0.36), "wood")
    p.box(V(0, 0.66, -0.48), (0.44, 0.2, 0.025), "wood", rx(-0.1))
    p.build()


# ---------- 候诊长椅：三副铸铁侧架（带扶手的弯腿）、三根木条座面、两根往后仰的木条靠背 ----------

def bench():
    p = Part("bench")
    for sx in (-0.8, 0.0, 0.8):
        p.tube([V(sx, 0.0, 0.2), V(sx, 0.2, 0.18), V(sx, 0.44, 0.16)], 0.018, "frame", 6)
        p.tube([V(sx, 0.0, -0.2), V(sx, 0.44, -0.18), V(sx, 0.95, -0.27)], 0.018, "frame", 6)
        p.tube([V(sx, 0.44, 0.2), V(sx, 0.44, -0.2)], 0.016, "frame", 6)
        if sx != 0.0:
            p.tube([V(sx, 0.44, 0.18), V(sx, 0.62, 0.2), V(sx, 0.64, 0.05), V(sx, 0.62, -0.2)], 0.014, "frame", 6)
    for k in range(3):
        p.box(V(0, 0.465, -0.12 + k * 0.14), (1.8, 0.03, 0.12), "wood")
    for k in range(2):
        y = 0.7 + k * 0.18
        p.box(V(0, y, -0.215 - (y - 0.7) * 0.12), (1.8, 0.1, 0.025), "wood", rx(-0.12))
    p.build()


# ---------- 架子：两块侧板、四层隔板、背后两道斜拉条；瓶瓶罐罐三套（jar_dark 槽在游戏里可能是血） ----------

def shelf():
    p = Part("shelf")
    for sx in (-0.68, 0.68):
        p.box(V(sx, 1.0, 0), (0.04, 2.0, 0.38), "wood")
    for i in range(4):
        y = 0.15 + i * 0.6
        p.box(V(0, y, 0), (1.32, 0.03, 0.38), "wood")
        p.box(V(0, y - 0.035, 0.18), (1.32, 0.04, 0.02), "wood")                                              # 隔板前沿
    p.box(V(0, 2.02, 0), (1.44, 0.04, 0.42), "wood")
    for a in (1, -1):
        p.box(V(0, 1.05, -0.18), (0.03, 2.1, 0.01), "dark_wood", Matrix.Rotation(a * 0.62, 3, "Z"))
    p.build()

    rng_state = [7]

    def rnd():
        rng_state[0] = (rng_state[0] * 1103515245 + 12345) % 2147483648
        return rng_state[0] / 2147483648

    for variant in "abc":
        j = Part("shelf_jars_" + variant)
        for i in range(3):
            y = 0.15 + i * 0.6 + 0.015
            x = -0.6
            while x < 0.58:
                r = 0.05 + rnd() * 0.05
                h = 0.12 + rnd() * 0.23
                if rnd() < 0.75:
                    slot = "jar_dark" if rnd() < 0.4 else "glass"
                    z = (rnd() - 0.5) * 0.16
                    neck = r * (0.55 + rnd() * 0.3)
                    j.lathe([(0.0, 0.0), (r * 0.95, 0.0), (r, 0.02), (r, h * 0.78), (neck, h * 0.9), (neck, h), (0.0, h)],
                            slot, 12, Matrix.Translation(V(x + r, y, z)))
                    if rnd() < 0.6:                                                                       # 盖子
                        j.lathe([(0.0, h), (neck * 1.1, h), (neck * 1.1, h + 0.02), (0.0, h + 0.025)], "dark_wood", 10,
                                Matrix.Translation(V(x + r, y, z)))
                x += r * 2 + 0.06
        j.build()


# ---------- 木箱：边长 0.7 的板条箱（四周一圈加强框、一道斜撑），游戏里按大小缩放、摞起来 ----------

def crate():
    p = Part("crate")
    h = 0.35
    p.box(V(0, h, 0), (0.68, 0.68, 0.68), "wood")
    for sx in (-1, 1):                                                                                     # 每面的边框
        for sy in (-1, 1):
            p.box(V(sx * 0.33, h + sy * 0.33, 0), (0.06, 0.06, 0.72), "dark_wood")
            p.box(V(0, h + sy * 0.33, sx * 0.33), (0.72, 0.06, 0.06), "dark_wood")
            p.box(V(sx * 0.33, h, sy * 0.33), (0.06, 0.72, 0.06), "dark_wood")
    for nz in (-1, 1):
        p.box(V(0, h, nz * 0.345), (0.85, 0.06, 0.02), "dark_wood", Matrix.Rotation(math.pi / 4, 3, "Z"))
        p.box(V(nz * 0.345, h, 0), (0.02, 0.06, 0.85), "dark_wood", Matrix.Rotation(math.pi / 4, 3, "X"))
    for k in range(1, 4):                                                                                  # 板缝
        y = h - 0.3 + k * 0.15
        for nz in (-1, 1):
            p.box(V(0, y, nz * 0.342), (0.6, 0.008, 0.01), "black")
            p.box(V(nz * 0.342, y, 0), (0.01, 0.008, 0.6), "black")
    p.build()


# ---------- 落地钟：底座、开着前脸的钟身（看得见钟摆）、带拱顶和柱头的钟头；表盘、指针、钟摆在游戏里另摆 ----------

def grandfather():
    p = Part("grandfather")
    p.box(V(0, 0.04, 0), (0.98, 0.08, 0.62), "dark_wood")                                                     # 踢脚
    p.box(V(0, 0.34, 0), (0.9, 0.52, 0.55), "dark_wood")
    p.box(V(0, 0.62, 0), (0.96, 0.05, 0.6), "dark_wood")
    p.box(V(0, 0.36, 0.28), (0.6, 0.34, 0.02), "dark_wood")                                                   # 底座门板
    for sx in (-0.4, 0.4):
        p.box(V(sx, 1.4, 0), (0.1, 1.56, 0.5), "dark_wood")
        p.box(V(sx * 0.9, 1.4, 0.26), (0.04, 1.5, 0.02), "brass")                                             # 门框
    p.box(V(0, 1.4, -0.24), (0.8, 1.56, 0.04), "dark_wood")
    p.box(V(0, 1.4, -0.215), (0.7, 1.5, 0.01), "black")                                                       # 钟身里面
    p.box(V(0, 2.2, 0), (0.98, 0.06, 0.62), "dark_wood")
    p.box(V(0, 2.65, -0.02), (0.92, 0.86, 0.56), "dark_wood")                                                 # 钟头
    for sx in (-0.44, 0.44):                                                                                 # 钟头两边的小柱子
        p.lathe([(0.03, 0.0), (0.035, 0.05), (0.025, 0.4), (0.035, 0.8), (0.03, 0.86), (0.0, 0.86)], "brass", 10,
                Matrix.Translation(V(sx, 2.23, 0.27)))
    # 拱顶：一块弓形的顶板，两头一对柱头球
    arch = [V(-0.5, 3.08, 0.0)] + [V(-0.5 + i / 10, 3.08 + 0.18 * math.sin(math.pi * i / 10), 0.0) for i in range(1, 10)] + \
           [V(0.5, 3.08, 0.0)]
    p.bar(arch, 0.6, 0.08, "dark_wood", up=V(0, 1, 0))
    p.box(V(0, 3.1, 0), (1.02, 0.06, 0.64), "dark_wood")
    for sx in (-0.48, 0.0, 0.48):
        p.ball(V(sx, 3.2 + (0.19 if sx == 0 else 0.0), 0.0), 0.04, "brass", 10)
    p.build()

    pend = Part("pendulum")
    pend.tube([V(0, 0.0, 0), V(0, -1.15, 0)], 0.008, "brass", 6)
    pend.lathe([(0.0, -0.02), (0.11, -0.012), (0.12, 0.0), (0.11, 0.012), (0.0, 0.02)], "brass", 20,
               Matrix.Translation(V(0, -1.2, 0)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    pend.build()


# ---------- 挂钟的木壳（单位半径，游戏里按大小在 xy 上缩放）和表盘（单位半径的盘面、刻度、铜圈） ----------

def clock():
    p = Part("clock_case")
    p.lathe([(0.0, 0.0), (1.15, 0.0), (1.15, 0.05), (1.1, 0.07), (1.02, 0.08), (0.0, 0.08)], "dark_wood", 32,
            Matrix.Rotation(math.pi / 2, 4, "X") @ Matrix.Translation(V(0, 0, 0)))
    p.build()

    d = Part("dial")
    d.lathe([(0.0, -0.01), (1.0, -0.01), (1.0, 0.01), (0.0, 0.01)], "face", 32, Matrix.Rotation(math.pi / 2, 4, "X"))
    d.torus(V(0, 0, 0.01), Matrix.Rotation(math.pi / 2, 4, "X"), 1.0, 0.03, "brass", 32, 5)
    for i in range(12):
        a = 2 * math.pi * i / 12
        long = i % 3 == 0
        d.box(V(math.sin(a) * 0.82, math.cos(a) * 0.82, 0.015), (0.04, 0.16 if long else 0.08, 0.01), "black",
              Matrix.Rotation(-a, 3, "Z"))
    for i in range(60):                                                                                      # 分钟小点
        if i % 5:
            a = 2 * math.pi * i / 60
            d.box(V(math.sin(a) * 0.9, math.cos(a) * 0.9, 0.013), (0.015, 0.03, 0.006), "black", Matrix.Rotation(-a, 3, "Z"))
    d.build()


def preview(objs, out_dir):
    world = bpy.data.worlds.new("dim")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.03, 0.035, 1.0)
    bpy.context.scene.world = world
    for name, loc, energy in (("key", (2.0, -3.0, 3.5), 400.0), ("fill", (-3.0, -1.0, 2.0), 120.0)):
        light = bpy.data.lights.new(name, "POINT")
        light.energy = energy
        o = bpy.data.objects.new(name, light)
        o.location = loc
        bpy.context.collection.objects.link(o)
    floor = Part("floor")
    floor.box(V(0, -0.05, 2.5), (14, 0.1, 11), "cloth")
    floor.box(V(0, 1.5, -1.6), (12, 3.0, 0.1), "cloth")
    floor.build()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 800
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 30
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (0.0, -11.5, 2.8)
    cam.rotation_euler = (Vector((0, 0, 0.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "room_props_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "room_props.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for s in SLOTS:
        col, rough, metal = COLORS[s]
        m = bpy.data.materials.new(s)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
    for build in (bed, rocking_chair, crib, wheelchair, doll, mannequin,
                  optable, gurney, iv_stand, cart, sink, bathtub, lockers, cabinet,
                  chair, stool, table, long_table, desk, bench, shelf, crate, grandfather, clock):
        build()
    objs = [o for o in bpy.data.objects]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_normals=True)
    print("exported", out)
    if len(argv) > 1:
        # 预览：一字排开（娃娃放大两倍看得清）
        place = {"bed_frame": (-4.3, 0), "bed_mattress": (-4.3, 0), "rocking_chair": (-2.6, 0), "crib": (-1.0, 0),
                 "wheelchair": (0.7, 0), "doll_body": (1.9, 0), "doll_head": (1.9, 0),
                 "mannequin_stand": (3.2, 0), "mannequin_body": (3.2, 0),
                 "optable": (-4.6, 2.6), "gurney": (-3.4, 2.6), "gurney_sheet": (-3.4, 2.6), "iv_stand": (-2.4, 2.6),
                 "iv_bag": (-2.4, 2.6), "cart": (-1.5, 2.6), "sink": (-0.5, 2.6), "sink_fill": (-0.5, 2.6),
                 "bathtub": (0.6, 2.6), "bathtub_fill": (0.6, 2.6), "lockers_body": (2.0, 2.6),
                 "locker_door": (1.77, 2.85), "cabinet": (3.5, 2.6), "cabinet_door_r": (4.0, 2.855),
                 "cabinet_door_l": (3.0, 2.855),
                 "chair": (-4.6, 5.0), "stool": (-4.0, 5.0), "table": (-3.0, 5.0), "table_setting": (-3.0, 5.0),
                 "long_table": (-0.8, 5.0), "desk": (1.0, 5.0), "bench": (2.4, 5.0), "shelf": (4.2, 4.6),
                 "shelf_jars_a": (4.2, 4.6), "shelf_jars_b": (99, 99), "shelf_jars_c": (99, 99), "crate": (-4.4, 6.0),
                 "grandfather": (5.4, 4.6), "pendulum": (99, 99), "clock_case": (99, 99), "dial": (99, 99)}
        for o in objs:
            x, z = place[o.name]
            o.location = (x, -z, 0.0)
            if o.name.startswith("doll"):
                o.scale = (2.5, 2.5, 2.5)
                o.location = (x, -z, 0.27 * 2.5 if o.name == "doll_head" else 0.0)
            if z < 1:
                o.rotation_euler = (0, 0, math.radians(-25))
            if o.name == "locker_door":
                o.rotation_euler = (0, 0, math.radians(70))        # 开着一扇
        preview(objs, argv[1])


main()
