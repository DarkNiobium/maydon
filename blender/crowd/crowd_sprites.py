"""Stadium spectator sprite atlas (MultiMesh billboards, seen from 15-80 m).

    nice blender -b --python ~/maydon/blender/crowd/crowd_sprites.py -- [out.png]

Atlas 1024x512 RGBA: 8 columns (people) x 2 rows (row 0 / top = idle, row 1 / bottom = cheering),
cells 128x256. Orthographic front view, same world scale in every cell: 256 px = 2.25 m (113.8 px/m),
feet 4 px above the cell bottom. Flat ambient lighting (white world, no lamps, Standard view transform).
People are MPFB humans (CC0 MakeHuman base + skins/hair/shoes) with procedural plain-colour clothes built by
the character library (../chars/mlib.py: KitBuilder offsets body faces) -> no logos anywhere.
"""
import bpy, bmesh, os, sys, math, random
import numpy as np
sys.path.insert(0, os.path.expanduser("~/maydon/blender/chars"))
import mlib
from mlib import log
from mathutils import Vector, Matrix
from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = next((a for a in argv if a.endswith(".png")), os.path.expanduser("~/maydon/game/assets/gen/fans.png"))
ONLY = [int(a) for a in argv if a.isdigit()]
CELL_W, CELL_H = 128, 256
SS = 2                                   # supersampling
WORLD_H = 2.25                           # metres covered by the cell height
FOOT_MARGIN_PX = 4
TMP = os.path.join(HERE, "tmp")
os.makedirs(TMP, exist_ok=True)

ASIAN = "young_asian_male/young_lightskinned_male_diffuse3.png"
ASIAN_MID = "middleage_asian_male/middleage_lightskinned_male_diffuse2.png"
ASIAN_OLD = "old_asian_male/old_lightskinned_male_diffuse2.png"
ASIAN_F = "young_asian_female/young_lightskinned_female_diffuse3.png"
CAUC = "young_caucasian_male/young_lightskinned_male_diffuse.png"
CAUC2 = "young_caucasian_male2/young_lightskinned_male_diffuse2.png"
CAUC_F = "young_caucasian_female/young_lightskinned_female_diffuse.png"
CAUC_MID = "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png"
AFR = "young_african_male/young_darkskinned_male_diffuse.png"

BLACK = (0.025, 0.021, 0.018)
DARKB = (0.05, 0.036, 0.026)
GREY = (0.32, 0.31, 0.30)
LBROWN = (0.22, 0.15, 0.09)
UZ = dict(tex=[ASIAN, CAUC2], blend=0.45, tone=(0.97, 0.93, 0.83), sat=0.85, val=0.97, ao=0.45)

JEANS = (0.10, 0.16, 0.30)
BLACKP = (0.04, 0.04, 0.045)
KHAKI = (0.40, 0.34, 0.24)
GREYP = (0.22, 0.22, 0.23)

