"""Dump bone rest heads/tails of ~/maydon/blender/anim/ref.blend to work/ref_bones.json (run with ref.blend)."""
import bpy, json, os
rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
d = {b.name: dict(head=list(b.head_local), tail=list(b.tail_local), roll_matrix=[list(r) for r in b.matrix_local])
     for b in rig.data.bones}
json.dump(d, open(os.path.expanduser("~/maydon/blender/custom/work/ref_bones.json"), "w"), indent=0)
print("[maydon] dumped", len(d))
