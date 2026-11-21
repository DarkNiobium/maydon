"""Hairstyles for the customizable footballer: MakeHuman hair cards (CC0) reshaped per style, plus two
self-made shell styles (buzz cut, cornrow braids) laid on the scalp.

Every style follows the head morphs: card vertices are refitted with the MHCLO binding for each morph
(base + delta), shells copy the scalp deltas. Textures are neutral light grey (tinted in the shader).
"""
import bpy, bmesh, os, math
import numpy as np
from mathutils import Vector
import clib as C
from clib import log, M, smoothstep

GREY = (0.35, 0.35, 0.35)
EAR_Z, TOP_Z = 1.6685, 1.8007          # base landmarks (ear centre, crown)
HEAD_C = np.array([0.0, -0.035, 1.705])

# id: spec. scalp = recommended skin-shader scalp mask (custom.json)
HAIR = {
    "hair_buzz": dict(kind="shell", tex="buzz", offset=0.0011, tris=1100, scalp=("scalp_full", 0.92),
                      label="buzz cut (scalp shell)"),
    "hair_short_fade": dict(asset="short01", scale=0.92, taper=(0.28, 0.80, 0.12), tris=2400, alpha_boost=1.25, min_off=0.0024,
                            scalp=("scalp_fade", 0.78), label="short textured top, skin fade"),
    "hair_crop": dict(asset="short02", scale=0.66, taper=(0.20, 0.70, 0.45), tris=2400, min_off=0.0024,
                      scalp=("scalp_full", 0.6), label="textured crop with a short fringe"),
    "hair_side_part": dict(asset="short04", scale=1.0, tris=1100, scalp=("scalp_full", 0.6),
                           label="classic side part"),
    "hair_slick_back": dict(asset="ponytail01", tail="cut", scale=0.97, tris=2400, scalp=("scalp_full", 0.55),
                            label="slicked back"),
    "hair_quiff": dict(asset="short02", scale=0.78, taper=(0.25, 0.75, 0.35), min_off=0.0026,
                       lift=dict(up=0.024, fwd=0.008), tris=2400, scalp=("scalp_fade", 0.75), label="quiff"),
    "hair_curly": dict(asset="afro01", scale=0.58, tris=2200, scalp=("scalp_full", 0.7), label="short curly"),
    "hair_afro": dict(asset="afro01", scale=1.28, tris=2200, scalp=("scalp_full", 0.7), label="afro"),
    "_hair_mohawk_disabled": dict(asset="short02", strip=0.034, lat_taper=(0.014, 0.032, 0.3), scale=1.25,
                        lift=dict(up=0.012, fwd=0.0), tris=1800,
                        scalp=("scalp_full", 0.35), label="mohawk (shaved sides)"),
    "hair_man_bun": dict(asset="ponytail01", tail="bun", scale=0.97, tris=2450, scalp=("scalp_full", 0.55),
                         label="man bun"),
    "hair_long": dict(asset="long01", compress=(1.66, 0.24), tris=2450, scalp=("scalp_full", 0.55),
                      label="long, to the neck"),
    "hair_braids": dict(kind="shell", tex="braids", offset=0.0032, tris=1500, scalp=("scalp_full", 0.7),
                        label="cornrows (scalp shell)"),
}


def hz_of(p):
    return (p[..., 2] - EAR_Z) / (TOP_Z - EAR_Z)


# ---------------------------------------------------------------------------------------------
# card styles
# ---------------------------------------------------------------------------------------------

