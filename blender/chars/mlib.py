"""MAYDON footballer generator library (Blender 5.2 + MPFB2).

Used by build_chars.py. Everything runs headless:  blender -b --python build_chars.py -- p01 p02 ...
"""
import bpy, bmesh, os, sys, math, json, random, time
import numpy as np
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.entities.clothes.mhclo import Mhclo

ASSETS = os.path.expanduser("~/mh_assets_dl/extracted")
MPFB_TARGETS = LocationService.get_mpfb_data("targets")
NBODY = 13380          # basemesh body vertices are indices 0..13379 (helpers follow)

TORSO = {"Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r"}
FINGERS = ["thumb", "index", "middle", "ring", "pinky"]


def side_set(kind, s):
    if kind == "arm":
        b = {"upperarm_" + s, "lowerarm_" + s, "hand_" + s}
        for f in FINGERS:
            for i in (1, 2, 3):
                b.add("%s_0%d_%s" % (f, i, s))
        return b
    return {"thigh_" + s, "calf_" + s, "foot_" + s, "ball_" + s}


SETS = {"torso": TORSO, "arm_l": side_set("arm", "l"), "arm_r": side_set("arm", "r"),
        "leg_l": side_set("leg", "l"), "leg_r": side_set("leg", "r")}
SET_NAMES = list(SETS.keys())


def log(*a):
    print("[maydon]", *a, flush=True)


def age_to_macro(years):
    if years < 25:
        return 0.1875 + (years - 11.0) / (25.0 - 11.0) * (0.5 - 0.1875)
    return 0.5 + (years - 25.0) / (90.0 - 25.0) * 0.5


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images,
                 bpy.data.cameras, bpy.data.lights, bpy.data.node_groups):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def target_path(name):
    """'nose/nose-hump-incr' -> full path of the .target.gz"""
    p = os.path.join(MPFB_TARGETS, name + ".target.gz")
    if not os.path.exists(p):
        raise IOError("missing target " + p)
    return p


# ---------------------------------------------------------------------------------------------
# 1. MPFB human
# ---------------------------------------------------------------------------------------------

def build_human(spec):
    macro = TargetService.get_default_macro_info_dict()
    macro.update(gender=spec.get("gender", 1.0), age=age_to_macro(spec["age"]),
                 muscle=min(0.96, spec["muscle"] + 0.05), weight=min(0.68, spec["weight"] + 0.03),
                 proportions=spec.get("proportions", 0.52),
                 height=spec.get("height_macro", 0.5), cupsize=spec.get("cupsize", 0.5), firmness=0.5)
    a, c, f = spec["race"]
    macro["race"] = {"asian": a, "caucasian": c, "african": f}
    bm = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
    for tname, w in spec.get("targets", {}).items():
        if abs(w) < 1e-4:
            continue
        TargetService.load_target(bm, target_path(tname), weight=w)
    # sym targets for l/r pairs given with "x-" prefix
    rig = HumanService.add_builtin_rig(bm, "game_engine")
    return bm, rig


def add_asset(bm, rel, asset_type):
    path = os.path.join(ASSETS, rel)
    ob = HumanService.add_mhclo_asset(path, bm, asset_type=asset_type, subdiv_levels=0, material_type="NONE")
    for m in list(ob.modifiers):
        if m.type == "SUBSURF":
            ob.modifiers.remove(m)
    mh = Mhclo()
    mh.load(path)
    return ob, mh


def shape_coords(bm):
    """Vertex coordinates of the basemesh with all shape keys mixed (rest pose, metres)."""
    me = bm.data
    n = len(me.vertices)
    co = np.zeros(n * 3, dtype=np.float64)
    tmp = bm.shape_key_add(name="__mix", from_mix=True)
    tmp.data.foreach_get("co", co)
    bm.shape_key_remove(tmp)
    return co.reshape(n, 3)


def mhclo_base_points(mh, coords, nverts):
    """Barycentric anchor (without offset) for each asset vertex."""
    out = np.zeros((nverts, 3))
    for i in range(nverts):
        d = mh.verts[i]
        v = d["verts"]; w = d["weights"]
        out[i] = coords[v[0]] * w[0] + coords[v[1]] * w[1] + coords[v[2]] * w[2]
    return out


def freeze_body(bm, coords):
    """Copy of the basemesh body (no helpers) with shape keys baked; keeps vertex groups and UVs."""
    me = bm.data.copy()
    ob = bpy.data.objects.new("body", me)
    bpy.context.scene.collection.objects.link(ob)
    if me.shape_keys:
        for k in list(me.shape_keys.key_blocks)[::-1]:
            ob.shape_key_remove(k)
    me.vertices.foreach_set("co", coords.reshape(-1).astype(np.float32))
    for vg in bm.vertex_groups:
        ob.vertex_groups.new(name=vg.name)
    b = bmesh.new(); b.from_mesh(me)
    b.verts.ensure_lookup_table()
    bmesh.ops.delete(b, geom=[v for v in b.verts if v.index >= NBODY], context="VERTS")
    b.to_mesh(me); b.free()
    me.update()
    assert len(me.vertices) == NBODY, len(me.vertices)
    return ob


# ---------------------------------------------------------------------------------------------
# helpers on bmesh deform layers
# ---------------------------------------------------------------------------------------------

class Groups:
    def __init__(self, ob):
        self.names = [vg.name for vg in ob.vertex_groups]
        self.idx = {n: i for i, n in enumerate(self.names)}
        self.set_of = {}
        for i, n in enumerate(self.names):
            for sname, bones in SETS.items():
                if n in bones:
                    self.set_of[i] = sname

    def membership(self, dv):
        acc = {}
        for gi, w in dv.items():
            s = self.set_of.get(gi)
            if s:
                acc[s] = acc.get(s, 0.0) + w
        if not acc:
            return "torso"
        return max(acc.items(), key=lambda kv: kv[1])[0]

    def weight(self, dv, name):
        gi = self.idx.get(name)
        return dv.get(gi, 0.0) if gi is not None else 0.0


def bone_seg(rig, name):
    b = rig.data.bones[name]
    return Vector(b.head_local), Vector(b.tail_local)


def tparam(p, seg):
    h, t = seg
    d = t - h
    return (p - h).dot(d) / d.length_squared


# ---------------------------------------------------------------------------------------------
# 2. Kit construction on the full-res body
# ---------------------------------------------------------------------------------------------

KIT_PARAMS = dict(
    T_SLEEVE=0.47,      # sleeve end, fraction along upperarm
    CUFF_W=0.022,       # cuff trim width (m)
    T_HEM=0.48,         # shorts hem, fraction along thigh
    T_SOCK=0.13,        # sock top, fraction along calf
    Z_HEM=-0.050,       # shirt hem rel. to hip joint (pelvis head), * S
    Z_WAIST=0.075,      # shorts waistband rel. to hip joint, * S
    COLLAR_F=-0.068,    # crew-neck line height rel. neck_01 head (front / side / back), * S
    COLLAR_S=-0.010,
    COLLAR_B=-0.012,
    COLLAR_K=1.2,       # cone factor: threshold rises away from the neck so shoulders stay covered
    O_SHIRT=0.011, O_SLEEVE=0.012, O_SHIRT_HEM=0.018, O_COLLAR=0.005,
    O_SHORTS=0.008, O_SHORTS_FLARE=0.020, O_SHORTS_INNER=0.006,
    O_SOCK=0.0032, O_SHIN=0.0045,
    BAND_H=0.011,
    DRAPE_SHIRT=14, DRAPE_SHORTS=8,
)

COL_SHIRT = (1.0, 0.0, 0.0, 0.0)
COL_TRIM = (0.5, 0.0, 0.0, 0.0)
COL_SHORTS = (0.0, 1.0, 0.0, 0.0)
COL_SOCKS = (0.0, 0.0, 1.0, 0.0)
COL_BOOTS = (0.0, 0.0, 0.0, 1.0)
COL_NONE = (0.0, 0.0, 0.0, 0.0)


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


