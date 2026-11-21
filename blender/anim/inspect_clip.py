"""Print a timeline summary of a BVH clip: hips position/speed/facing, foot heights/speeds.
Usage: python3 inspect_clip.py <bvh> [step_s] [t0] [t1]"""
import sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mlib as M


def kind_of(path):
    for k in ('cmu', 'accad', 'cologne', '100style'):
        if '/%s/' % k in path:
            return k
    return 'cmu'


def main():
    path = sys.argv[1]
    step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
    kind = kind_of(path)
    s = M.source_from_bvh(path, skip_first=(kind == 'cmu'))
    if kind == 'accad' and not s.has('ToSpine'):
        kind = 'cologne'
    legs = M.LEGS[kind]
    ratio = 0.894 / M.leg_len_src(s, kind)
    t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    t1 = float(sys.argv[4]) if len(sys.argv) > 4 else s.F / s.fps
    hr, hl = M.FRAME_REF[kind]['hips']
    hc = 0.5 * (s.P(hl) + s.P(hr)) * ratio
    lat = s.P(hr) - s.P(hl)  # right - left ... facing = cross(left, up)
    left = -lat
    fwd = np.cross(left, M.UP)
    fz = np.percentile(np.minimum(s.P(legs['l'][2])[:, 2], s.P(legs['r'][2])[:, 2]), 5)
    print('%s kind=%s F=%d fps=%.1f dur=%.2fs ratio=%.4f' % (os.path.basename(path), kind, s.F, s.fps, s.F / s.fps, ratio))
    vel = np.gradient(M.gauss1d(hc, s.fps * 0.05), axis=0) * s.fps
    aL = s.P(legs['l'][2]) * ratio
    aR = s.P(legs['r'][2]) * ratio
    tL = s.P(legs['l'][3]) * ratio
    tR = s.P(legs['r'][3]) * ratio
    vR = np.linalg.norm(np.gradient(tR, axis=0), axis=-1) * s.fps
    vL = np.linalg.norm(np.gradient(tL, axis=0), axis=-1) * s.fps
    head = s.P('Head') * ratio
    print('  t     x      y      z(hc)  spd   vdir  face  | aL_z  aR_z  tL_z  tR_z | vtoeL vtoeR | headz')
    fl = fz * ratio
    t = t0
    while t < t1:
        i = min(int(t * s.fps), s.F - 1)
        f = fwd[i]
        face = math.degrees(math.atan2(f[0], -f[1]))
        v = vel[i]
        vd = math.degrees(math.atan2(v[0], -v[1]))
        print('%5.2f %6.2f %6.2f %5.2f %5.2f %5.0f %5.0f | %5.2f %5.2f %5.2f %5.2f | %5.2f %5.2f | %5.2f' % (
            t, hc[i, 0], hc[i, 1], hc[i, 2] - fl, np.linalg.norm(v[:2]), vd, face,
            aL[i, 2] - fl, aR[i, 2] - fl, tL[i, 2] - fl, tR[i, 2] - fl, vL[i], vR[i], head[i, 2] - fl))
        t += step


if __name__ == '__main__':
    main()