def card_style(hid, spec, bm, coords, D, keys, add_asset):
    rel = "hair/%s/%s.mhclo" % (spec["asset"], spec["asset"])
    ob, fit = add_asset(bm, rel, "Hair")
    A0 = fit.anchor(coords)
    F0 = fit(coords)
    n = len(A0)
    off0 = np.linalg.norm(F0 - A0, axis=1)
    hz = hz_of(A0)
    k = np.full(n, spec.get("scale", 1.0))
    if spec.get("taper"):
        lo, hi, kmin = spec["taper"]
        t = smoothstep(lo, hi, hz)
        k = k * (kmin + (1 - kmin) * t)
    if spec.get("lat_taper"):
        lo, hi, kmin = spec["lat_taper"]
        k = k * (kmin + (1 - kmin) * (1 - smoothstep(lo, hi, np.abs(A0[:, 0]))))
    lift = np.zeros((n, 3))
    if spec.get("lift"):
        L = spec["lift"]
        if spec.get("strip"):
            w = smoothstep(0.25, 0.75, hz) * (1 - smoothstep(0.008, 0.03, np.abs(A0[:, 0])))
        else:
            w = smoothstep(-0.07, -0.13, A0[:, 1]) * smoothstep(0.45, 0.85, hz)
        lift[:, 2] = L["up"] * w
        lift[:, 1] = -L["fwd"] * w
    tail = np.zeros(n, bool)
    if spec.get("tail"):
        # the ponytail = mesh islands hanging down the back (lowest point well below the nape)
        bb = bmesh.new(); bb.from_mesh(ob.data); bb.verts.ensure_lookup_table()
        seen = np.zeros(n, bool)
        for v0 in bb.verts:
            if seen[v0.index]:
                continue
            stack = [v0]; seen[v0.index] = True; comp = []
            while stack:
                v = stack.pop(); comp.append(v.index)
                for e in v.link_edges:
                    u = e.other_vert(v)
                    if not seen[u.index]:
                        seen[u.index] = True; stack.append(u)
            comp = np.array(comp)
            if F0[comp, 2].min() < 1.57 and F0[comp, 1].mean() > 0.03:
                tail[comp] = True
        bb.free()
        log("   tail verts", int(tail.sum()), "of", n)
    comp = spec.get("compress")

    min_off = spec.get("min_off", 0.0042)    # keeps cards off the (decimated) scalp: no skin poking through

    def transform(f, co):
        A = f.anchor(co); F = f(co)
        v = F - A
        ln = np.linalg.norm(v, axis=1)
        newlen = np.maximum(ln * k, np.minimum(min_off, ln + 0.002))
        p = A + v * (newlen / np.maximum(ln, 1e-6))[:, None] + lift
        if comp:
            z0, s = comp
            below = p[:, 2] < z0
            dz = z0 - p[below, 2]
            p[below, 2] = z0 - dz * s
            # pull the lower strands in towards the neck (they were lying on the shoulders)
            t = np.clip(dz / 0.6, 0, 1)
            p[below, 0] *= 1 - 0.35 * t
            p[below, 1] = p[below, 1] * (1 - 0.25 * t) + 0.02 * t
        return p
    base = transform(fit, coords)
    deltas = {kk: transform(fit, coords + D[kk]) - base for kk in keys}
    # bun: remap the tail into a rolled bun at the knot, it moves rigidly with the knot
    if spec.get("tail") == "bun":
        tp = base[tail]
        knot = tp[tp[:, 2] > np.percentile(tp[:, 2], 92)].mean(axis=0)
        zmin = tp[:, 2].min()
        s_ = np.clip((knot[2] - tp[:, 2]) / (knot[2] - zmin), 0, 1)
        hw = max(np.percentile(np.abs(tp[:, 0] - knot[0]), 95), 0.01)
        lat = np.clip((tp[:, 0] - knot[0]) / hw, -1, 1)
        dep = tp[:, 1] - np.median(tp[:, 1])
        # wrap the tail sheet around a ball (the bun) sitting on the knot
        theta = lat * math.pi * 0.95
        phi = 0.15 + s_ * (math.pi - 0.3)
        r = 0.027 + np.clip(dep, -0.01, 0.01) * 0.4
        cen = knot + np.array([0.0, 0.022, 0.024])
        e_up = np.array([0.0, -0.35, 0.94]); e_up /= np.linalg.norm(e_up)
        e_x = np.array([1.0, 0.0, 0.0]); e_b = np.cross(e_x, e_up)
        newp = cen + r[:, None] * (np.sin(phi)[:, None] * (np.cos(theta)[:, None] * (-e_b) + np.sin(theta)[:, None] * e_x)
                                   + np.cos(phi)[:, None] * e_up)
        base[tail] = newp
        kn_idx = np.nonzero(~tail & (np.linalg.norm(base - knot, axis=1) < 0.04))[0]
        for kk in keys:
            deltas[kk][tail] = deltas[kk][kn_idx].mean(axis=0) if len(kn_idx) else 0.0
    C.set_co(ob, base)
    C.add_delta_attrs(ob, deltas, keys)
    # topology: cuts
    b = bmesh.new(); b.from_mesh(ob.data)
    b.verts.ensure_lookup_table()
    kill = []
    for f in b.faces:
        ids = [v.index for v in f.verts]
        c = base[ids].mean(axis=0)
        a = A0[ids].mean(axis=0)
        h = hz_of(a)
        if spec.get("tail") == "cut" and tail[ids].any():
            kill.append(f); continue
        if spec.get("cut_hz") is not None and h < spec["cut_hz"] and a[1] > -0.06:
            kill.append(f); continue
        if spec.get("strip") and (abs(a[0]) > spec["strip"] or h < 0.15):
            kill.append(f); continue
    bmesh.ops.delete(b, geom=kill, context="FACES")
    b.to_mesh(ob.data); b.free()
    M.triangulate(ob)
    M.decimate_to(ob, spec["tris"], symmetry=False)
    # texture
    hd = os.path.join(C.ASSETS, "hair", spec["asset"])
    png = [f for f in os.listdir(hd) if f.endswith("diffuse.png")][0]
    tex = os.path.join(C.OUT, hid + ".png")
    M.process_hair_texture(os.path.join(hd, png), GREY, tex, size=1024, alpha_boost=spec.get("alpha_boost", 1.20))
    keep_uv(ob)
    return ob