# top: tee (short sleeve), long (long sleeve tee/hoodie), jacket (long, thicker), jersey (tee + trims)
PEOPLE = [
    dict(gender=1.0, age=24, muscle=0.5, weight=0.45, height=1.76, race=(0.6, 0.4, 0.0), skin=UZ,
         hair="short01", hair_scale=0.95, hair_color=BLACK, brow="eyebrow002", beard=0.15,
         top="jersey", top_col=(0.03, 0.18, 0.62), trim_col=(0.95, 0.95, 0.95), bottom_col=JEANS, shoes="shoes05",
         cheer="V"),
    dict(gender=1.0, age=45, muscle=0.45, weight=0.72, height=1.72, race=(0.55, 0.45, 0.0),
         skin=dict(tex=[ASIAN_MID, CAUC2], blend=0.4, tone=(0.94, 0.86, 0.76), sat=0.88, val=0.95, ao=0.5),
         hair="short04", hair_scale=0.85, hair_color=DARKB, brow="eyebrow003", beard=0.5,
         top="jacket", top_col=(0.10, 0.11, 0.12), bottom_col=GREYP, shoes="shoes04", cheer="pump"),
    dict(gender=1.0, age=17, muscle=0.4, weight=0.35, height=1.70, race=(0.7, 0.3, 0.0), skin=UZ,
         hair="short02", hair_scale=0.8, hair_color=BLACK, brow="eyebrow001", beard=0.0,
         top="long", top_col=(0.85, 0.12, 0.10), bottom_col=BLACKP, shoes="shoes05", cheer="V"),
    dict(gender=0.0, age=26, muscle=0.35, weight=0.42, height=1.63, race=(0.6, 0.4, 0.0), cupsize=0.55,
         skin=dict(tex=[ASIAN_F, CAUC_F], blend=0.4, tone=(0.98, 0.93, 0.85), sat=0.85, val=0.98, ao=0.45),
         hair="ponytail01", hair_scale=0.95, hair_color=BLACK, brow="eyebrow006", beard=0.0,
         top="tee", top_col=(0.96, 0.96, 0.95), bottom_col=JEANS, shoes="shoes05", cheer="clap"),
    dict(gender=1.0, age=58, muscle=0.35, weight=0.62, height=1.69, race=(0.55, 0.45, 0.0),
         skin=dict(tex=[ASIAN_OLD, CAUC_MID], blend=0.4, tone=(0.93, 0.85, 0.75), sat=0.85, val=0.95, ao=0.55),
         hair=None, hair_color=GREY, brow="eyebrow012", beard=0.65, scalp_density=0.55,
         top="long", top_col=(0.20, 0.30, 0.20), bottom_col=KHAKI, shoes="shoes01", cheer="pump"),
    dict(gender=1.0, age=31, muscle=0.6, weight=0.5, height=1.84, race=(0.0, 1.0, 0.0),
         skin=dict(tex=[CAUC, CAUC2], blend=0.5, tone=(1.0, 0.95, 0.92), sat=0.9, val=1.0, ao=0.45),
         hair="short01", hair_scale=0.9, hair_color=LBROWN, brow="eyebrow004", beard=0.3,
         top="long", hoodie=True, top_col=(0.55, 0.57, 0.60), bottom_col=JEANS, shoes="shoes02", cheer="V"),
    dict(gender=1.0, age=21, muscle=0.6, weight=0.45, height=1.80, race=(0.0, 0.05, 0.95),
         skin=dict(tex=[AFR], tone=(1, 1, 1), sat=1.0, val=1.0, ao=0.4),
         hair="afro01", hair_scale=0.6, hair_color=BLACK, brow="eyebrow004", beard=0.1,
         top="jersey", top_col=(0.95, 0.80, 0.10), trim_col=(0.05, 0.25, 0.10), bottom_col=BLACKP,
         shoes="shoes05", cheer="mixed"),
    dict(gender=0.0, age=38, muscle=0.3, weight=0.55, height=1.60, race=(0.5, 0.5, 0.0), cupsize=0.6,
         skin=dict(tex=[ASIAN_F, CAUC_F], blend=0.5, tone=(0.96, 0.90, 0.82), sat=0.85, val=0.96, ao=0.5),
         hair="bob01", hair_scale=0.95, hair_color=DARKB, brow="eyebrow011", beard=0.0,
         top="jacket", top_col=(0.45, 0.12, 0.28), bottom_col=BLACKP, shoes="shoes04", cheer="V"),
]

TOPS = {
    "tee": dict(T_SLEEVE=0.5, O_SHIRT=0.012, O_SLEEVE=0.013, O_SHIRT_HEM=0.02, Z_HEM=-0.06, DRAPE_SHIRT=14),
    "jersey": dict(T_SLEEVE=0.5, O_SHIRT=0.012, O_SLEEVE=0.013, O_SHIRT_HEM=0.02, Z_HEM=-0.06, DRAPE_SHIRT=14),
    "long": dict(T_SLEEVE=1.62, O_SHIRT=0.014, O_SLEEVE=0.012, O_SHIRT_HEM=0.022, Z_HEM=-0.07, DRAPE_SHIRT=16),
    "jacket": dict(T_SLEEVE=1.62, O_SHIRT=0.024, O_SLEEVE=0.018, O_SHIRT_HEM=0.03, Z_HEM=-0.10, DRAPE_SHIRT=22,
                   COLLAR_F=-0.03, COLLAR_S=0.0, COLLAR_B=0.0),
}
TROUSERS = dict(T_HEM=6.0, T_SOCK=0.94, O_SHORTS=0.009, O_SHORTS_FLARE=0.012, O_SHORTS_INNER=0.004,
                DRAPE_SHORTS=10, Z_WAIST=0.06)


