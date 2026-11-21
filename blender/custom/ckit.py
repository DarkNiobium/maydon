"""Kit geometry for the customizable base: a copy of mlib.kit_build_geometry (chars/mlib.py, unchanged
there) with one change: the body skin under the socks is kept, because Socks_low can replace the high socks.
Generated from mlib.py by hand-editing; keep in sync manually if the kit construction changes."""
import bmesh
from mathutils import Vector
from mlib import COL_SHIRT, COL_TRIM, COL_SHORTS, COL_SOCKS, smoothstep, tparam


def kit_build_geometry(kb, b, dl, cls, boot_inside, layers, keep_sock_skin=True):
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
    # the skin under the socks stays (Socks_low alternative shows the calves)
    keep = set(piece_faces["socks"]) if keep_sock_skin else set()
    bmesh.ops.delete(b, geom=[f for f in covered if f not in keep], context="FACES")
    for v in protect_verts:
        if v.is_valid:
            v[dl][gprot] = 1.0
    stats["half_w"] = half_w
    return stats


