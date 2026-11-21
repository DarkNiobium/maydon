"""Preview sheet of assets/chars/custom/base.glb: the base look + 6 random looks (catalog.PREVIEW),
with the skin-tone blend, beard/brow/scalp/iris masks, kit recolour and hair/acc tints approximated
in EEVEE (the same maths the Godot shader is expected to do).

    nice blender -b --python ~/maydon/blender/custom/preview.py -- [out.png] [--looks=base,look1]
"""
import bpy, sys, os, math
from mathutils import Vector
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import catalog as CAT

CUST = os.path.expanduser("~/maydon/game/assets/chars/custom")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUTP = next((a for a in argv if a.endswith(".png")), os.path.join(CUST, "preview.png"))
SEL = None
MODE = "looks"
ZOOM = 1.0
for a in argv:
    if a.startswith("--zoom="):
        ZOOM = float(a.split("=", 1)[1])
    if a.startswith("--looks="):
        SEL = a.split("=", 1)[1].split(",")
    if a.startswith("--mode="):
        MODE = a.split("=", 1)[1]
TMP = os.path.join(HERE, "work", "preview_parts")
os.makedirs(TMP, exist_ok=True)
LOOKS = [(n, l) for n, l in CAT.PREVIEW if SEL is None or n in SEL]
if MODE == "hair":
    LOOKS = [(h, dict(CAT.DEFAULT, hair=h)) for h in CAT.HAIR_IDS if SEL is None or h in SEL]
elif MODE == "beard":
    LOOKS = [(bd, dict(CAT.DEFAULT, hair="hair_buzz", beard=bd, beard_density=1.0, brows=br))
             for bd, br in zip(CAT.BEARD_IDS + [None, None, None], ["brows_normal"] * 6 + CAT.BROW_IDS)]
    LOOKS[6:] = [("brows_" + l[1]["brows"][6:], dict(l[1], beard=None)) for l in LOOKS[6:]]
elif MODE == "keys":
    import morphs as MO
    ks = SEL or (list(MO.FACE) + list(MO.EXTRA))
    LOOKS = [(k, dict(CAT.DEFAULT, morphs={k: 1.0})) for k in ks]
elif MODE == "bodykeys":
    import morphs as MO
    LOOKS = [("base", dict(CAT.DEFAULT))] + [(k, dict(CAT.DEFAULT, morphs={k: 1.0}, sleeves=sl))
                                             for k in MO.BODY for sl in ("short", "long")]
