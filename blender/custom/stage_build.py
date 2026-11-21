"""Stage 3: geometry + GLB for the customizable footballer.

    nice blender -b --python ~/maydon/blender/custom/stage_build.py [-- --keep-blend] [--hair=a,b]

Needs work/deltas.npz (stage_deltas.py) and the textures of stage_tex.py. Writes
assets/chars/custom/base.glb, hair_*.png, acc.png and work/build_stats.json.
"""
import bpy, bmesh, sys, os, math, json, time
import numpy as np
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clib as C
from clib import log, M, smoothstep
import morphs
import ckit
from bl_ext.user_default.mpfb.services.humanservice import HumanService
import hairstyles as HS

D = None
FACE_KEYS = list(morphs.FACE.keys()) + list(morphs.EXTRA.keys())
BODY_KEYS = list(morphs.BODY.keys())
ALL_KEYS = morphs.ORDER
TEX = json.load(open(os.path.join(C.WORK, "tex_info.json")))
BOOT_RECTS = TEX["BOOT_RECTS"]
ACC_RECTS = TEX["ACC_RECTS"]
EYE_RECT, TEETH_RECT = M.EYE_RECT, M.TEETH_RECT

BUDGET = 16500
HAIR_MAX = 2500
BOOT_TRIS = 860          # both feet, before studs (6 studs x 16 tris per foot are added)
EYES_TEETH = 640
BODY_KIT = BUDGET - HAIR_MAX - (BOOT_TRIS + 192) - 10
SHARES = dict(kit=0.34, head=0.38, hands=0.08, skin=0.20)

# kit-material encodings (COLOR_0)
COL_SHIRT = (1.0, 0.0, 0.0, 0.0)
COL_SOCKS = (0.0, 0.0, 1.0, 0.0)
COL_BOOTS = (0.0, 0.0, 0.0, 1.0)

BOOTS = [  # name, mesh asset, texture asset, deformation
    ("Boots_1", "shoes02", "shoes05", None),
    ("Boots_2", "shoes02", "shoes06", "speed"),
    ("Boots_3", "shoes01", "shoes01", "classic"),
    ("Boots_4", "shoes03", "shoes03", "sockboot"),
]


# ---------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------

def add_asset(bm, rel, typ):
    path = os.path.join(C.ASSETS, rel)
    ob = HumanService.add_mhclo_asset(path, bm, asset_type=typ, subdiv_levels=0, material_type="NONE")
    for m in list(ob.modifiers):
        if m.type != "ARMATURE":
            ob.modifiers.remove(m)
    mh, _ = C.load_mhclo(rel)
    return ob, C.Fit(mh, len(ob.data.vertices))


def fit_deltas(fit, coords, keys, fn=None):
    """fn(fit, coords) -> positions (default: plain mhclo fit). Returns base positions and per-key deltas."""
    fn = fn or (lambda f, c: f(c))
    base = fn(fit, coords)
    out = {}
    for k in keys:
        out[k] = fn(fit, coords + D[k]) - base
    return base, out


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def set_layers(ob, col=None, uv2=True):
    """UV2 + float corner colour 'Col' for kit-material meshes."""
    me = ob.data
    if len(me.uv_layers) == 0:
        me.uv_layers.new(name="UVMap")
    me.uv_layers[0].name = "UVMap"
    if uv2 and "UV2" not in me.uv_layers:
        l = me.uv_layers.new(name="UV2")
        for d in l.data:
            d.uv = (0.0, 1.0)
    if col is not None:
        if "Col" not in me.color_attributes:
            me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        a = me.color_attributes["Col"]
        a.data.foreach_set("color", np.tile(np.array(col, np.float32), len(a.data)))
        me.color_attributes.active_color = a
    me.uv_layers.active = me.uv_layers["UVMap"]
    me.uv_layers["UVMap"].active_render = True


def finish_mesh(ob, rig, keys, keep_all=False, limit=4, min_disp=2e-4):
    """weights clean-up, sk_ attributes -> shape keys, armature modifier, parent."""
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    M.clean_vertex_groups(ob, rig, limit=limit)
    made = C.attrs_to_shape_keys(ob, keys, keep_all=keep_all, min_disp=min_disp)
    for a in [a.name for a in ob.data.attributes if a.name.startswith("sk_")]:
        ob.data.attributes.remove(ob.data.attributes[a])
    mod = ob.modifiers.new("Armature", "ARMATURE"); mod.object = rig
    ob.parent = rig
    ob.matrix_parent_inverse.identity()
    for p in ob.data.polygons:
        p.use_smooth = True
    return made


def knn_transfer(ob, src_co, src_weights, src_deltas, groups, keys, k=6):
    """Skin weights + morph deltas for procedural meshes from the k nearest source vertices."""
    kd = KDTree(len(src_co))
    for i, c in enumerate(src_co):
        kd.insert(c, i)
    kd.balance()
    for g in groups:
        if g not in ob.vertex_groups:
            ob.vertex_groups.new(name=g)
    co = C.get_co(ob)
    W = np.zeros((len(co), len(groups)))
    Dl = {kk: np.zeros((len(co), 3)) for kk in keys}
    for i, c in enumerate(co):
        res = kd.find_n(c, k)
        ids = np.array([r[1] for r in res]); ds = np.array([r[2] for r in res])
        w = 1.0 / np.maximum(ds, 1e-4) ** 2
        w /= w.sum()
        W[i] = (src_weights[ids] * w[:, None]).sum(axis=0)
        for kk in keys:
            Dl[kk][i] = (src_deltas[kk][ids] * w[:, None]).sum(axis=0)
    for j, g in enumerate(groups):
        vg = ob.vertex_groups[g]
        for i in range(len(co)):
            if W[i, j] > 0.003:
                vg.add([i], float(W[i, j]), "REPLACE")
    C.add_delta_attrs(ob, Dl, keys)


def body_weight_matrix(ob, groups):
    n = len(ob.data.vertices)
    W = np.zeros((n, len(groups)))
    gi = {ob.vertex_groups[g].index: j for j, g in enumerate(groups) if g in ob.vertex_groups}
    for v in ob.data.vertices:
        for g in v.groups:
            j = gi.get(g.group)
            if j is not None:
                W[v.index, j] = g.weight
    return W


