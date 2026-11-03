# 迷宫里的东西（原创造型，不参考任何影视角色），按参数生成，导出成 assets/models/creatures.glb。
# 目前一种：拖链者——比墙还高的佝偻巨影，裹着破布、头埋在兜帽里看不见脸，一只手拖着链子和一块锈铁板。
# 拆成几件，游戏里用代码摆动（scripts/hauler.gd）：
#   hauler_body（骨盆、躯干、肩、兜帽、破布）原点在两髋中间；hauler_leg 原点在髋关节；hauler_arm 原点在肩关节；
#   hauler_plate 原点在铁板前沿拴链子的地方（地面上）；hauler_chain 一条 8 米长的链子，沿 +z，游戏里按长短缩放。
# 材质槽：skin（发灰的皮）、rag（破布）、iron（锈铁）、dark（兜帽里的黑）。
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/creatures.py -- assets/models/creatures.glb [预览图目录]
#
# 坐标约定：脚本里按 Godot 写（y 向上，+z 是它面朝、往前走的方向），落到 Blender 时换成 (x, -z, y)。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SLOTS = ["skin", "rag", "iron", "dark"]
COLORS = {"skin": (0.09, 0.08, 0.075), "rag": (0.11, 0.095, 0.08), "iron": (0.17, 0.1, 0.06), "dark": (0.005, 0.005, 0.006)}

HIP = 6.0            # 髋关节离地多高（米）：站直约 14 米，比层内的墙（8～11 米）高出一截
SHOULDER = V = None


