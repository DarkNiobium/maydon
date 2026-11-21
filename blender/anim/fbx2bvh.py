"""Mixamo FBX (no skin) -> BVH with plain bone names (mixamorig:Hips -> Hips).
blender -b --factory-startup -P fbx2bvh.py -- <in_dir> <out_dir>"""
import bpy, os, sys
argv = sys.argv[sys.argv.index('--') + 1:]
src, dst = argv[0], argv[1]
os.makedirs(dst, exist_ok=True)
for fn in sorted(os.listdir(src)):
    if not fn.endswith('.fbx'):
        continue
    out = os.path.join(dst, fn[:-4] + '.bvh')
    if os.path.exists(out) and os.path.getmtime(out) > os.path.getmtime(os.path.join(src, fn)):
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(src, fn), automatic_bone_orientation=False, ignore_leaf_bones=False)
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    for b in arm.data.bones:
        b.name = b.name.split(':')[-1]
    act = arm.animation_data.action if arm.animation_data else None
    if act is None:
        print('NOANIM', fn); continue
    f0, f1 = (int(x) for x in act.frame_range)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.frame_start, sc.frame_end = f0, f1
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_anim.bvh(filepath=out, frame_start=f0, frame_end=f1, root_transform_only=False,
                            rotate_mode='NATIVE', global_scale=1.0)
    print('BVH', fn, f1 - f0 + 1, 'frames')
