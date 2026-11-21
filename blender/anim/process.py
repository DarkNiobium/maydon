"""process.py -- retarget/clean clips into cache/<name>.npz (plain python3, numpy only).

Usage: python3 process.py [clip names...]   (no names = all clips in clips.CLIPS)
Each cache file holds local quaternions L (F,B,4) for every bone of the game_engine rig,
pelvis location (F,3) in pelvis-local rest space, and a JSON meta string."""
import sys, os, json, math
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mlib as M

RAW = os.path.expanduser('~/maydon/raw/anim')
CACHE = os.path.join(HERE, 'cache')
FPS = 30.0
os.makedirs(CACHE, exist_ok=True)

DIRS = {'fwd': np.array([0, -1.0, 0]), 'back': np.array([0, 1.0, 0]),
        'left': np.array([1.0, 0, 0]), 'right': np.array([-1.0, 0, 0])}


def load_rig():
    d = json.load(open(os.path.join(HERE, 'rig.json')))
    return M.Rig(d['names'], d['parents'], d['head'], d['tail'], d['rest_q'])


RIG = load_rig()


def kind_of(path, src=None):
    for k in ('cmu', 'accad', 'cologne', '100style', 'mixamo'):
        if '/%s/' % k in path or path.startswith(k + '/'):
            if k == 'accad' and src is not None and not src.has('ToSpine'):
                return 'cologne'
            return k
    raise ValueError(path)


_SRC_CACHE = {}
_CAL_CACHE = {}


MIXAMO_CAL = 'mixamo/bvh/idle_breathing.bvh'   # every Mixamo export shares the X Bot skeleton


def get_cal(rel, c_gen=None, c_foot=None):
    if rel.startswith('mixamo/') and rel != MIXAMO_CAL and c_gen is None and c_foot is None \
            and os.path.exists(os.path.join(RAW, MIXAMO_CAL)):
        return get_cal(MIXAMO_CAL)
    key = (rel, c_gen, tuple(sorted(c_foot.items())) if c_foot else None)
    if key not in _CAL_CACHE:
        src, kind = load_src(rel)
        _CAL_CACHE[key] = M.calibrate(src, RIG, kind, c_gen=c_gen, c_foot=c_foot)
        cal = _CAL_CACHE[key]
        print('  calib %s: c_gen=%.2fs feet=%s' % (rel, cal.c_gen / src.fps, {k: round(v / src.fps, 2) for k, v in cal.c_foot.items()}))
    return _CAL_CACHE[key]


# CMU subjects captured at 60 Hz although Hahne's BVH header says 120 fps
# (gait check: walk strides of 0.55-0.69 s at 120 fps are physically impossible)
FPS_FIX = {'cmu/139/': 60.0, 'cmu/141/': 60.0, 'cmu/143/': 60.0}


def load_src(rel):
    if rel in _SRC_CACHE:
        return _SRC_CACHE[rel]
    path = os.path.join(RAW, rel)
    k0 = kind_of(rel)
    if path.endswith('.bvh'):
        s = M.source_from_bvh(path, skip_first=(k0 == 'cmu'), label=rel)
        for pre, fps in FPS_FIX.items():
            if rel.startswith(pre):
                s.fps = fps
    else:
        raise ValueError('use load_glb for ' + rel)
    kind = kind_of(rel, s)
    _SRC_CACHE[rel] = (s, kind)
    return s, kind


def hip_center(src, kind):
    r, l = M.FRAME_REF[kind]['hips']
    return 0.5 * (src.P(r) + src.P(l))


def facing(src, kind):
    r, l = M.FRAME_REF[kind]['hips']
    left = src.P(l) - src.P(r)
    left[:, 2] = 0
    f = np.cross(M.unit(left), M.UP)
    return M.unit(f)


def chest_facing(src, kind):
    r, l = M.FRAME_REF[kind]['chest']
    left = src.P(l) - src.P(r)
    left[:, 2] = 0
    return M.unit(np.cross(M.unit(left), M.UP))


def save(name, mo, meta, closed_loop=False):
    L, loc = mo.to_local()
    meta = dict(meta)
    meta['frames'] = int(L.shape[0])
    meta['fps'] = FPS
    np.savez_compressed(os.path.join(CACHE, name + '.npz'), L=L.astype(np.float32), loc=loc.astype(np.float32),
                        meta=json.dumps(meta))
    print('saved %-14s frames=%d %s' % (name, L.shape[0], {k: v for k, v in meta.items() if k in ('speed', 'duration', 'contact_time', 'src')}))