def read_delta_attrs(ob, keys):
    me = ob.data; n = len(me.vertices)
    out = {}
    for k in keys:
        a = me.attributes.get("sk_" + k)
        d = np.zeros(n * 3, np.float32)
        if a is not None:
            a.data.foreach_get("vector", d)
        out[k] = d.reshape(-1, 3).astype(np.float64)
    return out


def uv_islands(b, uvl):
    """UV-connected face islands of a bmesh."""
    b.faces.ensure_lookup_table()
    seen = set(); isl = []
    for f in b.faces:
        if f.index in seen:
            continue
        stack = [f]; seen.add(f.index); fs = []
        while stack:
            g = stack.pop(); fs.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index in seen:
                        continue
                    ok = True
                    for v in e.verts:
                        u1 = [l[uvl].uv for l in g.loops if l.vert == v][0]
                        u2 = [l[uvl].uv for l in h.loops if l.vert == v][0]
                        if (u1 - u2).length > 1e-4:
                            ok = False
                    if ok:
                        seen.add(h.index); stack.append(h)
        isl.append(fs)
    return isl


def new_object(name, me):
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------------------------------------
# boots
# ---------------------------------------------------------------------------------------------

def build_boot(bm, coords, name, mesh, texname, deform, idx):
    ob, fit = add_asset(bm, "clothes/%s/%s.mhclo" % (mesh, mesh), "Clothes")
    base, dl = fit_deltas(fit, coords, BODY_KEYS)
    err = np.abs(C.get_co(ob) - base).max()
    C.set_co(ob, base)
    C.add_delta_attrs(ob, dl, BODY_KEYS)
    # remove the sock part of the MakeHuman shoe (its own UV island reaching up the calf)
    b = bmesh.new(); b.from_mesh(ob.data)
    uvl = b.loops.layers.uv.active
    kill = []
    for fs in uv_islands(b, uvl):
        zmax = max(v.co.z for f in fs for v in f.verts)
        if zmax > 0.15:
            kill.extend(fs)
    bmesh.ops.delete(b, geom=kill, context="FACES")
    b.to_mesh(ob.data); b.free()
    co = C.get_co(ob)
    # boundary (collar) points for the "inside" test of the kit
    b = bmesh.new(); b.from_mesh(ob.data)
    bco = np.array([v.co[:] for v in b.verts if v.is_boundary and v.co.z > 0.03])
    b.free()
    # shape variations
    if deform:
        for side in (1, -1):
            sel = (co[:, 0] * side) > 0
            p = co[sel]
            cx = np.median(p[:, 0]); zs = p[:, 2].min()
            y0, y1 = p[:, 1].min(), p[:, 1].max()          # toe (-y) .. heel
            t_toe = np.clip((y0 + 0.30 * (y1 - y0) - p[:, 1]) / (0.30 * (y1 - y0)), 0, 1)
            if deform == "speed":     # slimmer, lower, longer pointed toe
                p[:, 0] = cx + (p[:, 0] - cx) * (0.92 - 0.06 * t_toe)
                p[:, 2] = zs + (p[:, 2] - zs) * (0.92 - 0.10 * t_toe)
                p[:, 1] -= 0.008 * t_toe ** 1.5
            elif deform == "classic":  # dress-shoe last: flatter, rounder, a bit wider at the ball
                p[:, 2] = zs + (p[:, 2] - zs) * 0.96
                p[:, 0] = cx + (p[:, 0] - cx) * (1.0 + 0.03 * t_toe)
            elif deform == "sockboot":  # ankle collar hugging the leg, thinner (football) sole
                hz = np.clip((p[:, 2] - 0.06) / 0.04, 0, 1)
                p[:, 0] = cx + (p[:, 0] - cx) * (1.0 - 0.08 * hz)
                low = p[:, 2] < 0.0
                p[low, 2] *= 0.55
            co[sel] = p
        C.set_co(ob, co)
    # budget, then studs
    M.triangulate(ob)
    M.decimate_to(ob, BOOT_TRIS, symmetry=True)
    add_studs(ob)
    set_layers(ob, COL_BOOTS)
    M.remap_uv(ob, BOOT_RECTS[idx])
    ob.name = ob.data.name = name
    log("boot", name, mesh, texname, deform, "tris", tri_count(ob), "fit err %.5f" % err)
    return ob, bco


def add_studs(ob, nseg=6, h=0.0075, r0=0.0055, r1=0.0034):
    me = ob.data
    co = C.get_co(ob)
    b = bmesh.new(); b.from_mesh(me)
    dl = b.verts.layers.deform.verify()
    uvl = b.loops.layers.uv.active
    b.verts.ensure_lookup_table()
    sk_layers = [l for l in b.verts.layers.float_vector.keys() if l.startswith("sk_")]
    for side in (1, -1):
        sel = np.nonzero(co[:, 0] * side > 0)[0]
        p = co[sel]
        zs = p[:, 2].min()
        sole = p[p[:, 2] < zs + 0.012]
        y0, y1 = sole[:, 1].min(), sole[:, 1].max()
        L = y1 - y0

        def width_at(y):
            dd = np.abs(sole[:, 1] - y)
            band = sole[dd < 0.015] if (dd < 0.015).sum() >= 3 else sole[np.argsort(dd)[:8]]
            xm, xM = band[:, 0].min(), band[:, 0].max()
            return (xm + xM) / 2, (xM - xm) / 2
        studs = []
        for fy, fw in ((0.15, 0.55), (0.34, 0.62)):
            y = y0 + fy * L
            c, w = width_at(y)
            studs += [(c - w * fw, y), (c + w * fw, y)]
        y = y0 + 0.85 * L
        c, w = width_at(y)
        studs += [(c - w * 0.5, y), (c + w * 0.5, y)]
        for (x, y) in studs:
            d = np.linalg.norm(p[:, :2] - np.array([x, y]), axis=1) + np.abs(p[:, 2] - zs) * 4
            b.verts.ensure_lookup_table()
            src = b.verts[int(sel[np.argmin(d)])]
            ztop = zs + 0.0015
            ring0, ring1 = [], []
            for j in range(nseg):
                a = 2 * math.pi * j / nseg
                v0 = b.verts.new((x + r0 * math.cos(a), y + r0 * math.sin(a), ztop), src)
                v1 = b.verts.new((x + r1 * math.cos(a), y + r1 * math.sin(a), ztop - h), src)
                ring0.append(v0); ring1.append(v1)
            uv = None
            for l in src.link_loops:
                uv = l[uvl].uv.copy(); break
            faces = []
            for j in range(nseg):
                k = (j + 1) % nseg
                faces.append(b.faces.new([ring0[j], ring0[k], ring1[k], ring1[j]]))
            faces.append(b.faces.new(list(reversed(ring1))))
            for f in faces:
                for l in f.loops:
                    l[uvl].uv = uv if uv is not None else (0.5, 0.05)
    bmesh.ops.triangulate(b, faces=[f for f in b.faces if len(f.verts) > 4])
    b.to_mesh(me); b.free()
    me.update()


