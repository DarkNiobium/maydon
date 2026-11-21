"""Stage 1: morph deltas on the full-resolution MPFB basemesh (all vertices incl. helpers).

    nice blender -b --python ~/maydon/blender/custom/stage_deltas.py [-- --force]

Writes work/deltas.npz: base (N,3), one (N,3) array per morph key, plus head weights.
"""
import bpy, sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clib as C
from clib import log
import morphs

OUTF = os.path.join(C.WORK, "deltas.npz")


def run(force=False):
    if os.path.exists(OUTF) and not force:
        d = np.load(OUTF)
        if all(k in d.files for k in morphs.ORDER):
            log("deltas cached", OUTF)
            return OUTF
    t0 = __import__("time").time()
    bm, rig = C.create_human()
    C.check_rig(rig)
    base = C.all_coords(bm)
    N = len(base)
    zr = base[:C.NBODY, 2]
    log("base human: verts", N, "height %.4f" % (zr.max() - zr.min()))
    head_w = C.vertex_group_weights(bm, "head", N)
    neck_w = C.vertex_group_weights(bm, "neck_01", N)
    tcache = {}
    out = {}
    hz = float(rig.data.bones["head"].head_local.z)
    nz = float(rig.data.bones["neck_01"].head_local.z)
    macro_jobs = {}
    for name, (desc, targets) in list(morphs.FACE.items()) + list(morphs.EXTRA.items()):
        d = np.zeros_like(base)
        for t, w in morphs.expand(targets):
            if t.startswith("@"):
                macro_jobs.setdefault(name, []).append((t[1:], w))
                continue
            if t not in tcache:
                tcache[t] = C.target_delta(bm, t)
            d += w * tcache[t]
        out[name] = d
        mx = np.linalg.norm(d, axis=1)
        log("face key %-16s max %.2f mm  verts>0.5mm %d" % (name, mx.max() * 1000, int((mx > 5e-4).sum())))
    # macro-based face parts (age / race), head only
    hel = np.arange(N) >= C.NBODY
    fhead = C.smoothstep(0.15, 0.9, head_w)
    fhead[hel] = C.smoothstep(nz + 0.6 * (hz - nz), hz + 0.02, base[hel, 2])
    for name, jobs in macro_jobs.items():
        for mk, val in jobs:
            bm2, _ = C.create_human(C.macro_dict(**{mk: val}), rig=False)
            co2 = C.all_coords(bm2)
            # remove translation + uniform scale of the head (race/age also change stature): shape only
            sel = np.nonzero(head_w[:C.NBODY] > 0.6)[0]
            c0 = base[sel].mean(axis=0); c2 = co2[sel].mean(axis=0)
            s = np.sqrt(((base[sel] - c0) ** 2).sum(axis=1).mean() / ((co2[sel] - c2) ** 2).sum(axis=1).mean())
            co2 = (co2 - c2) * s + c0
            log("   macro %s=%s: head shift %.1f mm, scale %.4f" % (mk, val, np.linalg.norm(c2 - c0) * 1000, s))
            out[name] = out[name] + (co2 - base) * fhead[:, None]
        mx = np.linalg.norm(out[name], axis=1)
        log("macro face key %-16s max %.2f mm" % (name, mx.max() * 1000))
    gj = C.joint_groups()
    joints = [g for g in gj if g.startswith("joint-")]
    jidx = {g: C.group_vertices(gj, g) for g in joints}
    # body keys: rebuild the human with changed macros
    for name, (desc, change, strength) in morphs.BODY.items():
        bm2, _ = C.create_human(C.macro_dict(**change), rig=False)
        co2 = C.all_coords(bm2)
        d = (co2 - base) * strength
        # fade out on the head (face keys own it); helpers by height
        f = 1.0 - C.smoothstep(0.0, 0.85, head_w)
        f[hel] = 1.0 - C.smoothstep(nz + 0.6 * (hz - nz), hz + 0.02, base[hel, 2])
        d *= f[:, None]
        out[name] = d
        js = sorted(((float(np.linalg.norm(d[ix].mean(axis=0))), g) for g, ix in jidx.items()), reverse=True)
        log("body key %-14s max %.1f mm; joint shifts (mm): %s" % (
            name, np.linalg.norm(d, axis=1).max() * 1000, ", ".join("%s %.1f" % (g[6:], s * 1000) for s, g in js[:6])))
    C.npz_save(OUTF, base=base, head_w=head_w, neck_w=neck_w, **out)
    log("deltas written", OUTF, "%.1fs" % (__import__("time").time() - t0))
    return OUTF


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    run(force="--force" in argv or bool(os.environ.get("MAYDON_FORCE")))
