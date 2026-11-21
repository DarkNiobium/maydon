import sys, numpy as np, process as P, mlib as M
for a in sys.argv[1:]:
    rel, step = (a.split('@') + ['0.2'])[:2]
    src, kind = P.load_src(rel)
    r = 0.894 / M.leg_len_src(src, kind)
    S = M.SPEC[kind]
    hl = src.P(S['arm']['l'][3]) * r; hr = src.P(S['arm']['r'][3]) * r
    hc = P.hip_center(src, kind) * r
    fz = np.percentile(np.minimum(src.P(S['leg']['l'][2])[:, 2], src.P(S['leg']['r'][2])[:, 2]), 5) * r
    vr = np.linalg.norm(np.gradient(hr, axis=0), axis=-1) * src.fps
    vl = np.linalg.norm(np.gradient(hl, axis=0), axis=-1) * src.fps
    print(rel, 'fps', src.fps, 'dur', round(src.F / src.fps, 2))
    print('   t   handR_z handL_z  dist  vR   vL   hips_z  hips_xy')
    for t in np.arange(0, src.F / src.fps, float(step)):
        i = int(t * src.fps)
        print('  %5.2f  %5.2f  %5.2f  %5.2f %5.1f %5.1f  %5.2f  %5.2f %5.2f' % (t, hr[i, 2] - fz, hl[i, 2] - fz, np.linalg.norm(hr[i] - hl[i]), vr[i], vl[i], hc[i, 2] - fz, hc[i, 0], hc[i, 1]))