# ---------------------------------------------------------------------------------------------
# shells from the full-resolution body (sleeves, low socks, gloves)
# ---------------------------------------------------------------------------------------------

def shell(src, name, cuts, face_pred, offset_fn, rim_in=0.001, rim_top=None, smooth_iters=3):
    """Duplicate body faces (after implicit cuts) into an offset shell with inward rims at the borders.
    offset_fn(bmvert, normal) -> metres; rim_top(bmvert) -> inner offset for the rim (default rim_in)."""
    me = src.data.copy()
    ob = new_object(name, me)
    b = bmesh.new(); b.from_mesh(me)
    dl = b.verts.layers.deform.verify()
    for fn_faces, fn in cuts:
        KB.cut(b, [f for f in b.faces if fn_faces(f, dl)], fn)
    b.normal_update()
    nrm = {v: v.normal.copy() for v in b.verts}
    keep = [f for f in b.faces if face_pred(f, dl)]
    ks = set(keep)
    bmesh.ops.delete(b, geom=[f for f in b.faces if f not in ks], context="FACES")
    verts = list(b.verts)
    off = {v: offset_fn(v, nrm[v]) for v in verts}
    adj = {v: [e.other_vert(v) for e in v.link_edges] for v in verts}
    for _ in range(smooth_iters):
        off = {v: 0.5 * off[v] + 0.5 * (sum(off[u] for u in adj[v]) / len(adj[v]) if adj[v] else off[v]) for v in verts}
    orig = {v: v.co.copy() for v in verts}
    bnd = [e for e in b.edges if len(e.link_faces) == 1]
    for v in verts:
        v.co = orig[v] + nrm[v] * off[v]
    uvl = b.loops.layers.uv.active
    inner = {}
    for e in bnd:
        f = e.link_faces[0]
        for v in e.verts:
            if v not in inner:
                ri = rim_top(v) if rim_top else rim_in
                inner[v] = b.verts.new(orig[v] + nrm[v] * ri, v)
        # keep winding consistent with the face
        loop = next(l for l in f.loops if l.edge == e)
        a, c = loop.vert, loop.link_loop_next.vert
        uva, uvc = loop[uvl].uv.copy(), loop.link_loop_next[uvl].uv.copy()
        nf = b.faces.new([c, a, inner[a], inner[c]])
        for l, uv in zip(nf.loops, (uvc, uva, uva, uvc)):
            l[uvl].uv = uv
    b.to_mesh(me); b.free()
    me.update()
    return ob


def arm_t(c, s, bone):
    return M.tparam(c, KB.seg_ext[bone + "_" + s])


# ---------------------------------------------------------------------------------------------
# rings (headband, wristbands, armband, neck)
# ---------------------------------------------------------------------------------------------

def ring(name, ref, origin, axis, length, t0, t1, rows, nseg, margin, rect, thick=0.003, smooth=2):
    axis = Vector(axis).normalized()
    e1 = axis.orthogonal().normalized(); e2 = axis.cross(e1).normalized()
    o = Vector(origin)
    ref = np.asarray(ref)
    rel = ref - np.array(o)
    tt = rel @ np.array(axis) / length
    radial = rel - np.outer(tt * length, np.array(axis))
    ang = np.arctan2(radial @ np.array(e2), radial @ np.array(e1))
    rad = np.linalg.norm(radial, axis=1)
    R = np.zeros((rows + 1, nseg))
    dt = (t1 - t0) / rows
    for r in range(rows + 1):
        t = t0 + dt * r
        sel = np.abs(tt - t) < max(dt * 0.35, 0.005 / length)
        for j in range(nseg):
            a = -math.pi + 2 * math.pi * (j + 0.5) / nseg
            da = np.abs((ang[sel] - a + math.pi) % (2 * math.pi) - math.pi)
            m = da < (2 * math.pi / nseg)
            R[r, j] = rad[sel][m].max() if m.any() else np.nan
    valid_rows = [r for r in range(rows + 1) if not np.isnan(R[r]).any()]
    for r in range(rows + 1):
        row = R[r]
        if np.isnan(row).all() and valid_rows:
            row = R[min(valid_rows, key=lambda rr: abs(rr - r))].copy()
        if np.isnan(row).any():
            good = ~np.isnan(row)
            if good.any():
                row[~good] = np.interp(np.nonzero(~good)[0], np.nonzero(good)[0], row[good], period=nseg)
        R[r] = row
    for _ in range(smooth):
        R = 0.5 * R + 0.25 * (np.roll(R, 1, axis=1) + np.roll(R, -1, axis=1))
        R = np.maximum(R, 0.5 * R + 0.25 * (np.roll(R, 1, axis=1) + np.roll(R, -1, axis=1)))
    R = R + margin
    u0, v0, u1, v1 = rect
    verts, faces, uvs = [], [], []
    idx = {}
    for layer, dr in (("out", 0.0), ("in", -thick)):
        for r in range(rows + 1):
            t = t0 + dt * r
            for j in range(nseg + 1):
                a = -math.pi + 2 * math.pi * (j % nseg + 0.5) / nseg
                rr = R[r, j % nseg] + dr
                p = o + axis * (t * length) + (e1 * math.cos(a) + e2 * math.sin(a)) * rr
                idx[(layer, r, j)] = len(verts)
                verts.append(p[:])
    me = bpy.data.meshes.new(name)
    fl, ful = [], []
    for r in range(rows):
        for j in range(nseg):
            q = [idx[("out", r, j)], idx[("out", r, j + 1)], idx[("out", r + 1, j + 1)], idx[("out", r + 1, j)]]
            fl.append(q)
            ful.append([(u0 + (u1 - u0) * jj / nseg, v0 + (v1 - v0) * rr_ / rows) for (rr_, jj) in ((r, j), (r, j + 1), (r + 1, j + 1), (r + 1, j))])
    # rims at both edges (outer -> inner)
    for r, sgn in ((0, 1), (rows, -1)):
        for j in range(nseg):
            q = [idx[("out", r, j + 1)], idx[("out", r, j)], idx[("in", r, j)], idx[("in", r, j + 1)]]
            if sgn < 0:
                q = q[::-1]
            fl.append(q)
            vv = v0 if r == 0 else v1
            ful.append([(u0 + (u1 - u0) * jj / nseg, vv) for jj in (j + 1, j, j, j + 1)])
    me.from_pydata(verts, [], fl)
    uvl = me.uv_layers.new(name="UVMap")
    for p, fu in zip(me.polygons, ful):
        for li, uv in zip(p.loop_indices, fu):
            uvl.data[li].uv = uv
    me.validate(); me.update()
    ob = new_object(name, me)
    # outward normals: flip if the first quad points inward
    p0 = me.polygons[0]
    if p0.normal.dot(Vector(p0.center) - (o + axis * (axis.dot(Vector(p0.center) - o)))) < 0:
        for p in me.polygons:
            p.flip()
    return ob


