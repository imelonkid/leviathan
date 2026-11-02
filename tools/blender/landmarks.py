# 迷宫里的地标建筑：三种塔楼和一座门楼，按参数生成，导出成 assets/models/landmarks.glb。
# 每件一个物体，按名字取；材质槽名字决定游戏里套什么材质：stone（墙面着色器）、roof（深色瓦顶）、dark（门窗洞里的黑）。
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/landmarks.py -- assets/models/landmarks.glb [预览图目录]
#
# 坐标约定（按 Godot 说）：y 向上，原点在塔脚（地面）正中；Blender 里写成 z 向上，导出时自动换。
# 尺寸和 scripts/maze.gd 对齐：一块 5 米，塔身正好占一块墙角；门楼横跨一条通道，两头的墩子各占一块墙角。

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

BLOCK = 5.0
MATS = {}


def mat(name, color, rough=0.9, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    MATS[name] = m
    return m


def cube(bm, x0, x1, y0, y1, z0, z1, mi=0):
    """Blender 坐标的轴对齐方块（z 向上），面的材质槽 mi"""
    res = bmesh.ops.create_cube(bm, size=1.0)
    vs = res["verts"]
    bmesh.ops.scale(bm, vec=(x1 - x0, y1 - y0, z1 - z0), verts=vs)
    bmesh.ops.translate(bm, vec=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), verts=vs)
    for f in {f for v in vs for f in v.link_faces}:
        f.material_index = mi


def pyramid(bm, half, z0, z1, mi):
    """四坡尖顶"""
    base = [bm.verts.new((sx * half, sy * half, z0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    tip = bm.verts.new((0, 0, z1))
    bm.faces.new(list(reversed(base))).material_index = mi
    for i in range(4):
        bm.faces.new([base[i], base[(i + 1) % 4], tip]).material_index = mi


def arch_hole(bm, cx, cy, z0, w, h, depth, normal, mi=2):
    """墙面上的拱形黑洞（凹进去的深色面片近似）：一块矩形 + 半圆，贴在 normal 方向的墙面外一点"""
    nx, ny = normal
    off = 0.02
    seg = 8
    r = w / 2
    pts = [(-r, 0.0), (r, 0.0), (r, h - r)]
    for k in range(1, seg):
        a = math.pi * k / seg
        pts.append((r * math.cos(a), h - r + r * math.sin(a)))
    pts.append((-r, h - r))
    side = (-ny, nx)
    verts = [bm.verts.new((cx + side[0] * u + nx * off, cy + side[1] * u + ny * off, z0 + v)) for u, v in pts]
    f = bm.faces.new(verts)
    f.material_index = mi
    f.normal_update()
    if f.normal.dot(Vector((nx, ny, 0))) < 0:
        f.normal_flip()


def obj(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if len(f.verts) > 0 and f.calc_area() > 0 and f.material_index != 2])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = False
    for k in ("stone", "roof", "dark"):
        mesh.materials.append(MATS[k])
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return o


def openings(bm, half, z0, w, h):
    for nx, ny in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        arch_hole(bm, nx * half, ny * half, z0, w, h, 0.0, (nx, ny))


# ---------- 塔楼 A：钟楼——方塔身，顶上一层四面开拱的钟室，四坡尖顶 ----------

def bell_tower():
    bm = bmesh.new()
    h = BLOCK / 2
    cube(bm, -h, h, -h, h, 0.0, 19.0)                    # 塔身
    cube(bm, -h - 0.3, h + 0.3, -h - 0.3, h + 0.3, 19.0, 19.6)   # 束腰线脚
    cube(bm, -h, h, -h, h, 19.6, 25.0)                   # 钟室
    openings(bm, h, 20.3, 2.2, 4.0)
    cube(bm, -h - 0.45, h + 0.45, -h - 0.45, h + 0.45, 25.0, 25.7)   # 檐口
    pyramid(bm, h + 0.6, 25.7, 34.0, 1)
    for k in range(3):   # 塔身上几个窄窗
        openings(bm, h, 6.0 + k * 4.5, 0.7, 2.0)
    return obj("tower_bell", bm)


# ---------- 塔楼 B：望楼——下粗上细两段，顶上一圈雉堞 ----------

def watch_tower():
    bm = bmesh.new()
    h = BLOCK / 2
    cube(bm, -h, h, -h, h, 0.0, 14.0)
    cube(bm, -h + 0.5, h - 0.5, -h + 0.5, h - 0.5, 14.0, 22.0)
    cube(bm, -h - 0.2, h + 0.2, -h - 0.2, h + 0.2, 22.0, 22.8)   # 挑出的平台
    for i in range(4):   # 雉堞：每边三个垛口
        for k in range(3):
            u = -h + 0.3 + k * 1.75
            a, b = u, u + 1.0
            if i == 0:
                cube(bm, a, b, -h - 0.2, -h + 0.5, 22.8, 24.2)
            elif i == 1:
                cube(bm, a, b, h - 0.5, h + 0.2, 22.8, 24.2)
            elif i == 2:
                cube(bm, -h - 0.2, -h + 0.5, a, b, 22.8, 24.2)
            else:
                cube(bm, h - 0.5, h + 0.2, a, b, 22.8, 24.2)
    openings(bm, h - 0.5, 16.0, 1.1, 3.0)
    for k in range(2):
        openings(bm, h, 4.0 + k * 5.0, 0.6, 1.8)
    return obj("tower_watch", bm)


# ---------- 塔楼 C：尖塔——方塔身转八角，细长的八角尖顶 ----------

def spire_tower():
    bm = bmesh.new()
    h = BLOCK / 2
    cube(bm, -h, h, -h, h, 0.0, 16.0)
    cube(bm, -h - 0.3, h + 0.3, -h - 0.3, h + 0.3, 16.0, 16.6)
    m = Matrix.Translation((0, 0, 16.6 + 3.5)) @ Matrix.Rotation(math.pi / 8, 4, "Z")
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=h * 0.98, radius2=h * 0.98, depth=7.0, matrix=m)
    m = Matrix.Translation((0, 0, 23.6 + 7.0)) @ Matrix.Rotation(math.pi / 8, 4, "Z")
    res2 = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=h * 1.05, radius2=0.15, depth=14.0, matrix=m)
    for f in {f for v in res2["verts"] for f in v.link_faces}:
        f.material_index = 1
    openings(bm, h * 0.9, 18.2, 1.0, 3.2)
    for k in range(2):
        openings(bm, h, 5.0 + k * 5.0, 0.6, 1.8)
    return obj("tower_spire", bm)