def keep_uv(ob):
    me = ob.data
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[1])
    me.uv_layers[0].name = "UVMap"


# ---------------------------------------------------------------------------------------------
# shell styles (buzz, braids)
# ---------------------------------------------------------------------------------------------

def shell_style(hid, spec, bm, coords, D, keys):
    body = M.freeze_body(bm, coords)
    C.add_delta_attrs(body, {k: D[k][:C.NBODY] for k in keys}, keys)
    scalp = C.vertex_group_weights(body, "scalp", C.NBODY)
    ears = C.vertex_group_weights(body, "ears", C.NBODY)
    adj = M.mesh_adjacency(body.data)
    adj = [[j for j in nb if j < C.NBODY] for nb in adj[:C.NBODY]]
    sc = M.diffuse(scalp, adj, 4)
    b = bmesh.new(); b.from_mesh(body.data)
    b.verts.ensure_lookup_table()
    b.normal_update()
    nrm = {v: v.normal.copy() for v in b.verts}
    keepf = [f for f in b.faces if max(sc[v.index] for v in f.verts) > 0.06 and max(ears[v.index] for v in f.verts) < 0.3]
    ks = set(keepf)
    bmesh.ops.delete(b, geom=[f for f in b.faces if f not in ks], context="FACES")
    for v in b.verts:
        v.co = v.co + nrm[v] * spec["offset"]
    b.to_mesh(body.data); b.free()
    body.data.update()
    ob = body
    ob.name = ob.data.name = hid
    # per-texel texture from 3D position: raster the shell in its own UV (scalp part of the layout)
    me = ob.data
    luv = C.loop_uvs(me, "UVMap")
    lo = luv.min(axis=0) - 0.004; hi = luv.max(axis=0) + 0.004
    new = (luv - lo) / (hi - lo)
    me.uv_layers["UVMap"].data.foreach_set("uv", new.astype(np.float32).reshape(-1))
    co = C.get_co(ob)
    vsc = np.array([sc[i] if i < C.NBODY else 0.0 for i in range(len(co))])
    # vertices of the shell keep their body index order? no: deleted faces -> re-read scalp via KD
    from mathutils.kdtree import KDTree
    kd = KDTree(C.NBODY)
    for i in range(C.NBODY):
        kd.insert(coords[i], i)
    kd.balance()
    vsc = np.array([sc[kd.find(Vector(c))[1]] for c in co])
    tris = C.mesh_loop_tris(me)
    lv = C.loop_verts(me)
    vals = np.concatenate([co, vsc[:, None]], axis=1).astype(np.float32)
    N = 512
    img, cov = C.raster(new[tris], vals[lv[tris]], N)
    P = img[..., :3]; s = img[..., 3]
    jit = (C.fbm(P, 380.0, 3, seed=5) - 0.5) * 0.22
    edge = smoothstep(0.22, 0.62, s + jit) * (cov > 0)
    if spec["tex"] == "buzz":
        rng = np.random.default_rng(71)
        g = rng.random((N, N))
        g = 0.65 * g + 0.35 * C.vnoise(P, 900.0, seed=73)
        dens = 0.55 * edge
        alpha = (g > 1 - dens).astype(np.float64)
        lum = 0.70 + 0.2 * C.vnoise(P, 1200.0, seed=75)
    else:
        # cornrows running from the forehead to the nape: rows = longitude around the axis between
        # a pole under the front hairline and a pole at the nape
        Fp = np.array([0.0, -0.118, 1.725]); Bp = np.array([0.0, 0.080, 1.590])
        ax = (Bp - Fp) / np.linalg.norm(Bp - Fp)
        e1 = np.array([1.0, 0.0, 0.0]); e2 = np.cross(ax, e1)
        rel = P - (Fp + Bp) / 2
        along = rel @ ax
        rad = rel - along[..., None] * ax
        phi = np.arctan2(rad @ e1, rad @ e2)
        rows = phi / 0.17
        fr = rows - np.floor(rows)
        d = np.abs(fr - 0.5) * 2
        side = np.where(fr < 0.5, 1.0, -1.0)
        tw = (along / 0.0095 + side * d * 0.45) % 1.0
        plait = 0.5 + 0.5 * np.cos(tw * 2 * math.pi)
        strand = C.vnoise(P, 2600.0, seed=77)
        lum = (0.40 + 0.50 * (1 - d ** 2)) * (0.60 + 0.40 * plait) * (0.86 + 0.14 * strand)
        alpha = ((d < 0.86 - 0.08 * (strand - 0.5)) & (edge > 0.35)).astype(np.float64)
        lum = np.clip(lum + 0.05, 0, 1)
    rgb = np.clip(np.dstack([lum, lum, lum]) * np.array(GREY) / 0.8, 0, 1)
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    filled = M.dilate(np.concatenate([rgb, (alpha > 0.5)[..., None].astype(np.float64)], axis=2))
    out[..., :3] = np.where((alpha > 0.5)[..., None], rgb, filled[..., :3])
    C.write_png(os.path.join(C.OUT, hid + ".png"), out, "RGBA")
    # faces fully outside the hair (alpha 0 everywhere) are dropped, then budget
    M.triangulate(ob)
    M.decimate_to(ob, spec["tris"], symmetry=True)
    for vg in list(ob.vertex_groups):
        pass
    return ob


def build_all(bm, rig, coords, D, keys, add_asset, only=None):
    out = []
    for hid, spec in HAIR.items():
        if hid.startswith("_"):
            continue
        if only and hid not in only:
            continue
        if spec.get("kind") == "shell":
            ob = shell_style(hid, spec, bm, coords, D, keys)
        else:
            ob = card_style(hid, spec, bm, coords, D, keys, add_asset)
        ob.name = ob.data.name = hid
        log("hair", hid, "tris", sum(len(p.vertices) - 2 for p in ob.data.polygons))
        out.append(ob)
    return out
