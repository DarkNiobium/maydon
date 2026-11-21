"""Stage 2: textures in the MakeHuman skin UV layout (+ kit / acc / procedural hair textures).

    nice blender -b --python ~/maydon/blender/custom/stage_tex.py [-- --force] [--only=masks,skin,...]

Outputs (assets/chars/custom/): skin_light.jpg, skin_mid.jpg, skin_dark.jpg, skin_normal.jpg,
beard_*.png, brows_*.png, iris_mask.png, scalp_full.png, scalp_fade.png, kit.png, acc.png,
hair_buzz.png, hair_braids.png. Intermediates in work/ (posmap, AO, landmarks).
"""
import bpy, sys, os, math, json, time
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clib as C
from clib import log, M, smoothstep

S = 2048            # output size (face gets 2x the old texel density)
SS = 2048           # working size for masks
EYE_RECT, TEETH_RECT = M.EYE_RECT, M.TEETH_RECT
# 4 boot texture rects inside the head island of the kit texture (no kit-material mesh uses it)
BOOT_RECTS = [(0.648, 0.175, 0.800, 0.335), (0.806, 0.175, 0.958, 0.335),
              (0.648, 0.345, 0.800, 0.505), (0.806, 0.345, 0.958, 0.505)]
SKINS = {
    "light": dict(tex=["young_caucasian_male/young_lightskinned_male_diffuse.png",
                       "young_caucasian_male2/young_lightskinned_male_diffuse2.png"], blend=0.35,
                  tone=(1.0, 0.97, 0.94), sat=0.92, val=1.0),
    "mid": dict(tex=["young_asian_male/young_lightskinned_male_diffuse3.png",
                     "young_caucasian_male2/young_lightskinned_male_diffuse2.png"], blend=0.4,
                tone=(0.95, 0.88, 0.76), sat=0.95, val=0.93),
    "dark": dict(tex=["young_african_male/young_darkskinned_male_diffuse.png"], blend=0.0,
                 tone=(1.0, 0.98, 0.96), sat=1.0, val=1.0),
}
BROWS = {"thin": "eyebrow005", "normal": "eyebrow012", "thick": "eyebrow009"}
FORCE = False
ONLY = None


def want(name, outs):
    if ONLY and name not in ONLY:
        return False
    if FORCE:
        return True
    return not all(os.path.exists(o) for o in outs)


# ---------------------------------------------------------------------------------------------
# base: full-res body, posmap, AO, landmarks
# ---------------------------------------------------------------------------------------------

def base_body():
    bm, rig = C.create_human()
    coords = C.all_coords(bm)
    body = M.freeze_body(bm, coords)
    return bm, rig, body, coords


def compute_posmap(body, size):
    me = body.data
    tris = C.mesh_loop_tris(me)
    luv = C.loop_uvs(me, "UVMap" if "UVMap" in me.uv_layers else None)
    lv = C.loop_verts(me)
    co = C.get_co(body)
    me.calc_normals() if hasattr(me, "calc_normals") else None
    nrm = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("normal", nrm); nrm = nrm.reshape(-1, 3)
    groups = {}
    for g in ("head", "neck_01", "scalp", "lips", "ears"):
        groups[g] = C.vertex_group_weights(body, g, len(me.vertices))
    vals = np.concatenate([co, nrm] + [groups[g][:, None] for g in ("head", "neck_01", "scalp", "lips", "ears")], axis=1)
    uv_tri = luv[tris]
    val_tri = vals[lv[tris]]
    t0 = time.time()
    img, cov = C.raster(uv_tri, val_tri.astype(np.float32), size)
    log("posmap %d raster %.1fs" % (size, time.time() - t0))
    return img, cov


