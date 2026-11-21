"""Create the MAYDON animation reference character: MPFB2 average adult male (~1.80 m)
with the built-in game_engine rig. Saves ~/maydon/blender/anim/ref.blend.
Usage: nice blender -b --python make_ref.py -- [height_param]"""
import bpy, sys, os
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
hparam = float(argv[0]) if argv else 0.5
OUT = os.path.expanduser("~/maydon/blender/anim/ref.blend")

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

macro = TargetService.get_default_macro_info_dict()
macro["gender"] = 1.0
macro["age"] = 0.5
macro["height"] = hparam
basemesh = HumanService.create_human(macro_detail_dict=macro)
rig = HumanService.add_builtin_rig(basemesh, "game_engine")
bpy.context.view_layer.update()

# measure
import numpy as np
dg = bpy.context.evaluated_depsgraph_get()
ev = basemesh.evaluated_get(dg)
me = ev.to_mesh()
co = np.array([basemesh.matrix_world @ v.co for v in me.vertices])
ev.to_mesh_clear()
print("REF height param", hparam, "mesh z range", co[:,2].min(), co[:,2].max(), "verts", len(co))
for b in rig.data.bones:
    print("BONE", b.name, b.parent.name if b.parent else None, tuple(round(x,4) for x in (rig.matrix_world @ b.head_local)),
          tuple(round(x,4) for x in (rig.matrix_world @ b.tail_local)), round(b.length,4), b.use_connect)
print("RIG obj", rig.name, tuple(rig.location), tuple(rig.rotation_euler), tuple(rig.scale))
print("MESH obj", basemesh.name, [m.type for m in basemesh.modifiers], basemesh.data.shape_keys and len(basemesh.data.shape_keys.key_blocks))
bpy.ops.wm.save_as_mainfile(filepath=OUT)
