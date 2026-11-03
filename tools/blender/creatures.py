# 迷宫里的东西（原创造型，不参考任何影视角色），按参数生成，导出成 assets/models/creatures.glb。
# 目前一种：拖链者——比墙还高、驼背的苍白巨物，头整个焊在一截矮胖的旧锅炉铁罐里（满是铆钉和铁箍，前头圆顶上一个
# 糊满污垢的观察窗，里面透出一点暗光），反关节的腿，长到垂过膝盖的胳膊和长爪；
# 穿着一身对它太小的旧衣服：褪色的暗红呢子长外套（袖子只到肘弯、前襟敞着、下摆撕成条）、发黑的皮围裙、
# 斜挎的皮挽具（背后一个铁环，拴着拖铁板的链子）、膝盖撑破的土黄帆布裤、小臂和脚踝缠着脏绷带。
#
# 身体用蒙皮修改器（Skin）沿一副“骨架”长出一整块连续的肉，再细分、置换出起伏；衣服是贴着身体的管子和布片。
# 一副骨骼（hauler_rig）带着身体和衣服，权重按离哪根骨头近来分；走路的动作在游戏里按骨骼摆（scripts/hauler.gd）。
# 另有两件不绑骨骼：hauler_plate（锈铁板，原点在拴链子的铁环）、hauler_chain（8 米长的链子，沿 +z，游戏里按长短伸缩）。
# 锅炉罩（hauler_helmet）整块绑在 head 骨头上，不跟着变形。
# 材质槽：skin、coat、leather、canvas、bandage、brass、iron、glass（观察窗，游戏里微微发光）。
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/creatures.py -- assets/models/creatures.glb [预览图目录]
#
# 坐标约定：脚本里按 Godot 写（y 向上，+z 是它面朝、往前走的方向，+x 是它的左手边），落到 Blender 时换成 (x, -z, y)。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SLOTS = ["skin", "coat", "leather", "canvas", "bandage", "brass", "iron", "glass"]
COLORS = {"skin": (0.42, 0.4, 0.35), "coat": (0.3, 0.07, 0.05), "leather": (0.11, 0.07, 0.045),
          "canvas": (0.4, 0.31, 0.15), "bandage": (0.55, 0.5, 0.37), "brass": (0.45, 0.33, 0.15),
          "iron": (0.17, 0.1, 0.06), "glass": (0.03, 0.035, 0.025)}


def V(x, y, z):
    return Vector((x, y, z))


def B(p):
    """Godot 坐标 → Blender 坐标"""
    return Vector((p.x, -p.z, p.y))


# ---------- 骨架：每根骨头（名字、起点、终点、父骨），Godot 坐标 ----------

SPINE = [V(0, 8.4, 0.0), V(0, 10.2, 0.35), V(0, 11.9, 1.2), V(0, 13.4, 2.3), V(0, 13.9, 3.4)]
SPINE_R = [1.2, 0.85, 1.7, 1.8, 1.05]          # 身体在这几处的粗细
BONES = [
    ("spine1", SPINE[0], SPINE[1], None), ("spine2", SPINE[1], SPINE[2], "spine1"),
    ("spine3", SPINE[2], SPINE[3], "spine2"), ("spine4", SPINE[3], SPINE[4], "spine3"),
    ("neck", SPINE[4], V(0, 12.9, 5.3), "spine4"), ("head", V(0, 12.9, 5.3), V(0, 12.9, 5.3) + V(0, -0.42, 1).normalized() * 2.6, "neck"),
]
for side, s in (("l", 1), ("r", -1)):
    BONES += [
        ("thigh_" + side, V(s * 1.0, 8.2, 0.0), V(s * 1.25, 5.6, 1.5), "spine1"),
        ("shin_" + side, V(s * 1.25, 5.6, 1.5), V(s * 1.15, 2.4, -1.1), "thigh_" + side),
        ("foot_" + side, V(s * 1.15, 2.4, -1.1), V(s * 1.15, 0.45, 0.15), "shin_" + side),
        ("toe_" + side, V(s * 1.15, 0.45, 0.15), V(s * 1.15, 0.1, 1.9), "foot_" + side),
        ("upperarm_" + side, V(s * 1.75, 13.3, 2.2), V(s * 2.4, 10.4, 2.4), "spine3"),
        ("forearm_" + side, V(s * 2.4, 10.4, 2.4), V(s * 2.2, 7.0, 3.3), "upperarm_" + side),
        ("hand_" + side, V(s * 2.2, 7.0, 3.3), V(s * 2.15, 3.8, 4.0), "forearm_" + side),
    ]