def landmarks(body, coords):
    gj = C.joint_groups()
    co = coords[:C.NBODY]
    names = [vg.name for vg in body.vertex_groups]
    me = body.data
    W = {g: C.vertex_group_weights(body, g, C.NBODY) for g in ("head", "neck_01", "lips", "ears", "scalp")}
    eye_l = coords[C.group_vertices(gj, "joint-l-eye")].mean(axis=0)
    eye_r = coords[C.group_vertices(gj, "joint-r-eye")].mean(axis=0)
    lips = co[W["lips"] > 0.5]
    ears = co[W["ears"] > 0.5]
    ear_l = ears[ears[:, 0] > 0].mean(axis=0)
    mouth = np.array([0.0, lips[:, 1].mean(), lips[:, 2].mean()])
    mcx = float(np.abs(lips[:, 0]).max())
    sel = (np.abs(co[:, 0]) < 0.008) & (co[:, 2] < eye_l[2]) & (co[:, 2] > mouth[2])
    nose_tip = co[sel][np.argmin(co[sel][:, 1])]
    mid = co[(np.abs(co[:, 0]) < 0.006) & (W["head"] > 0.3)]
    best = None
    zz = lips[:, 2].max()
    while zz < nose_tip[2]:
        band = mid[(mid[:, 2] >= zz) & (mid[:, 2] < zz + 0.0015)]
        if len(band):
            fy = band[:, 1].min()
            if best is None or fy > best[0]:
                best = (fy, zz)
        zz += 0.0015
    nose_base_z = best[1] if best else nose_tip[2] - 0.015
    selc = (np.abs(co[:, 0]) < 0.006) & (co[:, 2] < lips[:, 2].min() - 0.01) & (co[:, 2] > lips[:, 2].min() - 0.07) & (W["head"] > 0.3)
    cc = co[selc]
    chin = cc[np.argmin(cc[:, 1])]
    z_top = float(co[:, 2].max())
    L = dict(eye_l=eye_l, eye_r=eye_r, ear=ear_l, mouth=mouth, mcx=mcx, nose_tip=nose_tip, nose_base_z=nose_base_z,
             chin=chin, z_top=z_top, lip_top=float(lips[:, 2].max()), lip_bot=float(lips[:, 2].min()),
             ear_zmin=float(ears[:, 2].min()), ear_zmax=float(ears[:, 2].max()))
    log("landmarks", {k: (np.round(v, 4).tolist() if isinstance(v, np.ndarray) else round(v, 4)) for k, v in L.items()})
    return L


def load_base(force=False):
    pth = os.path.join(C.WORK, "texbase.npz")
    if os.path.exists(pth) and not force:
        d = np.load(pth, allow_pickle=True)
        return d["pos"], d["cov"], d["ao"], d["L"].item()
    bm, rig, body, coords = base_body()
    pos, cov = compute_posmap(body, SS)
    ao = M.bake_ao(body, size=S, samples=64, distance=0.12)
    L = landmarks(body, coords)
    C.npz_save(pth, pos=pos, cov=cov, ao=ao, L=np.array(L, dtype=object))
    d = np.load(pth, allow_pickle=True)
    return d["pos"], d["cov"], d["ao"], d["L"].item()


# ---------------------------------------------------------------------------------------------
# masks
# ---------------------------------------------------------------------------------------------

def beard_fields(pos, cov, L, p):
    """Per-texel beard region (0..1) with parameters p (dict). pos: (H,W,11) posmap."""
    P = pos[..., :3]
    x = np.abs(P[..., 0]); y = P[..., 1]; z = P[..., 2]
    headw = pos[..., 6]; neckw = pos[..., 7]; lips = pos[..., 9]
    ear = L["ear"]; mouth = L["mouth"]; chin = L["chin"]; mcx = L["mcx"]
    eye_z = L["eye_l"][2]
    jit = (C.fbm(P, 220.0, 3, seed=11) - 0.5) * p.get("jitter", 0.006)
    # upper boundary: cheek line from the sideburn to above the mouth corner
    y0, z0 = ear[1] - 0.012, ear[2] - 0.004 + p.get("dz_side", 0.0)
    y1, z1 = mouth[1] + 0.026, mouth[2] + 0.016 + p.get("dz_front", 0.0)
    t = np.clip((y - y0) / (y1 - y0), 0, 1)
    zl = z0 + (z1 - z0) * t
    eu = p.get("edge", 0.005)
    upper = smoothstep(0.0, eu, zl - z + jit)
    # moustache between nose base and upper lip
    if p.get("mustache", True):
        mus = smoothstep(0.0, 0.003, (L["nose_base_z"] - 0.0025) - z + jit * 0.5) * \
            (1 - smoothstep(0.85, 1.15, x / mcx)) * (y < mouth[1] + 0.03)
        upper = np.maximum(upper, mus)
    # sideburn strip in front of the ear
    sbz = ear[2] + p.get("sideburn_top", 0.03)
    sb = smoothstep(0.0, 0.006, sbz - z + jit) * smoothstep(0.0, 0.005, y - (ear[1] - 0.026)) * (y < ear[1] + 0.004)
    upper = np.maximum(upper, sb * p.get("sideburns", 1.0))
    # lower boundary (neck line) from under the chin to below the ear
    nd = p.get("neck_drop", 0.0)
    ya, za = chin[1] + 0.035, chin[2] - 0.026 - nd
    yb, zb = ear[1], ear[2] - 0.050 - nd * 0.5
    t2 = np.clip((y - ya) / (yb - ya), 0, 1)
    zn = za + (zb - za) * t2
    lower = smoothstep(0.0, p.get("edge_low", 0.007), z - zn + jit)
    front = smoothstep(0.0, p.get("edge_back", 0.010), (ear[1] + 0.006) - y + jit)
    valid = (headw + neckw > 0.3) & (z < eye_z - 0.005) & (cov > 0) & ~cavity_rect(pos.shape[0])
    b = upper * lower * front * valid
    b = b * (1 - np.clip(lips * 1.6, 0, 1))
    # jaw edge line (side view): from under the ear lobe to the bottom of the chin
    yja, zja = chin[1] + 0.004, chin[2] - 0.006
    yjb, zjb = ear[1] - 0.012, L["ear_zmin"] - 0.010
    t3 = np.clip((y - yja) / (yjb - yja), 0, 1)
    zj = zja + (zjb - zja) * t3
    return b, dict(zn=zn, zl=zl, zj=zj, x=x, y=y, z=z, jit=jit)


