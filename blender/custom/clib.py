"""MAYDON customizable footballer - shared helpers (Blender 5.2 + MPFB2, headless).

Reuses the generic parts of ~/maydon/blender/chars/mlib.py (read-only import) and adds what the
customizable base needs: the reference macro body, morph deltas, MHCLO refitting in numpy, etc.
"""
import bpy, bmesh, os, sys, math, json, time
import numpy as np
from mathutils import Vector

CHARS = os.path.expanduser("~/maydon/blender/chars")
sys.dont_write_bytecode = True        # never write caches into ~/maydon/blender/chars
if CHARS not in sys.path:
    sys.path.insert(0, CHARS)
import mlib as M                      # noqa: E402  (old generator; we only call its helpers)
from mlib import log                  # noqa: E402

from bl_ext.user_default.mpfb.services.humanservice import HumanService          # noqa: E402
from bl_ext.user_default.mpfb.services.targetservice import TargetService        # noqa: E402
from bl_ext.user_default.mpfb.services.locationservice import LocationService    # noqa: E402
from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo                # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
OUT = os.path.expanduser("~/maydon/game/assets/chars/custom")
ASSETS = M.ASSETS
NBODY = M.NBODY
os.makedirs(WORK, exist_ok=True)
os.makedirs(OUT, exist_ok=True)

# macro set of ~/maydon/blender/anim/ref.blend (make_ref.py run with height_param 0.56 -> 1.80 m)
REF_MACRO = dict(gender=1.0, age=0.5, muscle=0.5, weight=0.5, proportions=0.5, height=0.56, cupsize=0.5,
                 firmness=0.5, race=dict(asian=0.33, caucasian=0.33, african=0.33))
# a few bone heads of ref.blend (Blender space) to verify that the rig is identical
REF_BONES = {"pelvis": (0.0, -0.0035, 0.9682), "spine_03": (0.0, 0.0276, 1.194),
             "clavicle_l": (0.0235, -0.025, 1.4706), "head": (0.0, -0.04732, 1.64692),
             "foot_l": (0.20387, -0.01331, 0.07457)}

GROUPS_JSON = os.path.join(LocationService.get_mpfb_data("mesh_metadata"), "basemesh_vertex_groups.json")


def macro_dict(**over):
    m = json.loads(json.dumps(REF_MACRO))
    for k, v in over.items():
        if k == "race":
            m["race"].update(v)
        else:
            m[k] = v
    return m


# Athletic, masculine baseline applied to the customisable base mesh after the rig is built.
# Keeping the rig at REF_MACRO means every animation retargets exactly as before; these are
# detail targets that only change the body silhouette (the user can still morph slim/heavy).
BASE_TARGETS = {
    "torso/torso-vshape-incr": 0.82,
    "torso/measure-shoulder-dist-incr": 0.64,
    "torso/torso-muscle-pectoral-incr": 0.48,
    "torso/torso-muscle-dorsi-incr": 0.38,
    "torso/torso-scale-depth-incr": 0.14,
    "hip/hip-scale-horiz-decr": 0.10,
    "neck/neck-scale-horiz-incr": 0.40,
    "neck/measure-neck-circ-incr": 0.24,
    "neck/neck-scale-vert-decr": 0.26,
    "arms/x-upperarm-muscle-incr": 0.55,
    "arms/x-lowerarm-muscle-incr": 0.40,
    "arms/x-upperarm-shoulder-muscle-incr": 0.32,
    "arms/x-upperarm-scale-horiz-incr": 0.12,
    "arms/x-lowerarm-scale-horiz-incr": 0.09,
    "hands/x-hand-scale-decr": 0.30,
    "hands/x-hand-fingers-length-decr": 0.40,
    "hands/x-hand-fingers-diameter-decr": 0.10,
    "legs/x-upperleg-muscle-incr": 0.62,
    "legs/x-lowerleg-muscle-incr": 0.55,
    "legs/x-upperleg-scale-horiz-incr": 0.12,
    "legs/x-lowerleg-scale-horiz-incr": 0.10,
    "legs/measure-thigh-circ-incr": 0.24,
    "legs/measure-calf-circ-incr": 0.30,
    # male face outline (the morph keys still let a look go softer/narrower)
    "head/head-square": 0.32,
    "head/head-scale-vert-decr": 0.12,
    "head/head-scale-horiz-incr": 0.10,
    "chin/chin-width-incr": 0.35,
    "chin/chin-bones-incr": 0.25,
    "chin/chin-prominent-incr": 0.24,
    "cheek/x-cheek-bones-incr": 0.32,
    "eyebrows/eyebrows-trans-forward": 0.20,
    "eyes/x-eye-height1-incr": 0.22,
    "eyes/x-eye-height2-incr": 0.18,
    "eyes/x-eye-corner2-up": 0.08,
    "mouth/mouth-angles-up": 0.38,
    "mouth/mouth-upperlip-volume-decr": 0.14,
    "nose/nose-scale-depth-incr": 0.08,
    "nose/nose-volume-incr": 0.10,
    "nose/nose-hump-incr": 0.10,
    "ears/x-ear-scale-decr": 0.12,
}


