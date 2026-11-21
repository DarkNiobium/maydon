import sys, numpy as np, process as P, mlib as M
for rel in sys.argv[1:]:
    src, kind = P.load_src(rel)
    ratio = 0.894 / M.leg_len_src(src, kind)
    hc = P.hip_center(src, kind) * ratio
    f = P.facing(src, kind)
    w = max(1, int(0.25 * src.fps))
    v = (hc[w:] - hc[:-w]) / (w / src.fps)
    out = []
    for t in np.arange(0, (src.F - w) / src.fps, 0.25):
        i = int(t * src.fps)
        vi = v[i, :2]; sp = np.linalg.norm(vi)
        fi = f[i, :2]
        # signed angle of velocity relative to facing: +90 = moving to character's left
        ang = np.degrees(np.arctan2(fi[0] * vi[1] - fi[1] * vi[0], fi[0] * vi[0] + fi[1] * vi[1]))
        out.append('%.2f:%.1f@%+.0f' % (t, sp, ang))
    print(rel, src.F / src.fps, 's')
    print('   ', ' '.join(out))
