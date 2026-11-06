"""适配用户本机授权的 Last Offering；不保存/分发原 .blend 或纹理。
Blender -b --factory-startup --disable-autoexec --python tools/blender/hanged_one.py -- SOURCE.blend
输出仅在被 git 忽略且被公开导出排除的 assets/private/ 中。
"""
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

source = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
output = Path(__file__).resolve().parents[2] / 'assets/private/hanged_one.glb'
bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
assert {obj.name for obj in meshes} == {'Body', 'Foots', 'Glue', 'Hands', 'Rope'}
rope = bpy.data.objects['Rope']
points = [rope.matrix_world @ vertex.co for vertex in rope.data.vertices]
top = max(point.z for point in points)
tips = [point for point in points if point.z >= top - .015]
pivot = sum(tips, Vector()) / len(tips)
pivot.z = top
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    obj.select_set(True)
bpy.context.view_layer.objects.active = bpy.data.objects['Body']
bpy.ops.object.join()
model = bpy.context.object
model.name = 'hanged_one'
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.context.scene.cursor.location = pivot
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
model.location = (0, 0, 0)
model.data.calc_loop_triangles()
original = len(model.data.loop_triangles)
modifier = model.modifiers.new('game_budget', 'DECIMATE')
modifier.ratio = 11900 / original
bpy.ops.object.modifier_apply(modifier=modifier.name)
model.data.calc_loop_triangles()
textures = []
for node in model.active_material.node_tree.nodes:
    if node.type == 'TEX_IMAGE':
        node.image.scale(1024, 1024)
        # GLTF 使用缩小后的像素，避免重新取用原始 packed JPEG。
        node.image.pack()
        textures.append({'name': node.image.name, 'size': list(node.image.size)})
output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', use_selection=True,
                          export_animations=False, export_extras=False,
                          export_image_format='JPEG', export_jpeg_quality=85)
report = {'source_triangles': original, 'triangles': len(model.data.loop_triangles),
          'textures': textures, 'bytes': output.stat().st_size,
          'source_pivot': list(pivot), 'unit_scale': bpy.context.scene.unit_settings.scale_length,
          'bounds_blender': [list(model.matrix_world @ Vector(c)) for c in model.bound_box]}
Path('/tmp/leviathan-hanged-one').mkdir(exist_ok=True)
Path('/tmp/leviathan-hanged-one/model-report.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report))