elif MODE == "gear":
    LOOKS = [("gear%d" % i, dict(CAT.DEFAULT, boots=CAT.BOOT_IDS[i], sleeves=["short", "long"][i % 2],
                                  socks=["high", "low"][i // 2], acc=acc))
             for i, acc in enumerate([["Acc_headband", "Acc_wristband_l", "Acc_wristband_r"], ["Acc_armband"],
                                      ["Acc_gloves", "Acc_undershirt_neck"], ["Acc_gloves", "Acc_armband"]])]

PALETTES = [
    dict(shirt=(0.70, 0.05, 0.06), trim=(0.95, 0.95, 0.95), shorts=(0.95, 0.95, 0.95), socks=(0.70, 0.05, 0.06)),
    dict(shirt=(0.03, 0.12, 0.45), trim=(0.95, 0.80, 0.15), shorts=(0.03, 0.12, 0.45), socks=(0.95, 0.95, 0.95)),
    dict(shirt=(0.95, 0.95, 0.95), trim=(0.05, 0.05, 0.05), shorts=(0.05, 0.05, 0.05), socks=(0.95, 0.95, 0.95)),
    dict(shirt=(0.05, 0.35, 0.12), trim=(0.95, 0.95, 0.95), shorts=(0.95, 0.95, 0.95), socks=(0.05, 0.35, 0.12)),
]
BOOT_COLS = [(0.05, 0.05, 0.05), (0.92, 0.92, 0.92), (0.85, 0.35, 0.05), (0.10, 0.30, 0.80)]
ACC_COLS = [(0.95, 0.95, 0.95), (0.05, 0.05, 0.05), (0.95, 0.75, 0.10), (0.10, 0.35, 0.80)]

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
IMG = {}


def img(name, noncolor=False):
    if name not in IMG:
        im = bpy.data.images.load(os.path.join(CUST, name))
        if noncolor:
            im.colorspace_settings.name = "Non-Color"
        IMG[name] = im
    return IMG[name]


class NB:
    def __init__(self, mat):
        self.nt = mat.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.bs = self.nt.nodes.new("ShaderNodeBsdfPrincipled")
        self.nt.links.new(self.bs.outputs[0], self.out.inputs[0])
        self.uv = self.nt.nodes.new("ShaderNodeUVMap"); self.uv.uv_map = "UVMap"

    def tex(self, name, noncolor=False):
        t = self.nt.nodes.new("ShaderNodeTexImage"); t.image = img(name, noncolor)
        self.nt.links.new(self.uv.outputs[0], t.inputs[0])
        return t

    def mix(self, fac, a, b, blend="MIX"):
        n = self.nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = blend; n.clamp_result = True
        for idx, x in ((0, fac), (6, a), (7, b)):
            if isinstance(x, (int, float)):
                n.inputs[idx].default_value = x
            elif isinstance(x, tuple):
                n.inputs[idx].default_value = x if len(x) == 4 else tuple(x) + (1.0,)
            else:
                self.nt.links.new(x, n.inputs[idx])
        return n.outputs[2]

    def math(self, op, a, b=None):
        n = self.nt.nodes.new("ShaderNodeMath"); n.operation = op; n.use_clamp = True
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                self.nt.links.new(x, n.inputs[i])
        return n.outputs[0]

    def bw(self, c):
        n = self.nt.nodes.new("ShaderNodeRGBToBW"); self.nt.links.new(c, n.inputs[0]); return n.outputs[0]


def skin_material(look):
    m = bpy.data.materials.new("skin_prev")
    b = NB(m)
    t = look["skin_tone"]
    c = b.mix(min(1.0, t), b.tex("skin_light.jpg").outputs[0], b.tex("skin_mid.jpg").outputs[0])
    c = b.mix(max(0.0, t - 1.0), c, b.tex("skin_dark.jpg").outputs[0])
    hair_col = CAT.HAIR_COLORS[look["hair_color"]]
    hid = look.get("hair")
    if hid:
        import hairstyles as HS
        sm, ss = HS.HAIR[hid]["scalp"]
        f = b.math("MULTIPLY", b.tex(sm + ".png", True).outputs[0], ss)
        c = b.mix(f, c, hair_col)
    if look.get("beard"):
        f = b.math("MULTIPLY", b.tex(look["beard"] + ".png", True).outputs[0], look.get("beard_density", 1.0))
        c = b.mix(f, c, hair_col)
    if look.get("brows"):
        bc = CAT.HAIR_COLORS[look.get("brow_color", look["hair_color"])]
        f = b.math("MULTIPLY", b.tex(look["brows"] + ".png", True).outputs[0], 0.95)
        c = b.mix(f, c, bc)
    # iris: luminance of the neutral iris x eye colour
    ir = b.tex("iris_mask.png", True).outputs[0]
    lum = b.bw(c)
    ec = CAT.EYE_COLORS[look["eye_color"]]
    comb = b.nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        b.nt.links.new(b.math("MULTIPLY", lum, ec[i] * 3.0), comb.inputs[i])
    c = b.mix(ir, c, comb.outputs[0])
    b.nt.links.new(c, b.bs.inputs["Base Color"])
    # glossy eyes: EYE_RECT (Blender UV u 0.770-0.885, v 0.875-0.990) gets roughness 0.12
    sx = b.nt.nodes.new("ShaderNodeSeparateXYZ"); b.nt.links.new(b.uv.outputs[0], sx.inputs[0])
    ineye = b.math("MULTIPLY", b.math("GREATER_THAN", sx.outputs[0], 0.770), b.math("GREATER_THAN", sx.outputs[1], 0.875))
    ineye = b.math("MULTIPLY", ineye, b.math("LESS_THAN", sx.outputs[0], 0.885))
    rough = b.nt.nodes.new("ShaderNodeMapRange"); rough.inputs[3].default_value = 0.52; rough.inputs[4].default_value = 0.12
    b.nt.links.new(ineye, rough.inputs[0]); b.nt.links.new(rough.outputs[0], b.bs.inputs["Roughness"])
    b.bs.inputs["Specular IOR Level"].default_value = 0.4
    nt = b.tex("skin_normal.jpg", True)
    nm = b.nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.8
    b.nt.links.new(nt.outputs[0], nm.inputs["Color"]); b.nt.links.new(nm.outputs[0], b.bs.inputs["Normal"])
    try:
        b.bs.inputs["Subsurface Weight"].default_value = 0.12
        b.bs.inputs["Subsurface Radius"].default_value = (0.9, 0.35, 0.2)
        b.bs.inputs["Subsurface Scale"].default_value = 0.006
    except Exception:
        pass
    m.use_backface_culling = True
    return m


def kit_material(colattr, pal, boot_col, hide_socks):
    m = bpy.data.materials.new("kit_prev")
    b = NB(m)
    base = b.tex("kit.png").outputs[0]
    vc = b.nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = colattr
    sep = b.nt.nodes.new("ShaderNodeSeparateColor"); b.nt.links.new(vc.outputs[0], sep.inputs[0])
    R, G, B = sep.outputs[0], sep.outputs[1], sep.outputs[2]
    A = vc.outputs[1]
    is_shirt = b.math("GREATER_THAN", R, 0.75)
    is_trim = b.math("MULTIPLY", b.math("GREATER_THAN", R, 0.25), b.math("LESS_THAN", R, 0.75))
    c = b.mix(b.math("GREATER_THAN", A, 0.5), (0.5, 0.5, 0.5), boot_col)
    c = b.mix(b.math("GREATER_THAN", B, 0.5), c, pal["socks"])
    c = b.mix(b.math("GREATER_THAN", G, 0.5), c, pal["shorts"])
    c = b.mix(is_shirt, c, pal["shirt"])
    c = b.mix(is_trim, c, pal["trim"])
    shade = b.math("MULTIPLY", b.bw(base), 1.25)
    comb = b.nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        b.nt.links.new(shade, comb.inputs[i])
    c = b.mix(1.0, c, comb.outputs[0], "MULTIPLY")
    b.nt.links.new(c, b.bs.inputs["Base Color"])
    b.bs.inputs["Roughness"].default_value = 0.7
    if hide_socks:
        # emulates the shader option for Socks_low: Kit fragments with COLOR_0.b > 0.5 are discarded
        b.nt.links.new(b.math("LESS_THAN", B, 0.5), b.bs.inputs["Alpha"])
        m.surface_render_method = "DITHERED"
    m.use_backface_culling = True
    return m


def tint_material(texname, col, alpha=False, rough=0.5, gain=1.25, contrast=1.0):
    m = bpy.data.materials.new("tint_prev")
    b = NB(m)
    t = b.tex(texname)
    src = t.outputs[0]
    if contrast != 1.0:
        g = b.nt.nodes.new("ShaderNodeGamma"); g.inputs[1].default_value = contrast
        b.nt.links.new(src, g.inputs[0]); src = g.outputs[0]
    c = b.mix(1.0, src, tuple(x * gain for x in col), "MULTIPLY")
    b.nt.links.new(c, b.bs.inputs["Base Color"])
    b.bs.inputs["Roughness"].default_value = rough
    if alpha:
        b.nt.links.new(b.math("ROUND", t.outputs[1]), b.bs.inputs["Alpha"])
        m.surface_render_method = "DITHERED"
        m.use_backface_culling = False
    return m


def a_pose(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for s in "lr":
        for bn in ("lowerarm_" + s, "hand_" + s):
            pb = arm.pose.bones.get(bn)
            rest_rel = (pb.parent.bone.matrix_local.inverted() @ pb.bone.matrix_local).to_quaternion()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = rest_rel.inverted()
    bpy.ops.object.mode_set(mode="OBJECT")


chars = []
for i, (name, look) in enumerate(LOOKS):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(CUST, "base.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    meshes = {o.name.split(".")[0]: o for o in new if o.type == "MESH"}
    vis = {"Body", "Kit", look["boots"]}
    if look.get("hair"):
        vis.add(look["hair"])
    if look.get("sleeves") == "long":
        vis.add("Sleeves_long")
    if look.get("socks") == "low":
        vis.add("Socks_low")
    vis.update(look.get("acc", []))
    pal = PALETTES[i % len(PALETTES)]
    bcol = BOOT_COLS[i % len(BOOT_COLS)]
    acol = ACC_COLS[i % len(ACC_COLS)]
    for mn, o in meshes.items():
        o.hide_render = mn not in vis
        o.hide_set(mn not in vis)
        if o.data.shape_keys:
            for kb in o.data.shape_keys.key_blocks[1:]:
                kb.value = look["morphs"].get(kb.name, 0.0)
        if mn not in vis:
            continue
        colattr = o.data.color_attributes[0].name if len(o.data.color_attributes) else "Color"
        if mn == "Body":
            mat = skin_material(look)
        elif mn == "Kit":
            mat = kit_material(colattr, pal, bcol, look.get("socks") == "low")
        elif mn in ("Sleeves_long", "Socks_low") or mn.startswith("Boots_"):
            mat = kit_material(colattr, pal, bcol, False)
        elif mn.startswith("Acc_"):
            mat = tint_material("acc.png", acol, rough=0.8)
        elif mn.startswith("hair_"):
            mat = tint_material(mn + ".png", CAT.HAIR_COLORS[look["hair_color"]], alpha=True, gain=2.2,
                                contrast=1.7, rough=0.55)
        else:
            continue
        o.data.materials.clear(); o.data.materials.append(mat)
    a_pose(arm)
    arm.location = (i * 1.05, 0, 0)
    chars.append((name, look, arm, meshes, vis))

sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "AgX"
sc.eevee.taa_render_samples = 32
w = bpy.data.worlds.new("w"); sc.world = w
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.55, 0.58, 0.62, 1); bg.inputs[1].default_value = 0.85
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.rotation_euler = (math.radians(55), 0, math.radians(-30)); sun.data.energy = 3.0; sun.data.angle = math.radians(3)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill)
fill.rotation_euler = (math.radians(70), 0, math.radians(150)); fill.data.energy = 1.0
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
bpy.ops.mesh.primitive_plane_add(size=80, location=(3, 0, 0))
floor = bpy.context.object
fm = bpy.data.materials.new("floor"); fb = next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
fb.inputs[0].default_value = (0.30, 0.36, 0.31, 1); fb.inputs["Roughness"].default_value = 0.9
floor.data.materials.append(fm)


def show_only(items):
    keep = set(id(c[2]) for c in items)
    for name, look, arm, meshes, vis in chars:
        on = id(arm) in keep
        for mn, o in meshes.items():
            o.hide_render = not (on and mn in vis)


def render(path, res):
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


n = len(chars)
show_only(chars)
ROWS = ("front", "q34", "back") if MODE != "gear" or "--rows" in argv else ()
if MODE == "keys":
    ROWS = ("front", "q34")
if MODE == "bodykeys":
    ROWS = ()
cx = (n - 1) * 1.05 / 2
cam.data.type = "PERSP"; cam.data.lens = 50
dist = 1.05 * n * 1.35 + 1.5
cam.location = (cx, -dist, 1.0); cam.rotation_euler = (math.radians(90), 0, 0)
W_ = 400 * n
row = render(os.path.join(TMP, "row.png"), (W_, 1000))
fovw = dist * 36.0 / 50.0
ann = []
for k, (name, look, arm, meshes, vis) in enumerate(chars):
    x = W_ / 2 + (k * 1.05 - cx) * W_ / fovw
    ann.append("-annotate +%d+%d '%s'" % (int(x) - 40, 950, name))
os.system("magick %s -gravity NorthWest -font DejaVu-Sans -pointsize 30 -fill '#111' %s %s" % (row, " ".join(ann), row))
rows = [row] if MODE in ("looks", "gear", "bodykeys") else []
for tag, ang, el in [r for r in (("front", 0, 0.0), ("q34", 38, 0.0), ("back", 150, 0.03)) if r[0] in ROWS]:
    parts = []
    for k, c in enumerate(chars):
        name, look, arm, meshes, vis = c
        show_only([c])
        bpy.context.view_layer.update()
        hp = arm.matrix_world @ arm.pose.bones["head"].head
        target = Vector((hp.x, hp.y - 0.035, hp.z + 0.045)) if ZOOM == 1.0 else Vector((hp.x, hp.y - 0.08, hp.z + 0.05))
        a = math.radians(ang)
        cam.data.lens = 85
        d = (0.78 if tag != "back" else 0.95) / ZOOM
        cam.location = target + Vector((d * math.sin(a), -d * math.cos(a), el))
        cam.rotation_euler = (math.radians(90) - math.atan2(el, d), 0, a)
        parts.append(render(os.path.join(TMP, "%s_%s.png" % (tag, name)), (400, 480) if ZOOM == 1.0 else (800, 600)))
    rp = os.path.join(TMP, "row_%s.png" % tag)
    os.system("magick %s +append %s" % (" ".join(parts), rp))
    rows.append(rp)
os.system("magick %s -append %s" % (" ".join(rows), OUTP))
print("PREVIEW", OUTP)
