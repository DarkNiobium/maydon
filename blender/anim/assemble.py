"""assemble.py -- build actions from cache/*.npz into the reference rig, render contact
sheets, export the glb library + JSON sidecar.

nice blender -b ref.blend --python assemble.py -- [--render] [--export] [--side] [names...]
"""
import bpy, sys, os, json, math, subprocess, glob, shutil
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mlib as M

OUT = os.path.expanduser('~/maydon/game/assets/chars')
PREV = os.path.join(OUT, 'anim_previews')
CACHE = os.path.join(HERE, 'cache')
TMP = os.path.join(HERE, 'tmp_render')

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
DO_RENDER = '--render' in argv
DO_EXPORT = '--export' in argv
SIDE = '--side' in argv
names = [a for a in argv if not a.startswith('--')]
FRAMES = None
SUFFIX = ''
for a in argv:
    if a.startswith('--frames='):
        FRAMES = [int(x) for x in a.split('=')[1].split(',')]
    if a.startswith('--suffix='):
        SUFFIX = a.split('=')[1]
VIEW = 'side' if SIDE else 'q'
for a in argv:
    if a.startswith('--view='):
        VIEW = a.split('=')[1]

bpy.context.scene.render.fps = 30
bpy.context.scene.render.fps_base = 1.0
arm = bpy.data.objects['Human.rig']
body = bpy.data.objects['Human']
rig = M.Rig.from_blender(arm)

ORDER = []
try:
    import clips
    ORDER = list(clips.CLIPS.keys())
except Exception as e:
    print('WARN clips import', e)


def load_npz(n):
    d = np.load(os.path.join(CACHE, n + '.npz'))
    return d['L'].astype(float), d['loc'].astype(float), json.loads(str(d['meta']))


def remap(L, rig_names_cache=None):
    return L


if not names:
    names = [os.path.basename(p)[:-4] for p in sorted(glob.glob(os.path.join(CACHE, '*.npz')))]
    names = [n for n in names if not n.startswith('cand_') and not n.endswith('_dbg')]
    names.sort(key=lambda n: ORDER.index(n) if n in ORDER else 999)

actions = {}
metas = {}
for n in names:
    L, loc, meta = load_npz(n)
    act, slot = M.write_action(bpy, arm, n, L, loc, fps=30)
    actions[n] = (act, slot)
    metas[n] = meta
print('ACTIONS', len(actions))


def assign(n):
    act, slot = actions[n]
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        ad.action_slot = slot
    except Exception:
        pass


