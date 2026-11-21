"""Verification sheet: every morph key at 1.0 on the full-res base head (front + 3/4), EEVEE.

    nice blender -b --python ~/maydon/blender/custom/keysheet.py -- [out.png] [--keys a,b,c] [--value 1.0]
"""
import bpy, sys, os, math
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clib as C
from clib import log
import morphs

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUTP = next((a for a in argv if a.endswith(".png")), os.path.join(C.WORK, "keysheet.png"))
KEYS = None
VAL = 1.0
BODY = "--body" in argv
ZOOM = "--zoom" in argv
for a in argv:
    if a.startswith("--keys="):
        KEYS = a.split("=", 1)[1].split(",")
    if a.startswith("--value="):
        VAL = float(a.split("=", 1)[1])
D = np.load(os.path.join(C.WORK, "deltas.npz"))
keys = KEYS or ([k for k in morphs.ORDER if k.startswith("body_")] if BODY else list(morphs.FACE.keys()))
keys = ["(base)"] + keys

bm, _ = C.create_human(rig=False)
base = C.all_coords(bm)
basis = np.zeros(len(base) * 3); bm.data.shape_keys.key_blocks[0].data.foreach_get("co", basis)
basis = basis.reshape(-1, 3)


def asset(rel, typ):
    ob = bpy.data.objects.get(typ)
    path = os.path.join(C.ASSETS, rel)
    ob = HumanService.add_mhclo_asset(path, bm, asset_type=typ, subdiv_levels=0, material_type="NONE")
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    mh, _ = C.load_mhclo(rel)
    return ob, C.Fit(mh, len(ob.data.vertices))


from bl_ext.user_default.mpfb.services.humanservice import HumanService
eyes, feyes = asset("eyes/low-poly/low-poly.mhclo", "Eyes")
brows, fbrows = asset("eyebrows/eyebrow002/eyebrow002.mhclo", "Eyebrows")


def mat_tex(name, path, alpha=False, rough=0.55):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path)
    nt.links.new(t.outputs[0], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = rough
    if alpha:
        nt.links.new(t.outputs[1], bs.inputs["Alpha"])
        m.surface_render_method = "DITHERED"
    return m


skin_tex = os.path.join(C.OUT, "skin_mid.jpg")
if not os.path.exists(skin_tex):
    skin_tex = os.path.join(C.ASSETS, "skins/young_asian_male/young_lightskinned_male_diffuse3.png")
bm.data.materials.clear(); bm.data.materials.append(mat_tex("skin", skin_tex))
eyes.data.materials.clear(); eyes.data.materials.append(mat_tex("eye", os.path.join(C.ASSETS, "eyes/materials/brown_eye.png"), rough=0.2))
brows.data.materials.clear(); brows.data.materials.append(mat_tex("brow", os.path.join(C.ASSETS, "eyebrows/eyebrow002/eyebrow002.png"), alpha=True))
for o in (bm, eyes, brows):
    for p in o.data.polygons:
        p.use_smooth = True

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "AgX"
sc.eevee.taa_render_samples = 16
w = bpy.data.worlds.new("w"); sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.52, 0.55, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (math.radians(60), 0, math.radians(-35)); sun.data.energy = 3.0
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill)
fill.rotation_euler = (math.radians(75), 0, math.radians(140)); fill.data.energy = 0.8
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 85
headc = Vector((0.0, -0.035, 1.672))
if BODY:
    headc = Vector((0.0, 0.0, 0.95))
    cam.data.lens = 50
TMP = os.path.join(C.WORK, "keysheet_parts")
os.makedirs(TMP, exist_ok=True)
parts = []
sk = bm.shape_key_add(name="__test", from_mix=False)
for k in keys:
    d = D[k] * VAL if k in D.files else np.zeros_like(base)
    sk.data.foreach_set("co", (basis + d).astype(np.float32).reshape(-1))
    sk.value = 1.0
    co = base + d
    C.set_co(eyes, feyes(co)); C.set_co(brows, fbrows(co))
    row = []
    angs = (0, 40, 90) if not BODY else (0, 90)
    if ZOOM:
        angs = (0, 90)
    for ang in angs:
        a = math.radians(ang)
        dist = 0.82 if not BODY else 4.6
        if ZOOM:
            dist = 0.52
        hc = Vector((0, -0.08, 1.66)) if ZOOM else headc
        cam.location = hc + Vector((dist * math.sin(a), -dist * math.cos(a), 0.0))
        cam.rotation_euler = (math.radians(90), 0, a)
        sc.render.resolution_x, sc.render.resolution_y = (300, 380) if not BODY else (360, 700)
        if ZOOM:
            sc.render.resolution_x, sc.render.resolution_y = (340, 340)
        p = os.path.join(TMP, "%s_%d.png" % (k.strip("()"), ang))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        row.append(p)
    lab = os.path.join(TMP, "%s_row.png" % k.strip("()"))
    os.system("magick %s +append -gravity North -background '#222' -splice 0x30 -fill white -pointsize 24 -annotate +0+2 '%s' %s"
              % (" ".join(row), k, lab))
    parts.append(lab)
cols = 6 if ZOOM else 4
os.system("magick montage %s -tile %dx -geometry +4+4 -background '#111' %s" % (" ".join(parts), cols, OUTP))
log("keysheet", OUTP)