RING = V(0, 8.9, -1.35)          # 挽具背后的铁环（链子拴在这里），跟着 spine1 走
BONES.append(("ring", RING, RING + V(0, 0.3, -0.3), "spine1"))


# ---------- 网格拼装工具（Godot 坐标） ----------

class Part:
    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []

    def v(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def f(self, idx, slot, smooth=True):
        self.faces.append((idx, SLOTS.index(slot), smooth))

    def tube(self, pts, radii, slot, seg=10, skip=None, ragged=0.0, rng=None, caps=False):
        """沿折线一根管子；skip(i, k) 为真的面不要（开口、破洞）；ragged 让末端一圈参差"""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        rings = []
        prev = None
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            ref = prev if prev is not None else (V(1, 0, 0) if abs(t.x) < 0.9 else V(0, 0, 1))
            nn = (ref - t * ref.dot(t)).normalized()
            b = t.cross(nn)
            prev = nn
            r = radii[i] if isinstance(radii, (list, tuple)) else radii
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                q = p + (nn * math.cos(a) + b * math.sin(a)) * r
                if i == n - 1 and ragged > 0 and rng:
                    q += t * (rng() - 0.3) * ragged
                ring.append(self.v(q))
            rings.append(ring)
        for i in range(n - 1):
            for k in range(seg):
                if skip and skip(i, k, rings):
                    continue
                a, c = rings[i], rings[i + 1]
                self.f([a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]], slot)
        if caps:
            self.f(list(reversed(rings[0])), slot)
            self.f(rings[-1], slot)
        return rings

    def ellipsoid(self, c, radii, slot, rot=None, seg=12, rings=8):
        rot = rot or Matrix.Identity(3)
        c = Vector(c)
        top = self.v(c + rot @ V(0, radii[1], 0))
        bot = self.v(c + rot @ V(0, -radii[1], 0))
        grid = []
        for j in range(1, rings):
            a = math.pi * j / rings
            grid.append([self.v(c + rot @ V(math.sin(a) * math.cos(2 * math.pi * k / seg) * radii[0], math.cos(a) * radii[1],
                                            math.sin(a) * math.sin(2 * math.pi * k / seg) * radii[2])) for k in range(seg)])
        for k in range(seg):
            self.f([top, grid[0][(k + 1) % seg], grid[0][k]], slot)
            self.f([bot, grid[-1][k], grid[-1][(k + 1) % seg]], slot)
        for j in range(len(grid) - 1):
            a, b = grid[j], grid[j + 1]
            for k in range(seg):
                self.f([a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]], slot)

    def sheet(self, rows, slot):
        """一片布：rows 是一行行的点（每行点数相同），面不封口，游戏里双面画"""
        ids = [[self.v(p) for p in row] for row in rows]
        for j in range(len(ids) - 1):
            for i in range(len(ids[j]) - 1):
                self.f([ids[j][i], ids[j][i + 1], ids[j + 1][i + 1], ids[j + 1][i]], slot)

    def build(self):
        bm = bmesh.new()
        bv = [bm.verts.new(B(p)) for p in self.verts]
        for idx, mi, smooth in self.faces:
            try:
                face = bm.faces.new([bv[i] for i in idx])
            except ValueError:
                continue
            face.material_index = mi
            face.smooth = smooth
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for s in SLOTS:
            mesh.materials.append(bpy.data.materials[s])
        o = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(o)
        return o


class Rand:
    """可复现的随机数（每次生成的模型都一样）"""

    def __init__(self, seed):
        self.s = seed

    def __call__(self):
        self.s = (self.s * 1103515245 + 12345) % 2147483648
        return self.s / 2147483648


