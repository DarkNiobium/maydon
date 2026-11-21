import sys, numpy as np, process as P, mlib as M
for rel in sys.argv[1:]:
    src, kind = P.load_src(rel)
    r = 0.894 / M.leg_len_src(src, kind)
    S = M.SPEC[kind]
    out = []
    for side in 'rl':
        toe = src.P(S['leg'][side][3]) * r
        sp = M.gauss1d(np.linalg.norm(np.gradient(toe, axis=0), axis=-1) * src.fps, src.fps * 0.01)
        hc = P.hip_center(src, kind) * r
        # local peaks above 7 m/s
        i = 1
        while i < len(sp) - 1:
            if sp[i] > 7.0 and sp[i] >= sp[max(0, i - int(0.15 * src.fps)):i + int(0.15 * src.fps)].max():
                hv = np.linalg.norm(np.gradient(hc, axis=0)[i, :2]) * src.fps
                out.append((i / src.fps, side, sp[i], toe[i, 2] - toe[:, 2].min(), hv))
                i += int(0.3 * src.fps)
            i += 1
    out.sort()
    print(rel, '%.1fs' % (src.F / src.fps))
    for t, sd, v, z, hv in out:
        print('   t=%.2f %s toe %.1f m/s  toe_h %.2f  hips %.1f m/s' % (t, sd, v, z, hv))