# ------------------------------------------------------------------ preview scene
def setup_scene():
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.fps = 30
    sc.render.resolution_x = 280
    sc.render.resolution_y = 380
    sc.render.film_transparent = False
    world = sc.world or bpy.data.worlds.new('W')
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.32, 0.34, 0.37, 1)
    bg.inputs[1].default_value = 0.7
    mat = bpy.data.materials.new('grey')
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (0.62, 0.62, 0.62, 1)
    bsdf.inputs['Roughness'].default_value = 0.65
    body.data.materials.clear()
    body.data.materials.append(mat)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o not in (body,):
            o.hide_render = True
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    gp = bpy.context.active_object
    gm = bpy.data.materials.new('ground')
    gm.use_nodes = True
    gb = next(n for n in gm.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    # checker so foot sliding is visible across frames
    tex = gm.node_tree.nodes.new('ShaderNodeTexChecker')
    tex.inputs['Scale'].default_value = 16.0
    tex.inputs['Color1'].default_value = (0.42, 0.44, 0.40, 1)
    tex.inputs['Color2'].default_value = (0.36, 0.38, 0.34, 1)
    gm.node_tree.links.new(tex.outputs['Color'], gb.inputs['Base Color'])
    gp.data.materials.append(gm)
    cam = bpy.data.cameras.new('cam')
    co = bpy.data.objects.new('cam', cam)
    sc.collection.objects.link(co)
    sc.camera = co
    cam.type = 'ORTHO'
    cam.ortho_scale = 2.5
    if VIEW == 'side':  # from the character's right
        co.location = (-6.0, 0.0, 0.95)
        co.rotation_euler = (math.radians(90), 0, math.radians(-90))
    elif VIEW == 'front':
        co.location = (0.0, -6.0, 1.0)
        co.rotation_euler = (math.radians(88), 0, 0)
    elif VIEW == 'top':
        co.location = (0.0, 0.0, 7.0)
        co.rotation_euler = (0, 0, 0)
    if VIEW == 'q':
        # front-right three-quarter view (character faces -Y, its right side is -X)
        ang = math.radians(-35)
        d = 6.0
        co.location = (d * math.sin(ang), -d * math.cos(ang), 1.35)
        co.rotation_euler = (math.radians(84), 0, ang)
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 3.5
    so = bpy.data.objects.new('sun', sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(35), math.radians(10), math.radians(-30))
    return sc


def render_sheet(sc, n, frames, title):
    os.makedirs(TMP, exist_ok=True)
    for f in glob.glob(os.path.join(TMP, '*.png')):
        os.remove(f)
    assign(n)
    files = []
    cam = sc.camera
    base = cam.location.copy()
    for k, f in enumerate(frames):
        sc.frame_set(int(f))
        pw = arm.matrix_world @ arm.pose.bones['pelvis'].head
        cam.location = (base[0] + pw[0], base[1] + pw[1], base[2])
        fp = os.path.join(TMP, '%02d_f%03d_%.2fs.png' % (k, f, f / 30.0))
        sc.render.filepath = fp
        bpy.ops.render.render(write_still=True)
        files.append(fp)
    cam.location = base
    os.makedirs(PREV, exist_ok=True)
    out = os.path.join(PREV if not SUFFIX else TMP + '_dbg', n + SUFFIX + '.png')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    labels = []
    cmd = ['montage']
    for fp in files:
        lab = os.path.basename(fp)[3:-4].replace('_', ' ')
        cmd += ['-label', lab, fp]
    cmd += ['-tile', '%dx1' % len(files), '-geometry', '+2+2', '-pointsize', '13', '-background', '#202020',
            '-fill', '#dddddd', '-title', title, out]
    subprocess.run(cmd, check=False)
    print('SHEET', out)


def pick_frames(meta, F):
    if meta.get('type') == 'loop':
        N = F - 1
        return [int(round(i * N / 6.0)) for i in range(6)]
    fr = list(np.linspace(0, F - 1, 6).round().astype(int))
    ct = meta.get('contact_time')
    if ct is not None:
        c = int(round(ct * 30))
        j = int(np.argmin([abs(x - c) for x in fr[1:-1]])) + 1
        fr[j] = c
        fr = sorted(set(fr))
    return fr


if DO_RENDER:
    sc = setup_scene()
    for n in names:
        meta = metas[n]
        F = meta['frames']
        frames = FRAMES or pick_frames(meta, F)
        bits = [n, 'src=%s' % os.path.basename(str(meta.get('src', 'handkey')))]
        if 'speed' in meta:
            bits.append('%.2f m/s, cycle %.2fs' % (meta['speed'], meta['duration']))
        if 'contact_time' in meta:
            bits.append('contact %.2fs' % meta['contact_time'])
        render_sheet(sc, n, frames, '  '.join(bits))


# ------------------------------------------------------------------ export
def export_lib():
    # stand-in mesh: body without helpers/shape keys, decimated, keeps weights
    src = body
    arm_mods = [m for m in src.modifiers if m.type == 'ARMATURE']
    for m in arm_mods:
        m.show_viewport = False
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(src.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    for m in arm_mods:
        m.show_viewport = True
    me.name = 'MaydonRefBody'
    ob = bpy.data.objects.new('MaydonRefBody', me)
    bpy.context.scene.collection.objects.link(ob)
    for vg in src.vertex_groups:  # same order -> same dvert indices
        ob.vertex_groups.new(name=vg.name)
    ob.parent = arm
    ob.matrix_world = src.matrix_world.copy()
    dec = ob.modifiers.new('dec', 'DECIMATE')
    dec.ratio = 0.3
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=dec.name)
    # drop helper / non-bone vertex groups
    bone_names = set(b.name for b in arm.data.bones)
    for vg in list(ob.vertex_groups):
        if vg.name not in bone_names:
            ob.vertex_groups.remove(vg)
    am = ob.modifiers.new('Armature', 'ARMATURE')
    am.object = arm
    ob.data.materials.clear()
    mat = bpy.data.materials.new('MaydonRefGrey')
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (0.6, 0.6, 0.6, 1)
    ob.data.materials.append(mat)
    print('STANDIN verts', len(ob.data.vertices), 'polys', len(ob.data.polygons))
    # hide original body from export
    for o in bpy.data.objects:
        if o not in (arm, ob):
            o.select_set(False)
    # NLA: one track per action so the exporter writes each as an animation
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for n in names:
        act, slot = actions[n]
        tr = ad.nla_tracks.new()
        tr.name = n
        st = tr.strips.new(n, 0, act)
        try:
            st.action_slot = slot
        except Exception:
            pass
        tr.mute = True
    # reset pose
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(OUT, 'anims.glb')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False,
                              export_optimize_animation_keep_anim_armature=True,
                              export_anim_single_armature=True, export_reset_pose_bones=True,
                              export_anim_slide_to_zero=True, export_def_bones=False,
                              export_skins=True, export_morph=False, export_apply=False,
                              export_yup=True, export_materials='EXPORT')
    print('EXPORTED', path, os.path.getsize(path))


def write_json():
    data = {'fps': 30, 'rig': 'MPFB2 game_engine (reference adult male 1.80 m)',
            'coords': 'root_motion in Godot character space: +x = character left, +z = character forward (metres)',
            'bones': rig.names, 'clips': {}}
    for n in names:
        m = metas[n]
        e = {'type': m.get('type'), 'length': m.get('duration'), 'duration': m.get('duration'), 'frames': m.get('frames')}
        if m.get('type') == 'loop':
            e['speed'] = m.get('speed', 0.0)
            e['cycle'] = m.get('duration')
        if m.get('contact_time') is not None:
            e['contact'] = m['contact_time']
        for k in ('speed', 'velocity', 'direction', 'cycle_frames', 'contact_time', 'contact_kind', 'root_motion',
                  'loop', 'events', 'notes', 'src', 'src_range', 'foot_slide_mm', 'source_speed'):
            if k in m:
                e[k] = m[k]
        if e['type'] == 'loop':
            e['loop'] = True
        data['clips'][n] = e
    path = os.path.join(OUT, 'anims.json')
    with open(path, 'w') as f:
        json.dump(data, f, indent=1)
    print('JSON', path)


if DO_EXPORT:
    export_lib()
    write_json()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'anim_lib.blend'))