# ---------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------

class KitGeo:
    pass


KB = None


def run(keep_blend=False, hair_only=None):
    global D, KB
    t0 = time.time()
    D = np.load(os.path.join(C.WORK, "deltas.npz"))
    bm, rig = C.create_human()
    C.check_rig(rig)
    coords = C.all_coords(bm)
    assert np.abs(coords - D["base"]).max() < 1e-5, "deltas.npz is stale (base mesh differs)"
    stats = dict(meshes={})

    # --- bodyparts (MPFB fitted, weights interpolated) ---
    eyes, feyes = add_asset(bm, "eyes/low-poly/low-poly.mhclo", "Eyes")
    teeth, fteeth = add_asset(bm, "teeth/teeth_base/teeth_base.mhclo", "Teeth")
    lashes, flash = add_asset(bm, "eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes")
    for ob, fit in ((eyes, feyes), (teeth, fteeth), (lashes, flash)):
        base, dl = fit_deltas(fit, coords, FACE_KEYS)
        C.set_co(ob, base)
        C.add_delta_attrs(ob, dl, FACE_KEYS)
    # --- boots (needed first: the kit / socks stop inside the boots) ---
    boots, insides = [], []
    for i, (name, mesh, tex, deform) in enumerate(BOOTS):
        ob, bco = build_boot(bm, coords, name, mesh, tex, deform, i)
        boots.append(ob)
        insides.append(bco)
    # --- hair (each style its own mesh) ---
    hair_objs = HS.build_all(bm, rig, coords, D, FACE_KEYS, add_asset, only=hair_only)

    # --- full-res body with morph deltas as attributes ---
    body = M.freeze_body(bm, coords)
    C.add_delta_attrs(body, {k: D[k][:C.NBODY] for k in ALL_KEYS}, ALL_KEYS)
    pristine = body.copy(); pristine.data = body.data.copy(); pristine.name = "pristine"
    bpy.context.scene.collection.objects.link(pristine)
    # body vertices inside every boot (deleted; socks end there)
    inside_all = None
    for bco in insides:
        kd = KDTree(len(bco))
        for i, c in enumerate(bco):
            kd.insert(c, i)
        kd.balance()
        ins = set()
        for vi in range(C.NBODY):
            p = Vector(coords[vi])
            if p.z > 0.16 or abs(p.x) < 0.05:
                continue
            c, idx, dist = kd.find(p)
            if p.z < c.z - 0.014:
                ins.add(vi)
        inside_all = ins if inside_all is None else (inside_all & ins)
    log("body verts inside all boots", len(inside_all))

    # --- kit (shirt short sleeves + shorts + high socks) on the full-res body ---
    body.vertex_groups.new(name="decprot")
    me = body.data
    MATS = {}
    for mn in ("skin", "kit"):
        MATS[mn] = bpy.data.materials.new(mn)
        me.materials.append(MATS[mn])
    me.uv_layers.new(name="UV2")
    me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    KB = M.KitBuilder(body, rig, inside_all, None)
    KB.seg_ext = {}
    for s in "lr":
        for bn in ("upperarm", "lowerarm", "hand", "calf", "thigh", "foot"):
            KB.seg_ext[bn + "_" + s] = M.bone_seg(rig, bn + "_" + s)
    b = bmesh.new(); b.from_mesh(me)
    dl = b.verts.layers.deform.verify()
    layers = dict(uv=b.loops.layers.uv["UVMap"], uv2=b.loops.layers.uv["UV2"],
                  col=b.loops.layers.float_color["Col"], prot=body.vertex_groups["decprot"].index)
    for f in b.faces:
        for l in f.loops:
            l[layers["col"]] = (0, 0, 0, 0); l[layers["uv2"]].uv = (0, 1)
    KB.make_cuts(b, dl)
    cls = KB.classify(b, dl)
    binside = set(v for v in b.verts if v.index < C.NBODY and v.index in inside_all)
    kstats = ckit.kit_build_geometry(KB, b, dl, cls, binside, layers, keep_sock_skin=True)
    # mouth cavity (never visible: no jaw bone)
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
    # kit vertex cloud for the armband (outside of the sleeve)
    kit_pts = np.array([v.co[:] for f in b.faces if f.material_index == 1 for v in f.verts])
    G = M.Groups(body)
    gi_head = G.idx.get("head")
    hand_bones = set(i for n, i in G.idx.items() if any(n.startswith(f) for f in M.FINGERS) or n.startswith("hand_"))
    dl = b.verts.layers.deform.verify()
    for f in b.faces:
        if f.material_index == 1:
            continue
        hw = sum(v[dl].get(gi_head, 0.0) for v in f.verts) / len(f.verts)
        hd = sum(sum(v[dl].get(i, 0.0) for i in hand_bones) for v in f.verts) / len(f.verts)
        f.material_index = 3 if hw > 0.5 else 4 if hd > 0.5 else 5
    for mn in ("_r3", "_r4", "_r5"):
        me.materials.append(bpy.data.materials.new(mn))
    b.to_mesh(me); b.free()
    me.update()
    body.parent = rig

    # --- gear from the pristine body (needs KB for cuts/params) ---
    gear = build_gear(pristine, rig, kit_pts, coords)

    # --- decimation ---
    M.triangulate(teeth); M.decimate_to(teeth, 140, symmetry=True)
    M.triangulate(lashes); M.decimate_to(lashes, 300, symmetry=True)
    target = BODY_KIT - tri_count(eyes) - tri_count(teeth) - tri_count(lashes)
    M.staged_decimate(body, target, SHARES)
    for p in body.data.polygons:
        if p.material_index >= 3:
            p.material_index = 0
    while len(body.data.materials) > 2:
        body.data.materials.pop()
    # split Body (skin) / Kit
    kit = body.copy(); kit.data = body.data.copy()
    bpy.context.scene.collection.objects.link(kit)
    for ob, keep_kit in ((body, False), (kit, True)):
        bb = bmesh.new(); bb.from_mesh(ob.data)
        bmesh.ops.delete(bb, geom=[f for f in bb.faces if (f.material_index == 1) != keep_kit], context="FACES")
        bmesh.ops.delete(bb, geom=[v for v in bb.verts if not v.link_faces], context="VERTS")
        bb.to_mesh(ob.data); bb.free()
    for a in ("Col",):
        if a in body.data.color_attributes:
            body.data.color_attributes.remove(body.data.color_attributes[a])
    if "UV2" in body.data.uv_layers:
        body.data.uv_layers.remove(body.data.uv_layers["UV2"])
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    # eyes, teeth and lashes stay separate meshes with their own materials (real eye texture
    # instead of a 70 px eye painted into the skin atlas)
    for o in (eyes, teeth, lashes):
        set_layers(o, uv2=False)
        for m in list(o.modifiers):
            o.modifiers.remove(m)
    body.data.materials.clear(); body.data.materials.append(MATS["skin"])
    for p in body.data.polygons:
        p.material_index = 0
    kit.data.materials.clear(); kit.data.materials.append(MATS["kit"])
    for p in kit.data.polygons:
        p.material_index = 0
    kit.data.color_attributes.active_color = kit.data.color_attributes["Col"]
    if "decprot" in kit.vertex_groups:
        kit.vertex_groups.remove(kit.vertex_groups["decprot"])
    body.name = body.data.name = "Body"
    kit.name = kit.data.name = "Kit"

    # --- finish all meshes ---
    made = {}
    made["Body"] = finish_mesh(body, rig, ALL_KEYS, keep_all=True)
    made["Kit"] = finish_mesh(kit, rig, ALL_KEYS)
    made["Eyes"] = finish_mesh(eyes, rig, ALL_KEYS)
    made["Teeth"] = finish_mesh(teeth, rig, ALL_KEYS)
    made["Lashes"] = finish_mesh(lashes, rig, ALL_KEYS)
    for ob in boots:
        made[ob.name] = finish_mesh(ob, rig, ALL_KEYS)
    for ob in gear:
        made[ob.name] = finish_mesh(ob, rig, ALL_KEYS)
    for ob in hair_objs:
        made[ob.name] = finish_mesh(ob, rig, ALL_KEYS, min_disp=8e-4)
    bpy.data.objects.remove(pristine, do_unlink=True)

    # --- materials ---
    mats = make_materials(MATS)
    for ob in boots + [kit] + [g for g in gear if g.name in ("Sleeves_long", "Socks_low")]:
        ob.data.materials.clear(); ob.data.materials.append(mats["kit"])
        for p in ob.data.polygons:
            p.material_index = 0
    for ob in gear:
        if ob.name.startswith("Acc_"):
            ob.data.materials.clear(); ob.data.materials.append(mats["acc"])
    for ob in hair_objs:
        ob.data.materials.clear(); ob.data.materials.append(mats["hair_" + ob.name])
    eyes.data.materials.clear(); eyes.data.materials.append(mats["eye"])
    teeth.data.materials.clear(); teeth.data.materials.append(mats["teeth"])
    lashes.data.materials.clear(); lashes.data.materials.append(mats["lash"])
    # shade smooth everywhere, sharp edges kept where the kit folds
    for ob in [body, kit, eyes, teeth, lashes] + boots + gear + hair_objs:
        M.activate(ob)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(60), keep_sharp_edges=True)
    # remove everything else
    keep = set([rig, body, kit, eyes, teeth, lashes] + boots + gear + hair_objs)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    rig.name = "Armature"; rig.data.name = "Armature"
    # visibility default: base look (custom.json "default")
    for ob in keep:
        if ob.type == "MESH":
            stats["meshes"][ob.name] = dict(tris=tri_count(ob), verts=len(ob.data.vertices),
                                            material=ob.data.materials[0].name if ob.data.materials else None,
                                            morphs=made.get(ob.name, []))
    stats["budget_example"] = dict(
        Body=tri_count(body), Kit=tri_count(kit),
        hair_max=max(tri_count(h) for h in hair_objs) if hair_objs else 0,
        boots_max=max(tri_count(bo) for bo in boots))
    stats["budget_example"]["total_worst"] = sum(stats["budget_example"].values())
    log("TRIS", stats["budget_example"])
    if keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(C.WORK, "base.blend"))
    export(rig, list(keep - {rig}))
    stats["seconds"] = round(time.time() - t0, 1)
    stats["bones"] = [bn.name for bn in rig.data.bones]
    json.dump(stats, open(os.path.join(C.WORK, "build_stats.json"), "w"), indent=1)
    log("DONE %.1fs" % (time.time() - t0))