# ---------- 门楼：横跨一条通道（x 方向是街道走向，z 方向跨街），两头墩子各占一块墙角 ----------

def gatehouse():
    bm = bmesh.new()
    h = BLOCK / 2
    span = BLOCK          # 中间那块通道
    for s in (-1, 1):     # 两头的墩子：各一块墙角，比墙高
        y0 = s * (span / 2) + (0 if s > 0 else -BLOCK)
        cube(bm, -h, h, y0, y0 + BLOCK, 0.0, 17.0)
        cube(bm, -h - 0.35, h + 0.35, y0 - 0.35, y0 + BLOCK + 0.35, 17.0, 17.6)
        pyramid_center = (0.0, y0 + BLOCK / 2)
    # 跨街的楼身：从 7.5 米到 15 米，下面留出拱下的通道
    cube(bm, -h + 0.4, h - 0.4, -span / 2, span / 2, 7.5, 15.0)
    cube(bm, -h, h, -span / 2 - 0.1, span / 2 + 0.1, 15.0, 15.6)
    # 两面各一排三个窄拱窗
    for nx in (1, -1):
        for k in (-1, 0, 1):
            arch_hole(bm, nx * (h - 0.4), k * 1.4, 9.5, 0.8, 2.6, 0.0, (nx, 0))
    # 楼身下的拱：两面贴一圈深色拱形（门洞本身空着，通道照走）
    # 双坡屋顶，顺着跨街方向
    a = bm.verts.new((-h - 0.3, -span / 2 - 0.3, 15.6))
    b = bm.verts.new((h + 0.3, -span / 2 - 0.3, 15.6))
    c = bm.verts.new((h + 0.3, span / 2 + 0.3, 15.6))
    d = bm.verts.new((-h - 0.3, span / 2 + 0.3, 15.6))
    e = bm.verts.new((0, -span / 2 - 0.3, 19.0))
    f = bm.verts.new((0, span / 2 + 0.3, 19.0))
    for face in ([a, b, e], [c, d, f], [b, c, f, e], [d, a, e, f]):
        bm.faces.new(face).material_index = 1
    # 墩子顶上的小尖顶
    for s in (-1, 1):
        cy = s * (span / 2 + BLOCK / 2)
        base = [bm.verts.new((sx * (h + 0.4), cy + sy * (h + 0.4), 17.6)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        tip = bm.verts.new((0, cy, 23.0))
        bm.faces.new(list(reversed(base))).material_index = 1
        for i in range(4):
            bm.faces.new([base[i], base[(i + 1) % 4], tip]).material_index = 1
        for nx, ny in ((1, 0), (-1, 0)):
            arch_hole(bm, nx * h, cy, 11.0, 0.7, 2.2, 0.0, (nx, ny))
    return obj("gatehouse", bm)


def preview(out_dir):
    world = bpy.data.worlds.new("storm")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.06, 0.08, 1.0)
    bpy.context.scene.world = world
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = 3.0
    o = bpy.data.objects.new("key", sun)
    o.rotation_euler = (math.radians(50), 0, math.radians(-35))
    bpy.context.collection.objects.link(o)
    # 一段地面和两边的矮墙作比例参照（墙 9 米高）
    bm = bmesh.new()
    cube(bm, -40, 40, -20, 20, -1.0, 0.0)
    cube(bm, -40, 40, 15.0, 20.0, 0.0, 9.0)      # 后面一道 9 米高的墙
    ref = obj("ref", bm)
    ref.location = (0, 0, 0)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 1600
    sc.render.resolution_y = 900
    sc.view_settings.view_transform = "AgX"
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 28
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (2.0, -42.0, 4.0)
    cam.rotation_euler = (Vector((0, 12.0, 13.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, "landmarks_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "landmarks.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat("stone", (0.5, 0.46, 0.4))
    mat("roof", (0.09, 0.09, 0.1), 0.6, 0.3)
    mat("dark", (0.01, 0.01, 0.012))
    objs = [bell_tower(), watch_tower(), spire_tower(), gatehouse()]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True,
        export_normals=True)
    print("exported", out)
    if len(argv) > 1:
        # 预览：一字排开，前面放一段墙作比例
        for o, x in zip(objs, (-27.0, -14.0, -1.0, 20.0)):
            o.location = (x, 12.5, 0.0)
            if o.name == "gatehouse":
                o.rotation_euler = (0, 0, math.pi / 2)   # 侧过来：看得见街从楼下穿过
        preview(argv[1])


main()