def cavity_rect(n):
    """Texels of the mouth-cavity UV island (removed from the mesh; must stay empty in masks)."""
    m = np.zeros((n, n), bool)
    m[int(0.0 * n):int(0.16 * n), int(0.74 * n):int(0.95 * n)] = True
    return m


def grain(P, seed=0):
    """Per-texel follicle grain in [0,1] (random dots ~0.6 mm)."""
    g = C.vnoise(P, 1500.0, seed=seed + 31)
    g2 = C.vnoise(P, 650.0, seed=seed + 37)
    return np.clip(0.55 * g + 0.45 * g2, 0, 1)


def strands(P, seed=0):
    """Hair strand streak noise: elongated along z (beard grows downward)."""
    return C.fbm(P, 420.0, 3, seed=seed + 41, aniso=(1.0, 1.0, 0.18))


def make_masks(pos, cov, L):
    P = pos[..., :3]
    out = {}
    gr = grain(P)
    st = strands(P)
    base_p = dict(edge=0.005, edge_low=0.010, jitter=0.008)
    # short beard: the classic shape, dense
    b, f = beard_fields(pos, cov, L, base_p)
    dens = np.clip(0.80 + 0.35 * (st - 0.5) + 0.25 * (gr - 0.5), 0, 1)
    out["beard_short"] = b * dens
    # full beard: lower on the neck, higher on the cheeks, very dense
    bf, ff = beard_fields(pos, cov, L, dict(base_p, dz_side=0.006, dz_front=0.008, neck_drop=0.018,
                                             edge=0.006, edge_low=0.016, jitter=0.012, sideburn_top=0.04))
    densf = np.clip(0.92 + 0.30 * (st - 0.5) + 0.12 * (gr - 0.5), 0, 1)
    out["beard_full"] = bf * densf
    # stubble: same region as the short beard, soft edges, grainy dots
    bs, fs = beard_fields(pos, cov, L, dict(base_p, edge=0.009, edge_low=0.012, jitter=0.010, neck_drop=0.004))
    out["beard_stubble"] = bs * np.clip(0.25 + 0.9 * smoothstep(0.35, 0.75, gr), 0, 1) * 0.85
    # goatee: moustache + chin, connected around the mouth
    x = f["x"]; z = f["z"]
    lat = 1 - smoothstep(0.80, 1.10, x / (L["mcx"] * 1.28) + f["jit"] * 20)
    chin_low = smoothstep(0.0, 0.008, z - (L["chin"][2] - 0.030))
    out["beard_goatee"] = b * lat * chin_low * dens
    # moustache only
    # top: just under the nose; bottom: down to the mouth line, corners droop a little
    xr = x / L["mcx"]
    zbot = L["mouth"][2] - 0.001 - 0.006 * smoothstep(0.6, 1.1, xr)
    mus = smoothstep(0.0, 0.0025, (L["nose_base_z"] + 0.0012) - z + f["jit"] * 0.4) * \
        smoothstep(0.0, 0.002, z - zbot) * (1 - smoothstep(1.05, 1.25, xr + f["jit"] * 8))
    lipcut = smoothstep(0.80, 0.97, pos[..., 9]) * smoothstep(L["lip_top"] - 0.005, L["lip_top"] - 0.009, z)
    mus = mus * (f["y"] < L["mouth"][1] + 0.03) * (1 - lipcut) * (cov > 0) * \
        ~cavity_rect(pos.shape[0])
    out["beard_mustache"] = mus * dens
    # chinstrap: ~1.6 cm band centred on the jaw edge, from the sideburns round the chin
    bc, fc = beard_fields(pos, cov, L, dict(base_p, neck_drop=0.004, edge_low=0.006))
    band = 1 - smoothstep(0.006, 0.010, np.abs(z - fc["zj"] + fc["jit"] * 0.7))
    sideb = smoothstep(0.0, 0.010, f["y"] - (L["ear"][1] - 0.038)) * smoothstep(0.0, 0.006, z - (fc["zj"] - 0.006))
    out["beard_chinstrap"] = bc * np.maximum(band, sideb) * dens
    return out