def build_gear(src, rig, kit_pts, coords):
    """Sleeves_long, Socks_low, Acc_gloves, Acc_wristband_l/r, Acc_armband, Acc_headband, Acc_undershirt_neck."""
    P = KB.P
    out = []
    G = M.Groups(src)
    bones = [b.name for b in rig.data.bones]

    def member(f, dl):
        return KB.fmember(f, dl)

    # ---- Sleeves_long: forearm extension, over the short-sleeve cuff down to the wrist
    for s in "lr":
        pass
    t_end = 0.93
    ua_len = {s: (KB.seg_ext["upperarm_" + s][1] - KB.seg_ext["upperarm_" + s][0]).length for s in "lr"}
    t_start = {s: P["T_SLEEVE"] - (P["CUFF_W"] + 0.03) / ua_len[s] for s in "lr"}

    def sl_pred(f, dl):
        m = member(f, dl)
        if not m.startswith("arm"):
            return False
        s = m[-1]
        c = f.calc_center_median()
        return arm_t(c, s, "upperarm") > t_start[s] and arm_t(c, s, "lowerarm") < t_end

    def sl_off(v, n):
        s = "l" if v.co.x > 0 else "r"
        tu = arm_t(v.co, s, "upperarm")
        tl = arm_t(v.co, s, "lowerarm")
        hi = P["O_SLEEVE"] + 0.0065
        lo = 0.0085 - 0.002 * smoothstep(0.5, 0.95, tl)
        k = smoothstep(P["T_SLEEVE"] + 0.04 / ua_len[s], 1.05, tu) if tl < 0 else 1.0
        return hi * (1 - k) + lo * k

    cuts = []
    for s in "lr":
        ua = KB.seg_ext["upperarm_" + s]; la = KB.seg_ext["lowerarm_" + s]
        cuts.append(((lambda s: lambda f, dl: member(f, dl) == "arm_" + s)(s),
                     (lambda ua, t: lambda p: M.tparam(p, ua) - t)(ua, t_start[s])))
        cuts.append(((lambda s: lambda f, dl: member(f, dl) == "arm_" + s)(s),
                     (lambda la: lambda p: M.tparam(p, la) - t_end)(la)))

    def sl_rim(v):
        s = "l" if v.co.x > 0 else "r"
        return P["O_SLEEVE"] - 0.003 if arm_t(v.co, s, "lowerarm") < 0.3 else 0.001
    sl = shell(src, "Sleeves_long", cuts, sl_pred, sl_off, rim_top=sl_rim)
    M.triangulate(sl); M.decimate_to(sl, 360, symmetry=True)
    set_layers(sl, COL_SHIRT)
    uv2_sleeve(sl)
    out.append(sl)

    # ---- Socks_low: scrunched socks from inside the boot to ~40 % up the calf
    T_LOW = 0.62
    calf_len = {s: (KB.seg_ext["calf_" + s][1] - KB.seg_ext["calf_" + s][0]).length for s in "lr"}
    inside = KB.boot_del

    def so_pred(f, dl):
        m = member(f, dl)
        if not m.startswith("leg"):
            return False
        if all(v.index in inside for v in f.verts if v.index < C.NBODY):
            return False
        c = f.calc_center_median()
        return M.tparam(c, KB.seg_ext["calf_" + m[-1]]) > T_LOW

    def so_off(v, n):
        s = "l" if v.co.x > 0 else "r"
        t = M.tparam(v.co, KB.seg_ext["calf_" + s])
        top = 1 - smoothstep(0.0, 0.05 / calf_len[s], t - T_LOW)
        ang = math.atan2(v.co.y, v.co.x - KB.seg_ext["calf_" + s][0].x)
        ripple = 0.5 + 0.5 * math.sin(ang * 7 + t * 60)
        return 0.0042 + top * (0.0035 + 0.0025 * ripple)
    cuts = []
    for s in "lr":
        ca = KB.seg_ext["calf_" + s]
        cuts.append(((lambda s: lambda f, dl: member(f, dl) == "leg_" + s)(s),
                     (lambda ca: lambda p: M.tparam(p, ca) - T_LOW)(ca)))
    so = shell(src, "Socks_low", cuts, so_pred, so_off, rim_in=0.0008)
    # drop the faces inside every boot that the shell rim may have created at the bottom
    M.triangulate(so); M.decimate_to(so, 380, symmetry=True)
    set_layers(so, COL_SOCKS)
    out.append(so)

    # ---- Acc_gloves (goalkeeper): hands + wrist strap
    T_CUFF = 0.78

    def gl_pred(f, dl):
        m = member(f, dl)
        if not m.startswith("arm"):
            return False
        c = f.calc_center_median()
        return arm_t(c, m[-1], "lowerarm") > T_CUFF

    def gl_off(v, n):
        s = "l" if v.co.x > 0 else "r"
        tl = arm_t(v.co, s, "lowerarm")
        palm = max(0.0, n.dot(Vector((-1.0 if s == "l" else 1.0, 0.0, 0.0))))
        o = 0.0034 + 0.0022 * palm
        strap = smoothstep(T_CUFF, T_CUFF + 0.03, tl) * (1 - smoothstep(0.96, 1.02, tl))
        o = o + 0.0045 * strap * (1 - smoothstep(1.0, 1.06, tl)) + 0.003 * (1 - smoothstep(0.98, 1.08, tl))
        return o
    cuts = []
    for s in "lr":
        la = KB.seg_ext["lowerarm_" + s]
        cuts.append(((lambda s: lambda f, dl: member(f, dl) == "arm_" + s)(s),
                     (lambda la: lambda p: M.tparam(p, la) - T_CUFF)(la)))
    global DLAYER
    DLAYER = None
    gl = shell(src, "Acc_gloves", cuts, gl_pred, gl_off, rim_in=0.0012, smooth_iters=2)
    M.triangulate(gl); M.decimate_to(gl, 1100, symmetry=True)
    glove_uv_and_texture(gl)
    out.append(gl)

    # ---- rings
    groups = [vg.name for vg in src.vertex_groups if vg.name in bones]
    sco = C.get_co(src)
    W = body_weight_matrix(src, groups)
    SD = read_delta_attrs(src, ALL_KEYS)
    head_w = W[:, groups.index("head")]

    def finish_ring(ob, rect_name):
        knn_transfer(ob, sco, W, SD, groups, ALL_KEYS)
        M.triangulate(ob)
        return ob

    for s in "lr":
        la = KB.seg_ext["lowerarm_" + s]
        L = (la[1] - la[0]).length
        axis = (la[1] - la[0]).normalized()
        # stable band: a synthetic wrist-radius ring (the body has too few vertices at t=0.74
        # for the old implicit-surface fit once the forearm is more muscular).
        ctr = la[0] + axis * (0.84 * L)
        e1 = axis.orthogonal().normalized(); e2 = axis.cross(e1).normalized()
        a = np.linspace(0, 2 * math.pi, 48, endpoint=False)
        ref = np.array([ctr + (e1 * math.cos(t) + e2 * math.sin(t)) * 0.040 for t in a])
        ob = ring("Acc_wristband_" + s, ref, la[0], la[1] - la[0], L, 0.79, 0.91, 2, 12, 0.0042, ACC_RECTS["band"])
        out.append(finish_ring(ob, "band"))
    ua = KB.seg_ext["upperarm_l"]
    L = (ua[1] - ua[0]).length
    refk = kit_pts[(kit_pts[:, 0] > 0.12)]
    rel = refk - np.array(ua[0]); tt = rel @ np.array((ua[1] - ua[0]).normalized()) / L
    rad = np.linalg.norm(rel - np.outer(tt * L, np.array((ua[1] - ua[0]).normalized())), axis=1)
    refk = refk[(tt > 0.1) & (tt < 0.45) & (rad < 0.15)]
    ob = ring("Acc_armband", refk, ua[0], ua[1] - ua[0], L, 0.20, 0.33, 2, 14, 0.0032, ACC_RECTS["armband"])
    out.append(finish_ring(ob, "armband"))
    # headband: axis tilted back so the band sits low on the forehead and higher at the back
    hb = rig.data.bones["head"]
    hpos = Vector(hb.head_local)
    up = Matrix.Rotation(math.radians(-16), 3, "X") @ Vector((0, 0, 1))
    refh = sco[(head_w > 0.6) & (sco[:, 2] > hpos.z + 0.03)]
    ob = ring("Acc_headband", refh, hpos, up, 0.1, 0.60, 0.86, 2, 22, 0.0040, ACC_RECTS["band"])
    out.append(finish_ring(ob, "band"))
    # undershirt neck: band from inside the crew neck up the neck
    nb = rig.data.bones["neck_01"]
    n0, n1 = Vector(nb.head_local), Vector(nb.tail_local)
    nw = W[:, groups.index("neck_01")]
    nax = (n1 - n0).normalized()
    reln = sco - np.array(n0)
    radn = np.linalg.norm(reln - np.outer(reln @ np.array(nax), np.array(nax)), axis=1)
    refn = sco[(head_w < 0.6) & (radn < 0.11) & (sco[:, 2] > n0.z - 0.05)]
    ob = ring("Acc_undershirt_neck", refn, n0, n1 - n0, (n1 - n0).length, -0.12, 0.28, 3, 24, 0.0042, ACC_RECTS["neck"])
    out.append(finish_ring(ob, "neck"))
    for ob in out:
        log("gear", ob.name, "tris", tri_count(ob))
    return out


