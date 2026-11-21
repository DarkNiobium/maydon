"""Deformation / clipping check: poses an exported GLB (running stride, arms up, kick) and renders it.

    nice blender -b --python ~/maydon/blender/chars/posetest.py -- p01 [out.png]
"""
import bpy, sys, os, math
from mathutils import Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mlib

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
name = argv[0] if argv else "p01"
out = argv[1] if len(argv) > 1 else os.path.join(HERE, "work", "pose_%s.png" % name)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=os.path.expanduser("~/maydon/game/assets/chars/variants/%s.glb" % name))
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for o in bpy.data.objects:
    if o.type == "MESH":
        for m in o.data.materials:
            nt = m.node_tree
            bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            t = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
            if t and m.name.startswith("kit"):
                # tint kit parts by mask so clipping of skin through cloth is obvious
                vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
                mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.inputs[0].default_value = 0.6
                nt.links.new(t.outputs[0], mix.inputs[6]); nt.links.new(vc.outputs[0], mix.inputs[7])
                nt.links.new(mix.outputs[2], bs.inputs[0])
            elif t:
                nt.links.new(t.outputs[0], bs.inputs[0])

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")


def rot(bone, x=0, y=0, z=0):
    pb = arm.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = Euler((math.radians(x), math.radians(y), math.radians(z)))


# running stride: right thigh forward, left back, knees bent, arms swinging, torso twist
rot("thigh_r", 55, 0, 0); rot("calf_r", -70, 0, 0)
rot("thigh_l", -30, 0, 0); rot("calf_l", -60, 0, 0)
rot("spine_02", 0, 12, 0); rot("spine_03", 8, 0, 0)
rot("upperarm_l", 60, 0, 30); rot("lowerarm_l", 0, 0, -60)
rot("upperarm_r", -40, 0, -70); rot("lowerarm_r", 0, 0, 40)
rot("neck_01", -10, 0, 0)
bpy.ops.object.mode_set(mode="OBJECT")
mlib.render_views(out, (0, 0, 1.0), 2.1, angles=(0, 60, 120, 200, 300), res=(500, 900))
print("POSE", out)
