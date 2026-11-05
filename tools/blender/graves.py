"""原创破墓三件套。Godot: x 沿墙，y 向上，+z 朝通道；原点在墙根地面。
Blender -b --factory-startup --python tools/blender/graves.py -- assets/models/graves.glb [预览目录]
单件实体范围限制在 x ±1.42、z 0..1.02，留出 5 米街道的中央通行带。
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
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
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
    # 导出原点统一在墙根地面，方便通行区和碰撞的独立验证。
    bpy.context.scene.cursor.location = (0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    obj.data.name = name
    return obj


def mound():
    before = set(bpy.context.scene.objects)
    stone('sunken earth', (0,0.12,0.53),(2.55,0.38,0.87),'earth')
    # 侧向立的断碑，斜断的顶沿、露出的断口和磨掉的铭文。
    stone('headstone foot',(-1.06,0.1,0.53),(0.4,0.2,0.83))
    obj = slab('broken upright', [(-0.36,0),(.36,0),(.34,.66),(.16,.82),(.03,.73),(-.13,.93),(-.34,.85)],(0,0.15))
    obj.location = v(-1.04,0.16,0.52)
    obj.rotation_euler = (0,math.radians(-9),math.pi/2)
    # 刮除名字的深色石牌和五道无法计完的刻痕。
    box('rubbed plaque',(-0.91,0.58,0.52),(.025,.28,.46),'void',.005)
    scratches(-0.893,.48,.34,5,False)
    for x in [-.35,-.08,.2,.48]:
        box('exposed coffin plank',(x,.22,.63),(.22,.06,.48),'wood',.009,rotation=(0,0,.04))
    line('coffin fracture',[(-.45,.254,.61),(-.15,.255,.55),(.1,.254,.65),(.57,.252,.62)],.012,'void',4)
    for i in range(7):
        x=RNG.uniform(-1.25,1.25); z=RNG.uniform(.12,.92)
        stone('fallen masonry',(x,.07,z),(RNG.uniform(.13,.3),.13,RNG.uniform(.1,.2)))
    return finish('grave_mound', before)


def open_grave():
    before = set(bpy.context.scene.objects)
    # 抬起的破墓边缘包住空棺，不需要给迷宫地面挖出无碰撞的洞。
    box('black grave bed',(0,.035,.52),(2.42,.025,.82),'void',0)
    for side in [-1,1]:
        z=.1 if side==-1 else .93
        for i in range(5):
            if side==1 and i==3:continue
            box('broken curb',(-1.08+i*.54,.17,z),(.49,.3 if i%2 else .25,.16),'stone',.045,rotation=(0,RNG.uniform(-.04,.04),0))
    for x in [-1.31,1.31]:
        box('endstone',(x,.16,.52),(.16,.3,.89),'stone',.035)
    for x in [-.9,.3]:
        line('curb crack',[(x,.31,.89),(x+.06,.23,1.015),(x-.025,.08,1.015)],.009,'void',4)
    # 空棺有独立侧板、内壁、铁把手，裂盖倚在墙边。
    for z in [.25,.79]:
        box('coffin side',(0,.17,z),(2.15,.23,.055),'wood',.012)
    for x in [-1.08,1.08]:
        box('coffin end',(x,.17,.52),(.05,.23,.59),'wood',.01)
    for x in [-.62,.62]:
        line('rusted handle',[(x-.14,.16,.85),(x-.14,.12,.89),(x+.14,.12,.89),(x+.14,.16,.85)],.022,'iron')
    lid = slab('split lid',[(-1.04,0),(.05,0),(.17,.14),(.07,.23),(.21,.38),(.1,.56),(-1.04,.56)],(0,.055),'wood')
    lid.location=v(-.02,.28,.12)
    lid.rotation_euler=(math.radians(8),0,0)
    box('lid iron strap',(-.73,.54,.17),(.09,.5,.035),'iron',.01,rotation=(.14,0,0))
    stone('fallen lid fragment',(.69,.12,.55),(.55,.17,.38),'wood')
    for i in range(5):
        stone('spilled soil',(RNG.uniform(-1.2,1.2),.08,RNG.uniform(.15,.9)),(.18,.14,.15),'earth')
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
    for obj,x in zip(objs,[-3.4,0,3.4]):
        obj.location.x=x
    bpy.ops.mesh.primitive_plane_add(size=30,location=(0,0,-.025))
    bpy.context.object.data.materials.append(MATS['earth'])
    # 预览只在导出之后搭建，墙与灯不会进入 GLB。
    for x in [-3.4,0,3.4]:
        box('reference wall',(x,1.5,-.14),(3.2,3,.25),'stone',.01)
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
    cam.location=(7,-11,7)
    cam.rotation_euler=(Vector((0,-.3,.85))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.camera=cam;scene.render.filepath=os.path.join(directory,'graves_preview.png')
    bpy.ops.render.render(write_still=True)


def main():
    args=sys.argv[sys.argv.index('--')+1:]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    material('stone',(.4,.37,.32));material('earth',(.2,.13,.085));material('wood',(.24,.15,.09))
    material('iron',(.26,.12,.055),.65);material('void',(.018,.014,.014))
    objs=[mound(),open_grave(),wall_crypt()]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(args[0]),export_format='GLB',use_selection=True,export_apply=True,export_normals=True,
                              export_vertex_color='NAME',export_vertex_color_name='weather',export_all_vertex_colors=False)
    for obj in objs:
        corners=[obj.matrix_world@Vector(c) for c in obj.bound_box]
        print(obj.name,'vertices=',len(obj.data.vertices),'bounds=',tuple(min(v[i] for v in corners) for i in range(3)),tuple(max(v[i] for v in corners) for i in range(3)))
    if len(args)>1:preview(objs,args[1])


if __name__=='__main__':main()
