# 带拱廊的小楼：两种层数 × 两种拱数，外加一个铁阳台，导出成 assets/models/houses.glb。
# 每件一个物体，按名字取：house_s{2,3}_a{3,5}、house_balcony。
# 材质槽名字决定游戏里套什么材质：stone（墙面着色器）、roof（深色瓦顶）、dark（门洞里的黑）、wood（钉死的门板）、
# frame（铁阳台）、cloth（阳台上搭的旧布）。
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/houses.py -- assets/models/houses.glb [预览图目录]
#
# 坐标约定：脚本里按 Godot 写（y 向上），落到 Blender 时换成 (x, -z, y)，导出时 glTF 再换回来。
# 楼的局部坐标：x 沿着街（楼长 15 米，占三块墙），+z 朝街（进深 5 米，-2.5～2.5），y 从本层地面算起。
# 窗户不在这里：游戏里在立面上摆现成的拱窗（窗洞里是假室内），位置和这里的层高约定一致（见 scripts/maze.gd 的 HOUSE_*）。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

SLOTS = ["stone", "roof", "dark", "wood", "frame", "cloth"]
COLORS = {"stone": (0.5, 0.46, 0.4), "roof": (0.09, 0.09, 0.1), "dark": (0.01, 0.01, 0.012),
          "wood": (0.2, 0.13, 0.08), "frame": (0.2, 0.19, 0.18), "cloth": (0.5, 0.47, 0.4)}

