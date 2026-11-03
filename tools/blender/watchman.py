# 追人的怪物：守夜人（原创造型，不参考任何影视、游戏角色），按参数生成，导出成 assets/models/watchman.glb。
# 瘦高的人形（约 2.8 米），胳膊长得垂过膝盖、手指又细又长；头是一只铁笼提灯，没有脸，笼里一团冷白的火，
# 玻璃熏黑、碎了一块；穿深灰绿的长大衣（下摆撕烂）、肩上一件短披肩、一排铜扣，小腿缠着绷带，左手拎着一大串长钥匙。
#
# 身体用蒙皮修改器（Skin）长出一整块；衣服是贴着身体的单层布（游戏里双面画）。一副骨骼（watchman_rig）：
# 身体、袖子按离哪根骨头近来分权重；大衣下摆在两条大腿和骨盆之间按左右平滑分；提灯整块绑在 head 上，钥匙串绑在 hand_l 上。
# 走路的动作在游戏里按骨骼摆（scripts/watchman.gd）。
# 材质槽：skin、coat、cape、leather、iron、brass、glass、flame、bandage。
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/watchman.py -- assets/models/watchman.glb [预览图目录]
#
# 坐标约定和 creatures.py 一样：脚本里按 Godot 写（y 向上，+z 是它面朝的方向，+x 是它的左手边），落到 Blender 时换成 (x, -z, y)。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SLOTS = ["skin", "coat", "cape", "leather", "iron", "brass", "glass", "flame", "bandage"]
COLORS = {"skin": (0.42, 0.4, 0.36), "coat": (0.12, 0.13, 0.1), "cape": (0.09, 0.095, 0.08),
          "leather": (0.08, 0.055, 0.04), "iron": (0.08, 0.065, 0.055), "brass": (0.4, 0.29, 0.11),
          "glass": (0.2, 0.22, 0.2), "flame": (0.8, 0.9, 1.0), "bandage": (0.5, 0.46, 0.36)}


def V(x, y, z):
    return Vector((x, y, z))


def B(p):
    """Godot 坐标 → Blender 坐标"""
    return Vector((p.x, -p.z, p.y))


# ---------- 骨架：每根骨头（名字、起点、终点、父骨），Godot 坐标 ----------

LANTERN = V(0, 2.78, 0.1)                    # 提灯笼子的中心
LEAN = Matrix.Rotation(math.radians(14), 3, "X")   # 提灯往前探
KEYS = V(0.43, 0.62, 0.09)                   # 钥匙串的铁环
BONES = [
    ("hips", V(0, 1.4, -0.02), V(0, 1.75, 0.0), None), ("spine", V(0, 1.75, 0.0), V(0, 2.1, 0.02), "hips"),
    ("chest", V(0, 2.1, 0.02), V(0, 2.38, 0.0), "spine"), ("neck", V(0, 2.38, 0.0), V(0, 2.55, 0.06), "chest"),
    ("head", V(0, 2.55, 0.06), LANTERN + LEAN @ V(0, 0.35, 0), "neck"),
]
for side, s in (("l", 1), ("r", -1)):
    BONES += [
        ("thigh_" + side, V(s * 0.12, 1.36, -0.02), V(s * 0.14, 0.76, 0.06), "hips"),
        ("shin_" + side, V(s * 0.14, 0.76, 0.06), V(s * 0.14, 0.1, -0.04), "thigh_" + side),
        ("foot_" + side, V(s * 0.14, 0.1, -0.04), V(s * 0.14, 0.035, 0.16), "shin_" + side),
        ("upperarm_" + side, V(s * 0.27, 2.2, -0.02), V(s * 0.38, 1.62, -0.05), "chest"),
        ("forearm_" + side, V(s * 0.38, 1.62, -0.05), V(s * 0.42, 1.05, 0.0), "upperarm_" + side),
        ("hand_" + side, V(s * 0.42, 1.05, 0.0), V(s * 0.43, 0.6, 0.07), "forearm_" + side),
    ]


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

    def tube(self, pts, radii, slot, seg=10, ragged=0.0, rng=None, caps=False, smooth=True):
        """沿折线一根管子；半径可以是 (左右, 前后) 的椭圆；ragged 让末端一圈参差（撕烂的下摆）"""
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
            rx, rz = r if isinstance(r, (list, tuple)) else (r, r)
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                q = p + nn * math.cos(a) * rx + b * math.sin(a) * rz
                if i == n - 1 and ragged > 0 and rng:
                    q += t * rng() * ragged
                ring.append(self.v(q))
            rings.append(ring)
        for i in range(n - 1):
            for k in range(seg):
                a, c = rings[i], rings[i + 1]
                self.f([a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]], slot, smooth)
        if caps:
            self.f(list(reversed(rings[0])), slot, smooth)
            self.f(rings[-1], slot, smooth)
        return rings

    def ellipsoid(self, c, radii, slot, rot=None, seg=12, rings=8, skip=None):
        """椭球；skip(p) 为真的面不要（碎掉的玻璃）"""
        rot = rot or Matrix.Identity(3)
        c = Vector(c)
        top = self.v(c + rot @ V(0, radii[1], 0))
        bot = self.v(c + rot @ V(0, -radii[1], 0))
        grid = []
        for j in range(1, rings):
            a = math.pi * j / rings
            grid.append([self.v(c + rot @ V(math.sin(a) * math.cos(2 * math.pi * k / seg) * radii[0], math.cos(a) * radii[1],
                                            math.sin(a) * math.sin(2 * math.pi * k / seg) * radii[2])) for k in range(seg)])

        def face(idx):
            if skip and skip(sum((self.verts[i] for i in idx), Vector()) / len(idx)):
                return
            self.f(idx, slot)
        for k in range(seg):
            face([top, grid[0][(k + 1) % seg], grid[0][k]])
            face([bot, grid[-1][k], grid[-1][(k + 1) % seg]])
        for j in range(len(grid) - 1):
            a, b = grid[j], grid[j + 1]
            for k in range(seg):
                face([a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]])

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