def _expand_targets(targets):
    out = {}
    for k, w in targets.items():
        if "/x-" in k:
            out[k.replace("/x-", "/l-")] = w
            out[k.replace("/x-", "/r-")] = w
        else:
            out[k] = w
    return out


def create_human(macro=None, rig=True):
    M.clear_scene()
    bm = HumanService.create_human(macro_detail_dict=macro or macro_dict(), scale=0.1)
    r = HumanService.add_builtin_rig(bm, "game_engine") if rig else None
    # rig first: joints must stay on the animation reference; detail targets move only skin
    for t, w in _expand_targets(BASE_TARGETS).items():
        TargetService.load_target(bm, M.target_path(t), weight=w)
    return bm, r


def check_rig(rig, tol=6e-4):
    worst = 0.0
    refp = os.path.join(WORK, "ref_bones.json")
    ref_all = json.load(open(refp)) if os.path.exists(refp) else {n: dict(head=h) for n, h in REF_BONES.items()}
    devs = []
    for n, rd in ref_all.items():
        b = rig.data.bones[n]
        for key, cur in (("head", b.head_local), ("tail", b.tail_local)):
            if key in rd:
                dv = max(abs(cur[i] - rd[key][i]) for i in range(3))
                devs.append((dv, n + "." + key, tuple(round(x, 4) for x in cur), tuple(round(x, 4) for x in rd[key])))
    devs.sort(reverse=True)
    worst = devs[0][0]
    if devs[0][0] > 1e-5:
        for d in devs[:5]:
            log("  rig dev", d)
    log("rig check vs ref.blend: max bone deviation %.5f m over %d bones" % (worst, len(ref_all)))
    if worst > tol:
        raise RuntimeError("rig differs from the anim reference (%.4f m)" % worst)
    return worst


def all_coords(bm):
    """All basemesh vertices (body + helpers) with shape keys mixed, mesh space (= metres, Z up)."""
    return M.shape_coords(bm)


def target_delta(bm, tname, base_key=None):
    """Delta of one MPFB target at weight 1 (all vertices incl. helpers)."""
    sk = TargetService.load_target(bm, M.target_path(tname), weight=1.0)
    ref = sk.relative_key
    n = len(bm.data.vertices)
    a = np.zeros(n * 3, np.float64); b = np.zeros(n * 3, np.float64)
    sk.data.foreach_get("co", a); ref.data.foreach_get("co", b)
    bm.shape_key_remove(sk)
    return (a - b).reshape(n, 3)


def joint_groups():
    gj = json.load(open(GROUPS_JSON))
    return gj


def group_vertices(gj, name):
    out = []
    for a, b in gj[name]:
        out.extend(range(a, b + 1))
    return np.array(out, dtype=np.int64)


# ---------------------------------------------------------------------------------------------
# MHCLO fitting in numpy (same formula as MPFB ClothesService.fit_clothes_to_human)
# ---------------------------------------------------------------------------------------------

class Fit:
    def __init__(self, mh, nverts):
        self.mh = mh
        self.n = nverts
        self.vidx = np.array([mh.verts[i]["verts"] for i in range(nverts)], np.int64)
        self.w = np.array([mh.verts[i]["weights"] for i in range(nverts)], np.float64)
        self.off = np.array([mh.verts[i]["offsets"] for i in range(nverts)], np.float64)

    def sizes(self, co):
        mh = self.mh
        if mh.x_scale:
            xs = abs(co[mh.x_scale[0], 0] - co[mh.x_scale[1], 0]) / mh.x_scale[2]
            ys = abs(co[mh.y_scale[0], 2] - co[mh.y_scale[1], 2]) / mh.y_scale[2]
            zs = abs(co[mh.z_scale[0], 1] - co[mh.z_scale[1], 1]) / mh.z_scale[2]
        else:
            xs = ys = zs = 0.1
        return np.array([xs, zs, ys])

    def anchor(self, co):
        return (co[self.vidx] * self.w[..., None]).sum(axis=1)

    def __call__(self, co):
        return self.anchor(co) + self.off * self.sizes(co)[None, :]


