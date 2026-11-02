# 建筑装饰件：墙顶压檐、墙脚基座、转角壁柱、拱门的拱石圈。
# 在 Blender 里按参数生成，导出成一个 glb（每件一个物体，按名字取），Godot 里用 MultiMesh 成批摆到墙上。
# 不用贴图、不展 UV：游戏里套的是按世界坐标生成的墙面着色器。
#
# 生成：
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python tools/blender/trim_kit.py -- assets/models/trim_kit.glb
#
# 坐标约定（按 Godot 说）：x 沿墙面，y 向上，z 朝墙外（0 = 墙面）。
# Blender 是 z 向上，导出 glTF 时 (x, y, z) → (x, z, -y)，所以这里 Godot 的 +z（朝外）写成 Blender 的 -y。
# 尺寸和 scripts/maze.gd 对齐：一块 5 米，拱门门洞半宽 1.7 米、起拱 3.2 米。

import math
import sys

import bmesh
import bpy

BLOCK = 5.0
GATE_R = 1.7
GATE_SPRING = 3.2


def godot(x, y, out):
    """Godot 坐标（x 沿墙、y 向上、out 朝外）→ Blender 坐标"""
    return (x, -out, y)


def new_object(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def prism(bm, profile, x0, x1):
    """截面 profile（[(out, y), ...]，一圈）沿 x 从 x0 拉到 x1"""
    a = [bm.verts.new(godot(x0, y, o)) for o, y in profile]
    b = [bm.verts.new(godot(x1, y, o)) for o, y in profile]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])


def box(bm, x0, x1, y0, y1, o0, o1):
    prism(bm, [(o0, y0), (o1, y0), (o1, y1), (o0, y1)], x0, x1)


def slab(bm, outline, o0, o1):
    """贴在墙面上的一块：outline 是墙面上的轮廓（[(x, y), ...]），朝外凸出 o0..o1"""
    a = [bm.verts.new(godot(x, y, o0)) for x, y in outline]
    b = [bm.verts.new(godot(x, y, o1)) for x, y in outline]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])


# ---------- 墙顶压檐：顶面和墙顶齐平，往外挑出 0.3 米，底下一道凹弧收回墙面 ----------

COPING = [(-0.02, 0.0), (0.30, 0.0), (0.30, -0.10), (0.25, -0.13), (0.24, -0.20)]
for k in range(1, 7):   # 凹弧：圆心 (0.24, -0.40)，半径 0.20，从正上方转到正左方
    a = math.pi / 2 + k * (math.pi / 2) / 6
    COPING.append((0.24 + 0.20 * math.cos(a), -0.40 + 0.20 * math.sin(a)))
COPING += [(0.03, -0.44), (0.0, -0.48), (-0.02, -0.48)]


def coping():
    bm = bmesh.new()
    prism(bm, COPING, -BLOCK / 2, BLOCK / 2)
    return new_object("coping", bm)


def coping_corner():
    # 外转角：两条压檐在角上留下的方块，原点在墙角顶上，往 +x、+z 两个方向挑出
    bm = bmesh.new()
    box(bm, 0.0, 0.30, -0.10, 0.0, 0.0, 0.30)
    box(bm, 0.0, 0.24, -0.40, -0.10, 0.0, 0.24)
    return new_object("coping_corner", bm)


# ---------- 墙脚基座：0.72 米高，凸出 0.14 米，顶上一道斜面 ----------

PLINTH = [(-0.02, 0.0), (0.14, 0.0), (0.14, 0.55), (0.06, 0.68), (0.0, 0.72), (-0.02, 0.72)]


def plinth():
    bm = bmesh.new()
    prism(bm, PLINTH, -BLOCK / 2, BLOCK / 2)
    return new_object("plinth", bm)


def plinth_corner():
    bm = bmesh.new()
    box(bm, 0.0, 0.14, 0.0, 0.58, 0.0, 0.14)
    return new_object("plinth_corner", bm)


# ---------- 转角壁柱：柱身高 1 米（游戏里按墙高拉伸），正中一条凸起的竖条；柱头另一件 ----------

def pilaster():
    bm = bmesh.new()
    box(bm, -0.6, 0.6, 0.0, 1.0, -0.02, 0.10)
    box(bm, -0.38, 0.38, 0.0, 1.0, 0.10, 0.16)
    return new_object("pilaster", bm)


def pilaster_cap():
    # 原点在柱头顶面；往下 0.34 米：一块挑出的顶板，下面一层收进去的垫层，再下面一道细线脚
    bm = bmesh.new()
    box(bm, -0.78, 0.78, -0.12, 0.0, -0.02, 0.30)
    box(bm, -0.68, 0.68, -0.26, -0.12, -0.02, 0.22)
    box(bm, -0.62, 0.62, -0.34, -0.26, -0.02, 0.18)
    return new_object("pilaster_cap", bm)


# ---------- 拱石圈：贴在拱门两面，十一块楔形拱石，正中的拱心石更高、更凸；起拱处两块垫石 ----------

def voussoirs():
    bm = bmesh.new()
    inner = GATE_R
    outer = GATE_R + 0.55
    count = 11
    gap = math.radians(1.2)
    for i in range(count):
        a0 = math.pi * i / count + gap
        a1 = math.pi * (i + 1) / count - gap
        key = i == count // 2
        ro = outer + (0.18 if key else 0.0)
        steps = 3
        outline = []
        for s in range(steps + 1):
            a = a0 + (a1 - a0) * s / steps
            outline.append((inner * math.cos(a), GATE_SPRING + inner * math.sin(a)))
        for s in range(steps, -1, -1):
            a = a0 + (a1 - a0) * s / steps
            outline.append((ro * math.cos(a), GATE_SPRING + ro * math.sin(a)))
        slab(bm, outline, -0.02, 0.16 if key else 0.10)
    for side in (-1.0, 1.0):
        x0 = side * (inner - 0.05)
        x1 = side * (outer + 0.1)
        box(bm, min(x0, x1), max(x0, x1), GATE_SPRING - 0.28, GATE_SPRING, -0.02, 0.14)
    return new_object("voussoirs", bm)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = argv[0] if argv else "trim_kit.glb"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for build in (coping, coping_corner, plinth, plinth_corner, pilaster, pilaster_cap, voussoirs):
        build()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
        export_materials="NONE", export_normals=True)
    print("exported", out)


main()
