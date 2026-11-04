"""量墙人 / 扶门者：原创模型。复用现有网格工具，刚性骨段在 Godot 内驱动。

Blender -b --factory-startup --python tools/blender/threshold_creatures.py -- assets/models /tmp/leviathan-creatures
"""
import math
import os
import runpy
import sys

import bpy
import bmesh
from mathutils import Vector

kit = runpy.run_path(os.path.join(os.path.dirname(__file__), "watchman.py"))
Part, V, B = (kit[k] for k in ("Part", "V", "B"))
SLOTS = kit["SLOTS"]


def palette(kind):
    colors = dict(kit["COLORS"])
    colors.update(skin=(0.51, 0.43, 0.33), iron=(0.065, 0.047, 0.035),
                  brass=(0.55, 0.32, 0.09), bandage=(0.68, 0.56, 0.36),
                  leather=(0.14, 0.055, 0.027), glass=(0.018, 0.009, 0.007))
    colors["coat"] = (0.43, 0.235, 0.08) if kind == "surveyor" else (0.105, 0.245, 0.195)
    colors["cape"] = (0.24, 0.12, 0.045) if kind == "surveyor" else (0.27, 0.1, 0.085)
    return colors


def cloth(p, centers, widths, depths, slot, phase=0):
    """带有非均匀纵褶、腰部束紧和破边的布面，避免圆锥纸筒轮廓。"""
    rings, count = [], 64
    for j, c in enumerate(centers):
        ring = []
        for k in range(count):
            a = k * math.tau / count
            ripple = 1 + 0.055 * math.sin(a * 13 + phase + j * 0.45) + 0.025 * math.sin(a * 23 - j)
            q = c + V(math.cos(a) * widths[j] * ripple, 0, math.sin(a) * depths[j] * ripple)
            if j == 0:
                q.y += 0.018 * math.sin(a * 17) + 0.025 * math.sin(a * 7 + 1)
            ring.append(p.v(q))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(count):
            p.f([rings[j][k], rings[j][(k + 1) % count], rings[j + 1][(k + 1) % count], rings[j + 1][k]], slot)


def seam(p, points, slot="bandage", radius=0.003):
    p.tube(points, radius, slot, seg=6, caps=True)


def panel(p, points, slot):
    ids = [p.v(q) for q in points]
    p.f(ids, slot, False)
    p.f(list(reversed(ids)), slot, False)


def stitches(p, start, end, count=18):
    for i in range(count):
        q = start.lerp(end, (i + 0.5) / count)
        seam(p, [q + V(-0.012, -0.006, 0), q + V(0.012, 0.006, 0)], radius=0.0025)


def sleeve(p, start, end, slot):
    centers = [start.lerp(end, i / 10) for i in range(11)]
    radii = [0.075 * (1 - i * 0.025) * (1 + 0.12 * math.sin(i * 2.6)) for i in range(11)]
    p.tube(centers, radii, slot, seg=24, caps=True)
    p.tube([end - (end - start).normalized() * 0.065, end], [0.076, 0.078], "cape", seg=24, caps=True)