def load_mhclo(rel):
    path = os.path.join(ASSETS, rel)
    mh = Mhclo(); mh.load(path)
    return mh, path


# ---------------------------------------------------------------------------------------------
# misc
# ---------------------------------------------------------------------------------------------

def npz_save(path, **arrays):
    tmp = path + ".tmp.npz"
    np.savez_compressed(tmp, **arrays)
    os.replace(tmp, path)


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def vertex_group_weights(ob, name, n=None):
    n = n or len(ob.data.vertices)
    out = np.zeros(n)
    if name not in ob.vertex_groups:
        return out
    gi = ob.vertex_groups[name].index
    for v in ob.data.vertices:
        if v.index >= n:
            break
        for g in v.groups:
            if g.group == gi:
                out[v.index] = g.weight
    return out


def get_co(ob):
    me = ob.data
    a = np.zeros(len(me.vertices) * 3, np.float64)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_co(ob, co):
    ob.data.vertices.foreach_set("co", np.asarray(co, np.float32).reshape(-1))
    ob.data.update()


def add_delta_attrs(ob, deltas, names):
    """Store per-vertex morph deltas as float-vector point attributes 'sk_<name>' (survive bmesh edits and
    decimation, which interpolate vertex custom data)."""
    me = ob.data
    for nm in names:
        a = me.attributes.get("sk_" + nm) or me.attributes.new("sk_" + nm, "FLOAT_VECTOR", "POINT")
        a.data.foreach_set("vector", np.asarray(deltas[nm], np.float32).reshape(-1))


def attrs_to_shape_keys(ob, names, min_disp=2e-4, keep_all=False):
    """Turn sk_* attributes into shape keys; keys that move nothing (< min_disp m) are skipped."""
    me = ob.data
    n = len(me.vertices)
    base = get_co(ob)
    made = []
    if ob.data.shape_keys is None:
        ob.shape_key_add(name="Basis", from_mix=False)
    for nm in names:
        at = me.attributes.get("sk_" + nm)
        if at is None:
            continue
        d = np.zeros(n * 3, np.float32); at.data.foreach_get("vector", d)
        d = d.reshape(-1, 3)
        mx = float(np.linalg.norm(d, axis=1).max()) if n else 0.0
        if mx < min_disp and not keep_all:
            continue
        k = ob.shape_key_add(name=nm, from_mix=False)
        k.data.foreach_set("co", (base + d).astype(np.float32).reshape(-1))
        k.value = 0.0
        made.append(nm)
    for nm in names:
        at = me.attributes.get("sk_" + nm)
        if at is not None:
            me.attributes.remove(at)
    return made


# ---------------------------------------------------------------------------------------------
# numpy rasterizer (UV space) and noise
# ---------------------------------------------------------------------------------------------

def mesh_loop_tris(me, uv_name=None):
    """Triangles of a mesh as loop-index triples (fan triangulation of polygons)."""
    tris = []
    for p in me.polygons:
        li = list(p.loop_indices)
        for k in range(1, len(li) - 1):
            tris.append((li[0], li[k], li[k + 1]))
    return np.array(tris, np.int64)


def loop_uvs(me, name=None):
    uvl = me.uv_layers[name] if name else me.uv_layers.active
    a = np.zeros(len(me.loops) * 2, np.float64)
    uvl.data.foreach_get("uv", a)
    return a.reshape(-1, 2)


