"""Survey clips: target-scale speeds. Usage: python3 survey.py files..."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlib as M
from inspect_clip import kind_of
for path in sys.argv[1:]:
    kind = kind_of(path)
    try:
        s = M.source_from_bvh(path, skip_first=(kind == 'cmu'))
    except Exception as e:
        print(path, 'ERR', e); continue
    if kind == 'accad' and not s.has('ToSpine'):
        kind = 'cologne'
    if kind == 'accad' and not s.has('Hips'):
        print(path, 'skip (asf names)'); continue
    ratio = 0.894 / M.leg_len_src(s, kind)
    hr, hl = M.FRAME_REF[kind]['hips']
    hc = 0.5 * (s.P(hl) + s.P(hr)) * ratio
    w = max(1, int(0.5 * s.fps))
    v = np.linalg.norm((hc[w:, :2] - hc[:-w, :2]), axis=-1) / (w / s.fps)
    print('%-60s %-8s dur %5.2f  v50 %4.2f v90 %4.2f vmax %4.2f  ratio %.4f' % (path.split('anim/')[-1], kind, s.F / s.fps,
          np.percentile(v, 50), np.percentile(v, 90), v.max(), ratio))