def build(kind, out, preview_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COLORS = palette(kind)
    for slot in SLOTS:
        mat = bpy.data.materials.new(slot)
        mat.use_nodes = True
        shader = mat.node_tree.nodes["Principled BSDF"]
        shader.inputs["Base Color"].default_value = (*COLORS[slot], 1)
        shader.inputs["Roughness"].default_value = 0.85
        if slot == "brass":
            shader.inputs["Metallic"].default_value = 0.65
        # 预览也显示旧布、锈蚀和污渍；游戏中替换为共享的三平面材质。
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 12 if slot == "skin" else 7
        noise.inputs["Detail"].default_value = 4
        ramp = nodes.new("ShaderNodeValToRGB")
        base = COLORS[slot]
        ramp.color_ramp.elements[0].color = (*(c * 0.65 for c in base), 1)
        ramp.color_ramp.elements[1].color = (*base, 1)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.3
        bump.inputs["Distance"].default_value = 0.008
        fine = nodes.new("ShaderNodeTexNoise")
        fine.inputs["Scale"].default_value = 145
        fine.inputs["Detail"].default_value = 3
        links.new(fine.outputs["Fac"], bump.inputs["Height"])
        rough = nodes.new("ShaderNodeMapRange")
        rough.inputs["To Min"].default_value = 0.63 if slot == "skin" else 0.8
        rough.inputs["To Max"].default_value = 0.95
        links.new(noise.outputs["Fac"], rough.inputs["Value"])
        links.new(rough.outputs["Result"], shader.inputs["Roughness"])
        links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    bones, pieces = [], []

    def piece(name, head, tail, parent, draw):
        p = Part(name)
        draw(p)
        obj = p.build()
        bones.append((name, head, tail, parent))
        pieces.append(obj)
        return p

    if kind == "surveyor":
        def survey_coat(p):
            centers = [V(0, y, 0) for y in (0.84, 0.94, 1.1, 1.28, 1.43, 1.6, 1.8, 1.97, 2.13, 2.21)]
            cloth(p, centers, [0.27, 0.26, 0.235, 0.215, 0.18, 0.175, 0.19, 0.235, 0.27, 0.17],
                  [0.19, 0.19, 0.17, 0.16, 0.14, 0.135, 0.145, 0.16, 0.145, 0.11], "coat")
            p.tube([V(0, 2.15, 0), V(0, 2.28, 0)], [(0.14, 0.105), (0.115, 0.095)], "cape", seg=32)
            for sign in (-1, 1):
                panel(p, [V(sign * 0.06, 2.2, 0.13), V(sign * 0.23, 2.08, 0.155), V(sign * 0.09, 1.91, 0.17)], "cape")
                seam(p, [V(sign * 0.16, 2.14, 0.15), V(sign * 0.14, 1.78, 0.17), V(sign * 0.13, 1.44, 0.15)], "leather", 0.023)
                # 有翻盖的工具口袋与缝边。
                panel(p, [V(sign * 0.07, 1.25, 0.18), V(sign * 0.21, 1.24, 0.17), V(sign * 0.2, 1.02, 0.19), V(sign * 0.07, 1.04, 0.2)], "cape")
                seam(p, [V(sign * 0.07, 1.23, 0.195), V(sign * 0.21, 1.22, 0.185)], "bandage", 0.004)
                stitches(p, V(sign * 0.22, 1.04, 0.19), V(sign * 0.21, 1.22, 0.19), 8)
            p.tube([V(0, 1.41, 0), V(0, 1.48, 0)], [(0.2, 0.157)] * 2, "leather", seg=40)
            for y in (1.56, 1.7, 1.84, 1.98):
                p.ellipsoid(V(0, y, 0.166), (0.016, 0.016, 0.008), "brass", seg=12)
            stitches(p, V(0.028, 0.94, 0.205), V(0.028, 2.05, 0.17), 38)
            # 粗皮胸带、针线补片与钉在胸口的旧号牌。
            panel(p, [V(-0.22, 1.93, 0.18), V(-0.08, 1.93, 0.19), V(-0.08, 1.83, 0.19), V(-0.22, 1.83, 0.18)], "brass")
            for j in range(4):
                seam(p, [V(-0.2 + j * 0.026, 1.85, 0.195), V(-0.2 + j * 0.026, 1.9, 0.195)], "iron", 0.0025)
            panel(p, [V(0.09, 1.07, 0.205), V(0.22, 1.04, 0.19), V(0.21, 0.92, 0.205), V(0.08, 0.93, 0.22)], "leather")
            stitches(p, V(0.09, 0.95, 0.225), V(0.21, 0.94, 0.21), 7)
            for sign in (-1, 1):
                for j in range(3):
                    seam(p, [V(sign * 0.18, 1.5 + j * 0.03, 0.13), V(sign * 0.13, 1.62 + j * 0.04, 0.14), V(sign * 0.2, 1.76 + j * 0.04, 0.13)], "coat", 0.007)

        piece("body", V(0, 1.35, 0), V(0, 2.2, 0), None, survey_coat)
        # 没有眼睛和嘴：面部是铆接的测绘仪，中央刻度盘与窄读数缝。
        p = Part("instruments")
        p.ellipsoid(V(0, 2.41, -0.015), (0.145, 0.205, 0.12), "skin", seg=32, rings=20)
        p.tube([V(0, 2.18, 0), V(0, 2.3, 0)], [0.07, 0.09], "leather", seg=24, caps=True)
        outline = [(-0.15, 2.25), (0.15, 2.25), (0.18, 2.48), (0.11, 2.64), (-0.1, 2.64), (-0.18, 2.48)]
        panel(p, [V(x, y, 0.095) for x, y in outline], "brass")
        panel(p, [V(x * 0.91, 2.44 + (y - 2.44) * 0.94, 0.105) for x, y in outline], "iron")
        for i in range(len(outline)):
            x, y = outline[i]
            nx, ny = outline[(i + 1) % len(outline)]
            seam(p, [V(x, y, 0.1), V(nx, ny, 0.1)], "brass", 0.012)
            p.ellipsoid(V(x * 0.85, 2.44 + (y - 2.44) * 0.84, 0.122), (0.01, 0.01, 0.009), "brass", seg=12)
        dial = V(0, 2.46, 0.125)
        p.ellipsoid(dial, (0.11, 0.11, 0.016), "brass", seg=40, rings=12)
        p.ellipsoid(dial + V(0, 0, 0.015), (0.091, 0.091, 0.008), "glass", seg=40, rings=12)
        seam(p, [dial + V(0.103 * math.cos(a), 0.103 * math.sin(a), 0.021) for a in [math.tau * i / 64 for i in range(65)]], "brass", 0.005)
        for i in range(24):
            a = i * math.tau / 24
            r = 0.065 if i % 3 == 0 else 0.077
            seam(p, [dial + V(r * math.cos(a), r * math.sin(a), 0.027), dial + V(0.087 * math.cos(a), 0.087 * math.sin(a), 0.027)], "bandage", 0.002)
        seam(p, [dial + V(-0.045, -0.05, 0.032), dial + V(0.05, 0.055, 0.032)], "brass", 0.004)
        p.ellipsoid(dial + V(0, 0, 0.034), (0.012, 0.012, 0.006), "brass", seg=16)
        panel(p, [V(-0.022, 2.28, 0.12), V(0.022, 2.28, 0.12), V(0.022, 2.35, 0.12), V(-0.022, 2.35, 0.12)], "glass")
        for sign in (-1, 1):
            seam(p, [V(sign * 0.055, 2.28, 0.13), V(sign * 0.055, 2.36, 0.13)], "brass", 0.008)
            p.tube([V(sign * 0.15, 2.38, 0), V(sign * 0.21, 2.38, 0)], 0.033, "brass", seg=20, caps=True)
        for i in range(5):
            x = (i - 2) * 0.085
            end = V(x + (i - 2) * 0.055, 2.65 + 0.16 * (i % 3), -0.04)
            p.tube([V(x, 2.05, -0.14), end - V(0, 0, 0.12)], 0.016, "brass", seg=6, caps=True)
            for j in range(4):
                y = 2.3 + j * 0.07
                p.tube([V(x - 0.025, y, 0), V(x + 0.025, y, 0)], 0.005, "iron", seg=4)
        ruler = [V(-0.95, 2.05, -0.2), V(0.05, 2.4, -0.2), V(0.75, 1.85, -0.2), V(-0.25, 1.45, -0.2)]
        p.tube(ruler, [(0.035, 0.025)] * len(ruler), "brass", seg=4, caps=True, smooth=False)
        for a, b in zip(ruler, ruler[1:]):
            for i in range(1, 18):
                q = a.lerp(b, i / 18)
                seam(p, [q + V(0, -0.024, 0.032), q + V(0, 0.024 if i % 3 == 0 else 0.005, 0.032)], "iron", 0.003)
        for q in ruler:
            p.ellipsoid(q, (0.055, 0.055, 0.035), "iron")
        pieces.append(p.build())
        bones.append(("instruments", V(0, 2, 0), V(0, 2.6, 0), "body"))
        for side, sign in (("l", 1), ("r", -1)):
            hip, knee, ankle = V(sign * 0.12, 1.35, 0), V(sign * 0.16, 0.66, 0.04), V(sign * 0.16, 0.08, 0)
            piece("leg_" + side, hip, knee, "body", lambda p, h=hip, k=knee: p.tube([h, k], [0.075, 0.05], "coat", caps=True))
            piece("shin_" + side, knee, ankle, "leg_" + side, lambda p, k=knee, a=ankle: p.tube([k, a, a + V(0, -0.04, 0.15)], [0.05, 0.035, 0.025], "leather", caps=True))
            shoulder, elbow, hand = V(sign * 0.24, 2.12, 0), V(sign * 0.32, 1.25, 0), V(sign * 0.38, 0.25, 0.04)
            def survey_arm(p, s=shoulder, e=elbow, h=hand):
                sleeve(p, s, e + V(0, 0.15, 0), "coat")
                p.tube([e + V(0, 0.18, 0), e, h + V(0, 0.12, 0), h], [0.045, 0.048, 0.026, 0.022], "skin", seg=24, caps=True)
                for i in range(5):
                    y = e.y - i * 0.045
                    p.tube([V(e.x, y, 0), V(e.x, y - 0.024, 0)], [0.051, 0.05], "bandage", seg=20)
                for j in range(4):
                    q = h + V((j - 1.5) * 0.019, 0.06, 0.025)
                    p.tube([q, q + V(0, -0.06, 0.02), q + V(0.01, -0.12, 0.01)], [0.012, 0.01, 0.005], "skin", seg=10, caps=True)
            piece("arm_" + side, shoulder, elbow, "body", survey_arm)
            p = Part("plumb_" + side)
            p.tube([hand, hand + V(0, -0.16, 0)], [0.045, 0.005], "brass", seg=6, caps=True)
            pieces.append(p.build())
            bones.append(("plumb_" + side, hand, hand + V(0, -0.16, 0), "arm_" + side))
        # 左手旁的铰接量尺：两段各 0.8 米，展开时竖起，顶端垂线校准。
        base = V(0.38, 0.02, 0.04)
        joint = base + V(0, 0.8, 0)
        def gauge_segment(p, start):
            p.tube([start, start + V(0, 0.8, 0)], [(0.028, 0.017)] * 2, "brass", seg=4, caps=True, smooth=False)
            for i in range(1, 20):
                y = i * 0.04
                seam(p, [start + V(-0.022, y, 0.02), start + V(0.018 if i % 5 == 0 else -0.002, y, 0.02)], "iron", 0.0025)
            p.ellipsoid(start, (0.038, 0.038, 0.024), "iron", seg=20, rings=12)
        piece("gauge", base, joint, "arm_l", lambda p: gauge_segment(p, base))
        piece("gauge_tip", joint, joint + V(0, 0.8, 0), "gauge", lambda p: gauge_segment(p, joint))
        def plumbline(p):
            top = base + V(0.065, 1.58, 0)
            seam(p, [top, top - V(0, 1.48, 0)], "leather", 0.002)
            p.tube([top - V(0, 1.44, 0), top - V(0, 1.54, 0)], [0.025, 0.002], "iron", seg=16, caps=True)
        piece("gauge_line", base + V(0.065, 1.58, 0), base + V(0.065, 1.2, 0), "gauge_tip", plumbline)

    else:
        def holder_coat(p):
            centers = [V(0.05 - max(0, y - 0.8) * 0.36, y, 0) for y in (0.45, 0.6, 0.8, 1, 1.18, 1.4, 1.6, 1.78, 1.93)]
            cloth(p, centers, [0.29, 0.28, 0.26, 0.23, 0.19, 0.205, 0.24, 0.25, 0.16],
                  [0.2, 0.2, 0.19, 0.17, 0.145, 0.145, 0.16, 0.16, 0.13], "coat", 1.6)
            for sign in (-1, 1):
                # 腰侧向肩头斜拉的受力褶，肘部皱褶由袖子圆环构成。
                for j in range(4):
                    seam(p, [V(-0.05 + sign * 0.14, 1.05 + j * 0.04, 0.16), V(-0.15 + sign * 0.12, 1.33 + j * 0.035, 0.16), V(-0.29 + sign * 0.09, 1.7 + j * 0.025, 0.16)], "coat", 0.008)
            # 斜披的酒红肩布，留出腋下的脸。
            cloth(p, [V(-0.17, 1.45, -0.045), V(-0.29, 1.68, -0.025), V(-0.36, 1.9, -0.015), V(-0.38, 2, 0)],
                  [0.34, 0.35, 0.29, 0.15], [0.23, 0.25, 0.23, 0.14], "cape", 0.3)
            seam(p, [V(-0.12, 1.5, 0.17), V(-0.22, 1.7, 0.19), V(-0.35, 1.94, 0.15)], "bandage", 0.007)
            for i in range(5):
                y = 0.88 + i * 0.13
                x = 0.05 - max(0, y - 0.8) * 0.36
                p.ellipsoid(V(x, y, 0.185), (0.019, 0.018, 0.009), "brass", seg=12)
            stitches(p, V(0.1, 0.53, 0.21), V(-0.17, 1.4, 0.18), 30)
            panel(p, [V(-0.14, 1.13, 0.167), V(0.07, 1.12, 0.17), V(0.06, 0.92, 0.2), V(-0.14, 0.93, 0.2)], "leather")
            for i in range(12):
                q = V(-0.24 + i * 0.038, 0.5 + 0.018 * math.sin(i * 1.7), 0.195)
                seam(p, [q, q + V(0.014, -0.08 - (i % 3) * 0.025, 0)], "coat", 0.004)
        piece("body", V(0, 0.9, 0), V(-0.35, 1.8, 0), None, holder_coat)
        p = Part("buried_head")
        # 扶门者独立的挤压头颅：一侧萎缩、眼睑收拢，嘴被牵向腋下。
        c = V(-0.44, 1.68, 0.16)
        def h(x, y, z):
            return c + V(x * 0.86 + y * 0.38, y * 0.93 - x * 0.28, z)
        p.ellipsoid(c, (0.14, 0.215, 0.125), "skin", seg=40, rings=24)
        p.ellipsoid(h(-0.045, -0.09, 0), (0.105, 0.13, 0.105), "skin", seg=32, rings=20)
        # 颈根、挤压的腮肉、眉弓融合到同一张皮肤里。
        p.tube([V(-0.23, 1.95, -0.015), V(-0.35, 1.86, 0.035), h(0.06, 0.07, -0.03)], [0.09, 0.085, 0.075], "skin", seg=32, caps=True)
        for sign in (-1, 1):
            x = sign * 0.062
            ey = 0.04 if sign < 0 else 0.065
            seam(p, [h(x - 0.035, ey, 0.108), h(x, ey - 0.008, 0.126), h(x + 0.03, ey + 0.002, 0.11)], "glass", 0.004)
            seam(p, [h(x - 0.037, ey + 0.016, 0.11), h(x, ey + 0.014, 0.127), h(x + 0.03, ey + 0.015, 0.113)], "skin", 0.012)
            seam(p, [h(x - 0.028, ey - 0.02, 0.111), h(x, ey - 0.025, 0.123), h(x + 0.025, ey - 0.018, 0.11)], "skin", 0.009)
            p.ellipsoid(h(sign * 0.08, -0.035, 0.08), (0.043, 0.065, 0.038), "skin", seg=24, rings=16)
        p.tube([h(0.008, 0.07, 0.1), h(-0.014, -0.015, 0.15), h(-0.02, -0.045, 0.137)], [0.02, 0.023, 0.013], "skin", seg=20, caps=True)
        for sign in (-1, 1):
            p.ellipsoid(h(-0.02 + sign * 0.02, -0.042, 0.132), (0.012, 0.008, 0.008), "glass", seg=16)
        mouth = [h(-0.065, -0.13, 0.09), h(-0.025, -0.112, 0.122), h(0.02, -0.088, 0.116), h(0.046, -0.06, 0.087)]
        seam(p, mouth, "glass", 0.005)
        seam(p, [q + V(0, -0.012, 0.002) for q in mouth], "skin", 0.009)
        # 额侧缝片呈不规则薄片，避开脸部；暗线沿固定孔下方延伸。
        for i in range(4):
            q = h(-0.075 + i * 0.012, 0.12 + i * 0.032, 0.075 - i * 0.025)
            panel(p, [q + V(-0.047, -0.007, 0), q + V(0.046, 0.008, 0), q + V(0.033, 0.02, 0.005), q + V(-0.04, 0.014, 0.006)], "bandage")
            for sign in (-1, 1):
                p.ellipsoid(q + V(sign * 0.032, 0.007, 0.009), (0.004, 0.004, 0.004), "iron", seg=10)
        for i in range(4):
            seam(p, [h(-0.11 + i * 0.012, -0.04, 0.085), h(-0.1 + i * 0.012, -0.12, 0.085)], "skin", 0.004)
        pieces.append(p.build())
        bones.append(("buried_head", V(-0.4, 1.6, 0), V(-0.4, 1.9, 0), "body"))
        # 手掌朝 +z 压在墙面；根节点离内墙 0.65 米，掌面恰好贴墙。
        for side, shoulder, elbow, hand in (
            ("l", V(-0.34, 1.9, 0), V(-0.2, 2.35, 0.25), V(0.58, 2.7, 0.605)),
            ("r", V(-0.1, 1.8, 0), V(0.3, 1.62, 0.3), V(0.62, 1.93, 0.605))):
            piece("arm_" + side, shoulder, elbow, "body", lambda p, s=shoulder, e=elbow: sleeve(p, s, e, "coat"))
            def forearm(p, e=elbow, h=hand):
                p.tube([e, e.lerp(h, 0.3), e.lerp(h, 0.75), h], [0.055, 0.048, 0.03, 0.035], "skin", seg=28, caps=True)
                for j in range(3):
                    q = e.lerp(h, 0.9 - j * 0.025)
                    seam(p, [q + V(-0.025, 0, 0.018), q + V(0.02, 0, 0.018)], "leather", 0.002)
            piece("hand_" + side, elbow, hand, "arm_" + side, forearm)
            def palm(p, h=hand):
                p.ellipsoid(h, (0.1, 0.125, 0.045), "skin", seg=32, rings=20)
                p.tube([h + V(-0.07, -0.03, 0), h + V(-0.16, 0.045, 0.015), h + V(-0.18, 0.095, 0.025)], [0.03, 0.023, 0.012], "skin", seg=16, caps=True)
                for j in range(3):
                    seam(p, [h + V(-0.065, -0.05 + j * 0.03, 0.043), h + V(0, -0.025 + j * 0.03, 0.046), h + V(0.055, -0.035 + j * 0.03, 0.043)], "leather", 0.0015)
            piece("palm_" + side, hand, hand + V(0, 0.12, 0), "hand_" + side, palm)
            for i in range(4):
                q = hand + V((i - 1.5) * 0.043, 0.085, 0.008)
                length = [0.16, 0.2, 0.19, 0.145][i]
                def finger(p, q=q, ln=length):
                    p.tube([q, q + V(0, ln * 0.4, 0.006), q + V(0.005, ln * 0.75, 0.014), q + V(0.009, ln, 0.018)], [0.018, 0.02, 0.015, 0.009], "skin", seg=16, caps=True)
                    p.ellipsoid(q + V(0, ln * 0.4, 0.006), (0.021, 0.023, 0.02), "skin", seg=16)
                    p.ellipsoid(q + V(0.009, ln * 0.93, -0.002), (0.011, 0.018, 0.003), "bandage", seg=16)
                piece("finger_%d_%s" % (i, side), q, q + V(0, length, 0), "palm_" + side, finger)
        for side, sign in (("l", 1), ("r", -1)):
            h, k, a = V(sign * 0.13, 0.95, 0), V(sign * 0.26, 0.4, -0.18), V(sign * 0.3, 0.05, 0.12)
            piece("leg_" + side, h, k, "body", lambda p, h=h, k=k, a=a: p.tube([h, k, a], [0.085, 0.06, 0.04], "leather", caps=True))

    for obj in pieces:
        attr = obj.data.color_attributes.new(name="wear", type="FLOAT_COLOR", domain="POINT")
        for v in obj.data.vertices:
            x, y, z = v.co.x, v.co.z, -v.co.y
            noise = 0.5 + 0.25 * math.sin(x * 35 + y * 16) * math.sin(y * 27 - z * 19) + 0.15 * math.sin(x * 71 + z * 61)
            hem = max(0, 1 - abs(y - (0.84 if kind == "surveyor" else 0.48)) / 0.35)
            sweat = math.exp(-((y - 1.9) / 0.16) ** 2) * 0.55
            dirt = min(0.75, hem * 0.6 + sweat + noise * 0.16)
            attr.data[v.index].color = (1 - dirt * 0.65, 1 - dirt * 0.85, 1 - dirt * 0.95, 1)
    for slot in SLOTS:
        mat = bpy.data.materials[slot]
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        shader = nodes["Principled BSDF"]
        source = shader.inputs["Base Color"].links[0].from_socket
        vertex = nodes.new("ShaderNodeVertexColor")
        vertex.layer_name = "wear"
        mix = nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1
        links.new(source, mix.inputs[1])
        links.new(vertex.outputs["Color"], mix.inputs[2])
        links.new(mix.outputs["Color"], shader.inputs["Base Color"])

    bindings = {obj: obj.name for obj in pieces}
    # 头部皮肤融合成连续曲面，避免鼻梁、颧骨看起来是拼上去的小积木。
    head = next(obj for obj in pieces if obj.name == ("instruments" if kind == "surveyor" else "buried_head"))
    skin_obj = head.copy()
    skin_obj.data = head.data.copy()
    bpy.context.collection.objects.link(skin_obj)
    skin_obj.name = "head_skin"
    for obj, keep_skin in ((head, False), (skin_obj, True)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        discard = [f for f in bm.faces if (f.material_index == SLOTS.index("skin")) != keep_skin]
        bmesh.ops.delete(bm, geom=discard, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
    bpy.context.view_layer.objects.active = skin_obj
    remesh = skin_obj.modifiers.new("continuous_skin", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = 0.007
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    soften = skin_obj.modifiers.new("soft_tissue", "SMOOTH")
    soften.factor, soften.iterations = 0.65, 4
    bpy.ops.object.modifier_apply(modifier=soften.name)
    for poly in skin_obj.data.polygons:
        poly.material_index = SLOTS.index("skin")
        poly.use_smooth = True
    wear = skin_obj.data.color_attributes.get("wear") or skin_obj.data.color_attributes.new(name="wear", type="FLOAT_COLOR", domain="POINT")
    for v in skin_obj.data.vertices:
        n = 0.88 + 0.07 * math.sin(v.co.x * 47) * math.sin(v.co.z * 39)
        wear.data[v.index].color = (n, n * 0.96, n * 0.9, 1)
    pieces.append(skin_obj)
    bindings[skin_obj] = bindings[head]

    for obj in pieces:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()

    arm = bpy.data.armatures.new(kind + "_rig")
    rig = bpy.data.objects.new(kind + "_rig", arm)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, h, t, parent in bones:
        bone = arm.edit_bones.new(name)
        bone.head, bone.tail = B(h), B(t)
        if parent:
            bone.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in pieces:
        obj.parent = rig
        obj.vertex_groups.new(name=bindings[obj]).add(list(range(len(obj.data.vertices))), 1, "REPLACE")
        # glTF 的节点名全局唯一，网格不能和骨头重名，否则导入后骨名会被改写。
        obj.name = kind + "_mesh_" + obj.name
        obj.modifiers.new("Armature", "ARMATURE").object = rig
    # 合并为一张蒙皮网格，保留每段的骨骼权重；细节增多不必增加几十次绘制。
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = kind + "_mesh"
    pieces = [merged]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [rig] + pieces:
        obj.select_set(True)
    path = os.path.join(out, kind + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=False)
    print(kind, "faces", sum(len(o.data.polygons) for o in pieces), "exported", path)
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        kit["preview"](preview_dir)
        os.replace(os.path.join(preview_dir, "watchman_preview.png"), os.path.join(preview_dir, kind + ".png"))
        sc = bpy.context.scene
        sc.render.resolution_x = sc.render.resolution_y = 900
        target = Vector((0, -0.035, 2.41)) if kind == "surveyor" else Vector((-0.43, -0.19, 1.65))
        sc.camera.location = target + Vector((0.38, -0.95, 0.18))
        sc.camera.rotation_euler = (target - sc.camera.location).to_track_quat("-Z", "Y").to_euler()
        sc.camera.data.lens = 65
        sc.render.filepath = os.path.join(preview_dir, kind + "_head.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:]
    for kind in (args[2:] or ["surveyor", "door_holder"]):
        assert kind in ("surveyor", "door_holder"), kind
        build(kind, args[0], args[1] if len(args) > 1 else None)
