import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlib as M
from inspect_clip import kind_of
for path in sys.argv[1:]:
    kind = kind_of(path)
    s = M.source_from_bvh(path, skip_first=(kind == 'cmu'))
    if kind == 'accad' and not s.has('ToSpine'): kind = 'cologne'
    ratio = 0.894 / M.leg_len_src(s, kind)
    legs = M.LEGS[kind]
    z = (s.P(legs['r'][2])[:, 2] - s.P(legs['l'][2])[:, 2])
    z = z - z.mean()
    ac = np.correlate(z, z, 'full')[len(z) - 1:]
    ac /= ac[0]
    lo = int(0.25 * s.fps)
    # first peak after lo
    k = lo + int(np.argmax(ac[lo:int(min(len(ac) - 1, 2.0 * s.fps))]))
    hr, hl = M.FRAME_REF[kind]['hips']
    hc = 0.5 * (s.P(hl) + s.P(hr)) * ratio
    w = max(1, int(0.5 * s.fps))
    v = np.median(np.linalg.norm(hc[w:, :2] - hc[:-w, :2], axis=-1) / (w / s.fps))
    print('%-40s stride %.2fs  v50 %.2f  stride_len %.2f m' % (path.split('anim/')[-1], k / s.fps, v, v * k / s.fps))
