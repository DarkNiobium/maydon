"""Contact sheet of the exported GLBs (EEVEE): 12 front views in A-pose + 3 face close-ups + 1 back view.

    nice blender -b --python ~/maydon/blender/chars/preview.py -- [out.png] [--names p01,p02]

The kit is recoloured with a sample team palette through the COLOR_0 masks, and a number is projected
with UV2, i.e. the same data the game shader uses (this checks the conventions visually).
"""
import bpy, sys, os, math, glob
from mathutils import Vector, Matrix, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
VAR = os.path.expanduser("~/maydon/game/assets/chars/variants")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = next((a for a in argv if a.endswith(".png")), os.path.expanduser("~/maydon/game/assets/chars/preview.png"))
names = None
FACES = ["p01", "p03", "p10"]
for a in argv:
    if a.startswith("--names"):
        names = a.split("=", 1)[1].split(",")
    if a.startswith("--faces"):
        FACES = a.split("=", 1)[1].split(",")
TMP = os.path.join(HERE, "work", "preview_parts")
os.makedirs(TMP, exist_ok=True)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
GLOB = os.path.join(VAR, "p*.glb")
for a in argv:
    if a.startswith("--glob="):
        GLOB = a.split("=", 1)[1]
files = sorted(glob.glob(GLOB))
if names:
    files = [f for f in files if os.path.basename(f)[:-4] in names]

PALETTES = [
    dict(shirt=(0.03, 0.16, 0.55), trim=(0.92, 0.92, 0.92), shorts=(0.9, 0.9, 0.9), socks=(0.03, 0.16, 0.55), boots=(0.05, 0.05, 0.05), num=(1, 1, 1)),
    dict(shirt=(0.65, 0.04, 0.05), trim=(0.95, 0.85, 0.2), shorts=(0.05, 0.05, 0.06), socks=(0.65, 0.04, 0.05), boots=(0.9, 0.9, 0.9), num=(1, 0.9, 0.3)),
]
num_img = bpy.data.images.load(os.path.join(HERE, "work", "number10.png"))


def kit_preview_material(mat, pal):
    nt = mat.node_tree
    bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = COLNAME
    sep = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(vc.outputs[0], sep.inputs[0])
    def rgb(c):
        n = nt.nodes.new("ShaderNodeRGB"); n.outputs[0].default_value = tuple(c) + (1,); return n.outputs[0]
    def mix(fac, a, b):
        n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"
        nt.links.new(fac, n.inputs[0]) if not isinstance(fac, float) else None
        if isinstance(fac, float): n.inputs[0].default_value = fac
        nt.links.new(a, n.inputs[6]); nt.links.new(b, n.inputs[7]); return n.outputs[2]
    def math_(op, a, b):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = op
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)): n.inputs[i].default_value = x
            else: nt.links.new(x, n.inputs[i])
        n.use_clamp = True
        return n.outputs[0]
    # trim: R in (0.25, 0.75)
    is_trim = math_("MULTIPLY", math_("GREATER_THAN", sep.outputs[0], 0.25), math_("LESS_THAN", sep.outputs[0], 0.75))
    is_shirt = math_("GREATER_THAN", sep.outputs[0], 0.75)
    col = mix(sep.outputs[2], rgb(pal["boots"]), rgb(pal["socks"]))
    col = mix(sep.outputs[1], col, rgb(pal["shorts"]))
    col = mix(is_shirt, col, rgb(pal["shirt"]))
    col = mix(is_trim, col, rgb(pal["trim"]))
    # number via UV2: back number box x in [1.55, 2.45], y in [0.30, 0.78]; front small number
    uv2 = nt.nodes.new("ShaderNodeUVMap"); uv2.uv_map = "UV2" if "UV2" in [l.name for l in OBJ_UV] else OBJ_UV[1].name
    sxyz = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(uv2.outputs[0], sxyz.inputs[0])
    x, y = sxyz.outputs[0], sxyz.outputs[1]
    # glTF import flips v back, so y here equals Blender v = 1 - y_gltf ... handle both by using 1 - v
    yv = math_("SUBTRACT", 1.0, y)
    def box(x0, x1, y0, y1):
        u = math_("DIVIDE", math_("SUBTRACT", x, x0), x1 - x0)
        v = math_("DIVIDE", math_("SUBTRACT", yv, y0), y1 - y0)
        cmb = nt.nodes.new("ShaderNodeCombineXYZ"); nt.links.new(u, cmb.inputs[0]); nt.links.new(v, cmb.inputs[1])
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = num_img; t.extension = "CLIP"
        nt.links.new(cmb.outputs[0], t.inputs[0])
        return t.outputs[1]
    a_back = box(1.45, 2.55, 0.28, 0.83)
    a_front = box(0.18, 0.58, 0.58, 0.80)
    a = math_("MAXIMUM", a_back, a_front)
    a = math_("MULTIPLY", a, is_shirt)
    col = mix(a, col, rgb(pal["num"]))
    # keep texture luminance (AO/boot details)
    lum = nt.nodes.new("ShaderNodeRGBToBW"); nt.links.new(tex.outputs[0], lum.inputs[0])
    shade = math_("MULTIPLY", lum.outputs[0], 1.25)
    m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = "RGBA"; m2.blend_type = "MULTIPLY"; m2.inputs[0].default_value = 1.0
    nt.links.new(col, m2.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3): nt.links.new(shade, comb.inputs[i])
    nt.links.new(comb.outputs[0], m2.inputs[7])
    nt.links.new(m2.outputs[2], bs.inputs["Base Color"])