def spine_at(y):
    """脊柱上高度 y 那一点的位置、切线、粗细"""
    for i in range(len(SPINE) - 1):
        a, b = SPINE[i], SPINE[i + 1]
        if a.y <= y <= b.y or i == len(SPINE) - 2:
            t = 0.0 if b.y == a.y else max(0.0, min(1.0, (y - a.y) / (b.y - a.y)))
            return a.lerp(b, t), (b - a).normalized(), SPINE_R[i] + (SPINE_R[i + 1] - SPINE_R[i]) * t
    return SPINE[0], V(0, 1, 0), SPINE_R[0]


# ---------- 身体：蒙皮修改器长出一整块肉 ----------

def body():
    pts, edges = [], []

    def chain(points, link_to=None):
        first = len(pts)
        pts.extend(points)
        for i in range(first, len(pts) - 1):
            edges.append((i, i + 1))
        if link_to is not None:
            edges.append((link_to, first))
        return first, len(pts) - 1

    spine0, neck = chain(list(zip(SPINE, SPINE_R)) + [(V(0, 13.4, 4.5), 0.55), (V(0, 12.9, 5.3), 0.45)])
    for s in (1, -1):
        _, toe = chain([(V(s * 1.0, 8.2, 0.0), 0.85), (V(s * 1.25, 5.6, 1.5), 0.5), (V(s * 1.15, 2.4, -1.1), 0.3),
                        (V(s * 1.15, 0.45, 0.15), 0.32), (V(s * 1.15, 0.15, 1.1), 0.18)], spine0)
        for k in (-1, 0, 1):
            chain([(V(s * 1.15 + k * 0.25, 0.15, 1.1), 0.12), (V(s * 1.15 + k * 0.45, 0.06, 1.9), 0.05)], toe)
        _, hand = chain([(V(s * 1.75, 13.3, 2.2), 0.7), (V(s * 2.4, 10.4, 2.4), 0.38), (V(s * 2.2, 7.0, 3.3), 0.22),
                         (V(s * 2.15, 6.0, 3.6), 0.3)], 3)
        for k in range(4):
            x = s * 2.15 + (k - 1.5) * 0.22
            chain([(V(x, 5.8, 3.7), 0.09), (V(x * 1.02, 4.6, 4.0), 0.06), (V(x * 1.03, 3.7, 3.7), 0.025)], hand)
    for k in range(5):                                                                       # 肋骨
        y = 11.0 + k * 0.55
        for s in (1, -1):
            chain([(V(s * 0.25, y, 2.75 + k * 0.25), 0.16), (V(s * 1.25, y - 0.25, 2.55 + k * 0.25), 0.17),
                   (V(s * 1.75, y - 0.7, 1.6 + k * 0.2), 0.14)])
    for k in range(6):                                                                       # 背上的骨刺
        t = k / 5
        base = V(0, 10.6 + t * 3.5, 0.35 + t * 2.4 - 1.45 - 0.2 * math.sin(t * math.pi))
        chain([(base, 0.3), (base + V(0, 0.9, -0.8), 0.05)])

    mesh = bpy.data.meshes.new("hauler_skin")
    mesh.from_pydata([B(p) for p, r in pts], edges, [])
    obj = bpy.data.objects.new("hauler_skin", mesh)
    bpy.context.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    for i, (p, r) in enumerate(pts):
        mesh.skin_vertices[0].data[i].radius = (r, r)
    mesh.skin_vertices[0].data[spine0].use_root = True
    obj.modifiers.new("Sub", "SUBSURF").levels = 2
    for name, kind, scale, strength in (("flesh", "VORONOI", 1.4, -0.22), ("wrinkle", "CLOUDS", 0.35, 0.1)):
        tex = bpy.data.textures.new(name, kind)
        tex.noise_scale = scale
        d = obj.modifiers.new(name, "DISPLACE")
        d.texture = tex
        d.strength = strength
    # 应用修改器，变成普通网格（之后要分骨骼权重）
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    obj.select_set(False)
    obj.data.materials.clear()
    for s in SLOTS:
        obj.data.materials.append(bpy.data.materials[s])
    return obj


# ---------- 衣服 ----------