def flat_world():
    sc = bpy.context.scene
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    bg = sc.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (1, 1, 1, 1)
    bg.inputs[1].default_value = 1.0
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.film_transparent = True
    sc.eevee.taa_render_samples = 12
    for o in list(sc.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)


def clothes_material(p, ao_img):
    m = bpy.data.materials.new("clothes")
    nt = m.node_tree
    bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bs.inputs["Roughness"].default_value = 0.85
    bs.inputs["Specular IOR Level"].default_value = 0.2
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
    sep = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(vc.outputs[0], sep.inputs[0])

    def rgb(c):
        n = nt.nodes.new("ShaderNodeRGB"); n.outputs[0].default_value = tuple(c) + (1,); return n.outputs[0]

    def mix(fac, a, b):
        n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"
        nt.links.new(fac, n.inputs[0]); nt.links.new(a, n.inputs[6]); nt.links.new(b, n.inputs[7])
        return n.outputs[2]

    def gt(x, v):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = "GREATER_THAN"; n.inputs[1].default_value = v
        nt.links.new(x, n.inputs[0]); return n.outputs[0]
    trim = p.get("trim_col", p["top_col"]) if p["top"] == "jersey" else p["top_col"]
    col = mix(sep.outputs[2], rgb(p["bottom_col"]), rgb((0.9, 0.9, 0.9)))          # socks hidden in shoes
    col = mix(sep.outputs[1], col, rgb(p["bottom_col"]))
    col = mix(gt(sep.outputs[0], 0.25), col, rgb(trim))
    col = mix(gt(sep.outputs[0], 0.75), col, rgb(p["top_col"]))
    ao = nt.nodes.new("ShaderNodeTexImage"); ao.image = ao_img; ao.image.colorspace_settings.name = "Non-Color"
    aom = nt.nodes.new("ShaderNodeMapRange"); nt.links.new(ao.outputs[0], aom.inputs[0])
    aom.inputs[3].default_value = 0.55; aom.inputs[4].default_value = 1.0
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = "RGBA"; mm.blend_type = "MULTIPLY"; mm.inputs[0].default_value = 1.0
    nt.links.new(col, mm.inputs[6])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        nt.links.new(aom.outputs[0], comb.inputs[i])
    nt.links.new(comb.outputs[0], mm.inputs[7])
    nt.links.new(mm.outputs[2], bs.inputs["Base Color"])
    return m