def a_pose(arm):
    """Straighten the forearms (MPFB rest has bent elbows) and lower the arms a bit, for the preview."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for s in "lr":
        for bn in ("lowerarm_" + s, "hand_" + s):
            pb = arm.pose.bones.get(bn)
            if pb is None:
                continue
            rest_rel = (pb.parent.bone.matrix_local.inverted() @ pb.bone.matrix_local).to_quaternion()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = rest_rel.inverted()
        ua = arm.pose.bones.get("upperarm_" + s)
        if ua:
            ua.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")


sys.path.insert(0, HERE)
try:
    from variants import VARIANTS
    import json as _json
    LABELS = {}
    for _n, _v in VARIANTS.items():
        _st = os.path.join(HERE, "work", _n, "stats.json")
        _h = _json.load(open(_st))["height"] if os.path.exists(_st) else _v["height"]
        LABELS[_n] = "%s %s %d y %.2f m" % (_n, _v.get("role", ""), _v["age"], _h)
except Exception as _e:
    LABELS = {}
chars = []
for i, f in enumerate(files):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = [o for o in new if o.type == "MESH"]
    mesh = meshes[0]
    name = os.path.basename(f)[:-4]
    for ms in meshes:
        OBJ_UV = list(ms.data.uv_layers)
        COLNAME = ms.data.color_attributes[0].name if len(ms.data.color_attributes) else "Col"
        for m in ms.data.materials:
            if m.name.startswith("kit"):
                kit_preview_material(m, PALETTES[0])
    a_pose(arm)
    chars.append((name, arm, mesh))

sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "AgX"
w = bpy.data.worlds.new("w"); sc.world = w
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.55, 0.58, 0.62, 1); bg.inputs[1].default_value = 0.9
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (math.radians(55), 0, math.radians(-30)); sun.data.energy = 3.2; sun.data.angle = math.radians(3)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill)
fill.rotation_euler = (math.radians(70), 0, math.radians(150)); fill.data.energy = 1.0
sc.eevee.taa_render_samples = 32
try:
    sc.eevee.use_shadows = True
except Exception:
    pass
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
# floor
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
floor = bpy.context.object
fm = bpy.data.materials.new("floor"); fb = next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
fb.inputs[0].default_value = (0.32, 0.36, 0.33, 1); fb.inputs["Roughness"].default_value = 0.9
floor.data.materials.append(fm)


def place_row(items, y=0.0):
    for k, (name, arm, mesh) in enumerate(items):
        arm.location = (k * 0.95, y, 0)
        arm.rotation_euler = (0, 0, 0)


def hide_all_but(items):
    keep = set(arm for name, arm, mesh in items)
    for name, arm, mesh in chars:
        vis = arm in keep
        arm.hide_render = not vis
        for ch in arm.children:
            ch.hide_render = not vis


def render(path, res):
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


parts = []
PER = 4
SP = 1.3
rows = [chars[i:i + PER] for i in range(0, len(chars), PER)]
RW, RH = 2400, 1150
for r, items in enumerate(rows):
    if not items:
        continue
    hide_all_but(items)
    for k, (name, arm, mesh) in enumerate(items):
        arm.location = (k * SP, 0, 0)
    bpy.context.view_layer.update()
    cx = (PER - 1) * SP / 2
    cam.data.type = "PERSP"; cam.data.lens = 50
    dist = 8.6
    cam.location = (cx, -dist, 1.0); cam.rotation_euler = (math.radians(90), 0, 0)
    p = os.path.join(TMP, "row%d.png" % r)
    render(p, (RW, RH))
    fovw = dist * 36.0 / 50.0
    ann = []
    for k, (name, arm, mesh) in enumerate(items):
        x = RW / 2 + (k * SP - cx) * RW / fovw
        info = LABELS.get(name, name)
        ann.append("-annotate +%d+%d '%s'" % (int(x) - 150, RH - 40, info))
    os.system("magick %s -gravity NorthWest -font DejaVu-Sans -pointsize 30 -fill '#1a1a1a' %s %s" % (p, " ".join(ann), p))
    parts.append(p)

# face close-ups
face_names = [n for n in FACES if any(c[0] == n for c in chars)] or [c[0] for c in chars[:3]]
faces = []
for k, fn in enumerate(face_names):
    item = next(c for c in chars if c[0] == fn)
    hide_all_but([item])
    item[1].location = (0, 0, 0)
    bpy.context.view_layer.update()
    head = item[1].pose.bones["head"]
    hp = item[1].matrix_world @ head.head
    for j, ang in enumerate((0, 35)):
        a = math.radians(ang)
        d = 0.95
        cam.data.type = "PERSP"; cam.data.lens = 85
        target = Vector((hp.x, hp.y - 0.02, hp.z + 0.035))
        cam.location = target + Vector((d * math.sin(a), -d * math.cos(a), 0.02))
        cam.rotation_euler = (math.radians(90), 0, a)
        p = os.path.join(TMP, "face_%s_%d.png" % (fn, j))
        render(p, (600, 800))
        faces.append(p)
# back / side views (UV2 number check, hair from behind)
backs = []
for nm, ang in (("p01", 180), ("p01", 90), ("p06", 180), ("p10", 160)):
    item = next((c for c in chars if c[0] == nm), chars[0])
    hide_all_but([item]); item[1].location = (0, 0, 0)
    bpy.context.view_layer.update()
    cam.data.lens = 50
    a = math.radians(ang)
    cam.location = (3.3 * math.sin(a), -3.3 * math.cos(a), 0.98); cam.rotation_euler = (math.radians(90), 0, a)
    p = os.path.join(TMP, "back_%s_%d.png" % (nm, ang))
    render(p, (600, 800))
    backs.append(p)

labels = " ".join(parts)
os.system("magick %s -append %s" % (" ".join(parts), os.path.join(TMP, "rows.png")))
os.system("magick %s +append -resize 2400x %s" % (" ".join(faces), os.path.join(TMP, "faces.png")))
os.system("magick %s +append -resize 2400x %s" % (" ".join(backs), os.path.join(TMP, "backs.png")))
os.system("magick %s %s %s -append %s" % (os.path.join(TMP, "rows.png"), os.path.join(TMP, "faces.png"),
                                          os.path.join(TMP, "backs.png"), OUT))
print("PREVIEW", OUT)