DLAYER = None


def uv2_sleeve(ob):
    """UV2 for Sleeves_long: same front/back projection as the shirt sleeves (x clamped to the side)."""
    info = getattr(KB, "uv2_info", None)
    me = ob.data
    uvl = me.uv_layers["UV2"]
    co = C.get_co(ob)
    if not info:
        return
    hw, zb, zf, zbk = info["half_w"], info["z_bottom"], info["zc_front"], info["zc_back"]
    for p in me.polygons:
        front = p.normal.y < 0
        for li, vi in zip(p.loop_indices, p.vertices):
            x, z = co[vi][0], co[vi][2]
            if front:
                u = max(-1.0, min(1.0, x / hw)); zc = zf
            else:
                u = max(-1.0, min(1.0, -x / hw)) + 2.0; zc = zbk
            y = (z - zb) / (zc - zb)
            uvl.data[li].uv = (u, 1.0 - y)


def glove_uv_and_texture(ob):
    """Glove UVs: body hand layout remapped into the glove rect of acc.png; texture = palm grip (dark),
    back (light), wrist strap (dark band), drawn per vertex by the rasterizer."""
    me = ob.data
    uvs = C.loop_uvs(me, "UVMap")
    u0, v0, u1, v1 = ACC_RECTS["glove"]
    lo = uvs.min(axis=0); hi = uvs.max(axis=0)
    new = np.empty_like(uvs)
    new[:, 0] = u0 + 0.01 + (uvs[:, 0] - lo[0]) / (hi[0] - lo[0]) * (u1 - u0 - 0.02)
    new[:, 1] = v0 + 0.01 + (uvs[:, 1] - lo[1]) / (hi[1] - lo[1]) * (v1 - v0 - 0.02)
    me.uv_layers["UVMap"].data.foreach_set("uv", new.astype(np.float32).reshape(-1))
    co = C.get_co(ob)
    nrm = np.zeros(len(co) * 3); me.vertices.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
    val = np.zeros(len(co))
    for i, (c, n) in enumerate(zip(co, nrm)):
        s = "l" if c[0] > 0 else "r"
        tl = M.tparam(Vector(c), KB.seg_ext["lowerarm_" + s])
        palm = smoothstep(0.15, 0.55, n[0] * (-1 if s == "l" else 1))
        strap = smoothstep(0.80, 0.83, tl) * (1 - smoothstep(0.93, 0.96, tl))
        edge = smoothstep(0.95, 0.97, tl) * (1 - smoothstep(0.99, 1.01, tl))
        g = 0.86 - 0.50 * palm
        g = g * (1 - strap) + 0.22 * strap
        g = g * (1 - edge) + 0.95 * edge
        val[i] = g
    tris = C.mesh_loop_tris(me)
    lv = C.loop_verts(me)
    acc_p = os.path.join(C.WORK, "acc_base.png")
    acc = C.load_image_np(acc_p)[..., :3] if os.path.exists(acc_p) else np.full((512, 512, 3), 0.82)
    n = acc.shape[0]
    img, cov = C.raster(new[tris], val[lv[tris]][..., None].astype(np.float32), n)
    sub = cov > 0
    g = img[..., 0]
    # dilate glove values a few texels for mip padding inside the glove rect
    for _ in range(4):
        nb = [np.roll(g, s_, a) for a in (0, 1) for s_ in (1, -1)]
        nc = [np.roll(cov, s_, a) for a in (0, 1) for s_ in (1, -1)]
        num = sum(x * c for x, c in zip(nb, nc)); den = sum(nc)
        grow = (cov == 0) & (den > 0)
        g = np.where(grow, num / np.maximum(den, 1e-6), g); cov = np.where(grow, 1.0, cov)
    r0, r1 = int(v0 * n), int(v1 * n)
    c0, c1 = int(u0 * n), int(u1 * n)
    region = np.zeros((n, n), bool); region[r0:r1, c0:c1] = True
    noise = np.random.default_rng(3).random((n, n)) * 0.04
    fill = np.where(cov > 0, g, 0.82) + noise
    acc[region] = np.repeat(np.clip(fill, 0, 1)[..., None], 3, axis=2)[region]
    C.write_png(os.path.join(C.OUT, "acc.png"), acc, "RGB")


