"""转换 Nodelete 的 CC0 乌鸦；保留原作外形，分成三个可批量绘制的网格。
Blender -b --factory-startup --disable-autoexec --python tools/blender/crows.py -- assets/models/crows.glb [预览目录]
源文件和原许可位于 tools/blender/sources/crow；原绑定不导入游戏。
"""
import json
import math
import os
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree

SOURCE = Path(__file__).resolve().parent / 'sources/crow/Crow.blend'
HEAD = Vector((0, .184930636, -.020764716))
WING = Vector((.056182187, .17, -.038051538))


def v(p):
    return Vector((p[0], -p[2], p[1]))


def group_part(name):
    if name == 'crow.head':
        return 'crow_head'
    if name.startswith(('crow.shoulder', 'crow.wing')):
        return 'crow_wing' if name.endswith('.R') else 'left'
    return 'crow_body'


def make_part(name, points, faces, colors):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(p) for p in points], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(MAT)
    attr = data.color_attributes.new(name='feather', type='FLOAT_COLOR', domain='CORNER')
    for poly, color in zip(data.polygons, colors):
        poly.use_smooth = True
        for loop in poly.loop_indices:
            attr.data[loop].color = (*color, 1)
    data.color_attributes.active_color_name = 'feather'
    data.color_attributes.render_color_index = 0
    return obj


def rod(points, faces, colors, a, b, radius):
    a, b = Vector(a), Vector(b)
    axis = (b-a).normalized()
    side = axis.cross(Vector((0, 0, 1))).normalized()*radius
    other = axis.cross(side)
    start = len(points)
    for center in [a, b]:
        for i in range(4):
            points.append(center+side*math.cos(i*math.tau/4)+other*math.sin(i*math.tau/4))
    new_faces = [(0, 3, 2, 1), (4, 5, 6, 7)]
    new_faces += [(i, (i+1)%4, (i+1)%4+4, i+4) for i in range(4)]
    faces.extend([tuple(start+i for i in face) for face in new_faces])
    colors.extend([(.07, .075, .08)]*len(new_faces))


def preview(parts, directory):
    os.makedirs(directory, exist_ok=True)
    # 展翅与收翅都用实际导出的网格，后者与 Godot 使用同样的转轴。
    for obj in parts.values():
        obj.hide_render = False
    body, head, wing = [parts[k] for k in ['crow_body', 'crow_head', 'crow_wing']]
    head.location = v(HEAD)
    wing.location = v(WING)
    left = wing.copy(); left.data = wing.data
    bpy.context.collection.objects.link(left)
    left.location = v((-WING.x, WING.y, WING.z))
    left.scale.x = -1
    # 模型之外的灯和相机只存在于预览中。
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 24
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    world = bpy.data.worlds.new('studio'); world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.25, .28, .32, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .7
    scene.world = world
    data = bpy.data.lights.new('key', 'AREA'); data.energy = 80; data.size = 1.5
    light = bpy.data.objects.new('key', data); scene.collection.objects.link(light)
    light.location = (1, 1, 1.5)
    light.rotation_euler = (Vector((0, 0, .2))-light.location).to_track_quat('-Z', 'Y').to_euler()
    data = bpy.data.cameras.new('camera'); data.lens = 52
    camera = bpy.data.objects.new('camera', data); scene.collection.objects.link(camera)
    camera.location = (1.1, 1.2, .9)
    camera.rotation_euler = (Vector((0, 0, .2))-camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = camera
    scene.render.filepath = os.path.join(directory, 'source_adapted.png')
    bpy.ops.render.render(write_still=True)


args = sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
crow = bpy.data.objects['Crow']
original_triangles = sum(len(p.vertices)-2 for p in crow.data.polygons)
for modifier in list(crow.modifiers):
    crow.modifiers.remove(modifier)
crow.hide_set(False)
crow.hide_viewport = False
bpy.context.view_layer.objects.active = crow
crow.select_set(True)
bpy.context.view_layer.update()
world_matrix = crow.matrix_world.copy()
weights = {}
for vertex in crow.data.vertices:
    sums = {}
    for group in vertex.groups:
        if group.weight <= 0:
            continue
        part = group_part(crow.vertex_groups[group.group].name)
        sums[part] = sums.get(part, 0)+group.weight
    weights[vertex.index] = sums
# 原作有 37 个未绑定顶点，包括翼尖的重合羽片；按最近的已绑定顶点补齐离线分区。
tree = KDTree(sum(bool(w) for w in weights.values()))
for vertex in crow.data.vertices:
    if weights[vertex.index]:
        tree.insert(vertex.co, vertex.index)
tree.balance()
for vertex in crow.data.vertices:
    if not weights[vertex.index]:
        _point, index, _distance = tree.find(vertex.co)
        weights[vertex.index] = weights[index]
polygons = {k: [] for k in ['crow_body', 'crow_head', 'crow_wing', 'left']}
for poly in crow.data.polygons:
    sums = {k: 0 for k in polygons}
    for index in poly.vertices:
        for part, weight in weights[index].items():
            sums[part] += weight
    polygons[max(sums, key=sums.get)].append(poly)
MAT = bpy.data.materials.new('crow game')
MAT.use_nodes = True
bsdf = MAT.node_tree.nodes['Principled BSDF']
bsdf.inputs['Roughness'].default_value = .92
color_node = MAT.node_tree.nodes.new('ShaderNodeVertexColor'); color_node.layer_name = 'feather'
MAT.node_tree.links.new(color_node.outputs['Color'], bsdf.inputs['Base Color'])
parts = {}
for name, pivot in [('crow_body', Vector()), ('crow_head', HEAD), ('crow_wing', WING)]:
    points, faces, colors, indices = [], [], [], {}
    for poly in polygons[name]:
        face = []
        for index in poly.vertices:
            if index not in indices:
                p = world_matrix @ crow.data.vertices[index].co
                # 源模型 +Y 朝前；转换为 Godot -Z，身体抬至脚上方。
                point = Vector((p.x, p.z+.17, -p.y))-pivot
                indices[index] = len(points)
                points.append(point)
            face.append(indices[index])
        faces.append(tuple(face))
        colors.append((.055, .065, .085))
    obj = make_part(name, points, faces, colors)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    # 先恢复并固定原作分区，再分别减面；运行时不需要保留权重。
    modifier = obj.modifiers.new('game reduction', 'DECIMATE')
    modifier.ratio = .86
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    if name == 'crow_body':
        # 原模型用于飞行剪影，没有脚；补上简化的栖枝脚爪。
        points, faces, colors = [], [], []
        for side in [-1, 1]:
            ankle = (side*.035, .025, .01)
            rod(points, faces, colors, (side*.03, .14, .02), ankle, .008)
            for dx, z in [(-.018, -.035), (.018, -.035), (0, .055)]:
                rod(points, faces, colors, ankle, (side*.035+dx, .004, z), .004)
        feet = make_part('feet', points, faces, colors)
        feet.select_set(True)
        bpy.ops.object.join()
    parts[name] = obj
for obj in list(bpy.context.scene.objects):
    if obj not in parts.values():
        bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.abspath(args[0]), export_format='GLB', use_selection=True, export_apply=True,
                         export_vertex_color='NAME', export_vertex_color_name='feather', export_all_vertex_colors=False)
report = {'source_triangles': original_triangles, 'parts': {name: sum(len(p.vertices)-2 for p in obj.data.polygons) for name, obj in parts.items()},
          'head_pivot': list(HEAD), 'wing_pivot': list(WING)}
print(json.dumps(report))
if len(args) > 1:
    preview(parts, args[1])