# ---------- 身体：蒙皮修改器长出又瘦又长的人形 ----------

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

    pelvis, _ = chain([(V(0, 1.4, -0.02), 0.15), (V(0, 1.75, 0.0), 0.12), (V(0, 2.1, 0.02), 0.17), (V(0, 2.38, 0.0), 0.07),
                       (V(0, 2.55, 0.06), 0.05), (LANTERN + LEAN @ V(0, -0.27, 0), 0.06)])
    chest = pelvis + 2
    for s in (1, -1):
        chain([(V(s * 0.12, 1.36, -0.02), 0.1), (V(s * 0.14, 0.76, 0.06), 0.065), (V(s * 0.14, 0.1, -0.04), 0.045),
               (V(s * 0.14, 0.035, 0.16), 0.04)], pelvis)
        _, wrist = chain([(V(s * 0.27, 2.2, -0.02), 0.075), (V(s * 0.38, 1.62, -0.05), 0.045),
                          (V(s * 0.42, 1.05, 0.05 if s < 0 else 0.0), 0.035), (V(s * 0.43, 0.93, 0.07), 0.045)], chest)
        for k in range(4):                                       # 四根又细又长的指头
            x = s * 0.43 + (k - 1.5) * 0.02
            chain([(V(x, 0.9, 0.08), 0.012), (V(x * 1.01, 0.72, 0.1), 0.009), (V(x * 1.02, 0.6, 0.06), 0.005)], wrist)

    mesh = bpy.data.meshes.new("watchman_body")
    mesh.from_pydata([B(p) for p, r in pts], edges, [])
    obj = bpy.data.objects.new("watchman_body", mesh)
    bpy.context.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    for i, (p, r) in enumerate(pts):
        mesh.skin_vertices[0].data[i].radius = (r, r)
    mesh.skin_vertices[0].data[pelvis].use_root = True
    obj.modifiers.new("Sub", "SUBSURF").levels = 2
    tex = bpy.data.textures.new("wrinkle", "CLOUDS")
    tex.noise_scale = 0.08
    d = obj.modifiers.new("wrinkle", "DISPLACE")
    d.texture = tex
    d.strength = 0.012
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
    p = Part("watchman_cloth")
    rnd = Rand(5)
    # 长大衣：从肩到小腿，往下越来越宽，下摆撕烂
    p.tube([V(0, 2.32, 0.0), V(0, 2.15, 0.0), V(0, 1.8, -0.01), V(0, 1.42, -0.02), V(0, 1.0, -0.02), V(0, 0.42, -0.03)],
           [(0.2, 0.15), (0.29, 0.19), (0.24, 0.17), (0.24, 0.2), (0.3, 0.26), (0.38, 0.33)], "coat", seg=24, ragged=0.12, rng=rnd)
    # 肩上的短披肩
    p.tube([V(0, 2.42, 0.0), V(0, 2.3, 0.0), V(0, 2.1, 0.0), V(0, 1.88, -0.01)],
           [(0.12, 0.1), (0.3, 0.22), (0.4, 0.3), (0.44, 0.34)], "cape", seg=24, ragged=0.08, rng=rnd)
    for s in (1, -1):
        # 袖子到小臂中间
        p.tube([V(s * 0.27, 2.2, -0.02), V(s * 0.38, 1.62, -0.05), V(s * 0.41, 1.3, -0.02)], [0.09, 0.075, 0.08], "coat",
               seg=12, ragged=0.05, rng=rnd)
        for k in range(6):                                       # 小腿上缠的绷带
            y = 0.2 + k * 0.08
            p.tube([V(s * 0.14, y - 0.02, -0.02 - 0.015 * (k % 2)), V(s * 0.14, y + 0.02, -0.02)], [0.058, 0.058], "bandage", seg=10)
    # 腰带、前襟一排铜扣
    p.tube([V(0, 1.47, -0.02), V(0, 1.53, -0.02)], [(0.255, 0.215), (0.255, 0.215)], "leather", seg=24)
    for k in range(6):
        y = 2.05 - k * 0.11
        p.ellipsoid(V(0, y, 0.165 + 0.01 * (k > 3)), (0.018, 0.018, 0.012), "brass", seg=8, rings=4)
    return p.build()


