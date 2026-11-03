# 房间道具（第一批）：铁床、摇椅、婴儿床、轮椅、瓷娃娃、人台，按参数生成，导出成 assets/models/room_props.glb。
# 每个物体一件（或一件的一个活动部分），按名字取；材质槽名字对应 scripts/rooms/props.gd 里的材质：
#   frame（铁或锈，游戏里按不安程度挑）、wood、cloth、porcelain、black、skin、steel
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

SLOTS = ["frame", "wood", "cloth", "porcelain", "black", "skin", "steel"]
COLORS = {
    "frame": ((0.2, 0.19, 0.18), 0.6, 0.7),
    "wood": ((0.24, 0.16, 0.1), 0.75, 0.0),
    "cloth": ((0.52, 0.49, 0.42), 0.95, 0.0),
    "porcelain": ((0.62, 0.62, 0.58), 0.3, 0.0),
    "black": ((0.03, 0.03, 0.03), 0.4, 0.3),
    "skin": ((0.62, 0.55, 0.5), 0.6, 0.0),
    "steel": ((0.5, 0.5, 0.5), 0.3, 0.9),
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
    floor.box(V(0, -0.05, 0), (12, 0.1, 6), "cloth")
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
    cam.location = (0.0, -6.5, 2.2)
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
    for build in (bed, rocking_chair, crib, wheelchair, doll, mannequin):
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
                 "mannequin_stand": (3.2, 0), "mannequin_body": (3.2, 0)}
        for o in objs:
            x, z = place[o.name]
            o.location = (x, -z, 0.0)
            if o.name.startswith("doll"):
                o.scale = (2.5, 2.5, 2.5)
                o.location = (x, -z, 0.27 * 2.5 if o.name == "doll_head" else 0.0)
            o.rotation_euler = (0, 0, math.radians(-25))
        preview(objs, argv[1])


main()