LENGTH = 15.0         # 楼长（三块墙）
DEPTH = 5.0           # 进深（一块墙）
GROUND = 4.6          # 底层高（拱廊层）
STOREY = 4.2          # 楼上每层高，和墙上的拱窗层高一致
PORCH = 2.0           # 廊子进深
FRONT_T = 0.5         # 拱廊那面墙的厚度
CORNICE = 0.6         # 檐口
ROOF_RISE = 2.0       # 屋脊比檐口高多少（坡度约 35°，站得住）
EAVE = 0.4            # 屋檐挑出


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

    def f(self, idx, slot):
        self.faces.append((idx, SLOTS.index(slot)))

    def box(self, x0, x1, y0, y1, z0, z1, slot):
        ids = [self.v(V(x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.f([ids[i] for i in q], slot)

    def prism(self, outline, z0, z1, slot):
        """xy 平面上的多边形（可以是凹的）沿 z 拉出厚度"""
        a = [self.v(V(x, y, z0)) for x, y in outline]
        b = [self.v(V(x, y, z1)) for x, y in outline]
        self.f(list(reversed(a)), slot)
        self.f(b, slot)
        n = len(outline)
        for i in range(n):
            self.f([a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]], slot)

    def build(self):
        bm = bmesh.new()
        bv = [bm.verts.new((p.x, -p.z, p.y)) for p in self.verts]
        for idx, mi in self.faces:
            try:
                face = bm.faces.new([bv[i] for i in idx])
            except ValueError:
                continue
            face.material_index = mi
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for p in mesh.polygons:
            p.use_smooth = False
        for s in SLOTS:
            mesh.materials.append(bpy.data.materials[s])
        o = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(o)
        return o


def arch_spandrel(x0, x1, spring, top, seg=10):
    """拱洞上方那块墙的轮廓：上边平的，下边是半圆拱"""
    r = (x1 - x0) / 2
    cx = (x0 + x1) / 2
    pts = [(x0, top), (x1, top), (x1, spring)]
    for k in range(1, seg):
        a = math.pi * k / seg
        pts.append((cx + r * math.cos(a), spring + r * math.sin(a)))
    pts.append((x0, spring))
    return pts


def arcade_layout(arches):
    """拱洞的位置：返回 [(x0, x1)]，和游戏里搭碰撞用的是同一套算法"""
    span = LENGTH / arches
    pier = 1.0 if arches == 3 else 0.8
    out = []
    for i in range(arches):
        cx = -LENGTH / 2 + span * (i + 0.5)
        out.append((cx - (span - pier) / 2, cx + (span - pier) / 2))
    return out


def house(storeys, arches):
    p = Part("house_s%d_a%d" % (storeys, arches))
    hl = LENGTH / 2
    top = GROUND + STOREY * (storeys - 1)            # 檐口下沿
    zf = DEPTH / 2                                   # 朝街的立面
    zb = -DEPTH / 2
    zp = zf - PORCH                                  # 廊子后墙
    # 底层：廊子后面的实心部分 + 两头的端墙
    p.box(-hl, hl, 0.0, GROUND, zb, zp, "stone")
    for x0, x1 in ((-hl, -hl + 0.6), (hl - 0.6, hl)):
        p.box(x0, x1, 0.0, GROUND, zp, zf, "stone")
    # 拱廊那面墙：拱洞之间的墩子 + 拱上的那块墙
    holes = arcade_layout(arches)
    spring = 2.4 if arches == 3 else 2.2
    edges = [-hl] + [x for h in holes for x in h] + [hl]
    for i in range(0, len(edges), 2):
        if edges[i + 1] - edges[i] > 0.01:
            p.box(edges[i], edges[i + 1], 0.0, spring, zf - FRONT_T, zf, "stone")
    for x0, x1 in holes:
        p.prism(arch_spandrel(x0, x1, spring, GROUND), zf - FRONT_T, zf, "stone")
        # 一圈凸出来的拱边
        r = (x1 - x0) / 2
        ring = []
        for k in range(11):
            a = math.pi * k / 10
            ring.append(((x0 + x1) / 2 + (r + 0.12) * math.cos(a), spring + (r + 0.12) * math.sin(a)))
        inner = [((x0 + x1) / 2 + r * math.cos(math.pi * k / 10), spring + r * math.sin(math.pi * k / 10)) for k in range(10, -1, -1)]
        p.prism(ring + inner, zf, zf + 0.06, "stone")
    # 廊子顶棚
    p.box(-hl, hl, GROUND - 0.5, GROUND, zp, zf - FRONT_T, "stone")
    # 廊子里：后墙上两扇钉死的门、一扇钉着木板的窗
    for k, x in enumerate(arcade_layout(3)):
        cx = (x[0] + x[1]) / 2
        if k == 1:
            p.box(cx - 0.6, cx + 0.6, 1.2, 2.4, zp, zp + 0.03, "dark")                  # 窗洞
            for j in range(3):
                p.box(cx - 0.7, cx + 0.7, 1.35 + j * 0.4, 1.55 + j * 0.4, zp + 0.03, zp + 0.06, "wood")
        else:
            p.box(cx - 0.7, cx + 0.7, 0.0, 2.7, zp, zp + 0.03, "dark")                  # 门洞
            for j in range(5):
                p.box(cx - 0.68 + j * 0.28, cx - 0.44 + j * 0.28, 0.05, 2.6, zp + 0.03, zp + 0.07, "wood")
            p.box(cx - 0.75, cx + 0.75, 1.9, 2.1, zp + 0.07, zp + 0.1, "wood")             # 横钉的木条
    # 楼上：整个进深都是实心的
    p.box(-hl, hl, GROUND, top, zb, zf, "stone")
    # 层间的腰线、底层上方一道
    for k in range(storeys - 1):
        y = GROUND + STOREY * k
        p.box(-hl - 0.1, hl + 0.1, y - 0.12, y + 0.08, zb - 0.1, zf + 0.1, "stone")
    # 檐口
    p.box(-hl - 0.25, hl + 0.25, top, top + CORNICE * 0.5, zb - 0.25, zf + 0.25, "stone")
    p.box(-hl - 0.15, hl + 0.15, top + CORNICE * 0.5, top + CORNICE, zb - 0.15, zf + 0.15, "stone")
    # 双坡屋顶，屋脊顺着街；两头是三角山墙
    y0 = top + CORNICE
    ze = zf + EAVE
    ridge = y0 + ROOF_RISE
    a = [p.v(V(x, y0, z)) for x, z in ((-hl - EAVE, ze), (hl + EAVE, ze), (hl + EAVE, -ze), (-hl - EAVE, -ze))]
    rl = p.v(V(-hl - EAVE, ridge, 0.0))
    rr = p.v(V(hl + EAVE, ridge, 0.0))
    t = 0.12
    a2 = [p.v(V(x, y0 + t, z)) for x, z in ((-hl - EAVE, ze), (hl + EAVE, ze), (hl + EAVE, -ze), (-hl - EAVE, -ze))]
    rl2 = p.v(V(-hl - EAVE, ridge + t, 0.0))
    rr2 = p.v(V(hl + EAVE, ridge + t, 0.0))
    p.f([a2[0], a2[1], rr2, rl2], "roof")
    p.f([a2[2], a2[3], rl2, rr2], "roof")
    p.f([a[1], a[0], rl, rr], "roof")
    p.f([a[3], a[2], rr, rl], "roof")
    for i, j in ((0, 1), (2, 3)):                                                            # 檐口边
        p.f([a[i], a[j], a2[j], a2[i]], "roof")
    p.f([a[3], a[0], a2[0], a2[3]], "roof")
    p.f([a[1], a[2], a2[2], a2[1]], "roof")
    p.f([rl, a[0], a2[0], rl2], "roof")
    p.f([a[3], rl, rl2, a2[3]], "roof")
    p.f([a[1], rr, rr2, a2[1]], "roof")
    p.f([rr, a[2], a2[2], rr2], "roof")
    for sx in (-1, 1):                                                                       # 山墙
        g = [p.v(V(sx * hl, y0, zf)), p.v(V(sx * hl, y0, zb)), p.v(V(sx * hl, ridge - 0.1, 0.0))]
        p.f(g, "stone")
        g2 = [p.v(V(sx * (hl - 0.3), y0, zf)), p.v(V(sx * (hl - 0.3), y0, zb)), p.v(V(sx * (hl - 0.3), ridge - 0.3, 0.0))]
        p.f(list(reversed(g2)), "stone")
    p.box(-hl - EAVE, hl + EAVE, ridge, ridge + 0.18, -0.2, 0.2, "roof")                    # 屋脊
    # 烟囱：从后坡伸出来
    cx, cz = hl - 3.0, -1.2
    p.box(cx - 0.45, cx + 0.45, y0, ridge + 1.6, cz - 0.4, cz + 0.4, "stone")
    p.box(cx - 0.55, cx + 0.55, ridge + 1.6, ridge + 1.8, cz - 0.5, cz + 0.5, "stone")
    p.box(cx - 0.3, cx + 0.3, ridge + 1.79, ridge + 1.81, cz - 0.3, cz + 0.3, "dark")
    return p.build()


def balcony():
    """铁阳台：原点在立面上、阳台地面那一点，往 +z 挑出 0.9 米"""
    p = Part("house_balcony")
    w, d = 1.6, 0.9
    p.box(-w / 2, w / 2, -0.12, 0.0, 0.0, d, "stone")
    for x in (-w / 2 + 0.1, w / 2 - 0.1):                                                    # 两根托架
        p.box(x - 0.06, x + 0.06, -0.6, -0.12, 0.0, 0.1, "stone")
        p.box(x - 0.05, x + 0.05, -0.45, -0.12, 0.1, d - 0.15, "stone")
    p.box(-w / 2, w / 2, 0.98, 1.02, d - 0.04, d, "frame")                                   # 扶手
    for x0, x1, z0, z1 in ((-w / 2, -w / 2 + 0.04, 0.0, d), (w / 2 - 0.04, w / 2, 0.0, d)):
        p.box(x0, x1, 0.98, 1.02, z0, z1, "frame")
    for i in range(13):                                                                      # 栏杆
        x = -w / 2 + 0.06 + i * (w - 0.12) / 12
        p.box(x - 0.012, x + 0.012, 0.0, 1.0, d - 0.03, d - 0.006, "frame")
    for z in (0.15, 0.45, 0.75):
        for x in (-w / 2 + 0.02, w / 2 - 0.02):
            p.box(x - 0.012, x + 0.012, 0.0, 1.0, z - 0.012, z + 0.012, "frame")
    # 搭在扶手上的旧布：一块往外垂下来的布
    for k in range(6):
        x0 = -0.5 + k * 0.14
        sag = 0.02 * math.sin(k * 1.7)
        p.box(x0, x0 + 0.14, 0.3 + sag, 1.03, d + 0.005, d + 0.02 + 0.01 * (k % 2), "cloth")
    return p.build()


def preview(out_dir):
    world = bpy.data.worlds.new("storm")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    bpy.context.scene.world = world
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = 3.0
    o = bpy.data.objects.new("key", sun)
    o.rotation_euler = (math.radians(55), 0, math.radians(-30))
    bpy.context.collection.objects.link(o)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 26
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (6.0, -30.0, 9.0)
    cam.rotation_euler = (Vector((0, 0, 7.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "houses_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "houses.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for s in SLOTS:
        m = bpy.data.materials.new(s)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COLORS[s], 1.0)
    objs = [house(s, a) for s in (2, 3) for a in (3, 5)] + [balcony()]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
                              export_normals=True)
    print("exported", out)
    if len(argv) > 1:
        # 预览：两栋并排（三层五拱、两层三拱），前面一段街，三层那栋二楼挂着阳台
        for o in objs:
            o.location = (100, 100, 0)
        bpy.data.objects["house_s3_a5"].location = (-8.5, 0, 0)
        bpy.data.objects["house_s2_a3"].location = (8.5, 0, 0)
        bal = bpy.data.objects["house_balcony"]
        bal.location = (-8.5, -2.5, GROUND + STOREY - 0.0 + 0.0)
        floor = Part("street")
        floor.box(-30, 30, -0.2, 0.0, -20, 8, "stone")
        floor.build()
        preview(argv[1])


main()