def simple_material(name, tex, alpha=False, rough=0.6, tint=None):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex, check_existing=True)
    nt.links.new(t.outputs[0], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Specular IOR Level"].default_value = 0.3
    if alpha:
        r = nt.nodes.new("ShaderNodeMath"); r.operation = "ROUND"
        nt.links.new(t.outputs[1], r.inputs[0]); nt.links.new(r.outputs[0], bs.inputs["Alpha"])
    return m


def aim(rig, name, direction):
    """Point a pose bone along an armature-space direction (keeps its head where the parent put it)."""
    pb = rig.pose.bones.get(name)
    if pb is None:
        return
    bpy.context.view_layer.update()
    rest = pb.bone.matrix_local
    rest_y = (rest.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = rest_y.rotation_difference(Vector(direction).normalized())
    rot = q.to_matrix() @ rest.to_3x3()
    m = rot.to_4x4()
    m.translation = pb.head
    pb.matrix = m
    bpy.context.view_layer.update()


def pose(rig, kind, seed):
    rng = random.Random(seed)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for s, sg in (("l", 1), ("r", -1)):
        k = kind
        if kind == "mixed":
            k = "V" if s == "l" else "pump"
        if k == "idle":
            ua = (sg * 0.20, 0.02, -1.0); la = (sg * 0.08, -0.12, -1.0)
        elif k == "V":
            ua = (sg * 0.62, -0.05, 0.80); la = (sg * 0.38, -0.12, 1.0)
        elif k == "pump":
            ua = (sg * 1.0, -0.15, 0.25); la = (sg * 0.12, -0.18, 1.0)
        elif k == "clap":
            ua = (sg * 0.35, -0.35, 0.85); la = (-sg * 0.45, -0.15, 1.0)
        aim(rig, "upperarm_" + s, ua)
        aim(rig, "lowerarm_" + s, la)
        aim(rig, "hand_" + s, la)
    if kind != "idle":
        hb = rig.pose.bones.get("head")
        if hb:
            hb.rotation_quaternion = Matrix.Rotation(math.radians(-10), 4, "X").to_quaternion()
    bpy.ops.object.mode_set(mode="OBJECT")


def build_person(i, p):
    mlib.clear_scene()
    spec = dict(p)
    spec["height_macro"] = 0.5 + (p["height"] - (1.69 if p["gender"] > 0.5 else 1.60)) / 1.40
    bm, rig = mlib.build_human(spec)
    eyes, _ = mlib.add_asset(bm, "eyes/low-poly/low-poly.mhclo", "Eyes")
    shoes, mh_sh = mlib.add_asset(bm, "clothes/%s/%s.mhclo" % (p["shoes"], p["shoes"]), "Clothes")
    hair = None
    if p.get("hair"):
        hair, mh_h = mlib.add_asset(bm, "hair/%s/%s.mhclo" % (p["hair"], p["hair"]), "Hair")
    coords = mlib.shape_coords(bm)
    if hair is not None:
        mlib.hair_adjust(hair, mh_h, coords, dict(scale=p.get("hair_scale", 1.0)))
    inside = mlib.prepare_boots(shoes, mh_sh, coords)
    body = mlib.freeze_body(bm, coords)
    ao = mlib.bake_ao(body, size=512, samples=24)
    # skin atlas (brows, eyes, scalp hair / stubble) via the character compositor
    cs = dict(skin=p["skin"], hair_color=p["hair_color"], eyes="brown" if p["race"][1] < 0.9 else "bluegreen",
              hair_paint=dict(density=p.get("scalp_density", 0.85)), beard=dict(density=p.get("beard", 0.0)),
              brow_opacity=0.8)
    brow = p.get("brow", "eyebrow002")
    mhb = Mhclo(); bp = os.path.join(mlib.ASSETS, "eyebrows/%s/%s.mhclo" % (brow, brow)); mhb.load(bp)
    skin_path = os.path.join(TMP, "skin_%d.png" % i)
    mlib.composite_skin(cs, body, mlib.compute_reference_masks(), ao, mhb, bp.replace(".mhclo", ".obj"), skin_path, size=512)
    # clothes
    me = body.data
    me.uv_layers.new(name="UV2")
    me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    body.vertex_groups.new(name="decprot")
    mats = [simple_material("skin", skin_path, rough=0.6)]
    ao_img = mlib.np_to_image(np.dstack([ao, ao, ao, np.ones_like(ao)]), "ao_%d" % i)
    mats.append(clothes_material(p, ao_img))
    for m in mats:
        me.materials.append(m)
    P = dict(TOPS[p["top"]]); P.update(TROUSERS)
    kb = mlib.KitBuilder(body, rig, inside, P)
    b = bmesh.new(); b.from_mesh(me)
    dl = b.verts.layers.deform.verify()
    layers = dict(uv=b.loops.layers.uv["UVMap"], uv2=b.loops.layers.uv["UV2"],
                  col=b.loops.layers.float_color["Col"], prot=body.vertex_groups["decprot"].index)
    for f in b.faces:
        for l in f.loops:
            l[layers["col"]] = (0, 0, 0, 0)
    kb.make_cuts(b, dl)
    cls = kb.classify(b, dl)
    if p["top"] != "jersey":
        for k in cls.values():
            k["trim"] = False
    binside = set(v for v in b.verts if v.index < mlib.NBODY and v.index in inside)
    mlib.kit_build_geometry(kb, b, dl, cls, binside, layers)
    if p["top"] != "jersey":
        # plain tops: no contrasting collar/cuff trims
        for f in b.faces:
            if f.material_index == 1:
                for l in f.loops:
                    c = l[layers["col"]]
                    if 0.25 < c[0] < 0.75:
                        l[layers["col"]] = (1.0, 0, 0, 0)
    b.to_mesh(me); b.free()
    for poly in me.polygons:
        poly.use_smooth = True
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE"); mod.object = rig
    # assets materials
    mlib.ensure_layers(eyes)
    mlib.remap_uv(eyes, mlib.EYE_RECT)
    eyes.data.materials.clear(); eyes.data.materials.append(mats[0])
    sd = os.path.join(mlib.ASSETS, "clothes", p["shoes"])
    stex = [f for f in os.listdir(sd) if f.endswith("diffuse.png")][0]
    shoes.data.materials.clear(); shoes.data.materials.append(simple_material("shoes", os.path.join(sd, stex), rough=0.5))
    if hair is not None:
        hd = os.path.join(mlib.ASSETS, "hair", p["hair"])
        png = [f for f in os.listdir(hd) if f.endswith("diffuse.png")][0]
        hp = os.path.join(TMP, "hair_%d.png" % i)
        mlib.process_hair_texture(os.path.join(hd, png), p["hair_color"], hp, alpha_boost=1.4)
        hm = simple_material("hair", hp, alpha=True, rough=0.5)
        hm.use_backface_culling = False
        hair.data.materials.clear(); hair.data.materials.append(hm)
    for o in (eyes, shoes, hair):
        if o is not None:
            for poly in o.data.polygons:
                poly.use_smooth = True
    bm.hide_render = True
    bm.hide_viewport = True
    return rig, body


def render_cell(rig, path):
    flat_world()
    sc = bpy.context.scene
    cam = bpy.data.objects.get("spr_cam")
    if cam is None:
        cam = bpy.data.objects.new("spr_cam", bpy.data.cameras.new("spr_cam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.ortho_scale = WORLD_H
    px_per_m = CELL_H / WORLD_H
    cz = WORLD_H / 2 - FOOT_MARGIN_PX / px_per_m - 0.018     # shoe soles reach ~1.8 cm below 0
    cam.location = (0, -10, cz)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.resolution_x, sc.render.resolution_y = CELL_W * SS, CELL_H * SS
    sc.render.resolution_percentage = 100
    sc.render.filter_size = 1.2
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_cell(path):
    img = bpy.data.images.load(path)
    a = mlib.image_to_np(img).copy()
    bpy.data.images.remove(img)
    # premultiplied downsample
    al = a[..., 3:4]
    rgb = mlib.downsample(a[..., :3] * al, SS)
    aa = mlib.downsample(al, SS)
    rgb = rgb / np.maximum(aa, 1e-6)
    out = np.concatenate([rgb, aa], axis=2)
    # bleed colour under transparent pixels (no dark fringes when filtered / mipmapped)
    filled = mlib.dilate(np.concatenate([rgb, (aa > 0.02).astype(np.float32)], axis=2))
    out[..., :3] = np.where(aa > 0.02, rgb, filled[..., :3])
    return np.clip(out, 0, 1)


def main():
    cells = {}
    for i, p in enumerate(PEOPLE):
        if ONLY and i not in ONLY:
            continue
        rig, body = build_person(i, p)
        for row, kind in enumerate(("idle", p.get("cheer", "V"))):
            pose(rig, kind, seed=i * 10 + row)
            path = os.path.join(TMP, "cell_%d_%d.png" % (i, row))
            render_cell(rig, path)
            cells[(i, row)] = path
        log("person", i, "done")
    atlas = np.zeros((CELL_H * 2, CELL_W * 8, 4), np.float32)
    old = None
    if ONLY and os.path.exists(OUT):
        im = bpy.data.images.load(OUT); old = mlib.image_to_np(im).copy(); bpy.data.images.remove(im)
        atlas[:] = old
    for (i, row), path in cells.items():
        a = load_cell(path)
        y0 = (1 - row) * CELL_H          # numpy rows are bottom-up: row 0 (idle) -> top half of the PNG
        atlas[y0:y0 + CELL_H, i * CELL_W:(i + 1) * CELL_W] = a
    mlib.save_np_png(atlas, OUT, "PNG")
    log("crowd atlas ->", OUT)


main()