def load_cached(name):
    d = np.load(os.path.join(CACHE, name + '.npz'))
    return d['L'].astype(float), d['loc'].astype(float), json.loads(str(d['meta']))


# ---------------------------------------------------------------- foot contact lock

HEEL_OFF = M.SOLE['heel']


def _segments(flags, period):
    F = len(flags)
    rs = [list(r) for r in M.runs(flags)]
    segs = []
    if period and rs and rs[0][0] == 0 and rs[-1][1] >= F - 1 and len(rs) >= 1:
        if len(rs) == 1:
            return [np.arange(0, F)], True
        a, b = rs[-1], rs[0]
        segs.append(np.r_[np.arange(a[0], F - 1), np.arange(0, b[1])])
        rs = rs[1:-1]
    for a, b in rs:
        segs.append(np.arange(a, b))
    return segs, False


def lock_feet(mo, side, v, period=False, zth=0.035, vth=0.5, edge=2, min_len=3):
    """Foot plant cleanup. During contact the heel and/or ball points are pinned in world
    space (world = in-place + v*t) to their rest heights, and the foot rotation is pinned to
    the segment mean while the foot is flat. The ankle IK target is derived from the pins."""
    rig = mo.rig
    F = mo.F
    T = (F - 1) / mo.fps
    t = np.arange(F) / mo.fps
    vv = np.array([v[0], v[1], 0.0])
    vth = max(vth, 0.3 * float(np.linalg.norm(vv[:2])))
    H = mo.heads()
    heel, ball, toe = M.sole_points(mo, side, H)
    dt = 1.0 / mo.fps
    def hspeed(p):
        g = np.gradient(p, axis=0) / dt + vv
        if period:  # wrap-consistent derivative at the seam
            g[0] = g[-1] = ((p[1] - p[-2]) / (2 * dt)) + vv
        return np.linalg.norm(g[:, :2], axis=-1)
    c_heel = (heel[:, 2] < zth) & (hspeed(heel) < vth)
    c_ball = (ball[:, 2] < zth) & (hspeed(ball) < vth)
    if period:
        c_heel[-1] = c_heel[0]
        c_ball[-1] = c_ball[0]
    flags = c_heel | c_ball
    segs, full = _segments(flags, period)
    ft = rig.i('foot_' + side)
    bl = rig.i('ball_' + side)
    ball_off = rig.head[bl] - rig.head[ft] + np.array([0, 0, -0.008])
    heel_z = (rig.head[ft] + HEEL_OFF)[2]
    ball_z = (rig.head[bl] + np.array([0, 0, -0.008]))[2]
    tgt = mo.ank_target[side].copy()
    newt = tgt.copy()
    dqf = mo.dq[:, ft].copy()
    dqb = mo.dq[:, bl].copy()
    for idx in segs:
        if len(idx) < min_len:
            continue
        # times unwrapped across the seam
        tt = t[idx].copy()
        if period and not full:
            seam = np.where(np.diff(idx) < 0)[0]
            if len(seam):
                tt[:seam[0] + 1] -= T
        n = len(idx)
        w = np.ones(n)
        if not full:
            e = min(edge if n > 7 else 1, n // 2)
            for k in range(e):
                w[k] = w[n - 1 - k] = (k + 1) / (e + 1)
        ch = c_heel[idx]
        cb = c_ball[idx]
        flat = ch & cb
        # pin foot rotation (mean over flat frames) -- toe bone follows
        if flat.sum() >= 2:
            qm = M.qn(M.qcontinuous(dqf[idx][flat]).mean(0))
            wf = w * flat
            # soften: ramp the rotation pin in/out over neighbouring frames
            wf = np.maximum(wf, np.convolve(wf, [0.25, 0.5, 0.25], 'same') * 0.999)
            corr_new = M.qslerp(dqf[idx], np.repeat(qm[None], n, 0), wf)
            dloc = M.qmul(corr_new, M.qinv(dqf[idx]))
            dqf[idx] = corr_new
            dqb[idx] = M.qn(M.qmul(dloc, dqb[idx]))
        wh = heel[idx] + np.outer(tt, vv)
        wb = ball[idx] + np.outer(tt, vv)
        hp = wh[ch].mean(0) if ch.any() else None
        bp = wb[cb].mean(0) if cb.any() else None
        for k, i in enumerate(idx):
            cands = []
            if ch[k] and hp is not None:
                pin = hp.copy(); pin[2] = heel_z
                cands.append(pin - np.outer(tt[k], vv)[0] - M.qrot(dqf[i], HEEL_OFF))
            if cb[k] and bp is not None:
                pin = bp.copy(); pin[2] = ball_z
                cands.append(pin - np.outer(tt[k], vv)[0] - M.qrot(dqf[i], ball_off))
            if cands:
                a = np.mean(cands, 0)
                newt[i] = a * w[k] + tgt[i] * (1 - w[k])
    if period:
        newt[-1] = newt[0]
        dqf[-1] = dqf[0]
        dqb[-1] = dqb[0]
    mo.ank_target[side] = newt
    mo.dq[:, ft] = dqf
    mo.dq[:, bl] = dqb
    return segs


# ---------------------------------------------------------------- loops

def find_strikes(mo, side, v=None, min_gap=0.25):
    """Heel strikes = ends of swing phases (foot world speed high) of a world-space motion."""
    H = mo.heads()
    heel, ball, toe = M.sole_points(mo, side, H)
    p = 0.5 * (heel + ball)
    vel = np.gradient(p, axis=0) * mo.fps
    if v is not None:
        vel = vel + np.array([v[0], v[1], 0])
    sp = M.gauss1d(np.linalg.norm(vel[:, :2], axis=-1), max(1.0, 0.01 * mo.fps))
    thr = 0.35 * np.percentile(sp, 95)
    swing = sp > thr
    rs = [r for r in M.runs(swing) if (r[1] - r[0]) / mo.fps >= 0.08]
    strikes = []
    for a, b in rs:
        if b >= mo.F:
            continue
        # refine: first frame after swing end where the foot is lowest within 0.1 s
        w = int(0.08 * mo.fps)
        seg = p[b:b + w, 2]
        k = b + (int(np.argmin(seg)) if len(seg) else 0)
        if strikes and (k - strikes[-1]) / mo.fps < min_gap:
            continue
        strikes.append(k)
    return strikes, rs


def pose_distance(moA, i, j):
    """Mismatch between frames i and j (local rotations of main bones + pelvis height)."""
    L, loc = moA.to_local()
    main = [RIG.i(b) for b in M.TARGET_CHAIN if b != 'pelvis']
    d = M.qangle(M.qmul(M.qinv(L[i, main]), L[j, main]))
    return float(np.degrees(d).mean() + 100 * abs(moA.pelvis[i, 2] - moA.pelvis[j, 2]))


def process_loop(name, rel, t_range, direction='fwd', strides=1, smooth=0.012, pick=None, extra_meta=None,
                 hand_fix=None, post=None, tweak=None, c_gen=None, c_foot=None, hscale=1.0, tscale=1.0,
                 mirror=False):
    src, kind = load_src(rel)
    cal = get_cal(rel, c_gen, c_foot)
    t0, t1 = t_range
    fr = slice(int(t0 * src.fps), int(t1 * src.fps))
    sub = src.copy_frames(fr)
    hc = hip_center(sub, kind)
    disp = hc[-1] - hc[0]
    disp[2] = 0
    sdir = {'left': 'right', 'right': 'left'}.get(direction, direction) if mirror else direction
    if direction == 'none':
        f = facing(sub, kind).mean(0)
        yaw = M.yaw_to(f, DIRS['fwd'])
    else:
        yaw = M.yaw_to(disp, DIRS[sdir])
    sub = sub.transformed(yaw=yaw)
    # pass 1: retarget at source rate to find right-foot strikes
    mo1 = M.retarget(sub, RIG, kind, cal, ik=True)
    v1 = (mo1.pelvis[-1] - mo1.pelvis[0]) / ((sub.F - 1) / sub.fps)
    if direction == 'none':
        strikes = []
    else:
        strikes, _ = find_strikes(mo1, 'r')
    if isinstance(pick, tuple) and pick[0] == 'auto':
        # best window of the requested length (pose mismatch + horizontal drift)
        L1, _ = mo1.to_local()
        main = [RIG.i(b) for b in M.TARGET_CHAIN if b != 'pelvis']
        n = int(round(pick[1] * sub.fps))
        step = max(1, int(sub.fps / 30))
        best = None
        for i in range(0, sub.F - n - 1, step):
            j = i + n
            d = float(np.degrees(M.qangle(M.qmul(M.qinv(L1[i, main]), L1[j, main]))).mean())
            d += 100 * abs(mo1.pelvis[i, 2] - mo1.pelvis[j, 2]) + 50 * np.linalg.norm(mo1.pelvis[i, :2] - mo1.pelvis[j, :2])
            # prefer windows where the feet stay planted (idle)
            if best is None or d < best[0]:
                best = (d, i, j)
        a_t, b_t = best[1] / sub.fps, best[2] / sub.fps
        print('  %s auto window %.2f..%.2f (src) mismatch %.2f' % (name, a_t + t0, b_t + t0, best[0]))
    elif pick is not None:
        a_t, b_t = pick
        a_t -= t0
        b_t -= t0
    else:
        # candidate cycles: strike k -> strike k+strides
        best = None
        for k in range(len(strikes) - strides):
            i, j = strikes[k], strikes[k + strides]
            dur = (j - i) / sub.fps
            if dur < 0.25:
                continue
            d = pose_distance(mo1, i, j)
            if best is None or d < best[0]:
                best = (d, i, j)
        if best is None:
            raise RuntimeError('%s: no cycle found, strikes=%s' % (name, strikes))
        a_t, b_t = best[1] / sub.fps, best[2] / sub.fps
        print('  %s strikes(s)=%s pick %.3f..%.3f (src %.3f..%.3f) mismatch %.1f' % (
            name, [round(s / sub.fps + t0, 2) for s in strikes], a_t, b_t, a_t + t0, b_t + t0, best[0]))
    dur = b_t - a_t
    N = max(2, int(round(dur * tscale * FPS)))
    times = a_t + np.arange(N + 1) * (dur / N)
    cyc = sub.sample(times, smooth_sigma_s=smooth)
    cyc.fps = N / dur  # true sample rate of the warped grid; we play it back at 30
    if hscale != 1.0:  # longer strides: scale horizontal positions (IK lengthens the reach)
        hc0 = hip_center(cyc, kind).mean(0)
        cyc.pos[..., :2] = (cyc.pos[..., :2] - hc0[:2]) * hscale + hc0[:2]
        for k in cyc.ends:
            cyc.ends[k] = (cyc.ends[k][0], (cyc.ends[k][1] - np.r_[hc0[:2], 0]) * np.r_[hscale, hscale, 1] + np.r_[hc0[:2], 0])
    mo = M.retarget(cyc, RIG, kind, cal, ik=False)
    mo.fps = FPS
    if mirror:
        mo = M.mirror_motion(mo)
    T = N / FPS
    hcm = mo.pelvis
    v = (hcm[-1] - hcm[0]) / T
    v[2] = 0
    if direction == 'none':
        pass
    M.remove_trend(mo, v)
    # center horizontally (pelvis mean at origin)
    c = mo.pelvis[:, :2].mean(0)
    mo.pelvis[:, :2] -= c
    for s in 'lr':
        mo.ank_target[s][:, :2] -= c
        mo.toe_src[s][:, :2] -= c
    # loop close (rotations + pelvis), IK targets closed linearly
    w = np.linspace(0, 1, mo.F)[:, None]
    for s in 'lr':
        err = mo.ank_target[s][0] - mo.ank_target[s][-1]
        mo.ank_target[s] = mo.ank_target[s] + w * err[None]
    keep = (mo.ank_target, mo.toe_src, mo.pole)
    mo = M.loop_close(mo)
    mo.ank_target, mo.toe_src, mo.pole = keep
    if tweak:
        tweak(mo)
    # IK, contact lock, IK again, ground
    for s in 'lr':
        M.leg_ik(mo, s, mo.ank_target[s])
    v_lock = v if direction != 'none' else np.zeros(3)
    for s in 'lr':
        lock_feet(mo, s, v_lock, period=True)
    M.reach_fix(mo, period=True)
    for s in 'lr':
        M.leg_ik(mo, s, mo.ank_target[s], soft=0.999)
    M.ground_fix(mo)
    if direction != 'none':
        swing_clearance(mo, v)
    if hand_fix:
        hand_fix(mo)
    if post:
        post(mo)
    # final exact closure of the last frame
    mo.dq[-1] = mo.dq[0]
    mo.pelvis[-1] = mo.pelvis[0]
    if mirror and direction != 'none':
        roll_to_strike(mo, 'r', v)
    speed = float(np.linalg.norm(v[:2])) if direction != 'none' else 0.0
    meta = dict(type='loop', src=rel, kind=kind, src_range=[round(a_t + t0, 3), round(b_t + t0, 3)],
                speed=round(speed, 3), duration=round(T, 4), cycle_frames=N, direction=direction,
                ratio=round(mo.meta['ratio'], 5), velocity=[round(float(x), 3) for x in v[:2]])
    if extra_meta:
        meta.update(extra_meta)
    slide = foot_slide_report(mo, v if direction != 'none' else np.zeros(3))
    meta['foot_slide_mm'] = slide
    save(name, mo, meta)
    return mo, meta


def swing_clearance(mo, v, clearance=0.02, period=True):
    """Keep fast-moving (swing) feet off the floor so toes don't scrape."""
    vv = np.array([v[0], v[1], 0.0])
    for s in 'lr':
        H = mo.heads()
        heel, ball, toe = M.sole_points(mo, s, H)
        low = np.minimum(np.minimum(heel[:, 2], ball[:, 2]), toe[:, 2])
        spd = np.linalg.norm((np.gradient(ball, axis=0) * mo.fps + vv)[:, :2], axis=-1)
        w = M.smoothstep(spd, 1.2, 2.5)
        lift = np.maximum(clearance * w - low, 0)
        if lift.max() < 1e-4:
            continue
        lift = np.maximum(M.gauss1d(lift, 1.0, mode='wrap' if period else 'nearest'), lift)
        tgt = H[:, mo.rig.i('foot_' + s)].copy()
        tgt[:, 2] += lift
        mo.ank_target[s] = tgt
        M.leg_ik(mo, s, tgt, soft=0.999)


def roll_to_strike(mo, side, v):
    """Rotate a closed loop (frame N == frame 0) so that frame 0 is a heel strike of `side`."""
    N = mo.F - 1
    t = np.arange(mo.F) / mo.fps
    world = mo.copy()
    world.pelvis = mo.pelvis + np.outer(t, [v[0], v[1], 0])
    # tile twice so a strike near the seam is found
    big = M.Motion(mo.rig, np.concatenate([mo.dq[:N], mo.dq[:N], mo.dq[:1]]),
                   np.concatenate([world.pelvis[:N], world.pelvis[:N] + np.array([v[0], v[1], 0]) * N / mo.fps,
                                   world.pelvis[:1] + np.array([v[0], v[1], 0]) * 2 * N / mo.fps]), mo.fps)
    st, _ = find_strikes(big, side)
    st = [k for k in st if 2 <= k < N + 2]
    if not st:
        return 0
    k = st[0] % N
    if k == 0:
        return 0
    idx = (np.arange(N) + k) % N
    dq = mo.dq[idx]
    pel = mo.pelvis[idx]
    mo.dq = np.concatenate([dq, dq[:1]])
    mo.pelvis = np.concatenate([pel, pel[:1]])
    print('  rolled loop by %d frames to %s strike' % (k, side))
    return k


def foot_slide_report(mo, v):
    """Max horizontal world drift (mm) of the heel (heel contact) / ball (ball contact) per contact."""
    out = {}
    t = np.arange(mo.F) / mo.fps
    vv = np.array([v[0], v[1], 0.0])
    H = mo.heads()
    for s in 'lr':
        heel, ball, toe = M.sole_points(mo, s, H)
        _, c_heel, c_ball = M.contacts(mo, s, vel_world=vv, zth=0.03, vth=max(0.4, 0.3 * float(np.linalg.norm(vv[:2]))))
        worst = 0.0
        for pts, c in ((heel, c_heel), (ball, c_ball)):
            for a, b in M.runs(c):
                if b - a < 3:
                    continue
                wpos = pts[a:b] + np.outer(t[a:b], vv)
                worst = max(worst, float(np.max(np.linalg.norm(wpos[:, :2] - wpos[:, :2].mean(0), axis=-1))))
        out[s] = round(worst * 1000, 1)
    return out


# ---------------------------------------------------------------- one-shots

def process_oneshot(name, rel, t_range, align='start', contact=None, smooth=0.01, root_sigma=0.12,
                    inplace=True, extra_meta=None, tweak=None, post=None, ik=True, floor=None, yaw_extra=0.0,
                    c_gen=None, c_foot=None):
    src, kind = load_src(rel)
    cal = get_cal(rel, c_gen, c_foot)
    t0, t1 = t_range
    N = int(round((t1 - t0) * FPS))
    times = t0 + np.arange(N + 1) / FPS
    sub = src.sample(times, smooth_sigma_s=smooth)
    sub.fps = FPS
    # heading
    if align == 'start':
        f = facing(sub, kind)[:5].mean(0)
    elif align == 'end':
        f = facing(sub, kind)[-5:].mean(0)
    elif align == 'mean':
        f = facing(sub, kind).mean(0)
    elif align == 'travel':
        hc = hip_center(sub, kind)
        f = hc[-1] - hc[0]
        f[2] = 0
    elif isinstance(align, tuple) and align[0] == 'at':
        i = int(round((align[1] - t0) * FPS))
        f = facing(sub, kind)[max(0, i - 2):i + 3].mean(0)
    elif isinstance(align, tuple) and align[0] == 'vel':
        # direction of a source point's velocity at time align[2] (e.g. kicking toe at contact)
        jn = M.SPEC[kind]['leg']['r'][4] if align[1] == 'toe_r' else align[1]
        i = int(round((align[2] - t0) * FPS))
        p = sub.P(jn)
        f = p[min(i + 1, sub.F - 1)] - p[max(i - 1, 0)]
        f[2] = 0
    elif isinstance(align, tuple) and align[0] == 'chest_at':
        i = int(round((align[1] - t0) * FPS))
        f = chest_facing(sub, kind)[max(0, i - 2):i + 3].mean(0)
    else:
        raise ValueError(align)
    yaw = M.yaw_to(f, DIRS['fwd']) + math.radians(yaw_extra)
    sub = sub.transformed(yaw=yaw)
    # full-clip floor from the whole source (more robust than from a short window)
    mo = M.retarget(sub, RIG, kind, cal, ik=False, floor=floor)
    mo.fps = FPS
    world = mo.copy()
    world.ank_target = {s: v.copy() for s, v in mo.ank_target.items()}
    world.toe_src = {s: v.copy() for s, v in mo.toe_src.items()}
    world.pole = mo.pole
    # root trajectory: smoothed horizontal hip-centre path
    hc_rest = 0.5 * (RIG.head[RIG.i('thigh_l')] + RIG.head[RIG.i('thigh_r')])
    pi = RIG.i('pelvis')
    hc = mo.pelvis - M.qrot(mo.dq[:, pi], (RIG.head[pi] - hc_rest)[None])
    traj = M.gauss1d(hc, root_sigma * FPS)
    traj[:, 2] = 0
    start = traj[0].copy()
    shift = traj if inplace else np.repeat(start[None], mo.F, 0)
    mo.pelvis = mo.pelvis - shift
    for s in 'lr':
        mo.ank_target[s] = mo.ank_target[s] - shift
        mo.toe_src[s] = mo.toe_src[s] - shift
    if tweak:
        tweak(mo)
    if ik:
        M.reach_fix(mo)
        for s in 'lr':
            M.leg_ik(mo, s, mo.ank_target[s], soft=0.999)
        M.ground_fix(mo)
    if post:
        post(mo)
    rm = traj - start  # root motion in character space at start (x right=-X ... see ANIMS.md)
    meta = dict(type='oneshot', src=rel, kind=kind, src_range=[t0, t1], duration=round(N / FPS, 4),
                ratio=round(mo.meta['ratio'], 5))
    meta['root_motion'] = root_motion_meta(rm)
    if contact is not None:
        ct = contact(world, mo) if callable(contact) else contact
        if ct is not None:
            meta['contact_time'] = round(float(ct), 3)
    if extra_meta:
        meta.update(extra_meta)
    save(name, mo, meta)
    return mo, meta, world


def root_motion_meta(rm):
    """Root motion in Godot character space: +X = character's left, +Z = character forward (Blender -Y)."""
    gx = rm[:, 0]
    gz = -rm[:, 1]
    tot = [round(float(gx[-1]), 3), 0.0, round(float(gz[-1]), 3)]
    return dict(total=tot, x=[round(float(a), 3) for a in gx], z=[round(float(a), 3) for a in gz])


# ---------------------------------------------------------------- contact detectors

def peak_speed_time(bone, side=None, window=None, point='tail'):
    def f(world, mo):
        H = world.heads()
        T = world.tails(H)
        b = RIG.i(bone)
        p = T[:, b] if point == 'tail' else H[:, b]
        vel = np.linalg.norm(np.gradient(p, axis=0), axis=-1) * FPS
        lo, hi = 0, world.F
        if window:
            lo, hi = int(window[0] * FPS), int(window[1] * FPS)
        i = lo + int(np.argmax(vel[lo:hi]))
        return i / FPS
    return f


def apex_time(bone='head'):
    def f(world, mo):
        H = world.heads()
        b = RIG.i(bone)
        return int(np.argmax(H[:, b, 2])) / FPS
    return f


if __name__ == '__main__':
    import clips
    names = sys.argv[1:] or list(clips.CLIPS.keys())
    for n in names:
        clips.CLIPS[n]()