def lantern():
    """头：铁笼提灯。脖子长进笼底的铁圈里；笼里一团冷白的火，熏黑的玻璃碎了一块"""
    p = Part("watchman_lantern")

    def H(q):
        return LANTERN + LEAN @ Vector(q)

    p.tube([H((0, -0.3, 0)), H((0, -0.24, 0))], 0.085, "skin", seg=12)                     # 被铁圈勒得鼓出来的脖子
    p.tube([H((0, -0.27, 0)), H((0, -0.21, 0))], 0.19, "iron", seg=24, caps=True, smooth=False)
    p.tube([H((0, 0.21, 0)), H((0, 0.26, 0))], 0.17, "iron", seg=24, caps=True, smooth=False)
    p.tube([H((0, 0.26, 0)), H((0, 0.34, 0)), H((0, 0.4, 0)), H((0, 0.42, 0))], [0.18, 0.12, 0.05, 0.02], "iron", seg=24,
           caps=True)
    p.tube([H((0.07 * math.cos(a), 0.42 + 0.07 * math.sin(a), 0)) for a in (math.pi * k / 12 for k in range(13))],
           0.012, "iron", seg=6)                                                            # 顶上的提环
    for k in range(8):                                                                      # 八根笼条，中间往外鼓
        a = 2 * math.pi * k / 8
        p.tube([H((r * math.cos(a), y, r * math.sin(a))) for y, r in ((-0.21, 0.17), (-0.1, 0.205), (0.0, 0.215), (0.1, 0.205),
                                                                     (0.21, 0.16))], 0.012, "iron", seg=6)
    p.ellipsoid(LANTERN, (0.195, 0.23, 0.195), "glass", LEAN, seg=24, rings=12,
                skip=lambda q: (LEAN.inverted() @ (q - LANTERN)).z > 0.12 and 0.0 < (LEAN.inverted() @ (q - LANTERN)).y < 0.12
                and (LEAN.inverted() @ (q - LANTERN)).x > -0.02)
    # 火：往上拉长、歪向一边的一团
    p.tube([H((0.4 * (y + 0.08) ** 2, y, 0)) for y in (-0.08, -0.06, -0.02, 0.03, 0.08, 0.13)],
           [0.01, 0.035, 0.05, 0.045, 0.03, 0.01], "flame", seg=12, caps=True)
    return p.build()


def keys():
    """左手拎着的一大串钥匙：一只铁环挂着十几把长钥匙"""
    p = Part("watchman_keys")
    rnd = Rand(11)
    p.tube([KEYS + V(0, 0.08 * math.sin(a), 0.08 * math.cos(a)) for a in (2 * math.pi * k / 24 for k in range(25))], 0.008, "iron", seg=6)
    for k in range(13):
        a = math.pi * (1.15 + 0.7 * k / 12)
        top = KEYS + V(0, 0.08 * math.sin(a), 0.08 * math.cos(a))
        d = V((rnd() - 0.5) * 0.4, -1, math.cos(a) * 0.4 + (rnd() - 0.5) * 0.3).normalized()
        ln = 0.14 + rnd() * 0.1
        slot = "brass" if k % 3 == 0 else "iron"
        p.tube([top, top + d * ln], [0.006, 0.005], slot, seg=6, caps=True)
        p.tube([top + d * ln * 0.75, top + d * ln * 0.75 + V(0.03, 0, 0)], 0.008, slot, seg=5, caps=True)    # 齿
        p.ellipsoid(top + d * 0.025, (0.018, 0.018, 0.006), slot, seg=8, rings=4)                              # 柄
    return p.build()