def _prep_tex(src, out, size=512, alpha=False, catchlight=False):
    """Resize an MPFB texture into the custom asset folder (keeps alpha only when asked)."""
    a = C.load_image_np(src)
    a = C.resize_np(a, size)
    if catchlight:
        rgb = a[..., :3].copy()
        yy, xx = np.mgrid[0:size, 0:size]
        for cx, cy in ((147.0, 366.5), (360.0, 155.5)):
            d2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (7.5 ** 2)
            k = np.clip(1.0 - d2, 0, 1) ** 2
            rgb = rgb * (1.0 - k[..., None]) + np.array([0.97, 0.98, 1.0])[None, None, :] * k[..., None]
        a[..., :3] = np.clip(rgb, 0, 1)
    if alpha:
        C.write_png(out, a[..., :4], "RGBA")
    else:
        C.write_png(out, a[..., :3], "RGB")
    return out


def make_materials(MATS):
    def tex_mat(m, path, rough, spec=0.35, alpha=False, normal=None, cull=True, alpha_thr=0.4):
        nt = m.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bs.outputs[0], out.inputs[0])
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(path, check_existing=True)
        nt.links.new(t.outputs[0], bs.inputs["Base Color"])
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Specular IOR Level"].default_value = spec
        if alpha:
            r = nt.nodes.new("ShaderNodeMath"); r.operation = "ROUND"
            nt.links.new(t.outputs[1], r.inputs[0]); nt.links.new(r.outputs[0], bs.inputs["Alpha"])
            m.blend_method = "CLIP"
            m.surface_render_method = "DITHERED"
            m.alpha_threshold = alpha_thr
        else:
            m.blend_method = "OPAQUE"
        if normal:
            tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = bpy.data.images.load(normal, check_existing=True)
            tn.image.colorspace_settings.name = "Non-Color"
            nm = nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 1.0
            nt.links.new(tn.outputs[0], nm.inputs["Color"]); nt.links.new(nm.outputs[0], bs.inputs["Normal"])
        m.use_backface_culling = cull
        return m
    eye_tex = _prep_tex(os.path.join(C.ASSETS, "eyes/materials/brown_eye.png"), os.path.join(C.OUT, "eye.png"), 512,
                         catchlight=True)
    teeth_tex = _prep_tex(os.path.join(C.ASSETS, "teeth/teeth_base/teeth.png"), os.path.join(C.OUT, "teeth.png"), 512, alpha=True)
    lash_tex = _prep_tex(os.path.join(C.ASSETS, "eyelashes/eyelashes01/eyelashes01.png"), os.path.join(C.OUT, "lash.png"), 512, alpha=True)
    mats = {}
    mats["skin"] = tex_mat(MATS["skin"], os.path.join(C.OUT, "skin_mid.jpg"), 0.52,
                           normal=os.path.join(C.OUT, "skin_normal.jpg"))
    mats["kit"] = tex_mat(MATS["kit"], os.path.join(C.OUT, "kit.png"), 0.72, 0.3)
    mats["acc"] = tex_mat(bpy.data.materials.new("acc"), os.path.join(C.OUT, "acc.png"), 0.8, 0.3)
    mats["eye"] = tex_mat(bpy.data.materials.new("eye"), eye_tex, 0.16, 0.45)
    mats["teeth"] = tex_mat(bpy.data.materials.new("teeth"), teeth_tex, 0.24, 0.45, alpha=True, alpha_thr=0.35)
    mats["lash"] = tex_mat(bpy.data.materials.new("lash"), lash_tex, 0.55, 0.35, alpha=True, cull=False, alpha_thr=0.28)
    for hid in HS.HAIR:
        p = os.path.join(C.OUT, hid + ".png")
        if os.path.exists(p):
            mats["hair_" + hid] = tex_mat(bpy.data.materials.new("hair_" + hid), p, 0.36, 0.55, alpha=True, cull=False, alpha_thr=0.42)
    return mats