class KitBuilder:
    def __init__(self, body, rig, boot_delverts, P=None):
        self.body = body
        self.rig = rig
        self.P = dict(KIT_PARAMS)
        if P:
            self.P.update(P)
        self.G = Groups(body)
        self.boot_del = set(boot_delverts)
        bones = rig.data.bones
        self.seg = {}
        for s in "lr":
            for n in ("upperarm", "thigh", "calf"):
                self.seg[n + "_" + s] = bone_seg(rig, n + "_" + s)
        co = np.array([v.co[:] for v in body.data.vertices])
        self.height = co[:, 2].max() - co[:, 2].min()
        self.S = self.height / 1.80
        P = self.P; S = self.S
        hip = Vector(bones["pelvis"].head_local)
        self.z_hem = hip.z + P["Z_HEM"] * S
        self.z_waist = hip.z + P["Z_WAIST"] * S
        self.n0 = Vector(bones["neck_01"].head_local)
        self.r_neck = 0.06
        self.neck_axis = (Vector(bones["head"].head_local) - self.n0).normalized()

    # --- membership -------------------------------------------------------------------------
    def vmember(self, b, dl):
        return {v: self.G.membership(v[dl]) for v in b.verts}

    def fmember(self, f, dl):
        acc = {}
        for v in f.verts:
            for gi, w in v[dl].items():
                s = self.G.set_of.get(gi)
                if s:
                    acc[s] = acc.get(s, 0.0) + w
        if not acc:
            return "torso"
        return max(acc.items(), key=lambda kv: kv[1])[0]

    def is_head_skin(self, p):
        if p.z > self.n0.z + 0.07 * self.S:
            return True
        if self.neck_r(p) > 0.16 * self.S or p.z < self.n0.z - 0.14 * self.S:
            return False
        return self.collar_fn(p) > 0

    # --- implicit-function cutting ----------------------------------------------------------
    def cut(self, b, faces, fn):
        """Split the given faces along the zero set of fn (like bisect_plane, but any function)."""
        faces = [f for f in faces if f.is_valid]
        if not faces:
            return
        fset = set(faces)
        edges = set()
        for f in faces:
            edges.update(f.edges)
        val = {}
        for e in edges:
            for v in e.verts:
                if v not in val:
                    val[v] = fn(v.co)
        newv = set()
        for e in list(edges):
            v1, v2 = e.verts
            f1, f2 = val[v1], val[v2]
            if abs(f1) < 1e-7 or abs(f2) < 1e-7 or (f1 > 0) == (f2 > 0):
                continue
            t = f1 / (f1 - f2)
            if t < 0.02 or t > 0.98:      # snap to existing vertex instead of creating slivers
                vv = v1 if t < 0.5 else v2
                newv.add(vv)
                continue
            ne, nv = bmesh.utils.edge_split(e, v1, t)
            newv.add(nv)
        # connect cut vertices inside each original face
        for f in list(fset):
            if not f.is_valid:
                continue
        touched = set()
        for v in newv:
            for f in v.link_faces:
                touched.add(f)
        for f in touched:
            if not f.is_valid:
                continue
            vs = [v for v in f.verts if v in newv]
            if len(vs) == 2:
                if not any(e.other_vert(vs[0]) is vs[1] for e in vs[0].link_edges):
                    try:
                        bmesh.utils.face_split(f, vs[0], vs[1])
                    except Exception:
                        pass
            elif len(vs) > 2:
                # order along the face loop and connect consecutive pairs (0-1, 2-3)
                order = [v for v in f.verts if v in newv]
                for i in range(0, len(order) - 1, 2):
                    try:
                        ff = [x for x in order[i].link_faces if order[i + 1] in x.verts]
                        if ff:
                            bmesh.utils.face_split(ff[0], order[i], order[i + 1])
                    except Exception:
                        pass

    def fields(self):
        """name -> (member sets, extra filter(center), fn)"""
        P = self.P; S = self.S
        F = {}
        for s in "lr":
            ua = self.seg["upperarm_" + s]
            L = (ua[1] - ua[0]).length
            F["sleeve_" + s] = ({"arm_" + s}, None, (lambda ua: lambda p: tparam(p, ua) - P["T_SLEEVE"])(ua))
            F["cuff_" + s] = ({"arm_" + s}, None,
                              (lambda ua, L: lambda p: tparam(p, ua) - (P["T_SLEEVE"] - P["CUFF_W"] / L))(ua, L))
            th = self.seg["thigh_" + s]
            F["hem_" + s] = ({"leg_" + s}, None, (lambda th: lambda p: tparam(p, th) - P["T_HEM"])(th))
            ca = self.seg["calf_" + s]
            F["sock_" + s] = ({"leg_" + s}, None, (lambda ca: lambda p: tparam(p, ca) - P["T_SOCK"])(ca))
        nonarm = {"torso", "leg_l", "leg_r"}
        F["z_hem"] = (nonarm, lambda c: abs(c.z - self.z_hem) < 0.1, lambda p: p.z - self.z_hem)
        F["z_waist"] = (nonarm, lambda c: abs(c.z - self.z_waist) < 0.1, lambda p: p.z - self.z_waist)
        F["collar"] = ({"torso"}, lambda c: self.neck_r(c) < 0.16 * S and self.n0.z - 0.14 * S < c.z < self.n0.z + 0.07 * S,
                       self.collar_fn)
        return F

    def neck_r(self, p):
        d = p - self.n0
        ax = self.neck_axis
        return (d - ax * d.dot(ax)).length

    def collar_fn(self, p):
        """>0 above the crew-neck line (neck skin), <0 below (shirt)."""
        P = self.P; S = self.S
        d = p - self.n0
        ax = self.neck_axis
        radial = d - ax * d.dot(ax)
        r = radial.length
        phi = math.atan2(radial.x, -radial.y)      # 0 = front, +-pi = back
        hf, hs, hb = P["COLLAR_F"] * S, P["COLLAR_S"] * S, P["COLLAR_B"] * S
        a1 = (hf - hb) / 2
        a0 = ((hf + hb) / 2 + hs) / 2
        a2 = ((hf + hb) / 2 - hs) / 2
        h = a0 + a1 * math.cos(phi) + a2 * math.cos(2 * phi)
        return d.z - h - P["COLLAR_K"] * max(0.0, r - self.r_neck)

    def estimate_neck_radius(self, b):
        rs = []
        for v in b.verts:
            if self.n0.z + 0.015 * self.S < v.co.z < self.n0.z + 0.045 * self.S:
                r = self.neck_r(v.co)
                if r < 0.12:
                    rs.append(r)
        rs.sort()
        self.r_neck = rs[len(rs) // 2] if rs else 0.06
        return self.r_neck

    def make_cuts(self, b, dl):
        self.estimate_neck_radius(b)
        for name, (sets, filt, fn) in self.fields().items():
            faces = [f for f in b.faces if self.fmember(f, dl) in sets and
                     (filt is None or filt(f.calc_center_median()))]
            self.cut(b, faces, fn)

    # --- classification ---------------------------------------------------------------------
    def classify(self, b, dl):
        P = self.P
        cls = {}
        for f in b.faces:
            c = f.calc_center_median()
            m = self.fmember(f, dl)
            k = dict(shirt=False, trim=False, shorts=False, socks=False, boot=False, member=m)
            if all(v.index in self.boot_del for v in f.verts if v.index < NBODY) and \
                    all(v.index < NBODY for v in f.verts):
                pass
            if m.startswith("arm"):
                s = m[-1]
                t = tparam(c, self.seg["upperarm_" + s])
                L = (self.seg["upperarm_" + s][1] - self.seg["upperarm_" + s][0]).length
                if t < P["T_SLEEVE"]:
                    k["shirt"] = True
                    if t > P["T_SLEEVE"] - P["CUFF_W"] / L:
                        k["trim"] = True
            else:
                head = self.is_head_skin(c)
                if not head and c.z >= self.z_hem:
                    k["shirt"] = True
                if m.startswith("leg"):
                    s = m[-1]
                    tc = tparam(c, self.seg["calf_" + s])
                    tt = tparam(c, self.seg["thigh_" + s])
                    if tc > P["T_SOCK"]:
                        k["socks"] = True
                    elif tt < P["T_HEM"] and c.z <= self.z_waist:
                        k["shorts"] = True
                elif m == "torso" and c.z <= self.z_waist:
                    k["shorts"] = True
            cls[f] = k
        return cls


# ---------------------------------------------------------------------------------------------
# debug / preview rendering helpers
# ---------------------------------------------------------------------------------------------

def setup_render_scene(res=(800, 800), engine="BLENDER_EEVEE", world=(0.45, 0.47, 0.5), sun=3.0):
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    cam = bpy.data.objects.get("dbg_cam")
    if cam is None:
        cam = bpy.data.objects.new("dbg_cam", bpy.data.cameras.new("dbg_cam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    if bpy.data.objects.get("dbg_sun") is None:
        s = bpy.data.objects.new("dbg_sun", bpy.data.lights.new("dbg_sun", "SUN"))
        sc.collection.objects.link(s)
        s.rotation_euler = (math.radians(50), 0, math.radians(35))
        s.data.energy = sun
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    bg = sc.world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = world + (1,)
    sc.view_settings.view_transform = "AgX"
    return cam


def render_views(path, center, scale, angles=(0, 90, 180), res=(600, 900), dist=6.0):
    """Orthographic renders around Z axis (angle 0 = front, character faces -Y), stitched horizontally."""
    cam = setup_render_scene(res)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    sc = bpy.context.scene
    parts = []
    for i, a in enumerate(angles):
        r = math.radians(a)
        cam.location = (center[0] + dist * math.sin(r), center[1] - dist * math.cos(r), center[2])
        cam.rotation_euler = (math.radians(90), 0, r)
        p = path.replace(".png", "_%d.png" % i)
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        parts.append(p)
    os.system("magick %s +append %s" % (" ".join(parts), path))
    for p in parts:
        os.remove(p)


def kit_build_geometry(kb, b, dl, cls, boot_inside, layers):
    """Duplicate classified faces into offset kit pieces, add rims / collar band, delete hidden body faces.
    layers: dict with 'uv', 'uv2', 'col' bmesh loop layers, 'prot' deform group index for decimation protection.
    Returns stats dict."""
    P = kb.P; S = kb.S
    uvl, uv2l, coll = layers["uv"], layers["uv2"], layers["col"]
    gprot = layers["prot"]
    b.normal_update()
    vnorm = {v: v.normal.copy() for v in b.verts}
    origco = {v: v.co.copy() for v in b.verts}
    covered = set()
    for f, k in cls.items():
        if k["shirt"] or k["shorts"] or k["socks"]:
            covered.add(f)
    boot_faces = set(f for f in b.faces if all(v in boot_inside for v in f.verts))
    for f in boot_faces:
        k = cls.get(f)
        if k:
            k["socks"] = False
    covered |= boot_faces
    skin_faces = set(f for f in b.faces if f not in covered)

    # UV2 projection parameters (shirt): half width across chest, hem / collar heights
    xs = [abs(origco[v].x) for f, k in cls.items() if k["shirt"] and k["member"] == "torso" for v in f.verts
          if abs(origco[v].z - (kb.n0.z - 0.20 * S)) < 0.03]
    half_w = max(xs) if xs else 0.17
    z_bottom = kb.z_hem
    zc_front = kb.n0.z + P["COLLAR_F"] * S
    zc_back = kb.n0.z + P["COLLAR_B"] * S
    kb.uv2_info = dict(half_w=half_w, z_bottom=z_bottom, zc_front=zc_front, zc_back=zc_back)

    def offset_for(piece, v, f_member):
        n = vnorm[v]; p = origco[v]
        if piece == "shirt":
            if f_member.startswith("arm"):
                o = P["O_SLEEVE"]
            else:
                o = P["O_SHIRT"]
                # loose over the hips / shorts
                o += (P["O_SHIRT_HEM"] - P["O_SHIRT"]) * (1 - smoothstep(kb.z_hem, kb.z_waist + 0.04 * S, p.z))
            # hug the neck near the collar
            if p.z > kb.n0.z - 0.12 * S and kb.neck_r(p) < 0.14 * S:
                fc = kb.collar_fn(p)
                o = P["O_COLLAR"] + (o - P["O_COLLAR"]) * smoothstep(-0.05 * S, -0.005 * S, -fc)
            return o
        if piece == "shorts":
            o = P["O_SHORTS"]
            for s in "lr":
                th = kb.seg["thigh_" + s]
                if f_member == "leg_" + s or (f_member == "torso" and (p.x > 0) == (s == "l")):
                    t = max(0.0, tparam(p, th)) / P["T_HEM"]
                    t = min(1.0, t) ** 1.6
                    lat = n.x if s == "l" else -n.x
                    inner = max(0.0, -lat)
                    flare = P["O_SHORTS_FLARE"] * (1 - inner) + P["O_SHORTS_INNER"] * inner
                    if f_member == "leg_" + s:
                        o += t * flare
            return o
        if piece == "socks":
            o = P["O_SOCK"]
            for s in "lr":
                if f_member == "leg_" + s:
                    tc = tparam(p, kb.seg["calf_" + s])
                    shin = max(0.0, -n.y) * smoothstep(0.15, 0.3, tc) * (1 - smoothstep(0.72, 0.85, tc))
                    o += P["O_SHIN"] * shin
            # sock top cuff slightly thicker
            return o
        return 0.01

    stats = {}
    piece_faces = {
        "shirt": [f for f, k in cls.items() if k["shirt"] and f not in boot_faces],
        "shorts": [f for f, k in cls.items() if k["shorts"] and f not in boot_faces],
        "socks": [f for f, k in cls.items() if k["socks"] and f not in boot_faces],
    }
    piece_sets = {k: set(v) for k, v in piece_faces.items()}
    new_kit_faces = []
    protect_verts = set()

    def set_face_attrs(fn, col, uv_src=None, uv2=None):
        fn.material_index = 1
        fn.smooth = True
        for i, l in enumerate(fn.loops):
            l[coll] = col
            if uv2 is not None:
                l[uv2l].uv = uv2[i]
            else:
                l[uv2l].uv = (0.0, 1.0)
        new_kit_faces.append(fn)

    def uv2_of(p, front):
        hw = half_w
        if front:
            x = max(-1.0, min(1.0, p.x / hw))
            zc = zc_front
        else:
            x = max(-1.0, min(1.0, -p.x / hw)) + 2.0
            zc = zc_back
        y = (p.z - z_bottom) / (zc - z_bottom)
        return (x, 1.0 - y)          # Blender v is flipped by the glTF exporter

    for piece in ("socks", "shorts", "shirt"):
        faces = piece_faces[piece]
        if not faces:
            continue
        # face member for offsets: use per-vertex dominant set
        vmap = {}
        vmem = {}
        for f in faces:
            m = cls[f]["member"]
            for v in f.verts:
                if v not in vmem:
                    vmem[v] = kb.G.membership(v[dl])
        disp = {}
        for v in vmem:
            disp[v] = vnorm[v] * offset_for(piece, v, vmem[v])
        # smooth displacement field over the piece (reduces creases in concave areas)
        adj = {v: set() for v in vmem}
        for f in faces:
            vs = list(f.verts)
            for i in range(len(vs)):
                a, c = vs[i], vs[(i + 1) % len(vs)]
                adj[a].add(c); adj[c].add(a)
        for it in range(4):
            nd = {}
            for v, nb in adj.items():
                if nb:
                    avg = sum((disp[u] for u in nb), Vector()) / len(nb)
                    nd[v] = disp[v] * 0.5 + avg * 0.5
                else:
                    nd[v] = disp[v]
            disp = nd
        pos = {v: origco[v] + disp[v] for v in vmem}
        iters = {"shirt": P["DRAPE_SHIRT"], "shorts": P["DRAPE_SHORTS"]}.get(piece, 0)
        if iters:
            # cloth-like drape: Laplacian smoothing of positions (bridges concavities such as the
            # sternum, spine groove, waist), constrained to stay outside the body by a min offset.
            bnd = set()
            for f in faces:
                for e in f.edges:
                    if sum(1 for ff in e.link_faces if ff in piece_sets[piece]) < 2:
                        bnd.update(e.verts)
            omin = {v: disp[v].length * 0.85 for v in vmem}
            lam = {}
            for v in vmem:
                p0 = origco[v]
                w = 1.0
                if piece == "shirt":
                    if vmem[v].startswith("arm"):
                        w = 0.35
                    if p0.z > kb.n0.z - 0.10 * S:
                        w *= 1 - smoothstep(kb.n0.z - 0.10 * S, kb.n0.z - 0.04 * S, p0.z)
                if piece == "shorts" and p0.z > kb.z_hem:
                    w = 0.15
                lam[v] = 0.0 if v in bnd else 0.5 * w
            for it in range(iters):
                newp = {}
                for v, nb in adj.items():
                    if lam[v] <= 0 or not nb:
                        newp[v] = pos[v]
                        continue
                    avg = sum((pos[u] for u in nb), Vector()) / len(nb)
                    q = pos[v] * (1 - lam[v]) + avg * lam[v]
                    d = (q - origco[v]).dot(vnorm[v])
                    if d < omin[v]:
                        q = q + vnorm[v] * (omin[v] - d)
                    newp[v] = q
                pos = newp
        for v in vmem:
            nv = b.verts.new(pos[v], v)
            vmap[v] = nv
        pset = piece_sets[piece]
        for f in faces:
            fn = b.faces.new([vmap[v] for v in f.verts], f)
            k = cls[f]
            col = COL_SHIRT if piece == "shirt" else COL_SHORTS if piece == "shorts" else COL_SOCKS
            if piece == "shirt" and k["trim"]:
                col = COL_TRIM
            uv2 = None
            if piece == "shirt":
                front = f.normal.y < 0
                uv2 = [uv2_of(origco[v], front) for v in f.verts]
            set_face_attrs(fn, col, uv2=uv2)
            for lo, ln in zip(f.loops, fn.loops):
                ln[uvl].uv = lo[uvl].uv
        # boundary edges
        n_rim = 0
        collar_loop = []
        hem_inner = {}
        for f in faces:
            loops = list(f.loops)
            for l in loops:
                e = l.edge
                a, c = l.vert, l.link_loop_next.vert
                others = [ff for ff in e.link_faces if ff is not f]
                if any(ff in pset for ff in others):
                    continue
                other = others[0] if others else None
                if other is None or other in boot_faces:
                    continue
                ka, kc = vmap[a], vmap[c]
                protect_verts.update((a, c, ka, kc))
                uva = l[uvl].uv.copy(); uvc = l.link_loop_next[uvl].uv.copy()
                if other in skin_faces:
                    is_collar = piece == "shirt" and not cls[f]["member"].startswith("arm") and \
                        origco[a].z > kb.n0.z - 0.15 * S
                    col = COL_SHIRT if piece == "shirt" else COL_SHORTS if piece == "shorts" else COL_SOCKS
                    if piece == "shirt":
                        col = COL_TRIM
                    if is_collar:
                        collar_loop.append((a, c, ka, kc, uva, uvc, l))
                        continue
                    fn = b.faces.new([kc, ka, a, c])
                    uv2 = None
                    if piece == "shirt":
                        front = f.normal.y < 0
                        uv2 = [uv2_of(origco[x], front) for x in (c, a, a, c)]
                    set_face_attrs(fn, col, uv2=uv2)
                    for ln, uvv in zip(fn.loops, (uvc, uva, uva, uvc)):
                        ln[uvl].uv = uvv
                    n_rim += 1
                elif piece == "shirt":
                    # shirt hem over the shorts: fold inward, ending inside the shorts layer
                    for x in (a, c):
                        if x not in hem_inner:
                            o_sh = offset_for("shorts", x, kb.G.membership(x[dl]))
                            hem_inner[x] = b.verts.new(origco[x] + vnorm[x] * max(0.0, o_sh - 0.003), x)
                    inner = hem_inner
                    fn = b.faces.new([kc, ka, inner[a], inner[c]])
                    front = f.normal.y < 0
                    set_face_attrs(fn, COL_SHIRT, uv2=[uv2_of(origco[x], front) for x in (c, a, a, c)])
                    for ln, uvv in zip(fn.loops, (uvc, uva, uva, uvc)):
                        ln[uvl].uv = uvv
                    n_rim += 1
        # collar band: stand-up rib following the neck axis, then a lip that tucks into the neck
        if collar_loop:
            band = {}
            lip = {}
            ax = kb.neck_axis
            for (a, c, ka, kc, uva, uvc, l) in collar_loop:
                for x, kx in ((a, ka), (c, kc)):
                    if x not in band:
                        n = vnorm[x]
                        band[x] = b.verts.new(kx.co + ax * (P["BAND_H"] * S) - n * 0.0015, x)
                        lip[x] = b.verts.new(origco[x] + ax * (P["BAND_H"] * S) - n * 0.003, x)
                        protect_verts.update((band[x], lip[x]))
            for (a, c, ka, kc, uva, uvc, l) in collar_loop:
                front = l.face.normal.y < 0
                for quad in ([kc, ka, band[a], band[c]], [band[c], band[a], lip[a], lip[c]]):
                    fn = b.faces.new(quad)
                    set_face_attrs(fn, COL_TRIM, uv2=[uv2_of(origco[a] if q in (ka, band.get(a), lip.get(a)) else origco[c], front) for q in quad])
                    for ln, uvv in zip(fn.loops, (uvc, uva, uva, uvc)):
                        ln[uvl].uv = uvv
            # first ring of shirt faces below the collar also gets trim colour
            ring_src = set(x for (a, c, *_r) in collar_loop for x in (a, c))
            for f in faces:
                if any(v in ring_src for v in f.verts):
                    pass
        stats[piece] = dict(faces=len(faces), rims=n_rim, collar=len(collar_loop))
    # protect cut loops (trim boundary, sleeve) via deform group
    for f in new_kit_faces:
        pass
    # delete covered body faces
    bmesh.ops.delete(b, geom=list(covered), context="FACES")
    for v in protect_verts:
        if v.is_valid:
            v[dl][gprot] = 1.0
    stats["half_w"] = half_w
    return stats


# ---------------------------------------------------------------------------------------------
# 3. Boots (MakeHuman shoes with the built-in sock part removed)
# ---------------------------------------------------------------------------------------------

def prepare_boots(shoes, mh, body_coords):
    """Remove the sock geometry of the MakeHuman shoe (UV island in the lower-right corner of its
    texture). Returns set of body vertex indices that are fully inside the shoe."""
    me = shoes.data
    b = bmesh.new(); b.from_mesh(me)
    uvl = b.loops.layers.uv.active
    kill = []
    for f in b.faces:
        u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
        if u > 0.74 and v < 0.20:
            kill.append(f)
    bmesh.ops.delete(b, geom=kill, context="FACES")
    # collar (top boundary) heights per side
    bco = np.array([v.co[:] for v in b.verts if v.is_boundary])
    b.to_mesh(me); b.free()
    me.update()
    kd = KDTree(len(bco))
    for i, c in enumerate(bco):
        kd.insert(c, i)
    kd.balance()
    inside = set()
    dels = set(mh.delverts)
    for vi in dels:
        if vi >= NBODY:
            continue
        p = Vector(body_coords[vi])
        if len(bco) == 0:
            break
        # nearest collar vertex in xy-ish sense: compare heights
        c, idx, dist = kd.find(p)
        if p.z < c.z - 0.012:
            inside.add(vi)
    return inside


# ---------------------------------------------------------------------------------------------
# 4. Per-vertex texture masks (scalp / fade / beard), computed once on a neutral reference male
# ---------------------------------------------------------------------------------------------

MASK_CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "masks_cache.json")


def joint_center(coords, rng):
    a, b = rng
    return Vector(coords[a:b + 1].mean(axis=0))


def mesh_adjacency(me):
    n = len(me.vertices)
    adj = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b); adj[b].append(a)
    return adj


def diffuse(vals, adj, iters, lam=0.5):
    v = np.array(vals, dtype=np.float64)
    for _ in range(iters):
        nv = v.copy()
        for i, nb in enumerate(adj):
            if nb:
                nv[i] = v[i] * (1 - lam) + lam * v[nb].mean()
        v = nv
    return v


def compute_reference_masks(force=False):
    if os.path.exists(MASK_CACHE) and not force:
        with open(MASK_CACHE) as f:
            d = json.load(f)
        return {k: np.array(v) for k, v in d.items()}
    clear_scene()
    spec = dict(age=25, muscle=0.5, weight=0.5, race=(0.34, 0.33, 0.33), proportions=0.5, height_macro=0.5)
    bm, rig = build_human(spec)
    coords = shape_coords(bm)
    gj = json.load(open(os.path.join(LocationService.get_mpfb_data("mesh_metadata"), "basemesh_vertex_groups.json")))
    eye_l = joint_center(coords, gj["joint-l-eye"][0]); eye_r = joint_center(coords, gj["joint-r-eye"][0])
    mouth = joint_center(coords, gj["joint-mouth"][0])
    names = [vg.name for vg in bm.vertex_groups]
    me = bm.data
    def group_ids(name):
        gi = names.index(name)
        return [v.index for v in me.vertices if v.index < NBODY and any(g.group == gi for g in v.groups)]
    scalp_ids = group_ids("scalp"); lips_ids = group_ids("lips"); ear_ids = group_ids("ears")
    hw = {v.index: 0.0 for v in me.vertices if v.index < NBODY}
    gi_head = names.index("head"); gi_neck = names.index("neck_01")
    headw = np.zeros(NBODY); neckw = np.zeros(NBODY)
    for v in me.vertices:
        if v.index >= NBODY:
            continue
        for g in v.groups:
            if g.group == gi_head:
                headw[v.index] = g.weight
            elif g.group == gi_neck:
                neckw[v.index] = g.weight
    co = coords[:NBODY]
    ears = co[ear_ids]
    ear_l = Vector(ears[ears[:, 0] > 0].mean(axis=0)); ear_r = Vector(ears[ears[:, 0] < 0].mean(axis=0))
    lips = co[lips_ids]
    mouth = Vector((0.0, float(lips[:, 1].mean()), float(lips[:, 2].mean())))
    m_corner_x = np.abs(lips[:, 0]).max()
    z_top = co[:, 2].max()
    # nose tip: most forward point near the midline between eyes and mouth
    sel = (np.abs(co[:, 0]) < 0.008) & (co[:, 2] < eye_l.z) & (co[:, 2] > mouth.z)
    nose_tip = Vector(co[sel][np.argmin(co[sel][:, 1])])
    # nose base (subnasale): along the midline between nose tip and mouth, the most backward point
    # nose base (subnasale): deepest point of the outer midline profile between lips and nose tip
    mid = co[(np.abs(co[:, 0]) < 0.006) & (headw > 0.3)]
    best = None
    zz = lips[:, 2].max()
    while zz < nose_tip.z:
        band = mid[(mid[:, 2] >= zz) & (mid[:, 2] < zz + 0.0015)]
        if len(band):
            fy = band[:, 1].min()
            if best is None or fy > best[0]:
                best = (fy, zz)
        zz += 0.0015
    nose_base_z = best[1] if best else nose_tip.z - 0.015
    log("LANDMARKS eye", eye_l, "mouth", mouth, "nose_tip", nose_tip, "nose_base_z", nose_base_z,
        "ear", ear_l, "lips z", lips[:, 2].min(), lips[:, 2].max(), "lips y", lips[:, 1].min(), lips[:, 1].max())
    selc = (np.abs(co[:, 0]) < 0.006) & (co[:, 2] < lips[:, 2].min() - 0.01) & (co[:, 2] > lips[:, 2].min() - 0.07) & (headw > 0.3)
    cc = co[selc]
    chin = Vector(cc[np.argmin(cc[:, 1])])
    log("CHIN", chin)
    adj = mesh_adjacency(me)
    adj = [[j for j in nb if j < NBODY] for nb in adj[:NBODY]]
    scalp = np.zeros(NBODY); scalp[scalp_ids] = 1.0
    scalp_s = diffuse(scalp, adj, 3)
    lipm = np.zeros(NBODY); lipm[lips_ids] = 1.0
    lipm0 = diffuse(lipm, adj, 1)
    lipm = diffuse(lipm, adj, 2)
    # head-relative height for fades: 0 at ear centre height, 1 at crown
    ez = (ear_l.z + ear_r.z) / 2
    hz = (co[:, 2] - ez) / (z_top - ez)
    # beard
    beard = np.zeros(NBODY)
    for i in range(NBODY):
        p = co[i]
        if headw[i] + neckw[i] < 0.5 or p[2] > eye_l.z:
            continue
        x, y, z = abs(p[0]), p[1], p[2]
        ear = ear_l
        if y > ear.y + 0.004:
            continue
        # cheek line (side view): from the sideburn (mid ear) to just above the mouth corner
        y0, z0 = ear.y - 0.012, ear.z - 0.004
        y1, z1 = mouth.y + 0.026, mouth.z + 0.016
        t = min(1.0, max(0.0, (y - y0) / (y1 - y0)))
        zl = z0 + (z1 - z0) * t
        upper = smoothstep(0.0, 0.005, zl - z)
        # moustache: between nose base and upper lip near the midline
        if x < m_corner_x * 1.15 and y < mouth.y + 0.03:
            upper = max(upper, smoothstep(0.0, 0.003, (nose_base_z - 0.0025) - z) * (1 - smoothstep(0.85, 1.15, x / m_corner_x)))
        # sideburn strip in front of the ear, connecting to the scalp
        if ear.y - 0.026 < y < ear.y + 0.004:
            sb = smoothstep(0.0, 0.006, (ear.z + 0.03) - z) * smoothstep(0.0, 0.005, y - (ear.y - 0.026))
            upper = max(upper, sb)
        # neck line: just under the chin to below the ear
        ya, za = chin.y + 0.035, chin.z - 0.026
        yb, zb = ear.y + 0.0, ear.z - 0.050
        t2 = min(1.0, max(0.0, (y - ya) / (yb - ya)))
        zn = za + (zb - za) * t2
        lower = smoothstep(0.0, 0.007, z - zn)
        front = smoothstep(0.0, 0.006, (ear.y + 0.004) - y)
        beard[i] = upper * lower * front
    beard = beard * (1 - np.clip(lipm0 * 1.0, 0, 1))
    beard = diffuse(beard, adj, 1)
    # chin/goatee sub-mask: near the midline below the mouth + moustache
    goatee = np.zeros(NBODY)
    for i in range(NBODY):
        p = co[i]
        dx = abs(p[0]) / (m_corner_x * 1.25)
        goatee[i] = beard[i] * (1 - smoothstep(0.75, 1.15, dx))
    d = dict(scalp=scalp_s.tolist(), beard=beard.tolist(), goatee=goatee.tolist(), hz=hz.tolist(),
             lips=lipm.tolist())
    with open(MASK_CACHE, "w") as f:
        json.dump(d, f)
    clear_scene()
    return {k: np.array(v) for k, v in d.items()}


# ---------------------------------------------------------------------------------------------
# 5. Textures
# ---------------------------------------------------------------------------------------------

# atlas rectangles in Blender UV space (u0, v0, u1, v1) inside free areas of the MakeHuman layout
EYE_RECT = (0.770, 0.875, 0.885, 0.990)    # free corner of the MakeHuman layout (top right)
TEETH_RECT = (0.892, 0.902, 0.980, 0.990)
BOOT_RECT = (0.737, 0.36, 0.925, 0.58)      # inside the head island (kit texture never uses it)


def enable_gpu_cycles():
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for dt in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = dt
                prefs.get_devices()
                devs = [d for d in prefs.devices if d.type == dt]
                if devs:
                    for d in prefs.devices:
                        d.use = d.type == dt
                    bpy.context.scene.cycles.device = "GPU"
                    return dt
            except Exception:
                continue
    except Exception as e:
        log("gpu setup failed", e)
    bpy.context.scene.cycles.device = "CPU"
    return "CPU"


def new_image(name, size, alpha=False, float_buf=False, color=(0, 0, 0, 1)):
    img = bpy.data.images.new(name, size, size, alpha=alpha, float_buffer=float_buf)
    img.generated_color = color
    return img


def image_to_np(img):
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def np_to_image(arr, name):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(arr.astype(np.float32).reshape(-1))
    return img


def save_np_png(arr, path, fmt="PNG", quality=92):
    img = np_to_image(arr, os.path.basename(path))
    img.filepath_raw = path
    img.file_format = fmt
    if fmt == "JPEG":
        bpy.context.scene.render.image_settings.quality = quality
    img.save(filepath=path, quality=quality) if fmt == "JPEG" else img.save()
    bpy.data.images.remove(img)


def dilate(arr, iters=None):
    """Push-pull fill of pixels with alpha==0 (UV padding for mipmaps). Output alpha = 1."""
    h, w = arr.shape[:2]
    a = (arr[..., 3] > 0.5).astype(np.float32)
    levels = [(arr[..., :3] * a[..., None], a)]
    while levels[-1][1].shape[0] > 4:
        c, wgt = levels[-1]
        hh, ww = wgt.shape
        c2 = c.reshape(hh // 2, 2, ww // 2, 2, 3).sum(axis=(1, 3))
        w2 = wgt.reshape(hh // 2, 2, ww // 2, 2).sum(axis=(1, 3))
        levels.append((c2, w2))
    c, wgt = levels[-1]
    col = c / np.maximum(wgt, 1e-6)[..., None]
    if (wgt <= 0).any():
        col[wgt <= 0] = (c.sum(axis=(0, 1)) / max(wgt.sum(), 1e-6))
    for c, wgt in reversed(levels[:-1]):
        up = np.repeat(np.repeat(col, 2, axis=0), 2, axis=1)
        cur = c / np.maximum(wgt, 1e-6)[..., None]
        m = (wgt > 0)[..., None]
        col = np.where(m, cur, up)
    out = np.concatenate([col, np.ones((h, w, 1), np.float32)], axis=2)
    keep = arr[..., 3] > 0.5
    out[keep, :3] = arr[keep, :3]
    return out


def downsample(arr, f):
    h, w, c = arr.shape
    return arr.reshape(h // f, f, w // f, f, c).mean(axis=(1, 3))


def box_blur(a, r):
    """Separable box blur (3 passes ~ gaussian) on (H,W,C); used for clean-skin donors."""
    out = np.asarray(a, dtype=np.float64)
    for _ in range(3):
        for ax in (0, 1):
            c = np.cumsum(out, axis=ax)
            c = np.concatenate([np.zeros_like(np.take(c, [0], axis=ax)), c], axis=ax)
            n = out.shape[ax]
            lo = np.clip(np.arange(n) - r, 0, n)
            hi = np.clip(np.arange(n) + r + 1, 0, n)
            shp = [-1 if i == ax else 1 for i in range(out.ndim)]
            out = (np.take(c, hi, axis=ax) - np.take(c, lo, axis=ax)) / (hi - lo).reshape(shp)
    return out


def blurred_texture(src_path, out_path, size=512, radius=10):
    """Heavily blurred, downsized copy of a skin texture (removes baked beard/eye shadow, keeps tone)."""
    img = bpy.data.images.load(src_path)
    a = image_to_np(img)
    bpy.data.images.remove(img)
    f = max(1, a.shape[0] // size)
    if f > 1:
        a = downsample(a, f)
    rgb = box_blur(a[..., :3], radius)
    out = np.concatenate([np.clip(rgb, 0, 1), a[..., 3:4]], axis=2)
    save_np_png(out, out_path, "PNG")
    return out_path


def bake_ao(body, size=1024, samples=48, distance=0.12):
    """Cycles AO bake of the full-res body into its MakeHuman UV layout. Returns numpy (H,W)."""
    sc = bpy.context.scene
    prev_engine = sc.render.engine
    sc.render.engine = "CYCLES"
    dev = enable_gpu_cycles()
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    sc.world.light_settings.distance = distance
    img = new_image("ao_bake", size, float_buf=True)
    mat = bpy.data.materials.new("ao_bake_mat")
    nt = mat.node_tree
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img
    nt.nodes.active = tn
    me = body.data
    saved = list(me.materials)
    me.materials.clear(); me.materials.append(mat)
    for p in me.polygons:
        p.material_index = 0
    hidden = []
    for o in sc.objects:
        if o is not body and o.type == "MESH" and not o.hide_render:
            o.hide_render = True; hidden.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    sc.render.bake.margin = 8
    t0 = time.time()
    bpy.ops.object.bake(type="AO", margin=8, use_clear=True)
    log("AO bake", dev, round(time.time() - t0, 1), "s")
    arr = image_to_np(img)[..., 0].copy()
    me.materials.clear()
    for m in saved:
        me.materials.append(m)
    for o in hidden:
        o.hide_render = False
    bpy.data.images.remove(img)
    bpy.data.materials.remove(mat)
    sc.render.engine = prev_engine
    return arr


def body_vertex_uvs(me):
    uv = me.uv_layers["UVMap"].data if "UVMap" in me.uv_layers else me.uv_layers[0].data
    out = np.zeros((len(me.vertices), 2))
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            out[vi] = uv[li].uv
    return out


def build_uvflat(body, masks, coll):
    """A flat copy of the body laid out in UV space (z=0) carrying masks & 3D position as attributes."""
    me = body.data
    uvd = me.uv_layers["UVMap"].data
    verts = []; key = {}; faces = []; src = []
    for p in me.polygons:
        fv = []
        for li, vi in zip(p.loop_indices, p.vertices):
            u, v = uvd[li].uv
            k = (vi, round(u, 5), round(v, 5))
            if k not in key:
                key[k] = len(verts); verts.append((u, v, 0.0)); src.append(vi)
            fv.append(key[k])
        faces.append(fv)
    m2 = bpy.data.meshes.new("uvflat")
    m2.from_pydata(verts, [], faces)
    uvl = m2.uv_layers.new(name="UVMap")
    for p in m2.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            uvl.data[li].uv = verts[vi][:2]
    src = np.array(src)
    co = np.array([v.co[:] for v in me.vertices])
    a = m2.attributes.new("co3", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", co[src].astype(np.float32).reshape(-1))
    for name, arr in masks.items():
        if len(arr) != NBODY:
            continue
        at = m2.attributes.new(name, "FLOAT", "POINT")
        at.data.foreach_set("value", np.asarray(arr)[src].astype(np.float32))
    ob = bpy.data.objects.new("uvflat", m2)
    coll.objects.link(ob)
    return ob


def build_brow_flat(mh, obj_path, body_uv, coll, z=0.001):
    """Eyebrow cards re-laid in body-UV space using the MHCLO barycentric binding."""
    vs = []; vts = []; fs = []
    for line in open(obj_path):
        t = line.split()
        if not t:
            continue
        if t[0] == "v":
            vs.append(tuple(map(float, t[1:4])))
        elif t[0] == "vt":
            vts.append(tuple(map(float, t[1:3])))
        elif t[0] == "f":
            fs.append([tuple(int(x) - 1 if x else -1 for x in (c.split("/") + ["", ""])[:2]) for c in t[1:]])
    verts = []
    for i in range(len(vs)):
        d = mh.verts[i]
        uv = sum((body_uv[d["verts"][k]] * d["weights"][k] for k in range(3)), np.zeros(2))
        verts.append((uv[0], uv[1], z))
    m2 = bpy.data.meshes.new("browflat")
    m2.from_pydata(verts, [], [[c[0] for c in f] for f in fs])
    uvl = m2.uv_layers.new(name="UVMap")
    for p, f in zip(m2.polygons, fs):
        for li, c in zip(p.loop_indices, f):
            uvl.data[li].uv = vts[c[1]]
    ob = bpy.data.objects.new("browflat", m2)
    coll.objects.link(ob)
    return ob


def rect_plane(name, rect, coll, z):
    u0, v0, u1, v1 = rect
    m = bpy.data.meshes.new(name)
    m.from_pydata([(u0, v0, z), (u1, v0, z), (u1, v1, z), (u0, v1, z)], [], [[0, 1, 2, 3]])
    uvl = m.uv_layers.new(name="UVMap")
    for li, uv in zip(range(4), [(0, 0), (1, 0), (1, 1), (0, 1)]):
        uvl.data[li].uv = uv
    ob = bpy.data.objects.new(name, m)
    coll.objects.link(ob)
    return ob


def _emission_mat(name, build):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    color, alpha = build(nt)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(color, em.inputs[0])
    if alpha is None:
        nt.links.new(em.outputs[0], out.inputs[0])
    else:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(alpha, mix.inputs[0])
        nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        m.surface_render_method = "DITHERED"
    return m


def _img_node(nt, path_or_img, colorspace="sRGB", interp="Linear"):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = path_or_img if isinstance(path_or_img, bpy.types.Image) else bpy.data.images.load(path_or_img, check_existing=True)
    n.image.colorspace_settings.name = colorspace
    n.interpolation = interp
    return n


def _math(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath"); n.operation = op; n.use_clamp = clamp
    for i, x in enumerate((a, b)):
        if x is None:
            continue
        if isinstance(x, (int, float)):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n.outputs[0]


def _maprange(nt, x, a, b, c=0.0, d=1.0, smooth=True):
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP" if smooth else "LINEAR"
    n.clamp = True
    if isinstance(x, (int, float)):
        n.inputs[0].default_value = x
    else:
        nt.links.new(x, n.inputs[0])
    for i, v in zip((1, 2, 3, 4), (a, b, c, d)):
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _mixrgb(nt, fac, a, b, blend="MIX"):
    n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = blend; n.clamp_result = True
    for idx, x in ((0, fac), (6, a), (7, b)):
        if isinstance(x, (int, float)):
            n.inputs[idx].default_value = x
        elif isinstance(x, tuple):
            n.inputs[idx].default_value = x
        else:
            nt.links.new(x, n.inputs[idx])
    return n.outputs[2]


def _attr(nt, name, kind="Fac"):
    n = nt.nodes.new("ShaderNodeAttribute"); n.attribute_name = name; n.attribute_type = "GEOMETRY"
    return n.outputs[kind]


def composite_skin(spec, body, masks, ao, brow_mh, brow_obj, out_path, size=1024, ss=2):
    """Render the final skin albedo atlas (skin + AO + scalp hair + beard + eyes + teeth).

    Brows are separate geometry (sharper at close range); pass brow_mh=None to skip the old baked
    eyebrow plane.
    """
    sc_main = bpy.context.scene
    sc = bpy.data.scenes.new("COMP")
    coll = sc.collection
    flat = build_uvflat(body, masks, coll)
    body_uv = body_vertex_uvs(body.data)
    brow = build_brow_flat(brow_mh, brow_obj, body_uv, coll) if brow_mh is not None else None
    eye_pl = rect_plane("eyerect", EYE_RECT, coll, 0.0005)
    teeth_pl = rect_plane("teethrect", TEETH_RECT, coll, 0.0005)
    ao_img = np_to_image(np.dstack([ao, ao, ao, np.ones_like(ao)]), "ao_img")
    ao_img.colorspace_settings.name = "Non-Color"
    S = spec["skin"]
    hair_rgb = tuple(spec["hair_color"]) + (1.0,)
    # clean skin tone for the scalp: sample the chest (no hair) of the same source texture.
    def _chest_rgb(path):
        im = bpy.data.images.load(path)
        a = image_to_np(im); bpy.data.images.remove(im)
        h = a.shape[0]
        sub = a[int(0.80 * h):int(0.93 * h), int(0.30 * h):int(0.55 * h), :3]
        return sub.reshape(-1, 3).mean(axis=0)
    chest = _chest_rgb(os.path.join(ASSETS, "skins", S["tex"][0]))
    if len(S["tex"]) > 1:
        c2 = _chest_rgb(os.path.join(ASSETS, "skins", S["tex"][1]))
        chest = chest * (1 - S.get("blend", 0.5)) + c2 * S.get("blend", 0.5)
    chest = tuple(np.clip(chest * 0.94, 0, 1)) + (1.0,)
    # blurred sources: replace baked beard shadow on the lower face with smooth skin, then
    # paint only the beard the spec asks for (clean-shaven players stop looking dirty).
    blur_paths = []
    for k, p in enumerate(S["tex"]):
        bp = os.path.join(os.path.dirname(out_path), "_blur%d.png" % k)
        blurred_texture(os.path.join(ASSETS, "skins", p), bp, size=512, radius=14)
        blur_paths.append(bp)

    def build_body(nt):
        uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "UVMap"
        ta = _img_node(nt, os.path.join(ASSETS, "skins", S["tex"][0]))
        nt.links.new(uvn.outputs[0], ta.inputs[0])
        col = ta.outputs[0]
        bcol = _img_node(nt, blur_paths[0]).outputs[0]
        if len(S["tex"]) > 1:
            tb = _img_node(nt, os.path.join(ASSETS, "skins", S["tex"][1]))
            nt.links.new(uvn.outputs[0], tb.inputs[0])
            col = _mixrgb(nt, S.get("blend", 0.5), col, tb.outputs[0])
            bb = _img_node(nt, blur_paths[1]).outputs[0]
            bcol = _mixrgb(nt, S.get("blend", 0.5), bcol, bb)
        clean = _maprange(nt, _attr(nt, "beard"), 0.10, 0.80, 0.0, 0.92)
        col = _mixrgb(nt, clean, col, bcol)
        col = _mixrgb(nt, 1.0, col, tuple(S.get("tone", (1, 1, 1))) + (1,), "MULTIPLY")
        hsv = nt.nodes.new("ShaderNodeHueSaturation")
        hsv.inputs["Saturation"].default_value = S.get("sat", 1.0)
        hsv.inputs["Value"].default_value = S.get("val", 1.0)
        nt.links.new(col, hsv.inputs["Color"])
        col = hsv.outputs[0]
        aon = _img_node(nt, ao_img, "Non-Color")
        nt.links.new(uvn.outputs[0], aon.inputs[0])
        aof = _maprange(nt, aon.outputs[0], 0.0, 1.0, 1.0 - S.get("ao", 0.55), 1.0, smooth=False)
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(aof, comb.inputs[i])
        col = _mixrgb(nt, 1.0, col, comb.outputs[0], "MULTIPLY")
        # hair noise fields (3D position based)
        co3 = _attr(nt, "co3", "Vector")
        nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 90.0
        nz.inputs["Detail"].default_value = 3.0
        nt.links.new(co3, nz.inputs["Vector"])
        fine = nt.nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 900.0
        fine.inputs["Detail"].default_value = 1.0
        nt.links.new(co3, fine.inputs["Vector"])
        vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 1400.0
        nt.links.new(co3, vor.inputs["Vector"])
        dots = _maprange(nt, vor.outputs["Distance"], 0.15, 0.55, 1.0, 0.0)
        grain = _math(nt, "MULTIPLY", _math(nt, "ADD", _math(nt, "MULTIPLY", fine.outputs["Fac"], 0.6), 0.4),
                      _math(nt, "ADD", _math(nt, "MULTIPLY", dots, 0.5), 0.5))
        H = spec["hair_paint"]
        # scalp
        jitter = _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", nz.outputs["Fac"], 0.5), 0.35)
        sc_m = _maprange(nt, _math(nt, "ADD", _attr(nt, "scalp"), jitter), H.get("edge_lo", 0.35), H.get("edge_hi", 0.62))
        fade = _maprange(nt, _attr(nt, "hz"), H.get("fade_lo", -5.0), H.get("fade_hi", -4.0), H.get("fade_min", 1.0), 1.0)
        scalp_d = _math(nt, "MULTIPLY", _math(nt, "MULTIPLY", sc_m, fade), H.get("density", 0.0))
        scalp_d = _math(nt, "MULTIPLY", scalp_d, spec.get("scalp_strength", 0.55), clamp=True)
        # beard
        B = spec.get("beard", {})
        bm_name = "goatee" if B.get("style") == "goatee" else "beard"
        jit2 = _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", nz.outputs["Fac"], 0.5), 0.45)
        bmask = _maprange(nt, _math(nt, "ADD", _attr(nt, bm_name), jit2), B.get("edge_lo", 0.25), B.get("edge_hi", 0.6))
        beard_d = _math(nt, "MULTIPLY", bmask, B.get("density", 0.0))
        dens = _math(nt, "MAXIMUM", scalp_d, beard_d)
        dens = _math(nt, "MULTIPLY", dens, _math(nt, "ADD", _math(nt, "MULTIPLY", grain, 0.55), 0.45), clamp=True)
        # keep the painted hairline/pores from the source: tint its luminance with hair colour
        # instead of flooding the scalp with one flat colour.
        dot = nt.nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
        nt.links.new(col, dot.inputs[0]); dot.inputs[1].default_value = (0.30, 0.55, 0.15)
        rel = _math(nt, "MINIMUM", _math(nt, "DIVIDE", dot.outputs["Value"], 0.055), 2.5)
        hf = _math(nt, "ADD", _math(nt, "MULTIPLY", rel, 0.90), 0.40)
        combh = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(hf, combh.inputs[i])
        hair_tex = _mixrgb(nt, 1.0, hair_rgb, combh.outputs[0], "MULTIPLY")
        col = _mixrgb(nt, dens, col, hair_tex)
        return col, None

    flat.data.materials.append(_emission_mat("comp_body", build_body))
    brow_rgb = tuple(spec.get("brow_color", spec["hair_color"])) + (1,)

    if brow is not None:
        def build_brow(nt):
            t = _img_node(nt, brow_obj.replace(".obj", ".png"))
            a = _math(nt, "MULTIPLY", t.outputs[1], 2.2 * spec.get("brow_opacity", 1.0), clamp=True)
            return _rgb(nt, brow_rgb), a
        brow.data.materials.append(_emission_mat("comp_brow", build_brow))
    eye_png = os.path.join(ASSETS, "eyes/materials", spec.get("eyes", "brown") + "_eye.png")

    def build_eye(nt):
        t = _img_node(nt, eye_png)
        hsv = nt.nodes.new("ShaderNodeHueSaturation")
        hsv.inputs["Saturation"].default_value = spec.get("eye_sat", 0.6 if spec.get("eyes", "brown") == "brown" else 0.9)
        hsv.inputs["Value"].default_value = 0.92
        nt.links.new(t.outputs[0], hsv.inputs["Color"])
        return hsv.outputs[0], None
    eye_pl.data.materials.append(_emission_mat("comp_eye", build_eye))

    def build_teeth(nt):
        t = _img_node(nt, os.path.join(ASSETS, "teeth/teeth_base/teeth.png"))
        c = _mixrgb(nt, 1.0, t.outputs[0], (0.92, 0.88, 0.82, 1.0), "MULTIPLY")
        return c, None
    teeth_pl.data.materials.append(_emission_mat("comp_teeth", build_teeth))

    cam = bpy.data.objects.new("comp_cam", bpy.data.cameras.new("comp_cam"))
    coll.objects.link(cam)
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.0
    cam.location = (0.5, 0.5, 1.0); cam.rotation_euler = (0, 0, 0)
    cam.data.clip_start = 0.01; cam.data.clip_end = 5
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = size * ss
    sc.render.film_transparent = True
    sc.render.filter_size = 0.8
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.eevee.taa_render_samples = 6
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    tmp = out_path + ".raw.png"
    sc.render.filepath = tmp
    t0 = time.time()
    bpy.ops.render.render(write_still=True, scene=sc.name)
    t1 = time.time()
    img = bpy.data.images.load(tmp)
    arr = image_to_np(img)
    bpy.data.images.remove(img)
    if not os.environ.get("MAYDON_KEEP_RAW"):
        os.remove(tmp)
    if ss > 1:
        a = arr[..., 3:4]
        rgb = downsample(arr[..., :3] * a, ss)
        aa = downsample(a, ss)
        arr = np.concatenate([rgb / np.maximum(aa, 1e-6), (aa > 0.02).astype(np.float32)], axis=2)
    arr = dilate(arr, 20)
    log("composite render %.1fs, post %.1fs" % (t1 - t0, time.time() - t1))
    save_np_png(arr, out_path, "JPEG" if out_path.endswith(".jpg") else "PNG")
    # cleanup
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(sc)
    bpy.data.images.remove(ao_img)
    return out_path


def _rgb(nt, c):
    n = nt.nodes.new("ShaderNodeRGB"); n.outputs[0].default_value = c
    return n.outputs[0]


# ---------------------------------------------------------------------------------------------
# 6. Mesh utilities
# ---------------------------------------------------------------------------------------------

def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def activate(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def decimate_to(ob, target, group=None, factor=0.0, symmetry=True, max_iter=4):
    for it in range(max_iter):
        cur = tri_count(ob)
        if cur <= target:
            break
        ratio = max(0.02, min(1.0, target / cur * (1.0 if it == 0 else 0.995)))
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = ratio
        m.use_collapse_triangulate = True
        m.use_symmetry = symmetry
        m.symmetry_axis = "X"
        if group:
            m.vertex_group = group
            m.vertex_group_factor = factor
        activate(ob)
        bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
        bpy.ops.object.modifier_apply(modifier="dec")
    return tri_count(ob)


def triangulate(ob):
    b = bmesh.new(); b.from_mesh(ob.data)
    bmesh.ops.triangulate(b, faces=b.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    b.to_mesh(ob.data); b.free()


def ensure_layers(ob):
    """Every mesh that gets joined needs UVMap + UV2 (corner) + Col (corner float colour)."""
    me = ob.data
    if len(me.uv_layers) == 0:
        me.uv_layers.new(name="UVMap")
    me.uv_layers[0].name = "UVMap"
    while len(me.uv_layers) > 1 and me.uv_layers[1].name != "UV2":
        me.uv_layers.remove(me.uv_layers[1])
    if "UV2" not in me.uv_layers:
        l = me.uv_layers.new(name="UV2")
        for d in l.data:
            d.uv = (0.0, 1.0)
    if "Col" not in me.color_attributes:
        me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")


def set_corner_color(ob, col):
    a = ob.data.color_attributes["Col"]
    n = len(a.data)
    a.data.foreach_set("color", np.tile(np.array(col, np.float32), n))


def remap_uv(ob, rect):
    u0, v0, u1, v1 = rect
    uvl = ob.data.uv_layers["UVMap"]
    a = np.zeros(len(uvl.data) * 2, np.float32)
    uvl.data.foreach_get("uv", a)
    a = a.reshape(-1, 2)
    a[:, 0] = u0 + np.clip(a[:, 0], 0, 1) * (u1 - u0)
    a[:, 1] = v0 + np.clip(a[:, 1], 0, 1) * (v1 - v0)
    uvl.data.foreach_set("uv", a.reshape(-1))


def set_material(ob, mat_index):
    for p in ob.data.polygons:
        p.material_index = mat_index


def apply_armature_free(ob):
    """Remove all modifiers except armature (MPFB adds masks etc.)."""
    for m in list(ob.modifiers):
        if m.type != "ARMATURE":
            ob.modifiers.remove(m)


def clean_vertex_groups(ob, rig, limit=4):
    bones = set(b.name for b in rig.data.bones)
    for vg in list(ob.vertex_groups):
        if vg.name not in bones:
            ob.vertex_groups.remove(vg)
    activate(ob)
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.01, keep_single=True)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=limit)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)


def hair_adjust(hair, mh, coords, spec, masks_hz_fn=None):
    """Shrink hair towards the scalp and optionally remove cards (fade sides / long ends)."""
    me = hair.data
    n = len(me.vertices)
    base = mhclo_base_points(mh, coords, n)
    pos = np.array([v.co[:] for v in me.vertices])
    k = spec.get("scale", 1.0)
    taper = spec.get("taper")       # (hz_lo, hz_hi, k_min): shrink side/back cards -> natural fade
    if taper and spec.get("hz_fn"):
        lo, hi, kmin = taper
        hzs = np.array([spec["hz_fn"](Vector(p)) for p in base])
        t = np.clip((hzs - lo) / (hi - lo), 0, 1)
        t = t * t * (3 - 2 * t)
        kk = k * (kmin + (1 - kmin) * t)
        pos = base + (pos - base) * kk[:, None]
    else:
        pos = base + (pos - base) * k
    me.vertices.foreach_set("co", pos.astype(np.float32).reshape(-1))
    cut = spec.get("cut")
    if cut:
        b = bmesh.new(); b.from_mesh(me)
        kill = []
        for f in b.faces:
            c = f.calc_center_median()
            if cut(c):
                kill.append(f)
        bmesh.ops.delete(b, geom=kill, context="FACES")
        b.to_mesh(me); b.free()
    me.update()


def process_hair_texture(src, color, out_path, size=512, gamma=1.0, alpha_boost=1.0):
    img = bpy.data.images.load(src)
    a = image_to_np(img)
    bpy.data.images.remove(img)
    f = a.shape[0] // size
    alpha = a[..., 3:4]
    rgb = a[..., :3]
    # downsample with premultiplied alpha
    rgb_d = downsample(rgb * alpha, f); al_d = downsample(alpha, f)
    rgb_d = rgb_d / np.maximum(al_d, 1e-6)
    lum = rgb_d @ np.array([0.299, 0.587, 0.114])
    m = lum[al_d[..., 0] > 0.5].mean() if (al_d > 0.5).any() else 0.3
    rel = np.clip(lum / max(m, 1e-4), 0, 3) ** gamma
    # keep strand contrast on black hair: a pure hair_color multiply turns cards into a black blob
    col = np.array(color)[None, None, :] * (0.45 + 1.65 * rel[..., None])
    # alpha shaping for alpha-scissor at 0.5: boost coverage a bit so strands don't vanish
    al = np.clip((al_d[..., 0] - 0.5) * alpha_boost + 0.5, 0, 1)
    out = np.concatenate([np.clip(col, 0, 1), al[..., None]], axis=2)
    # bleed colour into transparent texels (mip fringes)
    filled = dilate(np.concatenate([out[..., :3], (al > 0.3)[..., None].astype(np.float32)], axis=2))
    out[..., :3] = np.where((al > 0.3)[..., None], out[..., :3], filled[..., :3])
    # Blender images are bottom-up; loaded pixels are bottom-up too, so keep orientation
    save_np_png(out, out_path, "PNG")
    return out_path


def make_kit_texture(ao, boot_tex, out_path, size=512, base=0.80, ao_strength=0.45):
    """Neutral light-grey kit albedo in the body UV layout (AO darkening) + boots in BOOT_RECT."""
    f = ao.shape[0] // size
    aod = downsample(np.dstack([ao]), f)[..., 0] if f > 1 else ao
    g = base * (1 - ao_strength + ao_strength * np.clip(aod / max(np.percentile(aod, 90), 1e-3), 0, 1))
    out = np.dstack([g, g, g, np.ones_like(g)]).astype(np.float32)
    img = bpy.data.images.load(boot_tex)
    b = image_to_np(img)
    bpy.data.images.remove(img)
    u0, v0, u1, v1 = BOOT_RECT
    x0, x1 = int(u0 * size), int(u1 * size)
    y0, y1 = int(v0 * size), int(v1 * size)    # numpy rows are bottom-up like Blender
    w, h = x1 - x0, y1 - y0
    bh, bw = b.shape[:2]
    ys = (np.arange(h) + 0.5) / h * bh
    xs = (np.arange(w) + 0.5) / w * bw
    sub = b[ys.astype(int)[:, None], xs.astype(int)[None, :], :3]
    lum = sub @ np.array([0.299, 0.587, 0.114])
    # normalise: boot upper ~0.8, dark details remain darker (sole, laces) for the recolour shader
    lum = np.clip(0.18 + 0.75 * (lum / max(np.percentile(lum, 85), 1e-3)), 0.08, 0.95)
    out[y0:y1, x0:x1, :3] = lum[..., None]
    save_np_png(out, out_path, "PNG")
    return out_path


REGION_NAMES = {1: "kit", 3: "head", 4: "hands", 5: "skin"}


def region_tris(ob):
    out = {k: 0 for k in REGION_NAMES.values()}
    for p in ob.data.polygons:
        out[REGION_NAMES.get(p.material_index, "skin")] += len(p.vertices) - 2
    return out


def staged_decimate(ob, target, shares):
    """Decimate region by region. Kit boundaries (decprot group) and region borders stay fixed, so
    kit rims stay welded to the skin and every region gets its own triangle share."""
    triangulate(ob)
    me = ob.data
    cur = region_tris(ob)
    log("region tris full", cur)
    total = sum(cur.values())
    # targets per region, never above current
    tgt = {k: min(cur[k], int(target * shares[k])) for k in cur}
    spare = target - sum(tgt.values())
    # give spare budget to regions that were capped by their current size... distribute proportionally
    if spare > 0:
        free = {k: cur[k] - tgt[k] for k in cur if cur[k] > tgt[k]}
        fs = sum(free.values()) or 1
        for k in free:
            tgt[k] += int(spare * free[k] / fs)
    prot_gi = ob.vertex_groups["decprot"].index if "decprot" in ob.vertex_groups else None
    if "decfree" in ob.vertex_groups:
        ob.vertex_groups.remove(ob.vertex_groups["decfree"])
    vg = ob.vertex_groups.new(name="decfree")
    order = sorted(cur.keys(), key=lambda k: -(cur[k] - tgt[k]))
    for k in order:
        rid = [i for i, n in REGION_NAMES.items() if n == k][0]
        me = ob.data
        reg = np.zeros(len(me.polygons), np.int32)
        me.polygons.foreach_get("material_index", reg)
        nv = len(me.vertices)
        allin = np.ones(nv, bool)
        anyin = np.zeros(nv, bool)
        for p, r in zip(me.polygons, reg):
            vs = list(p.vertices)
            if r == rid:
                anyin[vs] = True
            else:
                allin[vs] = False
        free = allin & anyin
        if prot_gi is not None:
            for v in me.vertices:
                if free[v.index]:
                    for g in v.groups:
                        if g.group == prot_gi and g.weight > 0.5:
                            free[v.index] = False
        vg = ob.vertex_groups["decfree"]
        vg.remove(list(range(nv)))
        idx = np.nonzero(free)[0].tolist()
        if idx:
            vg.add(idx, 1.0, "REPLACE")
        now = region_tris(ob)
        want_total = tri_count(ob) - (now[k] - tgt[k])
        log("  pass", k, "free verts", len(idx), "now", now[k], "tgt", tgt[k], "want_total", want_total, "cur", tri_count(ob))
        if now[k] <= tgt[k]:
            continue
        for it in range(3):
            n_before = tri_count(ob)
            ratio = max(0.02, want_total / n_before)
            m = ob.modifiers.new("dec", "DECIMATE")
            m.decimate_type = "COLLAPSE"; m.ratio = ratio
            m.use_collapse_triangulate = True; m.use_symmetry = True; m.symmetry_axis = "X"
            m.vertex_group = "decfree"; m.vertex_group_factor = 1000.0
            activate(ob)
            bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
            bpy.ops.object.modifier_apply(modifier="dec")
            now = region_tris(ob)
            if now[k] <= tgt[k] * 1.03 or tri_count(ob) >= n_before - 2:
                break
            want_total = tri_count(ob) - (now[k] - tgt[k])
        log("  region", k, "->", now[k], "(target %d)" % tgt[k])
    log("region tris final", region_tris(ob), "total", tri_count(ob))