def clothes():
    p = Part("hauler_clothes")
    rnd = Rand(17)
    x_axis = V(1, 0, 0)

    def frame(y):
        c, t, r = spine_at(y)
        b = t.cross(x_axis).normalized()        # 背的方向（后上方）；-b 是胸腹那面
        return c, t, r, b

    # 外套的身子：沿着脊柱一圈圈，前襟敞开（正对胸腹的几列不要）
    seg = 24
    open_cols = set()
    for k in range(seg):
        a = 2 * math.pi * k / seg
        if abs((a - 1.5 * math.pi + math.pi) % (2 * math.pi) - math.pi) < math.radians(32):
            open_cols.add(k)
    rows = []
    for y in [9.3 + i * 0.4 for i in range(12)]:
        c, t, r, b = frame(y)
        rx, ry = r * 1.05 + 0.28, r + 0.25
        rows.append([c + (x_axis * math.cos(2 * math.pi * k / seg) * rx + b * math.sin(2 * math.pi * k / seg) * ry) for k in range(seg + 1)])
    ids = [[p.v(q) for q in row] for row in rows]
    for j in range(len(ids) - 1):
        for k in range(seg):
            if k in open_cols:
                continue
            p.f([ids[j][k], ids[j][k + 1], ids[j + 1][k + 1], ids[j + 1][k]], "coat")
    # 肩上收口：最上一圈往脖子收
    c, t, r, b = frame(13.9)
    for k in range(seg):
        if k in open_cols:
            continue
        a0, a1 = 2 * math.pi * k / seg, 2 * math.pi * (k + 1) / seg
        inner = [c + t * 0.3 + (x_axis * math.cos(a) * 0.75 + b * math.sin(a) * 0.65) for a in (a0, a1)]
        q0, q1 = p.v(inner[0]), p.v(inner[1])
        p.f([ids[-1][k], ids[-1][k + 1], q1, q0], "coat")
    # 竖起来的领子
    neck_c = V(0, 13.7, 3.6)
    p.tube([neck_c + V(0, -0.2, -0.3), neck_c + V(0, 0.5, 0.0)], [1.05, 1.15], "coat", seg=16,
           skip=lambda i, k, rr: k in (3, 4, 5))
    # 下摆：从腰那一圈往下垂，往外张开，每一列长短不一，撕成一条条
    waist = rows[0]
    hem_rows = []
    lengths = [3.2 + 2.2 * rnd() for _ in range(seg + 1)]
    for i in range(7):
        u = i / 6
        row = []
        for k in range(seg + 1):
            q = waist[k]
            out = V(q.x, 0, q.z) - V(0, 0, 0.1)
            out = out.normalized() if out.length > 0.01 else V(0, 0, -1)
            row.append(q + V(0, -lengths[k] * u, 0) + out * 0.9 * u * u)
        hem_rows.append(row)
    hids = [[p.v(q) for q in row] for row in hem_rows]
    for j in range(len(hids) - 1):
        for k in range(seg):
            if k in open_cols:
                continue
            # 撕开的条：每隔几列在下半截断开一条缝
            if j >= 3 and (k * 7 + j) % 5 == 0:
                continue
            p.f([hids[j][k], hids[j][k + 1], hids[j + 1][k + 1], hids[j + 1][k]], "coat")
    # 前襟两边一排铜扣（扣不上）
    for k in sorted(open_cols)[:1] + sorted(open_cols)[-1:]:
        for j in range(2, 10, 2):
            q = rows[j][k + (0 if k == min(open_cols) else 1)]
            p.ellipsoid(q + (q - frame(q.y)[0]).normalized() * 0.05, (0.1, 0.1, 0.1), "brass", seg=6, rings=4)
    # 袖子：只到肘弯下面一点，袖口参差
    for s in (1, -1):
        sh, el = V(s * 1.75, 13.3, 2.2), V(s * 2.4, 10.4, 2.4)
        p.tube([sh + V(0, 0.3, 0), sh.lerp(el, 0.5), el + (el - sh).normalized() * 0.6], [0.95, 0.68, 0.6], "coat",
               seg=12, ragged=0.5, rng=rnd)
    # 皮围裙：挂在胸前，垂过腰，下沿翘起一角
    c, t, r, b = frame(10.2)
    top = c - b * (r + 0.4)
    apron = []
    for i in range(6):
        u = i / 5
        row = []
        for j in range(5):
            w = (j / 4 - 0.5) * (1.5 + 0.4 * u)
            row.append(top + V(w, -3.4 * u, 0.5 * u + 0.15 * math.sin(j * 1.3) * u) + V(0, 0.25 * u * u * (j == 4), 0))
        apron.append(row)
    p.sheet(apron, "leather")
    # 挽具：两条皮带在胸前交叉，绕到背后，背后一个大铁环
    for s in (1, -1):
        pts = []
        for i in range(10):
            u = i / 9
            y = 9.4 + u * 4.0
            c, t, r, b = frame(y)
            a = math.radians(-90 + s * (-70 + 140 * u))     # 从一侧腰绕过胸前到另一侧肩
            pts.append(c + (x_axis * math.cos(a) * (r * 1.05 + 0.4) + b * math.sin(a) * (r + 0.36)))
        p.tube(pts, 0.13, "leather", seg=6)
    c, t, r, b = frame(9.0)
    p.tube([c + (x_axis * math.cos(a) * (r * 1.05 + 0.4) + b * math.sin(a) * (r + 0.36)) for a in
            [2 * math.pi * k / 16 for k in range(17)]], 0.15, "leather", seg=6)            # 腰带
    ring = []
    for k in range(13):
        a = 2 * math.pi * k / 12
        ring.append(RING + V(math.cos(a) * 0.35, math.sin(a) * 0.35, 0))
    p.tube(ring, 0.07, "iron", seg=6)
    # 帆布裤：大腿和小腿套着管子，膝盖前面撑破一个洞，裤脚到踝上面，参差
    for s in (1, -1):
        leg = [V(s * 1.0, 8.6, 0.0), V(s * 1.12, 6.9, 0.75), V(s * 1.25, 5.6, 1.5), V(s * 1.2, 4.0, 0.2), V(s * 1.15, 2.9, -0.7)]

        def knee_hole(i, k, rr, leg=leg):
            if i != 2:
                return False
            d = p.verts[rr[i][k]] - leg[i]
            return d.z > 0.35 and abs(d.x) < 0.3
        p.tube(leg, [1.0, 0.75, 0.66, 0.5, 0.45], "canvas", seg=12, skip=knee_hole, ragged=0.45, rng=rnd)
    # 绷带：小臂靠手腕一截、脚踝，一圈圈斜着缠
    for s in (1, -1):
        for a, b2, r in ((V(s * 2.4, 9.4, 2.6), V(s * 2.2, 7.0, 3.3), 0.31), (V(s * 1.15, 2.9, -0.8), V(s * 1.15, 1.4, -0.4), 0.38)):
            for k in range(6):
                u = k / 5
                q = a.lerp(b2, u)
                d = (b2 - a).normalized()
                tilt = Matrix.Rotation(0.35 * (1 if k % 2 else -1), 3, V(1, 0, 0).cross(d).normalized() if abs(d.x) < 0.9 else V(0, 0, 1))
                ring = [q + tilt @ ((V(1, 0, 0) * math.cos(2 * math.pi * j / 10) + d.cross(V(1, 0, 0)).normalized() * math.sin(2 * math.pi * j / 10)) * r)
                        for j in range(11)]
                p.tube(ring, 0.06, "bandage", seg=5)
    return p.build()