# ---------- 骨骼和权重 ----------

def seg_dist(q, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (q - a).dot(ab) / ab.length_squared))
    return (a + ab * t - q).length


def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def rig(objs, rigid):
    """objs 按离骨头远近分权重（大衣下摆另算）；rigid 是 {物体: 骨头}，整块绑在那根骨头上"""
    arm = bpy.data.armatures.new("watchman_rig")
    ao = bpy.data.objects.new("watchman_rig", arm)
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
    segs = [(name, h, t) for name, h, t, parent in BONES]
    for o in list(objs) + list(rigid):
        groups = {name: o.vertex_groups.new(name=name) for name, h, t in segs}
        o.parent = ao
        o.modifiers.new("Armature", "ARMATURE").object = ao
        if o in rigid:
            groups[rigid[o]].add([v.index for v in o.data.vertices], 1.0, "REPLACE")
            continue
        coat = {i for p in o.data.polygons if p.material_index == SLOTS.index("coat") for i in p.vertices}
        for v in o.data.vertices:
            g = Vector((v.co.x, v.co.z, -v.co.y))            # Blender → Godot
            if v.index in coat and g.y < 1.4 and abs(g.x) < 0.26 + (1.4 - g.y) * 0.15:
                # 大衣下摆：在骨盆和两条大腿之间按左右平滑分，越往下跟腿越多，不会被两条腿撕开
                leg = smooth(1.4, 0.7, g.y) * 0.6
                left = smooth(-0.2, 0.2, g.x)
                groups["hips"].add([v.index], 1.0 - leg, "REPLACE")
                groups["thigh_l"].add([v.index], leg * left, "REPLACE")
                groups["thigh_r"].add([v.index], leg * (1 - left), "REPLACE")
                continue
            ds = sorted(((seg_dist(g, h, t), name) for name, h, t in segs))
            d0, n0 = ds[0]
            d1, n1 = ds[1]
            w0 = 1.0 / (d0 + 0.01) ** 4
            w1 = 1.0 / (d1 + 0.01) ** 4
            if d1 - d0 > 0.06:                                # 离得差不多的两根骨头之间才混合（关节处）
                w1 = 0.0
            tot = w0 + w1
            groups[n0].add([v.index], w0 / tot, "REPLACE")
            if w1 > 0:
                groups[n1].add([v.index], w1 / tot, "ADD")
    return ao


# ---------- 预览 ----------

def preview(out_dir):
    world = bpy.data.worlds.new("fog")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.22, 0.25, 1.0)
    bpy.context.scene.world = world
    for name, rot, e in (("key", (55, 0, 30), 3.0), ("rim", (60, 0, 200), 3.5)):
        sun = bpy.data.lights.new(name, "SUN")
        sun.energy = e
        o = bpy.data.objects.new(name, sun)
        o.rotation_euler = tuple(math.radians(a) for a in rot)
        bpy.context.collection.objects.link(o)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1200
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (2.6, -4.6, 1.9)
    cam.rotation_euler = (Vector((0, 0, 1.55)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "watchman_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "watchman.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for s in SLOTS:
        m = bpy.data.materials.new(s)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*COLORS[s], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6 if s in ("skin", "iron", "brass") else 0.2 if s == "glass" else 0.95
        if s == "flame":
            bsdf.inputs["Emission Color"].default_value = (*COLORS[s], 1.0)
            bsdf.inputs["Emission Strength"].default_value = 8.0
    sk = body()
    cl = clothes()
    ln = lantern()
    ks = keys()
    ao = rig([sk, cl], {ln: "head", ks: "hand_l"})
    print("faces", sum(len(o.data.polygons) for o in (sk, cl, ln, ks)))
    bpy.ops.object.select_all(action="DESELECT")
    for o in (ao, sk, cl, ln, ks):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_normals=True, export_skins=True, export_animations=False)
    print("exported", out)
    if len(argv) > 1:
        preview(argv[1])


main()
