"""原创破墓与枯树。Godot: y 向上，土坟/开棺墓沿 Z，墙龛 +Z 朝通道；原点在地面。
Blender -b --factory-startup --python tools/blender/graves.py -- assets/models/graves.glb [预览目录]
土坟与开棺墓位于独立墓区，沿 Z 轴容纳成人棺材；墙龛仍贴墙摆放。
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

MATS = {}
RNG = random.Random(73091)


def v(x, y, z):
    return Vector((x, -z, y))


def material(name, color, metal=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = 0.94 if metal == 0 else 0.78
    bsdf.inputs['Metallic'].default_value = metal
    # 预览与 glTF 都使用顶点上的剥蚀、泥渍和锈斑。
    colors = mat.node_tree.nodes.new('ShaderNodeVertexColor')
    colors.layer_name = 'weather'
    mix = mat.node_tree.nodes.new('ShaderNodeMixRGB')
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1
    mix.inputs[1].default_value = (*color, 1)
    noise = mat.node_tree.nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 22 if name != 'earth' else 38
    noise.inputs['Detail'].default_value = 3
    ramp = mat.node_tree.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = .22
    ramp.color_ramp.elements[0].color = tuple(c*.34 for c in color)+(1,)
    ramp.color_ramp.elements[1].position = .78
    ramp.color_ramp.elements[1].color = (*color,1)
    mat.node_tree.links.new(noise.outputs['Fac'], ramp.inputs[0])
    mat.node_tree.links.new(ramp.outputs['Color'], mix.inputs[1])
    bump = mat.node_tree.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .55
    bump.inputs['Distance'].default_value = .045
    mat.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height'])
    mat.node_tree.links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
    mat.node_tree.links.new(colors.outputs['Color'], mix.inputs[2])
    mat.node_tree.links.new(mix.outputs[0], bsdf.inputs['Base Color'])
    MATS[name] = mat


def mesh(name, vertices, faces, slot, bevel=0.0):
    data = bpy.data.meshes.new(name)
    data.from_pydata([v(*p) for p in vertices], [], faces)
    data.materials.append(MATS[slot])
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    if bevel:
        modifier = obj.modifiers.new('worn edges', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        modifier.affect = 'EDGES'
    return obj


def box(name, at, size, slot, bevel=0.02, rotation=(0, 0, 0)):
    x, y, z = at
    w, h, d = size
    verts = [(x + sx*w/2, y + sy*h/2, z + sz*d/2) for sx, sy, sz in
             [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
    obj = mesh(name, verts, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], slot, bevel)
    if slot == 'stone':
        for vert in obj.data.vertices:
            vert.co += Vector((RNG.uniform(-.035,.035), RNG.uniform(-.013,.013), RNG.uniform(-.025,.025)))
    # 绕物件中心旋转，保持整体占地可控。
    center = v(x,y,z)
    for vert in obj.data.vertices:
        vert.co -= center
    obj.location = center
    obj.rotation_euler = (rotation[0], rotation[2], rotation[1])
    return obj


def stone(name, center, size, slot='stone'):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=v(*center))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0]/2, size[2]/2, size[1]/2)
    for p in obj.data.vertices:
        p.co *= RNG.uniform(0.82, 1.08)
    obj.data.materials.append(MATS[slot])
    if slot == 'earth':
        for poly in obj.data.polygons:
            poly.use_smooth = True
    obj.modifiers.new('chipped edges', 'BEVEL').width = 0.012
    return obj


def slab(name, outline, depth, slot='stone'):
    """沿 z 挤出的破碎轮廓。"""
    n = len(outline)
    verts = [(x,y,z) for z in depth for x,y in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name, verts, faces, slot, 0.012)


def line(name, points, radius, slot, sides=6):
    """低成本圆截面，铁链和刻痕都是真实几何。"""
    points = [v(*p) for p in points]
    verts = []
    for i, p in enumerate(points):
        tangent = (points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
        normal = tangent.cross(Vector((0,0,1)))
        if normal.length < 0.01:
            normal = tangent.cross(Vector((1,0,0)))
        normal.normalize()
        other = tangent.cross(normal).normalized()
        for j in range(sides):
            q = p + radius*(normal*math.cos(j*math.tau/sides)+other*math.sin(j*math.tau/sides))
            verts.append((q.x,q.z,-q.y))
    faces = []
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*sides+j; b=i*sides+(j+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces += [tuple(reversed(range(sides))), tuple(range((len(points)-1)*sides,len(points)*sides))]
    return mesh(name, verts, faces, slot)


def chain(name, a, b):
    a, b = Vector(a), Vector(b)
    axis = (b-a).normalized()
    across = axis.cross(Vector((0,0,1))).normalized()
    for i in range(18):
        center = a.lerp(b, i/17)
        side = across if i%2==0 else Vector((0,0,1))
        ring = [center + axis*math.cos(j*math.tau/12)*0.085 + side*math.sin(j*math.tau/12)*0.05 for j in range(13)]
        line(name, ring, 0.017, 'iron')


def scratches(x, y, z, count=5, along_x=True):
    for i in range(count):
        if along_x:
            p = x+i*0.09
            line('erased name', [(p,y,z),(p+0.015,y+0.18,z)],0.006,'void',4)
        else:
            p = z+i*0.085
            line('erased name', [(x,y,p),(x,y+0.2,p+0.012)],0.006,'void',4)


def finish(name, before):
    objs = [o for o in bpy.context.scene.objects if o.type=='MESH' and o not in before]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        # 对每片面染上稳定的泥渍和磨损色，避免均匀塑料外观。
        attr = obj.data.color_attributes.new(name='weather', type='FLOAT_COLOR', domain='CORNER')
        for poly in obj.data.polygons:
            brightness = RNG.uniform(0.65,1.0)
            for loop_index in poly.loop_indices:
                local = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
                world = obj.matrix_world @ local
                low = max(0.0,min(1.0,world.z/0.45))
                dirt = 0.62+0.38*low
                attr.data[loop_index].color = (brightness*dirt, brightness*dirt*0.98, brightness*dirt*0.91,1)
        obj.select_set(True)
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    for attr in list(obj.data.color_attributes):
        if attr.name != 'weather':
            obj.data.color_attributes.remove(attr)
    obj.data.color_attributes.active_color_name = 'weather'
    obj.data.color_attributes.render_color_index = 0
    # 导出原点统一在地面，方便通行区和碰撞的独立验证。
    bpy.context.scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    obj.data.name = name
    return obj


def cross(at, tilt, stone_cross=False):
    """接近两米长的十字架，绕底端倾倒，横梁保持清楚轮廓。"""
    from mathutils import Matrix
    before = set(bpy.context.scene.objects)
    slot = 'stone' if stone_cross else 'wood'
    box('cross upright', (0, .94, 0), (.19, 1.88, .19), slot, .022)
    box('cross arms', (0, 1.42, 0), (1.12, .21, .20), slot, .025)
    box('rusted cross binding', (0, 1.42, -.115), (.25, .32, .035), 'iron', .008)
    # Blender X 对应 Godot X；再向侧面歪斜，避免像整齐的公墓。
    rotation = Matrix.Rotation(math.radians(tilt), 4, 'X') @ Matrix.Rotation(math.radians(-10), 4, 'Y')
    matrix = Matrix.Translation(v(*at)) @ rotation
    bpy.context.view_layer.update()
    for obj in set(bpy.context.scene.objects) - before:
        obj.matrix_world = matrix @ obj.matrix_world


def headstone(cross_top):
    from mathutils import Matrix
    before = set(bpy.context.scene.objects)
    box('headstone plinth', (0,.12,0), (1.12,.24,.48), 'stone', .04)
    if cross_top:
        outline=[(-.44,.22),(.44,.22),(.44,.98),(.28,1.23),(.13,1.33),(.13,1.57),(.43,1.57),(.43,1.8),(.13,1.8),(.13,2.1),(-.13,2.1),(-.13,1.8),(-.43,1.8),(-.43,1.57),(-.13,1.57),(-.13,1.33),(-.29,1.2),(-.44,.98)]
    else:
        outline=[(-.44,.2),(.44,.2),(.44,1.18),(.34,1.36),(.15,1.45),(-.08,1.49),(-.3,1.4),(-.44,1.32)]
    slab('fractured headstone',outline,(-.13,.13))
    # 分叉裂纹和脱落的石片，正反面都可辨认。
    for face in [-.145,.145]:
        for points in [[(-.13,1.35),(-.2,1.08),(-.07,.83),(-.18,.54),(-.12,.23)], [(-.07,.83),(.15,.68),(.26,.42),(.44,.35)], [(-.2,1.08),(-.38,.95),(-.44,.76)]]:
            line('headstone crack',[(x,y,face) for x,y in points],.008,'void',4)
    # 极短的通用墓志，让远近都能读出墓碑用途。
    bpy.ops.object.text_add(location=v(0,.72,.15),rotation=(math.pi/2,0,0))
    text=bpy.context.object
    text.name='weathered epitaph'
    text.data.body='RIP'
    text.data.align_x='CENTER'
    text.data.size=.28
    text.data.extrude=.001
    text.data.materials.append(MATS['void'])
    bpy.ops.object.convert(target='MESH')
    matrix=Matrix.Translation(v(0,0,-1.35)) @ Matrix.Rotation(math.radians(-6 if cross_top else 8),4,'Y')
    bpy.context.view_layer.update()
    for obj in set(bpy.context.scene.objects)-before:
        obj.matrix_world=matrix @ obj.matrix_world


def dead_tree():
    before=set(bpy.context.scene.objects)
    def limb(points,radii):
        for a,b,ra,rb in zip(points,points[1:],radii,radii[1:]):
            a,b=v(*a),v(*b)
            bpy.ops.mesh.primitive_cone_add(vertices=7,radius1=ra,radius2=rb,depth=(b-a).length,location=(a+b)/2)
            obj=bpy.context.object
            obj.name='twisted dead branch'
            obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
            obj.data.materials.append(MATS['wood'])
    trunk=[(0,0,0),(.08,1.2,.06),(-.13,2.6,.1),(.06,3.8,0),(-.13,5,.15),(.1,6.3,.05)]
    limb(trunk,[.17,.15,.13,.1,.055,.008])
    branches=[[(.06,3.8,0),(-.65,4.25,.1),(-1.3,4.35,.05),(-1.9,4.95,-.1)],
              [(-.13,2.6,.1),(.7,3.6,.5),(1.4,4,.8),(1.9,4.7,1.0)],
              [(-.13,5,.15),(.6,5.3,-.6),(1.2,5.2,-1.2),(1.7,5.8,-1.55)],
              [(.06,3.8,0),(-.4,4.6,-.7),(-.8,5.4,-1.25),(-1.35,5.9,-1.5)],
              [(-.13,5,.15),(-.75,5.75,.7),(-1.1,6.5,1.25)],
              [(.7,3.6,.5),(.65,4.6,1.15),(.9,5.4,1.7)]]
    for points in branches:
        limb(points,[.08,.05,.025,.004][:len(points)])
        p=Vector(points[-2]); q=Vector(points[-1])
        for side in [-1,1]:
            root=p.lerp(q,.45 if side<0 else .72)
            twig=root+Vector((side*.4,.5,RNG.uniform(-.35,.35)))
            tip=twig+Vector((side*.2,.4,RNG.uniform(-.2,.2)))
            limb([tuple(root),tuple(twig),tuple(tip)],[.022,.012,.003])
    for dx,dz in [(.4,.15),(-.35,.24),(.1,-.42)]:
        limb([(dx,.025,dz),(0,.3,0)],[.025,.11])
    return finish('grave_tree',before)


def mound():
    before = set(bpy.context.scene.objects)
    stone('adult burial mound', (0, .23, .18), (1.5, .65, 2.95), 'earth')
    # 石圈标出完整墓穴边界，塌土里露出成人棺盖。
    for side in [-1, 1]:
        for i in range(6):
            stone('burial border', (side*.7, .1, -1.18+i*.5), (.24,.23,.36))
    for i in range(6):
        box('exposed coffin lid', (0,.4,-.76+i*.32), (.73,.065,.3), 'wood', .012, rotation=(.03,0,.025))
    line('split coffin lid', [(-.14,.44,-.85),(.04,.445,-.4),(-.08,.44,.12),(.1,.44,.7)], .015, 'void', 4)
    headstone(True)
    box('fallen name tablet', (.28,.12,1.45), (.7,.16,.43), 'stone', .03, rotation=(0,.16,0))
    for i in range(9):
        stone('loose grave soil',(RNG.uniform(-.62,.62),.07,RNG.uniform(-1.15,1.5)),(.17,.15,.23),'earth')
    return finish('grave_mound', before)


def open_grave():
    before = set(bpy.context.scene.objects)
    # 2.24 × 0.84 × 0.56 米完整棺材；石砌墓穴抬起，不挖穿迷宫地面。
    box('grave darkness', (0,.055,.12), (1.25,.055,2.72), 'void', 0)
    for side in [-1,1]:
        for i in range(6):
            if side == 1 and i == 3:
                continue
            box('broken grave curb',(side*.7,.22,-1.14+i*.5),(.18,.42,.45),'stone',.035,rotation=(0,RNG.uniform(-.05,.05),0))
    for z in [-1.4,1.62]:
        box('grave footstone',(0,.2,z),(1.52,.38,.18),'stone',.035)
    for side in [-1,1]:
        box('coffin side',(side*.42,.34,.12),(.065,.56,2.24),'wood',.015)
    for z in [-1.0,1.24]:
        box('coffin end',(0,.34,z),(.9,.56,.065),'wood',.015)
    for i in range(7):
        box('coffin bottom',(0,.095,-.85+i*.3),(.77,.065,.28),'wood',.008)
    for side in [-1,1]:
        for z in [-.55,.72]:
            line('coffin handle',[(side*.46,.36,z-.16),(side*.54,.27,z-.16),(side*.54,.27,z+.16),(side*.46,.36,z+.16)],.025,'iron')
    # 半片裂盖靠在棺沿，另一片已经折进墓里。
    box('split coffin lid',(-.22,.69,.08),(.39,.065,2.2),'wood',.015,rotation=(0,0,.28))
    for z in [-.62,.65]:
        box('lid iron strap',(-.22,.74,z),(.4,.035,.075),'iron',.008,rotation=(0,0,.28))
    box('fallen lid fragment',(.12,.2,.52),(.3,.07,.67),'wood',.012,rotation=(.13,.12,0))
    headstone(False)
    cross((0,.03,-.95), 74)
    for i in range(7):
        stone('spilled soil',(RNG.uniform(-.58,.58),.08,RNG.uniform(-1.25,1.4)),(.19,.15,.21),'earth')
    return finish('grave_open', before)


def wall_crypt():
    before=set(bpy.context.scene.objects)
    slab('sealed recess',[(-1.08,.06),(1.08,.06),(1.08,2.13),(.78,2.47),(-.78,2.47),(-1.08,2.13)],(.025,.09),'void')
    for side in [-1,1]:
        for i in range(5):
            if side == -1 and i == 3:
                continue
            box('crypt jamb',(side*.97,.27+i*.43,.21),(.21,.39,.3),'stone',.045)
    for x,y,angle in [(-.82,2.27,-.5),(-.5,2.47,-.3),(.09,2.51,.02),(.48,2.47,.32),(.81,2.27,.5)]:
        box('broken arch',(x,y,.19),(.35,.27,.32),'stone',.04,rotation=(0,0,angle))
    box('crypt sill',(0,.12,.29),(2.15,.24,.56),'stone',.035)
    # 纵立棺盖分成两片，中间黑缝和碎角清晰可见。
    slab('coffin left',[(-.7,.33),(-.05,.33),(-.02,.93),(-.09,1.28),(-.015,1.65),(-.08,2.17),(-.48,2.24),(-.72,1.93)],(.12,.47))
    slab('coffin right',[(.07,.33),(.68,.33),(.72,1.93),(.5,2.24),(.07,2.17),(.12,1.64),(.03,1.28),(.1,.9)],(.12,.49))
    for x in [-.62,.62]:
        for y in [.5,1.9]:
            box('rusted fixing',(x,y,.51),(.12,.14,.08),'iron',.012)
    chain('binding chain',(-.83,.42,.53),(.83,2.11,.53))
    chain('binding chain',(.83,.42,.58),(-.83,2.11,.58))
    box('corroded lock',(0,1.19,.62),(.23,.3,.1),'iron',.025)
    box('scraped tablet',(0,2.03,.515),(.65,.17,.02),'void',.004)
    scratches(-.22,1.96,.531)
    line('lid fracture',[(-.61,.7,.488),(-.43,.9,.488),(-.52,1.1,.488),(-.3,1.34,.488)],.009,'void',4)
    stone('broken jamb fragment',(-.83,.09,.41),(.31,.19,.25))
    return finish('grave_wall',before)


def preview(objs, directory):
    os.makedirs(directory,exist_ok=True)
    objs[3].hide_render=True
    for obj,x in zip(objs,[-4,0,4]):
        obj.location.x=x
    bpy.ops.mesh.primitive_plane_add(size=30,location=(0,0,-.025))
    bpy.context.object.data.materials.append(MATS['earth'])
    # 预览只在导出之后搭建，墙与灯不会进入 GLB。
    for x in [-4,0,4]:
        box('reference wall',(x,1.5,-2.1),(3.5,3,.25),'stone',.01)
    # 1.8 米无面孔人形，用于比较成人棺材的比例，不导出。
    stone('1.8m reference head',(-2,1.65,1.2),(.24,.3,.24),'stone')
    box('reference torso',(-2,1.17,1.2),(.42,.65,.24),'stone')
    for dx in [-.12,.12]:
        box('reference leg',(-2+dx,.44,1.2),(.15,.86,.17),'stone')
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and not obj.data.color_attributes.get('weather'):
            attr=obj.data.color_attributes.new(name='weather',type='FLOAT_COLOR',domain='CORNER')
            for item in attr.data:item.color=(1,1,1,1)
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=32
    scene.render.resolution_x=1500
    scene.render.resolution_y=820
    scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    world=bpy.data.worlds.new('overcast')
    world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.16,.19,.23,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
    scene.world=world
    for pos,power,size in [((-3,-4,7),1700,6),((5,-1,5),900,4)]:
        data=bpy.data.lights.new('softbox','AREA');data.energy=power;data.shape='DISK';data.size=size
        obj=bpy.data.objects.new('softbox',data);scene.collection.objects.link(obj);obj.location=pos
        obj.rotation_euler=(Vector((0,0,1))-obj.location).to_track_quat('-Z','Y').to_euler()
    data=bpy.data.cameras.new('camera');data.lens=43
    cam=bpy.data.objects.new('camera',data);scene.collection.objects.link(cam)
    cam.location=(8,-15,10)
    cam.rotation_euler=(Vector((0,0,.65))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.camera=cam;scene.render.filepath=os.path.join(directory,'graves_preview.png')
    bpy.ops.render.render(write_still=True)


def main():
    args=sys.argv[sys.argv.index('--')+1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    material('stone',(.4,.37,.32));material('earth',(.2,.13,.085));material('wood',(.24,.15,.09))
    material('iron',(.26,.12,.055),.65);material('void',(.018,.014,.014))
    objs=[mound(),open_grave(),wall_crypt(),dead_tree()]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(args[0]),export_format='GLB',use_selection=True,export_apply=True,export_normals=True,
                              export_vertex_color='NAME',export_vertex_color_name='weather',export_all_vertex_colors=False)
    for obj in objs:
        corners=[obj.matrix_world@Vector(c) for c in obj.bound_box]
        print(obj.name,'vertices=',len(obj.data.vertices),'bounds=',tuple(min(v[i] for v in corners) for i in range(3)),tuple(max(v[i] for v in corners) for i in range(3)))
    if len(args)>1:preview(objs,args[1])


if __name__=='__main__':main()