def brow_masks(body_uv_fn=None):
    """Eyebrow cards of MakeHuman eyebrow assets re-laid into body-UV space (mhclo binding)."""
    bm, rig = C.create_human(rig=False)
    coords = C.all_coords(bm)
    me = bm.data
    luv = C.loop_uvs(me, "UVMap" if "UVMap" in me.uv_layers else None)
    lv = C.loop_verts(me)
    vuv = np.zeros((len(me.vertices), 2)); vuv[lv] = luv
    out = {}
    for key, asset in BROWS.items():
        mh, path = C.load_mhclo("eyebrows/%s/%s.mhclo" % (asset, asset))
        vs, vts, fs = [], [], []
        for line in open(path.replace(".mhclo", ".obj")):
            t = line.split()
            if not t:
                continue
            if t[0] == "v":
                vs.append(1)
            elif t[0] == "vt":
                vts.append(tuple(map(float, t[1:3])))
            elif t[0] == "f":
                fs.append([tuple(int(x) - 1 if x else -1 for x in (c.split("/") + ["", ""])[:2]) for c in t[1:]])
        n = len(vs)
        fit = C.Fit(mh, n)
        buv = (vuv[fit.vidx] * fit.w[..., None]).sum(axis=1)
        tri_uv, tri_val = [], []
        vts = np.array(vts)
        for f in fs:
            for k in range(1, len(f) - 1):
                c = (f[0], f[k], f[k + 1])
                tri_uv.append([buv[i[0]] for i in c]); tri_val.append([vts[i[1]] for i in c])
        img, cv = C.raster(np.array(tri_uv), np.array(tri_val, np.float32), SS)
        tex = C.load_image_np(os.path.join(C.ASSETS, "eyebrows", asset, asset + ".png"))
        th, tw = tex.shape[:2]
        u = np.clip(img[..., 0], 0, 1); v = np.clip(img[..., 1], 0, 1)
        a = tex[(v * (th - 1)).astype(int), (u * (tw - 1)).astype(int), 3] * cv
        lum = tex[(v * (th - 1)).astype(int), (u * (tw - 1)).astype(int), :3].mean(axis=2)
        m = np.clip(a * (1.25 - 0.5 * lum) * 2.1, 0, 1)
        m = np.maximum(m, box_blur(m[..., None], 1)[..., 0] * 0.85)
        out["brows_" + key] = m
    return out