# ---------- 锅炉罩：头整个焊在里面 ----------

def helmet():
    p = Part("hauler_helmet")
    a = V(0, -0.42, 1).normalized()                         # 罐子的轴：顺着脖子往前下
    c0 = V(0, 12.95, 5.0)                                   # 罐底，脖子从这里插进去
    L, R = 1.9, 1.05
    x = V(1, 0, 0)
    up = a.cross(x).normalized()
    if up.y < 0:
        up = -up

    def around(c, n, r, k=24):
        nx = V(1, 0, 0)
        nu = n.cross(nx).normalized()
        return [c + (nx * math.cos(2 * math.pi * i / k) + nu * math.sin(2 * math.pi * i / k)) * r for i in range(k + 1)]

    # 罐身 + 前头的圆顶（截面一圈圈往前收）
    prof = [(0.0, 0.62), (0.02, 0.95), (0.12, R), (L, R)] + [(L + 0.75 * math.sin(t * math.pi / 2), R * math.cos(t * math.pi / 2) + 0.001)
                                                              for t in (0.2, 0.4, 0.6, 0.8, 1.0)]
    p.tube([c0 + a * d for d, r in prof], [r for d, r in prof], "iron", seg=28, caps=True)
    # 罐底的法兰：一圈厚铁边，皮肉被铁边磨得从里面翻出来
    p.tube([c0 + a * 0.02, c0 + a * 0.18], [1.14, 1.14], "iron", seg=28, caps=True)
    p.tube([c0 - a * 0.25, c0 + a * 0.05], [0.58, 0.7], "skin", seg=16)
    # 三道铁箍，每道一圈铆钉
    for d in (0.1, 0.95, L - 0.05):
        p.tube([c0 + a * (d - 0.07), c0 + a * (d + 0.07)], [R + 0.05, R + 0.05], "iron", seg=28, caps=True)
        for k in range(18):
            ang = 2 * math.pi * k / 18
            p.ellipsoid(c0 + a * d + (x * math.cos(ang) + up * math.sin(ang)) * (R + 0.07), (0.06, 0.06, 0.06), "iron", seg=6, rings=4)
    for k in range(9):                                      # 侧面一条焊缝
        p.ellipsoid(c0 + a * (0.2 + k * 0.2) + x * (R + 0.02), (0.05, 0.05, 0.05), "iron", seg=6, rings=4)
    # 观察窗：圆顶前脸上，铜框里一块发绿、糊满污垢的玻璃
    t = math.radians(55)
    wn = (a * math.sin(t) + up * math.cos(t)).normalized()
    wc = c0 + a * (L + 0.75 * math.sin(t)) + up * (R * math.cos(t)) + wn * 0.03
    p.tube(around(wc, wn, 0.34), 0.07, "brass", seg=8)
    p.tube([wc - wn * 0.1, wc + wn * 0.03], [0.3, 0.3], "glass", seg=20, caps=True)
    for i, q in enumerate(around(wc + wn * 0.02, wn, 0.42, 6)[:6]):
        p.ellipsoid(q, (0.05, 0.05, 0.05), "brass", seg=6, rings=4)
    # 顶上一截弯掉的排气管、侧面一个碎了表盘的压力表
    t0 = c0 + a * 0.9 + up * (R - 0.05)
    p.tube([t0, t0 + up * 0.55 - a * 0.15, t0 + up * 0.7 - a * 0.45], [0.2, 0.2, 0.2], "iron", seg=10, caps=True)
    gc = c0 + a * 1.35 - x * (R + 0.12) + up * 0.2
    p.tube([gc + x * 0.12, gc - x * 0.08], [0.24, 0.24], "brass", seg=14, caps=True)
    p.tube([gc - x * 0.08, gc - x * 0.1], [0.2, 0.2], "bandage", seg=14, caps=True)
    return p.build()