def loop_verts(me):
    a = np.zeros(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", a)
    return a


def raster(uv_tri, val_tri, size, rect=(0.0, 0.0, 1.0, 1.0), out=None, cov=None):
    """Rasterize triangles given in UV (T,3,2) with per-corner values (T,3,C) into an image (size,size,C)
    covering `rect` (u0,v0,u1,v1). Rows are bottom-up (row = v), like Blender image pixels."""
    T = len(uv_tri)
    C_ = val_tri.shape[2]
    H = W = size
    if out is None:
        out = np.zeros((H, W, C_), np.float32)
        cov = np.zeros((H, W), np.float32)
    u0, v0, u1, v1 = rect
    P = np.empty_like(uv_tri)
    P[..., 0] = (uv_tri[..., 0] - u0) / (u1 - u0) * W
    P[..., 1] = (uv_tri[..., 1] - v0) / (v1 - v0) * H
    for t in range(T):
        p = P[t]
        x0 = max(int(math.floor(p[:, 0].min() - 0.5)), 0); x1 = min(int(math.ceil(p[:, 0].max() + 0.5)), W - 1)
        y0 = max(int(math.floor(p[:, 1].min() - 0.5)), 0); y1 = min(int(math.ceil(p[:, 1].max() + 0.5)), H - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs = np.arange(x0, x1 + 1) + 0.5
        ys = np.arange(y0, y1 + 1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        l0 = ((by - cy) * (X - cx) + (cx - bx) * (Y - cy)) / den
        l1 = ((cy - ay) * (X - cx) + (ax - cx) * (Y - cy)) / den
        l2 = 1 - l0 - l1
        m = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not m.any():
            continue
        v = val_tri[t]
        vals = l0[m, None] * v[0] + l1[m, None] * v[1] + l2[m, None] * v[2]
        sub = out[y0:y1 + 1, x0:x1 + 1]
        sub[m] = vals
        cov[y0:y1 + 1, x0:x1 + 1][m] = 1.0
    return out, cov


def fill_empty(img, cov):
    """Push-pull fill of uncovered texels (keeps covered ones)."""
    a = np.concatenate([img[..., :3] if img.shape[2] >= 3 else np.repeat(img[..., :1], 3, 2), cov[..., None]], axis=2)
    f = M.dilate(a)
    if img.shape[2] >= 3:
        out = img.copy(); out[..., :3] = f[..., :3]
        return out
    return f[..., :1]


_NOISE_CACHE = {}


def vnoise(P, freq, seed=0, aniso=(1.0, 1.0, 1.0)):
    """3D value noise in [0,1] at points P (...,3) (metres), cell = 1/freq metres. Trilinear, smooth."""
    key = seed
    if key not in _NOISE_CACHE:
        rng = np.random.default_rng(1234 + seed)
        _NOISE_CACHE[key] = rng.random((64, 64, 64)).astype(np.float32)
    g = _NOISE_CACHE[key]
    Q = P * (freq * np.asarray(aniso))[None, :] if P.ndim == 2 else P * (freq * np.asarray(aniso))
    Q = Q + 1000.0
    i = np.floor(Q).astype(np.int64)
    f = Q - i
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * g[(i[..., 0] + dx) % 64, (i[..., 1] + dy) % 64, (i[..., 2] + dz) % 64]
    return out


def fbm(P, freq, octaves=3, seed=0, aniso=(1.0, 1.0, 1.0)):
    s = 0.0; a = 1.0; tot = 0.0
    for o in range(octaves):
        s = s + a * vnoise(P, freq * (2 ** o), seed + o * 7, aniso)
        tot += a; a *= 0.5
    return s / tot


def load_image_np(path):
    img = bpy.data.images.load(path, check_existing=False)
    a = M.image_to_np(img).copy()
    bpy.data.images.remove(img)
    return a


def resize_np(a, size):
    """Area resize of a square (H,W,C) image to (size,size,C) via Blender scale (bottom-up)."""
    h, w = a.shape[:2]
    if h == size and w == size:
        return a
    if h % size == 0 and w % size == 0:
        return M.downsample(a, h // size)
    img = M.np_to_image(a, "tmp_rs")
    img.scale(size, size)
    out = M.image_to_np(img).copy()
    bpy.data.images.remove(img)
    return out


def save_gray_png(m, path):
    m = np.clip(m, 0, 1).astype(np.float32)
    M.save_np_png(np.dstack([m, m, m, np.ones_like(m)]), path, "PNG")


def write_png(path, arr, mode="L"):
    """Minimal PNG writer. arr: bottom-up float [0,1] (H,W) for 'L', (H,W,4) for 'RGBA', (H,W,3) 'RGB'."""
    import zlib, struct
    a = np.clip(np.asarray(arr, np.float64), 0, 1)
    a = (a[::-1] * 255.0 + 0.5).astype(np.uint8)          # top-down for PNG
    h, w = a.shape[:2]
    ch = {"L": 1, "RGB": 3, "RGBA": 4}[mode]
    ctype = {"L": 0, "RGB": 2, "RGBA": 6}[mode]
    a = a.reshape(h, w * ch)
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)) + \
        chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def write_jpg(path, rgb, quality=92):
    h, w = rgb.shape[:2]
    a = np.concatenate([np.clip(rgb[..., :3], 0, 1), np.ones((h, w, 1))], axis=2)
    M.save_np_png(a.astype(np.float32), path, "JPEG", quality)


def _cpu_cycles():
    bpy.context.scene.cycles.device = "CPU"
    return "CPU"


# the GPU (4 GB) is usually busy with Godot editors; bake on the CPU unless MAYDON_GPU=1
if not os.environ.get("MAYDON_GPU"):
    M.enable_gpu_cycles = _cpu_cycles
