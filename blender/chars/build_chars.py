"""MAYDON footballer variants generator.

Usage (from anywhere):
    nice blender -b --python ~/maydon/blender/chars/build_chars.py -- [p01 p02 ...] [--keep-blend]

Writes ~/maydon/game/assets/chars/variants/pXX.glb (+ textures embedded) and a stats json per variant
into ~/maydon/blender/chars/work/.
"""
import bpy, bmesh, sys, os, json, math, time
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mlib
from mlib import log
from variants import VARIANTS
from mathutils import Vector

OUT_DIR = os.path.expanduser("~/maydon/game/assets/chars/variants")
WORK = os.path.join(HERE, "work")
TRI_BUDGET = 11200


def measure_height(coords):
    co = coords[:mlib.NBODY]
    return float(co[:, 2].max() - co[:, 2].min())


def _prep_tex(path, out_path, size):
    """Downscale a source texture to an exact power size (premultiplied alpha keeps card edges clean)."""
    img = bpy.data.images.load(path)
    a = mlib.image_to_np(img)
    bpy.data.images.remove(img)
    f = max(1, a.shape[0] // size)
    if f > 1:
        if a.shape[2] == 4:
            rgb = mlib.downsample(a[..., :3] * a[..., 3:4], f)
            al = mlib.downsample(a[..., 3:4], f)
            a = np.concatenate([rgb / np.maximum(al, 1e-6), al], axis=2)
        else:
            a = mlib.downsample(a, f)
    mlib.save_np_png(a, out_path, "PNG")
    return out_path


def _prep_eye(path, out_path, size=512):
    """Eye atlas: keep the iris/pupil, take the bloodshot red out of the sclera."""
    img = bpy.data.images.load(path)
    a = mlib.image_to_np(img)
    bpy.data.images.remove(img)
    f = max(1, a.shape[0] // size)
    if f > 1:
        a = mlib.downsample(a, f)
    rgb = a[..., :3]
    lum = rgb @ np.array([0.30, 0.55, 0.15])
    sclera = np.clip((lum - 0.52) / 0.28, 0, 1)[..., None]
    gray = lum[..., None]
    rgb = rgb * (1.0 - 0.62 * sclera) + gray * (0.62 * sclera)
    rgb = np.clip(rgb * (1.0 + 0.10 * sclera), 0, 1)
    # soft studio catchlights on both irises (baked; mobile eye mesh is too low-poly for a
    # reliable specular dot from the directional light)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    for cx, cy in ((147.0, 366.5), (360.0, 155.5)):
        d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (7.5 ** 2)
        k = np.clip(1.0 - d2, 0, 1) ** 2
        rgb = rgb * (1.0 - k[..., None]) + np.array([0.97, 0.98, 1.0])[None, None, :] * k[..., None]
    a[..., :3] = np.clip(rgb, 0, 1)
    mlib.save_np_png(a, out_path, "PNG")
    return out_path


def build_shape(spec):
    """Build MPFB human, iterating once on the height macro to hit spec['height']."""
    hm = spec.get("height_macro", 0.5 + (spec["height"] - 1.69) / 1.40)
    for it in range(3):
        mlib.clear_scene()
        s = dict(spec); s["height_macro"] = hm
        bm, rig = mlib.build_human(s)
        coords = mlib.shape_coords(bm)
        H = measure_height(coords)
        err = spec["height"] - H
        log("height iter", it, "macro %.3f -> %.3f m (target %.3f)" % (hm, H, spec["height"]))
        if abs(err) < 0.004:
            break
        slope = 1.40 if hm >= 0.5 else 0.70
        hm = hm + err / slope
    spec["_height"] = H
    spec["_height_macro"] = hm
    return bm, rig, coords


def make_materials(skin_path, kit_path, hair_path, eye_path, brow_path, lash_path, teeth_path, mats):
    def principled(name):
        m = mats[name]
        nt = m.node_tree
        bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        return m, nt, bs

    def tex_mat(name, path, rough, spec, alpha=False, cull=True, alpha_thr=0.45):
        m, nt, bs = principled(name)
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path)
        nt.links.new(t.outputs[0], bs.inputs["Base Color"])
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Specular IOR Level"].default_value = spec
        if alpha:
            a = nt.nodes.new("ShaderNodeMath"); a.operation = "ROUND"
            nt.links.new(t.outputs[1], a.inputs[0]); nt.links.new(a.outputs[0], bs.inputs["Alpha"])
            m.blend_method = "CLIP"
            m.surface_render_method = "DITHERED"
            m.alpha_threshold = alpha_thr
        else:
            m.blend_method = "OPAQUE"
            m.surface_render_method = "DITHERED"
        m.use_backface_culling = cull
        return m

    tex_mat("skin", skin_path, 0.50, 0.40)
    tex_mat("kit", kit_path, 0.74, 0.30)
    hair = tex_mat("hair", hair_path, 0.34, 0.62, alpha=True, cull=False, alpha_thr=0.42)
    eye = tex_mat("eye", eye_path, 0.16, 0.45)
    brow = tex_mat("brow", brow_path, 0.62, 0.35, alpha=True, cull=False, alpha_thr=0.28)
    lash = tex_mat("lash", lash_path, 0.55, 0.35, alpha=True, cull=False, alpha_thr=0.28)
    teeth = tex_mat("teeth", teeth_path, 0.24, 0.45)
    return hair, eye, brow, lash, teeth


def build(name, keep_blend=False):
    t_start = time.time()
    spec = dict(VARIANTS[name])
    os.makedirs(OUT_DIR, exist_ok=True)
    wd = os.path.join(WORK, name)
    os.makedirs(wd, exist_ok=True)
    masks = mlib.compute_reference_masks()

    bm, rig, coords = build_shape(spec)
    A = mlib.ASSETS
    # --- MPFB fitted assets (weights interpolated by MPFB) ---
    eyes, mh_eyes = mlib.add_asset(bm, "eyes/low-poly/low-poly.mhclo", "Eyes")
    teeth, mh_teeth = mlib.add_asset(bm, "teeth/teeth_base/teeth_base.mhclo", "Teeth")
    boot_name = spec.get("boots", "shoes05")
    shoes, mh_shoes = mlib.add_asset(bm, "clothes/%s/%s.mhclo" % (boot_name, boot_name), "Clothes")
    brow_name = spec.get("brow", "eyebrow002")
    brows, mh_brows = mlib.add_asset(bm, "eyebrows/%s/%s.mhclo" % (brow_name, brow_name), "Eyebrows")
    lash_name = spec.get("lashes", "eyelashes01")
    lashes, mh_lashes = mlib.add_asset(bm, "eyelashes/%s/%s.mhclo" % (lash_name, lash_name), "Eyelashes")
    H = spec.get("hair_cards")
    hair = None
    if H:
        hair, mh_hair = mlib.add_asset(bm, "hair/%s/%s.mhclo" % (H["asset"], H["asset"]), "Hair")
    coords = mlib.shape_coords(bm)        # unchanged by assets, but be safe
    for o in (eyes, teeth, shoes, brows, lashes, hair):
        if o is not None:
            mlib.apply_armature_free(o)

    # hair shaping
    if hair is not None:
        co = coords
        eye_z = mlib.joint_center(coords, (13606, 13613)).z
        top_z = coords[:mlib.NBODY, 2].max()
        ear_z = eye_z - 0.02
        hz = lambda c: (c.z - ear_z) / (top_z - ear_z)
        cut = None
        if H.get("keep_above_hz") is not None:
            thr = H["keep_above_hz"]
            front_keep = H.get("front_keep", True)
            cut = lambda c: hz(c) < thr and not (front_keep and c.y < -0.06 and hz(c) > thr - 0.25)
        if H.get("cut_below_z_rel") is not None:
            zc = eye_z + H["cut_below_z_rel"]
            cut = lambda c: c.z < zc
        if H.get("cut_front_below") is not None or H.get("cut_back_below") is not None:
            eye = mlib.joint_center(coords, (13606, 13613))
            split = eye.y + H.get("split_dy", 0.075)
            cf, cb = H.get("cut_front_below"), H.get("cut_back_below")
            def cut(c, eye=eye, split=split, cf=cf, cb=cb):
                zr = c.z - eye.z
                if c.y < split:
                    return cf is not None and zr < cf
                return cb is not None and zr < cb
        cut0 = cut
        if H.get("taper") and H.get("keep_above_hz") is None:
            thr = H["taper"][0] - 0.12
            cut = lambda c, cut0=cut0: (hz(c) < thr and c.y > -0.05) or (cut0 is not None and cut0(c))
        mlib.hair_adjust(hair, mh_hair, coords, dict(scale=H.get("scale", 1.0), cut=cut,
                                                      taper=H.get("taper"), hz_fn=hz))

    inside = mlib.prepare_boots(shoes, mh_shoes, coords)
    body = mlib.freeze_body(bm, coords)
    # MHCLO brow cards sit too low on the modified face: lift them 12 mm and re-project onto the
    # forehead surface (ray along +Y), 1.5 mm in front of the skin so they never sink in.
    if brows is not None:
        from mathutils.bvhtree import BVHTree
        bvh = BVHTree.FromPolygons([tuple(v.co[:]) for v in body.data.vertices],
                                   [tuple(p.vertices) for p in body.data.polygons])
        for v in brows.data.vertices:
            p = v.co.copy(); p.z += 0.003
            hit = bvh.ray_cast(Vector((p.x, -1.0, p.z)), Vector((0, 1, 0)))
            if hit[0] is not None:
                v.co = Vector((p.x, hit[0].y - 0.0015, p.z))

    # --- textures that need the full-res body ---
    ao = mlib.bake_ao(body)
    skin_path = os.path.join(wd, "skin.jpg")
    skin_size = int(spec.get("skin_size", 1024))
    mlib.composite_skin(spec, body, masks, ao, None, "", skin_path, size=skin_size)
    kit_path = os.path.join(wd, "kit.png")
    mlib.make_kit_texture(ao, os.path.join(A, "clothes/%s/%s_diffuse.png" % (boot_name, boot_name)), kit_path)
    hair_path = os.path.join(wd, "hair.png")
    if H:
        hd = os.path.join(A, "hair", H["asset"])
        png = [f for f in os.listdir(hd) if f.endswith("diffuse.png")][0]
        mlib.process_hair_texture(os.path.join(hd, png), spec["hair_color_cards"] if "hair_color_cards" in spec
                                  else spec["hair_color"], hair_path, size=1024,
                                  alpha_boost=H.get("alpha_boost", 1.3))
    else:
        mlib.process_hair_texture(os.path.join(A, "hair/short02/short02_diffuse.png"), spec["hair_color"],
                                  hair_path, size=1024)
    eye_src = os.path.join(A, "eyes/materials", spec.get("eyes", "brown") + "_eye.png")
    eye_path = _prep_eye(eye_src, os.path.join(wd, "eye.png"), 512)
    brow_src = os.path.join(A, "eyebrows/%s/%s.png" % (brow_name, brow_name))
    brow_path = _prep_tex(brow_src, os.path.join(wd, "brow.png"), 512)
    lash_src = os.path.join(A, "eyelashes/%s/%s.png" % (lash_name, lash_name))
    lash_path = _prep_tex(lash_src, os.path.join(wd, "lash.png"), 512)
    teeth_path = _prep_tex(os.path.join(A, "teeth/teeth_base/teeth.png"), os.path.join(wd, "teeth.png"), 512)

    # --- kit geometry ---
    body.vertex_groups.new(name="decprot")
    me = body.data
    MATS = {}
    for mn in ("skin", "kit", "hair", "eye", "brow", "lash", "teeth"):
        MATS[mn] = bpy.data.materials.new(mn)
        me.materials.append(MATS[mn])
    me.uv_layers.new(name="UV2")
    me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    kb = mlib.KitBuilder(body, rig, inside, spec.get("kit"))
    b = bmesh.new(); b.from_mesh(me)
    dl = b.verts.layers.deform.verify()
    layers = dict(uv=b.loops.layers.uv["UVMap"], uv2=b.loops.layers.uv["UV2"],
                  col=b.loops.layers.float_color["Col"], prot=body.vertex_groups["decprot"].index)
    for f in b.faces:
        for l in f.loops:
            l[layers["col"]] = (0, 0, 0, 0); l[layers["uv2"]].uv = (0, 1)
    kb.make_cuts(b, dl)
    cls = kb.classify(b, dl)
    binside = set(v for v in b.verts if v.index < mlib.NBODY and v.index in inside)
    kstats = mlib.kit_build_geometry(kb, b, dl, cls, binside, layers)
    # region per face for staged decimation: 0 kit, 1 head, 2 hands, 3 other skin
    G = mlib.Groups(body)
    gi_head = G.idx.get("head")
    hand_bones = set(i for n, i in G.idx.items() if any(n.startswith(f) for f in mlib.FINGERS) or n.startswith("hand_"))
    # drop the mouth cavity (mouth never opens: no jaw bone in game_engine) - UV island lower right
    uvl0 = layers["uv"]
    cav = []
    for f in b.faces:
        if f.material_index != 0:
            continue
        u = sum(l[uvl0].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uvl0].uv.y for l in f.loops) / len(f.loops)
        if 0.75 < u < 0.935 and 0.015 < v < 0.15:
            cav.append(f)
    bmesh.ops.delete(b, geom=cav, context="FACES")
    # regions are carried in material_index during decimation (kit=1, head=3, hands=4, skin=5)
    dl = b.verts.layers.deform.verify()
    for f in b.faces:
        if f.material_index == 1:
            continue
        hw = sum(v[dl].get(gi_head, 0.0) for v in f.verts) / len(f.verts)
        hd = sum(sum(v[dl].get(i, 0.0) for i in hand_bones) for v in f.verts) / len(f.verts)
        f.material_index = 3 if hw > 0.5 else 4 if hd > 0.5 else 5
    b.to_mesh(me); b.free()
    me.update()
    body.parent = rig
    for p in me.polygons:
        p.use_smooth = True

    # --- small assets: budgets ---
    parts = [o for o in (eyes, teeth, shoes, brows, lashes, hair) if o is not None]
    mlib.triangulate(teeth)
    mlib.decimate_to(teeth, spec.get("teeth_tris", 140), symmetry=True)
    mlib.triangulate(shoes)
    mlib.decimate_to(shoes, spec.get("boot_tris", 820), symmetry=True)
    if brows is not None:
        mlib.triangulate(brows)
        mlib.decimate_to(brows, spec.get("brow_tris", 240), symmetry=False)
    if lashes is not None:
        mlib.triangulate(lashes)
        mlib.decimate_to(lashes, spec.get("lash_tris", 260), symmetry=False)
    if hair is not None:
        mlib.triangulate(hair)
        mlib.decimate_to(hair, H.get("max_tris", 2000), symmetry=False)
    others = sum(mlib.tri_count(o) for o in parts)
    body_target = TRI_BUDGET - others
    log("tris before body decimation", mlib.tri_count(body), "target", body_target, "others", others)
    shares = spec.get("tri_shares", dict(kit=0.32, head=0.40, hands=0.08, skin=0.20))
    mlib.staged_decimate(body, body_target, shares)
    for p in body.data.polygons:
        if p.material_index >= 3:
            p.material_index = 0
    while len(body.data.materials) > 7:
        body.data.materials.pop()
    log("body tris", mlib.tri_count(body))

    # --- UVs / attributes / materials of parts ---
    for o in parts:
        mlib.ensure_layers(o)
        set_col = mlib.COL_BOOTS if o is shoes else mlib.COL_NONE
        mlib.set_corner_color(o, set_col)
        for p in o.data.polygons:
            p.use_smooth = True
    mlib.remap_uv(shoes, mlib.BOOT_RECT)
    hair_m, eye_m, brow_m, lash_m, teeth_m = make_materials(
        skin_path, kit_path, hair_path, eye_path, brow_path, lash_path, teeth_path, MATS)
    for o, m in ((eyes, eye_m), (teeth, teeth_m), (shoes, MATS["kit"]),
                 (brows, brow_m), (lashes, lash_m), (hair, hair_m)):
        if o is None:
            continue
        o.data.materials.clear()
        o.data.materials.append(m)
        for p in o.data.polygons:
            p.material_index = 0
    # body material indices: skin faces 0, kit faces 1, hair/eye/brow/lash/teeth 2..6

    # --- join ---
    for o in parts:
        for m in list(o.modifiers):
            o.modifiers.remove(m)
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [body] + parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    mlib.clean_vertex_groups(body, rig)
    mod = body.modifiers.new("Armature", "ARMATURE"); mod.object = rig
    body.parent = rig
    # sharp edges where the kit folds (rims) so normals stay crisp
    mlib.activate(body)
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(60), keep_sharp_edges=True)
    me = body.data
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.uv_layers.active = me.uv_layers["UVMap"]
    me.uv_layers["UVMap"].active_render = True

    # split: Body (skin + hair, no vertex colours) and Kit (kit surface with COLOR_0 masks + UV2).
    # glTF importers (Godot, Blender) multiply baseColor by COLOR_0, so skin/hair must not carry it.
    kit_ob = body.copy(); kit_ob.data = body.data.copy()
    bpy.context.scene.collection.objects.link(kit_ob)
    for ob, keep_kit in ((body, False), (kit_ob, True)):
        bb = bmesh.new(); bb.from_mesh(ob.data)
        dels = [f for f in bb.faces if (f.material_index == 1) != keep_kit]
        bmesh.ops.delete(bb, geom=dels, context="FACES")
        loose = [v for v in bb.verts if not v.link_faces]
        bmesh.ops.delete(bb, geom=loose, context="VERTS")
        bb.to_mesh(ob.data); bb.free()
    for a in ("Col", "region"):
        if a in body.data.attributes:
            body.data.attributes.remove(body.data.attributes[a])
    if "UV2" in body.data.uv_layers:
        body.data.uv_layers.remove(body.data.uv_layers["UV2"])
    if "region" in kit_ob.data.attributes:
        kit_ob.data.attributes.remove(kit_ob.data.attributes["region"])
    body.name = body.data.name = "Body"
    kit_ob.name = kit_ob.data.name = "Kit"
    kit_ob.parent = rig
    for ob in (body, kit_ob):
        for m in list(ob.modifiers):
            if m.type != "ARMATURE":
                ob.modifiers.remove(m)
        if not any(m.type == "ARMATURE" for m in ob.modifiers):
            mm = ob.modifiers.new("Armature", "ARMATURE"); mm.object = rig
        else:
            next(m for m in ob.modifiers if m.type == "ARMATURE").object = rig
    kit_ob.data.color_attributes.active_color = kit_ob.data.color_attributes["Col"]
    # remove everything except rig + meshes
    for o in list(bpy.data.objects):
        if o not in (rig, body, kit_ob):
            bpy.data.objects.remove(o, do_unlink=True)
    rig.name = "Armature"; rig.data.name = "Armature"
    tris = mlib.tri_count(body) + mlib.tri_count(kit_ob)
    log("FINAL tris", tris, "body", mlib.tri_count(body), "kit", mlib.tri_count(kit_ob))

    # --- export ---
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True); body.select_set(True); kit_ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_skins=True,
        export_all_influences=False, export_def_bones=False, export_animations=False, export_morph=False,
        export_cameras=False, export_lights=False, export_image_format="AUTO", export_jpeg_quality=90,
        export_extras=False)
    stats = dict(name=name, tris=tris, height=spec["_height"], height_macro=spec["_height_macro"],
                 kit=kstats, uv2=getattr(kb, "uv2_info", None), seconds=round(time.time() - t_start, 1),
                 bones=[b.name for b in rig.data.bones],
                 rest_pose_note="MPFB/MakeHuman default rest pose (arms down ~45deg, elbows slightly bent)")
    with open(os.path.join(wd, "stats.json"), "w") as f:
        json.dump(stats, f, indent=1, default=float)
    if keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(wd, name + ".blend"))
    log("DONE", name, tris, "tris", round(time.time() - t_start, 1), "s ->", path)
    return stats


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    keep = "--keep-blend" in argv
    names = [a for a in argv if not a.startswith("--")] or sorted(VARIANTS.keys())
    for n in names:
        build(n, keep_blend=keep)