def iris_and_eye():
    """Neutral eye texture for EYE_RECT and its iris mask (white = iris)."""
    tex = C.load_image_np(os.path.join(C.ASSETS, "eyes/materials/brown_eye.png"))
    h, w = tex.shape[:2]
    rgb = tex[..., :3]
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    yy, xx = np.mgrid[0:h, 0:w]
    cand = ((sat > 0.20) & (lum < 0.5)) | (lum < 0.12)
    pts = np.stack([yy[cand], xx[cand]], axis=1).astype(np.float64)
    cs = np.array([pts.min(axis=0), pts.max(axis=0)])
    for _ in range(20):
        d = ((pts[:, None, :] - cs[None]) ** 2).sum(axis=2)
        lab = d.argmin(axis=1)
        cs = np.array([pts[lab == k].mean(axis=0) for k in range(2)])
    mask = np.zeros((h, w))
    for k in range(2):
        cy, cx = cs[k]
        r = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
        rr = np.arange(2, min(h, w) // 4)
        prof = np.array([lum[(r >= a) & (r < a + 1)].mean() for a in rr])
        ir = rr[np.argmax((prof > 0.62) & (rr > 10))]
        mask = np.maximum(mask, 1 - smoothstep(ir * 0.90, ir * 1.03, r))
        log("eye texture %dx%d iris %d centre (%.0f,%.0f) r=%d" % (w, h, k, cx, cy, ir))
    # neutralise the iris: keep luminance pattern, mild warm-brown tint
    gl = rgb.max(axis=2) * 0.6 + rgb.mean(axis=2) * 0.4
    ref = np.percentile(gl[mask > 0.6], 75)
    gl = np.clip(gl / max(ref, 1e-3) * 0.42, 0, 0.6)
    neut = np.dstack([gl * 1.06, gl * 0.95, gl * 0.84])
    rgb2 = rgb * (1 - mask[..., None]) + neut * mask[..., None]
    return rgb2, mask


# ---------------------------------------------------------------------------------------------
# skin atlases
# ---------------------------------------------------------------------------------------------

def _up2(a):
    """Bilinear 2x upsample (H,W,C) -> (2H,2W,C)."""
    up = np.concatenate([a[:1], a, a[-1:]], axis=0)
    r0 = 0.75 * up[1:-1] + 0.25 * up[:-2]
    r1 = 0.75 * up[1:-1] + 0.25 * up[2:]
    rows = np.empty((a.shape[0] * 2,) + a.shape[1:], a.dtype)
    rows[0::2] = r0; rows[1::2] = r1
    up = np.concatenate([rows[:, :1], rows, rows[:, -1:]], axis=1)
    c0 = 0.75 * up[:, 1:-1] + 0.25 * up[:, :-2]
    c1 = 0.75 * up[:, 1:-1] + 0.25 * up[:, 2:]
    out = np.empty((rows.shape[0], a.shape[1] * 2) + a.shape[2:], a.dtype)
    out[:, 0::2] = c0; out[:, 1::2] = c1
    return out


def smooth_fill(rgb, known):
    """Push-pull with bilinear pull: fills texels where known==0 with a smooth extrapolation."""
    w = known.astype(np.float64)[..., None]
    levels = [(rgb * w, w)]
    while levels[-1][1].shape[0] > 1:
        c, ww = levels[-1]
        h, wd = ww.shape[:2]
        levels.append((c.reshape(h // 2, 2, wd // 2, 2, -1).sum(axis=(1, 3)),
                       ww.reshape(h // 2, 2, wd // 2, 2, -1).sum(axis=(1, 3))))
    c, ww = levels[-1]
    col = c / np.maximum(ww, 1e-9)
    for c, ww in reversed(levels[:-1]):
        up = _up2(col)
        cur = c / np.maximum(ww, 1e-9)
        a = np.clip(ww, 0, 1)
        col = cur * a + up * (1 - a)
    return col


def box_blur(a, r):
    """Separable box blur (3 passes ~ gaussian) on (H,W,C)."""
    out = a.astype(np.float64)
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(out, axis=ax)
            c = np.concatenate([np.zeros_like(np.take(c, [0], axis=ax)), c], axis=ax)
            n = out.shape[ax]
            lo = np.clip(np.arange(n) - r, 0, n); hi = np.clip(np.arange(n) + r + 1, 0, n)
            out = (np.take(c, hi, axis=ax) - np.take(c, lo, axis=ax)) / (hi - lo).reshape([-1 if i == ax else 1 for i in range(out.ndim)])
    return out


def hair_region(pos, cov, L, dark_tex=None):
    """Where the MakeHuman skins have painted scalp hair (to be replaced by clean skin). 0..1 at SS."""
    scalp = pos[..., 8]
    P = pos[..., :3]
    z = P[..., 2]; y = P[..., 1]
    headw = pos[..., 6] + pos[..., 7]
    ear = L["ear"]
    # generous region: scalp group + band around it (sideburns / nape) on the head
    r = smoothstep(0.02, 0.25, scalp)
    nape = smoothstep(ear[2] - 0.06, ear[2] - 0.02, z) * smoothstep(ear[1] - 0.005, ear[1] + 0.02, y) * (headw > 0.3)
    side = smoothstep(L["eye_l"][2] - 0.01, L["eye_l"][2] + 0.02, z) * smoothstep(ear[1] - 0.04, ear[1] - 0.01, y) * (headw > 0.3)
    r = np.maximum(r, np.maximum(nape, side))
    if dark_tex is not None:
        lum = dark_tex[..., :3].mean(axis=2)
        face = (pos[..., 6] > 0.5) & (scalp < 0.01) & (z < L["eye_l"][2]) & (z > L["mouth"][2]) & (cov > 0)
        ref = np.median(lum[face])
        dark = ((lum < 0.62 * ref) & (headw > 0.3) & (cov > 0) & (pos[..., 10] < 0.5)).astype(np.float32)
        dark = box_blur(dark[..., None], 6)[..., 0]
        r = np.maximum(r, smoothstep(0.15, 0.5, dark))
    ears = pos[..., 10]
    r = r * (1 - smoothstep(0.3, 0.8, ears)) * (cov > 0)
    # grow outward past the island border (8 texels) so no painted hair survives at the UV seams
    g = r.copy()
    for _ in range(8):
        g = np.maximum.reduce([g, np.roll(g, 1, 0), np.roll(g, -1, 0), np.roll(g, 1, 1), np.roll(g, -1, 1)])
    r = np.where(cov > 0, r, g)
    return np.clip(r, 0, 1)


def clean_skin(tex, R, cov, pos, L):
    """Replace painted hair (R) by extrapolated clean skin + donor pore detail. The low-frequency colour is
    extrapolated only from clean face skin in front of the ears (no lips, ears, nape or mouth cavity)."""
    H = tex.shape[0]
    rgb = tex[..., :3].astype(np.float64)
    keep = (R < 0.02) & (cov > 0) & (pos[..., 6] > 0.4) & (pos[..., 9] < 0.05) & (pos[..., 10] < 0.05) & \
        (pos[..., 1] < L["ear"][1] - 0.025) & ~cavity_rect(H)
    low = smooth_fill(box_blur(rgb, 2), keep)
    # donor: chest skin (no hair, no nipples): u 0.30-0.55, v 0.80-0.95 of the layout
    sx0, sx1 = int(0.30 * H), int(0.55 * H)
    sy0, sy1 = int(0.80 * H), int(0.93 * H)
    donor = rgb[sy0:sy1, sx0:sx1]
    hp = donor - box_blur(donor, max(2, H // 200))
    dh, dw = hp.shape[:2]
    yy = np.arange(H) % dh; xx = np.arange(H) % dw
    tile = hp[yy[:, None], xx[None, :]]
    filled = low + tile * 0.9
    Rm = R[..., None]
    out = rgb * (1 - Rm) + filled * Rm
    return np.clip(out, 0, 1)


def grade(rgb, tone, sat, val):
    rgb = rgb * np.array(tone)[None, None, :]
    g = rgb.mean(axis=2, keepdims=True)
    rgb = g + (rgb - g) * sat
    return np.clip(rgb * val, 0, 1)


def make_skins(pos, cov, ao, L, eye_rgb, iris_mask):
    texs = {}
    afr = C.load_image_np(os.path.join(C.ASSETS, "skins", SKINS["dark"]["tex"][0]))
    afr = C.resize_np(afr, SS)
    R = hair_region(pos, cov, L, dark_tex=afr)
    C.write_png(os.path.join(C.WORK, "hair_region.png"), M.downsample(R[..., None], SS // S)[..., 0], "L")
    aod = ao_filled(ao, cov, 95)
    out = {}
    for name, spec in SKINS.items():
        t0 = time.time()
        a = C.resize_np(C.load_image_np(os.path.join(C.ASSETS, "skins", spec["tex"][0])), SS)[..., :3]
        if len(spec["tex"]) > 1 and spec["blend"] > 0:
            b = C.resize_np(C.load_image_np(os.path.join(C.ASSETS, "skins", spec["tex"][1])), SS)[..., :3]
            a = a * (1 - spec["blend"]) + b * spec["blend"]
        a = clean_skin(a, R, cov, pos, L)
        a = M.downsample(a, SS // S)
        a = grade(a, spec["tone"], spec["sat"], spec["val"])
        # AO (body islands only)
        a = a * (0.45 + 0.55 * aod[..., None])
        # eyes + teeth rects
        a = place_rect(a, eye_rgb, EYE_RECT)
        teeth = C.load_image_np(os.path.join(C.ASSETS, "teeth/teeth_base/teeth.png"))[..., :3] * np.array([0.92, 0.88, 0.82])
        a = place_rect(a, teeth, TEETH_RECT)
        out[name] = a
        C.write_jpg(os.path.join(C.OUT, "skin_%s.jpg" % name), a, 92)
        log("skin_%s.jpg %.1fs" % (name, time.time() - t0))
    return out


def place_rect(img, src, rect):
    H, W = img.shape[:2]
    u0, v0, u1, v1 = rect
    x0, x1 = int(round(u0 * W)), int(round(u1 * W))
    y0, y1 = int(round(v0 * H)), int(round(v1 * H))
    sh, sw = src.shape[:2]
    ys = ((np.arange(y1 - y0) + 0.5) / (y1 - y0) * sh).astype(int)
    xs = ((np.arange(x1 - x0) + 0.5) / (x1 - x0) * sw).astype(int)
    out = img.copy()
    if src.ndim == 2:
        out[y0:y1, x0:x1] = src[ys[:, None], xs[None, :]]
    else:
        out[y0:y1, x0:x1, :src.shape[2]] = src[ys[:, None], xs[None, :]]
    return out


def make_normal(skin_mid, ao):
    """Mild pore/wrinkle tangent-space normal from the albedo high-pass (MakeHuman layout, OpenGL +Y)."""
    lum = skin_mid @ np.array([0.3, 0.55, 0.15])
    hp = lum - box_blur(lum[..., None], 3)[..., 0]
    hp = np.clip(hp / (np.std(hp) * 4 + 1e-6), -1, 1)
    h = box_blur(hp[..., None], 1)[..., 0] * 0.6
    gy, gx = np.gradient(h)
    k = 1.6
    n = np.dstack([-gx * k, -gy * k, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


# ---------------------------------------------------------------------------------------------
# scalp masks, procedural hair textures
# ---------------------------------------------------------------------------------------------

def scalp_masks(pos, cov, L):
    P = pos[..., :3]
    scalp = pos[..., 8]
    jit = (C.fbm(P, 380.0, 3, seed=5) - 0.5) * 0.22
    m = smoothstep(0.22, 0.70, scalp + jit) * (cov > 0) * (1 - smoothstep(0.3, 0.8, pos[..., 10]))
    gr = grain(P, seed=3)
    dens = m * (0.35 + 0.65 * m)            # sparser towards the hairline
    full = np.clip(dens * (0.66 + 0.8 * (gr - 0.5)), 0, 1)
    ear = L["ear"]
    hz = (P[..., 2] - ear[2]) / (L["z_top"] - ear[2])
    fade = 0.30 + 0.70 * smoothstep(-0.05, 0.50, hz)
    return dict(scalp_full=full, scalp_fade=full * fade), m


# ---------------------------------------------------------------------------------------------
# kit + acc textures
# ---------------------------------------------------------------------------------------------

def boot_tex(name):
    t = C.load_image_np(os.path.join(C.ASSETS, "clothes", name, name + "_diffuse.png"))[..., :3]
    lum = t @ np.array([0.299, 0.587, 0.114])
    lum = np.clip(0.18 + 0.75 * (lum / max(np.percentile(lum, 85), 1e-3)), 0.08, 0.95)
    return lum


def ao_filled(ao, cov, pct):
    """AO normalised to its pct percentile, with texels outside the UV islands (and the bake margin)
    filled from inside so island borders get no dark outline."""
    cv = M.downsample(cov[..., None], cov.shape[0] // ao.shape[0])[..., 0] > 0.99
    a = np.clip(ao / max(np.percentile(ao[cv], pct), 1e-3), 0, 1)
    return smooth_fill(a[..., None], cv)[..., 0]


def make_kit(ao, boots, cov):
    """Neutral light-grey kit albedo (AO) in the body layout + boot textures in BOOT_RECTS."""
    aod = ao_filled(ao, cov, 90)
    g = 0.80 * (0.55 + 0.45 * aod)
    out = np.dstack([g, g, g])
    for rect, (bname, tname) in zip(BOOT_RECTS, boots):
        lum = boot_tex(tname)
        out = place_rect(out, np.dstack([lum, lum, lum]), rect)
    return out


def make_acc():
    """acc.png (512): rows of rects. Band rib texture, armband with a 'C', glove texture is drawn by the
    build stage into GLOVE_RECT (it needs the glove geometry), here only a neutral base."""
    n = 512
    img = np.full((n, n, 3), 0.82)
    yy, xx = np.mgrid[0:n, 0:n] / n
    # band rect: vertical ribs (u along the band circumference)
    rib = 0.80 + 0.07 * np.cos(xx * 2 * math.pi * 64) + 0.03 * (np.random.default_rng(1).random((n, n)) - 0.5)
    img = np.where(((yy >= 0.0) & (yy < 0.25))[..., None], np.dstack([rib] * 3), img)
    # armband rect with C letter
    cu, cv = 0.25, 0.375
    r = np.sqrt(((xx - cu) * 2.2) ** 2 + ((yy - cv) / 0.125 * 0.5) ** 2)
    ang = np.arctan2((yy - cv), (xx - cu))
    ring = (r > 0.30) & (r < 0.44) & ~((np.abs(ang) < 0.75))
    arm = np.full((n, n), 0.84)
    arm[ring & (yy >= 0.25) & (yy < 0.5) & (xx < 0.5)] = 0.30
    img = np.where(((yy >= 0.25) & (yy < 0.5))[..., None], np.dstack([arm] * 3), img)
    return img


ACC_RECTS = dict(band=(0.0, 0.0, 1.0, 0.25), armband=(0.0, 0.25, 0.5, 0.5), neck=(0.5, 0.25, 1.0, 0.5),
                 glove=(0.0, 0.5, 1.0, 1.0))


def run():
    t0 = time.time()
    pos, cov, ao, L = load_base(force=FORCE and (ONLY is None or "base" in ONLY))
    info = dict(EYE_RECT=EYE_RECT, TEETH_RECT=TEETH_RECT, BOOT_RECTS=BOOT_RECTS, ACC_RECTS=ACC_RECTS,
                landmarks={k: (np.asarray(v).tolist()) for k, v in L.items()})
    # masks
    mask_names = ["beard_stubble", "beard_short", "beard_full", "beard_goatee", "beard_mustache", "beard_chinstrap"]
    if want("masks", [os.path.join(C.OUT, n + ".png") for n in mask_names]):
        ms = make_masks(pos, cov, L)
        for k, v in ms.items():
            C.write_png(os.path.join(C.OUT, k + ".png"), M.downsample(v[..., None], SS // S)[..., 0], "L")
        log("beard masks", list(ms))
    if want("brows", [os.path.join(C.OUT, "brows_%s.png" % k) for k in BROWS]):
        bs = brow_masks()
        for k, v in bs.items():
            C.write_png(os.path.join(C.OUT, k + ".png"), M.downsample(v[..., None], SS // S)[..., 0], "L")
        log("brow masks", list(bs))
    scalp_out = [os.path.join(C.OUT, n) for n in ("scalp_full.png", "scalp_fade.png")]
    if want("scalp", scalp_out):
        sm, _ = scalp_masks(pos, cov, L)
        for k, v in sm.items():
            C.write_png(os.path.join(C.OUT, k + ".png"), M.downsample(v[..., None], SS // S)[..., 0], "L")
    eye_rgb, imask = iris_and_eye()
    if want("iris", [os.path.join(C.OUT, "iris_mask.png")]):
        im = place_rect(np.zeros((S, S)), imask, EYE_RECT)
        C.write_png(os.path.join(C.OUT, "iris_mask.png"), im, "L")
    skin_out = [os.path.join(C.OUT, "skin_%s.jpg" % k) for k in SKINS]
    if want("skin", skin_out + [os.path.join(C.OUT, "skin_normal.jpg")]):
        sk = make_skins(pos, cov, ao, L, eye_rgb, imask)
        nm = make_normal(sk["mid"], ao)
        nm = C.resize_np(nm, 1024)
        # flat normal in the eye / teeth rects
        for rect in (EYE_RECT, TEETH_RECT):
            nm = place_rect(nm, np.full((4, 4, 3), (0.5, 0.5, 1.0)), rect)
        C.write_jpg(os.path.join(C.OUT, "skin_normal.jpg"), nm, 95)
    if want("kit", [os.path.join(C.OUT, "kit.png")]):
        boots = [("Boots_1", "shoes05"), ("Boots_2", "shoes06"), ("Boots_3", "shoes01"), ("Boots_4", "shoes03")]
        kt = make_kit(ao, boots, cov)
        C.write_png(os.path.join(C.OUT, "kit.png"), kt, "RGB")
    if want("acc", [os.path.join(C.WORK, "acc_base.png")]):
        C.write_png(os.path.join(C.WORK, "acc_base.png"), make_acc(), "RGB")
    json.dump(info, open(os.path.join(C.WORK, "tex_info.json"), "w"), indent=1)
    log("stage_tex done %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    FORCE = "--force" in argv or bool(os.environ.get("MAYDON_FORCE"))
    for a in argv:
        if a.startswith("--only="):
            ONLY = set(a.split("=", 1)[1].split(","))
    run()