# ---------- 骨骼和权重 ----------

def seg_dist(q, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (q - a).dot(ab) / ab.length_squared))
    return (a + ab * t - q).length


def rig(objs, rigid=()):
    """objs 按离骨头远近分权重；rigid 里的整块绑在 head 上"""
    arm = bpy.data.armatures.new("hauler_rig")
    ao = bpy.data.objects.new("hauler_rig", arm)
    bpy.context.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    for name, h, t, parent in BONES:
        eb = arm.edit_bones.new(name)
        eb.head = B(h)
        eb.tail = B(t)
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    segs = [(name, h, t) for name, h, t, parent in BONES if name != "ring"]
    for o in objs:
        groups = {name: o.vertex_groups.new(name=name) for name, h, t in segs}
        o.vertex_groups.new(name="ring")
        if o in rigid:
            groups["head"].add([v.index for v in o.data.vertices], 1.0, "REPLACE")
            o.parent = ao
            o.modifiers.new("Armature", "ARMATURE").object = ao
            continue
        for v in o.data.vertices:
            g = Vector((v.co.x, v.co.z, -v.co.y))            # Blender → Godot
            ds = sorted(((seg_dist(g, h, t), name) for name, h, t in segs))
            d0, n0 = ds[0]
            d1, n1 = ds[1]
            w0 = 1.0 / (d0 + 0.05) ** 4
            w1 = 1.0 / (d1 + 0.05) ** 4
            # 离得差不多的两根骨头之间才混合（关节处），不然只跟最近的那根
            if d1 - d0 > 0.6:
                w1 = 0.0
            tot = w0 + w1
            groups[n0].add([v.index], w0 / tot, "REPLACE")
            if w1 > 0:
                groups[n1].add([v.index], w1 / tot, "ADD")
        o.parent = ao
        m = o.modifiers.new("Armature", "ARMATURE")
        m.object = ao
    return ao