def export(rig, meshes):
    path = os.path.join(C.OUT, "base.glb")
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for o in meshes:
        o.select_set(True)
        o.hide_set(False); o.hide_render = False
    bpy.context.view_layer.objects.active = rig
    tmp = path + ".tmp.glb"
    bpy.ops.export_scene.gltf(
        filepath=tmp, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_skins=True,
        export_all_influences=False, export_def_bones=False, export_animations=False, export_morph=True,
        export_morph_normal=True, export_morph_tangent=False, export_cameras=False, export_lights=False,
        export_image_format="AUTO", export_jpeg_quality=92, export_extras=False)
    rename_glb_materials(tmp)
    os.replace(tmp, path)
    log("exported", path, "%.1f MB" % (os.path.getsize(path) / 1e6))


def rename_glb_materials(path):
    """All hair_* materials -> 'hair' (one name for every hairstyle, each keeps its own texture)."""
    import struct
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack("<III", data[:12])
    clen, ctype = struct.unpack("<II", data[12:20])
    js = json.loads(data[20:20 + clen])
    rest = data[20 + clen:]
    for m in js.get("materials", []):
        if m.get("name", "").startswith("hair_"):
            m["name"] = "hair"
    for im in js.get("images", []):
        pass
    nj = json.dumps(js, separators=(",", ":")).encode()
    nj += b" " * ((4 - len(nj) % 4) % 4)
    out = struct.pack("<III", magic, ver, 12 + 8 + len(nj) + len(rest)) + struct.pack("<II", len(nj), ctype) + nj + rest
    open(path, "wb").write(out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in argv:
        if a.startswith("--hair="):
            only = a.split("=", 1)[1].split(",")
    run(keep_blend="--keep-blend" in argv, hair_only=only)