def V(x, y, z):
    return Vector((x, y, z))


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

    def sweep(self, pts, radii, slot, seg=8, flat=1.0, caps=True):
        """沿折线扫一根粗细渐变的管子；flat < 1 时截面压扁（做布条）"""
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
            rings.append([self.v(p + (nn * math.cos(2 * math.pi * k / seg) * r + b * math.sin(2 * math.pi * k / seg) * r * flat))
                          for k in range(seg)])
        for i in range(n - 1):
            a, c = rings[i], rings[i + 1]
            for k in range(seg):
                self.f([a[k], a[(k + 1) % seg], c[(k + 1) % seg], c[k]], slot)
        if caps:
            self.f(list(reversed(rings[0])), slot)
            self.f(rings[-1], slot)

    def ellipsoid(self, c, radii, slot, rot=None, seg=12, rings=8):
        rot = rot or Matrix.Identity(3)
        c = Vector(c)
        top = self.v(c + rot @ V(0, radii[1], 0))
        bot = self.v(c + rot @ V(0, -radii[1], 0))
        grid = []
        for j in range(1, rings):
            a = math.pi * j / rings
            y = math.cos(a)
            r = math.sin(a)
            grid.append([self.v(c + rot @ V(r * math.cos(2 * math.pi * k / seg) * radii[0], y * radii[1],
                                            r * math.sin(2 * math.pi * k / seg) * radii[2])) for k in range(seg)])
        for k in range(seg):
            self.f([top, grid[0][(k + 1) % seg], grid[0][k]], slot)
            self.f([bot, grid[-1][k], grid[-1][(k + 1) % seg]], slot)
        for j in range(len(grid) - 1):
            a, b = grid[j], grid[j + 1]
            for k in range(seg):
                self.f([a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]], slot)

    def box(self, c, size, slot, rot=None):
        rot = rot or Matrix.Identity(3)
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        ids = [self.v(Vector(c) + rot @ V(sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.f([ids[i] for i in q], slot, False)

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


# 身上几个关节的位置（相对两髋中间），hauler.gd 里有同样的数
SHOULDER_X = 1.7
SHOULDER = V(0, 3.9, 1.6)
HIP_X = 0.8


def body():
    p = Part("hauler_body")
    p.ellipsoid(V(0, 0.1, 0), (1.15, 0.75, 0.85), "skin")                                  # 骨盆
    # 往前塌的躯干：几段椭球连起来，越往上越往前
    for c, r, tilt in ((V(0, 1.2, 0.35), (1.0, 1.1, 0.8), 0.25), (V(0, 2.4, 0.9), (1.2, 1.1, 0.9), 0.45),
                       (V(0, 3.5, 1.45), (1.55, 0.85, 1.0), 0.6)):
        p.ellipsoid(c, r, "skin", rx(tilt))
    # 背上一节节凸起的脊骨
    for k in range(7):
        t = k / 6
        p.ellipsoid(V(0, 0.8 + t * 3.0, 0.1 + t * 1.0 - 0.75 - 0.15 * math.sin(t * math.pi)), (0.18, 0.2, 0.16), "skin")
    # 两肩：被斗篷盖住，只留一点隆起
    for s in (-1, 1):
        p.ellipsoid(SHOULDER + V(s * SHOULDER_X, 0.05, 0), (0.7, 0.55, 0.7), "skin")
    # 斗篷：从肩上一圈披下来，一条条破布围成一圈，往下微微张开，下摆参差，垂到小腿
    for k in range(26):
        a = 2 * math.pi * k / 26
        sx, sz = math.sin(a), math.cos(a)
        top = SHOULDER + V(sx * 1.9, 0.35 - 0.25 * abs(sz), sz * 1.25 - 0.2)
        length = 7.2 + 1.4 * abs(math.sin(k * 2.7)) - (1.6 if sz > 0.7 else 0.0)   # 前襟短一点，露出腿
        flare = 0.55
        pts = [top + V(sx * flare * (i / 6) ** 1.5, -length * i / 6, sz * flare * (i / 6) ** 1.5 - 0.25 * (i / 6)) for i in range(7)]
        p.sweep(pts, [0.42, 0.44, 0.45, 0.45, 0.42, 0.34, 0.12], "rag", seg=6, flat=0.16)
    # 兜帽：一个很大的、往前低垂的罩子，后面拖一个尖，里面黑洞洞的看不见脸
    hood_c = V(0, 3.9, 2.45)
    p.ellipsoid(hood_c, (0.95, 1.05, 1.15), "rag", rx(1.0))
    p.sweep([hood_c + V(0, 0.6, -0.6), hood_c + V(0, 0.4, -1.4), hood_c + V(0, -0.3, -1.9)], [0.6, 0.35, 0.08], "rag", seg=8)
    p.ellipsoid(hood_c + V(0, -0.35, 0.75), (0.6, 0.7, 0.15), "dark", rx(1.0))
    # 腰上一圈破布
    for k in range(12):
        a = 2 * math.pi * k / 12
        top = V(math.sin(a) * 1.1, 0.4, math.cos(a) * 0.9)
        length = 2.2 + 1.3 * abs(math.sin(k * 1.7))
        pts = [top + V(math.sin(a) * 0.15 * i, -length * i / 4, math.cos(a) * 0.12 * i) for i in range(5)]
        p.sweep(pts, [0.3, 0.28, 0.24, 0.18, 0.06], "rag", seg=6, flat=0.2)
    return p.build()


def leg():
    """一条腿：大腿、膝、细长的小腿、扁平的脚；原点在髋关节，往下伸到地面（-HIP）"""
    p = Part("hauler_leg")
    knee = V(0, -2.9, 0.4)
    ankle = V(0, -HIP + 0.3, -0.05)
    p.sweep([V(0, 0, 0), V(0, -1.4, 0.25), knee], [0.42, 0.36, 0.28], "skin", seg=10)
    p.ellipsoid(knee, (0.3, 0.32, 0.3), "skin")
    p.sweep([knee, V(0, -4.3, 0.2), ankle], [0.27, 0.2, 0.16], "skin", seg=10)
    p.ellipsoid(ankle + V(0, -0.12, 0.35), (0.32, 0.16, 0.6), "skin")
    for k in range(3):                                                                     # 脚上缠的破布
        p.sweep([ankle + V(0, 0.9 - k * 0.3, 0), ankle + V(0.05, 0.6 - k * 0.3, 0.05)], 0.24, "rag", seg=8, flat=0.9)
    return p.build()


def arm():
    """一条胳膊：长得过分，垂到膝盖；手指细长、往里勾；原点在肩关节"""
    p = Part("hauler_arm")
    elbow = V(0, -2.8, 0.5)
    wrist = V(0, -5.4, 0.9)
    p.sweep([V(0, 0, 0), V(0, -1.4, 0.2), elbow], [0.4, 0.34, 0.26], "skin", seg=8)
    p.ellipsoid(elbow, (0.22, 0.24, 0.22), "skin")
    p.sweep([elbow, V(0, -4.1, 0.75), wrist], [0.25, 0.2, 0.15], "skin", seg=8)
    p.ellipsoid(wrist + V(0, -0.25, 0.05), (0.2, 0.3, 0.12), "skin")
    for k in range(4):
        x = -0.15 + k * 0.1
        p.sweep([wrist + V(x, -0.45, 0.05), wrist + V(x * 1.2, -1.0, 0.15), wrist + V(x * 1.2, -1.35, -0.05)],
                [0.05, 0.04, 0.02], "skin", seg=5)
    p.sweep([V(0, -0.2, 0), V(0.03, -1.8, 0.2), V(0.05, -3.2, 0.55)], [0.55, 0.5, 0.42], "rag", seg=8, flat=0.95)   # 破袖子
    return p.build()


def plate():
    """锈铁板：前沿翘起一点贴着地拖，前沿中间一个拴链子的铁环；原点在铁环（地面上）"""
    p = Part("hauler_plate")
    p.box(V(0, 0.25, -1.4), (3.4, 0.14, 2.8), "iron", rx(-0.12))
    for k in range(5):                                                                     # 铆钉一排
        p.ellipsoid(V(-1.4 + k * 0.7, 0.42, -0.2), (0.07, 0.05, 0.07), "iron", seg=6, rings=4)
    p.sweep([V(-0.25, 0.4, 0.0), V(0, 0.65, 0.15), V(0.25, 0.4, 0.0)], 0.06, "iron", seg=6)
    return p.build()


def chain():
    """一条 8 米长的链子，从原点沿 +z；一节一节，相邻两节转 90°"""
    p = Part("hauler_chain")
    for i in range(32):
        z = 0.125 + i * 0.25
        rot = Matrix.Rotation(math.pi / 2 if i % 2 else 0.0, 3, "Z")
        ring = [V(0, 0, z) + rot @ V(0.08 * math.cos(2 * math.pi * k / 8), 0.0, 0.15 * math.sin(2 * math.pi * k / 8)) for k in range(8)]
        p.sweep(ring + [ring[0]], 0.035, "iron", seg=5, caps=False)
    return p.build()


def preview(objs, out_dir):
    world = bpy.data.worlds.new("fog")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.27, 0.3, 1.0)
    bpy.context.scene.world = world
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = 2.0
    o = bpy.data.objects.new("key", sun)
    o.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.collection.objects.link(o)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1200
    sc.render.resolution_y = 1200
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (22.0, -20.0, 7.0)
    cam.rotation_euler = (Vector((0, 0, 6.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
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
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COLORS[s], 1.0)
    objs = {"body": body(), "leg": leg(), "arm": arm(), "plate": plate(), "chain": chain()}
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs.values():
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_normals=True)
    print("exported", out)
    if len(argv) > 1:
        # 预览：按游戏里的位置拼起来（Blender 坐标 = (x, -z, y)），旁边一堵 10 米的墙作比例
        hips = Vector((0, 0, HIP))
        objs["body"].location = hips
        objs["leg"].location = hips + Vector((HIP_X, 0, 0))
        leg2 = objs["leg"].copy()
        leg2.location = hips + Vector((-HIP_X, -0.6, 0))
        bpy.context.collection.objects.link(leg2)
        sh = Vector((SHOULDER.x, -SHOULDER.z, SHOULDER.y))
        objs["arm"].location = hips + sh + Vector((SHOULDER_X, 0, 0))
        arm2 = objs["arm"].copy()
        arm2.location = hips + sh + Vector((-SHOULDER_X, 0, 0))
        bpy.context.collection.objects.link(arm2)
        objs["plate"].location = (SHOULDER_X + 0.5, 6.0, 0)
        objs["chain"].location = (SHOULDER_X + 0.5, 6.0, 0.6)
        objs["chain"].scale = (1, 1, 1)
        wall = Part("wall")
        wall.box(V(-6, 5, 0), (2, 10, 30), "iron")
        wall.box(V(0, -0.05, 0), (40, 0.1, 40), "rag")
        wall.build()
        preview(objs, argv[1])


main()