# ---------- 铁板、链子 ----------

def plate():
    p = Part("hauler_plate")
    hx, hz = 2.2, 1.8
    q = [V(-hx, 0.35, 0.0), V(hx, 0.35, 0.0), V(hx, 0.1, -2 * hz), V(-hx, 0.1, -2 * hz)]
    top = [p.v(x + V(0, 0.18, 0)) for x in q]
    bot = [p.v(x) for x in q]
    p.f(top, "iron", False)
    p.f(list(reversed(bot)), "iron", False)
    for i in range(4):
        p.f([bot[i], bot[(i + 1) % 4], top[(i + 1) % 4], top[i]], "iron", False)
    for k in range(6):
        p.ellipsoid(V(-1.8 + k * 0.72, 0.56, -0.3), (0.09, 0.06, 0.09), "iron", seg=6, rings=4)
    p.tube([V(-0.3, 0.5, 0.05), V(0, 0.85, 0.2), V(0.3, 0.5, 0.05)], 0.08, "iron", seg=6)
    return p.build()


def chain():
    p = Part("hauler_chain")
    for i in range(32):
        z = 0.125 + i * 0.25
        rot = Matrix.Rotation(math.pi / 2 if i % 2 else 0.0, 3, "Z")
        ring = [V(0, 0, z) + rot @ V(0.1 * math.cos(2 * math.pi * k / 8), 0.0, 0.16 * math.sin(2 * math.pi * k / 8)) for k in range(9)]
        p.tube(ring, 0.045, "iron", seg=5)
    return p.build()


def preview(out_dir):
    world = bpy.data.worlds.new("fog")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.22, 0.25, 1.0)
    bpy.context.scene.world = world
    for name, rot, e in (("key", (55, 0, 40), 2.5), ("rim", (60, 0, 200), 3.5)):
        sun = bpy.data.lights.new(name, "SUN")
        sun.energy = e
        o = bpy.data.objects.new(name, sun)
        o.rotation_euler = tuple(math.radians(a) for a in rot)
        bpy.context.collection.objects.link(o)
    ground = Part("ground")
    ground.ellipsoid(V(0, -0.5, 0), (40, 0.5, 40), "canvas", seg=8, rings=4)
    ground.build()
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1100
    sc.render.resolution_y = 1300
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 40
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (17.0, -17.0, 8.0)
    cam.rotation_euler = (Vector((0, -2, 7.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "creatures_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "creatures.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for s in SLOTS:
        m = bpy.data.materials.new(s)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*COLORS[s], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6 if s in ("skin", "iron", "brass") else 0.95
    skin = body()
    cloth = clothes()
    helm = helmet()
    ao = rig([skin, cloth, helm], rigid=(helm,))
    pl = plate()
    ch = chain()
    print("faces", sum(len(o.data.polygons) for o in (skin, cloth, helm)))
    bpy.ops.object.select_all(action="DESELECT")
    for o in (ao, skin, cloth, helm, pl, ch):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_normals=True, export_skins=True, export_animations=False)
    print("exported", out)
    if len(argv) > 1:
        # 预览里摆成游戏里的样子：铁板拖在身后，链子从铁板的环拉到挽具背后的铁环
        pl.location = B(V(1.0, 0.0, -9.0))
        hook = V(1.0, 0.7, -9.0)
        d = B(RING) - B(hook)
        ch.location = B(hook)
        ch.rotation_mode = "QUATERNION"
        ch.rotation_quaternion = Vector((0, -1, 0)).rotation_difference(d.normalized())
        ch.scale = (1.4, d.length / 8.0, 1.4)
        preview(argv[1])


main()
