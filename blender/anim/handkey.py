"""handkey.py -- hand-keyed clips on the game_engine rig.

A clip is a list of keys (time_s, pose). A pose maps bone -> (rx, ry, rz) degrees about the body
axes carried by the parent (X = character left, Y = character back, Z = up), applied on top of a
base pose (a natural standing frame taken from the retargeted idle). Special entries:
  'pelvis_pos': (dx, dy, dz) metres, world offset of the pelvis from the base pose
  'pelvis':     (rx, ry, rz) rotation of the pelvis about world axes (pre-multiplied)
  'plant_l' / 'plant_r': 0..1, keep that foot pinned at its base position (IK)
  'hinge:<bone>': degrees about the bone's rest hinge axis (elbows), + = more flexion
Channels are interpolated with a C1 cubic Hermite spline (Catmull-Rom style tangents, eased ends),
which gives smooth arcs and ease-in/out on held keys.
"""
import math
import numpy as np
import mlib as M
import process as P

RIG = P.RIG
FPS = 30.0


def hinge_axis(bone):
    """Rest-space flexion axis for an elbow (lowerarm_*) or knee (calf_*)."""
    r = RIG
    if bone.startswith('lowerarm'):
        s = bone[-1]
        ua = r.head[r.i('lowerarm_' + s)] - r.head[r.i('upperarm_' + s)]
        fa = r.head[r.i('hand_' + s)] - r.head[r.i('lowerarm_' + s)]
        ax = M.unit(np.cross(ua, fa))
        return ax
    if bone.startswith('calf'):
        return np.array([1.0, 0, 0])
    raise ValueError(bone)


def axis_q(bone, axis, deg):
    b = RIG.i(bone)
    rq = RIG.rest_q[b]
    q = M.qaxis(axis, math.radians(deg))
    return M.qmul(M.qmul(M.qinv(rq), q), rq)


def spline(times, values, tq):
    """C1 cubic Hermite through (times, values); flat tangents at the ends and at local extrema
    (prevents overshoot on holds)."""
    t = np.asarray(times, float)
    v = np.asarray(values, float)
    n = len(t)
    if n == 1:
        return np.full(len(tq), v[0])
    m = np.zeros(n)
    for k in range(1, n - 1):
        d0 = (v[k] - v[k - 1]) / (t[k] - t[k - 1])
        d1 = (v[k + 1] - v[k]) / (t[k + 1] - t[k])
        if d0 * d1 <= 0:
            m[k] = 0.0
        else:
            m[k] = (v[k + 1] - v[k - 1]) / (t[k + 1] - t[k - 1])
            # limit to avoid overshoot
            m[k] = np.sign(m[k]) * min(abs(m[k]), 3 * min(abs(d0), abs(d1)))
    out = np.empty(len(tq))
    for i, x in enumerate(tq):
        if x <= t[0]:
            out[i] = v[0]
            continue
        if x >= t[-1]:
            out[i] = v[-1]
            continue
        k = np.searchsorted(t, x) - 1
        h = t[k + 1] - t[k]
        s = (x - t[k]) / h
        h00 = 2 * s ** 3 - 3 * s ** 2 + 1
        h10 = s ** 3 - 2 * s ** 2 + s
        h01 = -2 * s ** 3 + 3 * s ** 2
        h11 = s ** 3 - s ** 2
        out[i] = h00 * v[k] + h10 * h * m[k] + h01 * v[k + 1] + h11 * h * m[k + 1]
    return out


def base_pose(name='idle', frame=0):
    L, loc, meta = P.load_cached(name)
    return L[frame].copy(), loc[frame].copy()


def build(keys, duration=None, base=None, base_motion=None):
    """Evaluate keys into a Motion (with ank_target/pole set for planting)."""
    keys = sorted(keys, key=lambda k: k[0])
    T = duration if duration is not None else keys[-1][0]
    N = int(round(T * FPS))
    tq = np.arange(N + 1) / FPS
    F = N + 1
    if base_motion is not None:
        Lb, locb = base_motion.to_local()
    else:
        L0, loc0 = base if base is not None else base_pose()
        Lb = np.repeat(L0[None], F, 0)
        locb = np.repeat(loc0[None], F, 0)
    channels = set()
    for t, pose in keys:
        channels |= set(pose.keys())
    def chan(name, default):
        ts, vs = [], []
        for t, pose in keys:
            ts.append(t)
            vs.append(pose.get(name, default))
        vs = np.array(vs, float)
        if vs.ndim == 1:
            return spline(ts, vs, tq)
        return np.stack([spline(ts, vs[:, c], tq) for c in range(vs.shape[1])], -1)
    L = Lb.copy()
    for ch in channels:
        if ch in ('pelvis_pos', 'plant_l', 'plant_r', 'foot_off_l', 'foot_off_r') or ch.startswith('hinge:') or ch.startswith('z:') or ch == 'pelvis':
            continue
        b = RIG.i(ch)
        ang = chan(ch, (0.0, 0.0, 0.0))
        qs = np.stack([M.body_q(RIG, ch, *a) for a in ang])
        L[:, b] = M.qmul(qs, L[:, b])
    for ch in channels:
        if ch.startswith('hinge:'):
            bone = ch.split(':')[1]
            b = RIG.i(bone)
            ang = chan(ch, 0.0)
            ax = hinge_axis(bone)
            qs = np.stack([axis_q(bone, ax, a) for a in ang])
            L[:, b] = M.qmul(qs, L[:, b])
    for ch in channels:  # extra rotation about the parent-space Z axis applied last (e.g. horizontal adduction)
        if ch.startswith('z:'):
            bone = ch.split(':')[1]
            b = RIG.i(bone)
            ang = chan(ch, 0.0)
            qs = np.stack([M.body_q(RIG, bone, 0, 0, a) for a in ang])
            L[:, b] = M.qmul(qs, L[:, b])
    base_mo = M.Motion.from_local(RIG, Lb, locb, FPS)
    Hb = base_mo.heads()
    if 'pelvis' in channels:
        b = RIG.i('pelvis')
        ang = chan('pelvis', (0.0, 0.0, 0.0))
        qs = np.stack([M.body_q(RIG, 'pelvis', *a) for a in ang])
        L[:, b] = M.qmul(qs, L[:, b])
    mo = M.Motion.from_local(RIG, L, locb, FPS)
    off = chan('pelvis_pos', (0.0, 0.0, 0.0)) if 'pelvis_pos' in channels else np.zeros((F, 3))
    mo.pelvis = base_mo.pelvis + off
    # planting
    H = mo.heads()
    mo.ank_target = {}
    mo.pole = {}
    for s in 'lr':
        w = np.clip(chan('plant_' + s, 1.0), 0, 1) if ('plant_' + s) in channels else np.ones(F)
        fk = H[:, RIG.i('foot_' + s)]
        planted = Hb[:, RIG.i('foot_' + s)]
        if ('foot_off_' + s) in channels:
            planted = planted + chan('foot_off_' + s, (0.0, 0.0, 0.0))
        mo.ank_target[s] = planted * w[:, None] + fk * (1 - w[:, None])
        th = RIG.i('thigh_' + s)
        tdir = M.unit(RIG.head[RIG.i('calf_' + s)] - RIG.head[th])
        fwd = M.unit(M.FWD - np.dot(M.FWD, tdir) * tdir)
        pole_fk = M.qrot(mo.dq[:, th], fwd[None])
        # keep planted feet's knees over the toes
        ft = M.qrot(mo.dq[:, RIG.i('foot_' + s)], (RIG.head[RIG.i('ball_' + s)] - RIG.head[RIG.i('foot_' + s)])[None])
        mo.pole[s] = M.unit(pole_fk * (1 - w[:, None]) + M.unit(ft) * w[:, None] + 1e-6)
        mo.plant_w = getattr(mo, 'plant_w', {})
        mo.plant_w[s] = w
    return mo


def finish(mo, ik=True, ground=True):
    if ik:
        M.reach_fix(mo)
        for s in 'lr':
            M.leg_ik(mo, s, mo.ank_target[s], soft=0.999)
    if ground:
        M.ground_fix(mo)
    return mo


def process(name, keys, contact=None, meta=None, base=None, mirror=False, floor=True, inplace=True,
            root_sigma=0.1, post=None, base_motion=None, duration=None):
    mo = build(keys, base=base, base_motion=base_motion, duration=duration)
    if mirror:
        mo = M.mirror_motion(mo)
        mo.plant_w = {('l' if k == 'r' else 'r'): v for k, v in mo.plant_w.items()} if hasattr(mo, 'plant_w') else {}
    if floor:
        # lift with the keyed (FK) legs first, carry unplanted ankle targets along, then solve IK once
        need = M.body_floor(mo)
        for sd in 'lr':
            w = getattr(mo, 'plant_w', {}).get(sd, np.ones(mo.F))
            mo.ank_target[sd] = mo.ank_target[sd] + ((1 - w) * need)[:, None] * np.array([0, 0, 1.0])
    finish(mo, ground=False)
    if floor:
        M.body_floor(mo)
        finish(mo, ground=False)
    M.ground_fix(mo)
    if post:
        post(mo)
    # root motion (same convention as mocap one-shots)
    pi = RIG.i('pelvis')
    hc_rest = 0.5 * (RIG.head[RIG.i('thigh_l')] + RIG.head[RIG.i('thigh_r')])
    hc = mo.pelvis - M.qrot(mo.dq[:, pi], (RIG.head[pi] - hc_rest)[None])
    traj = M.gauss1d(hc, root_sigma * FPS)
    traj[:, 2] = 0
    start = traj[0].copy()
    if inplace:
        mo.pelvis = mo.pelvis - (traj - start[None])
        mo.pelvis[:, :2] -= start[:2]
    m = dict(type='oneshot', src='handkey', duration=round((mo.F - 1) / FPS, 4))
    m['root_motion'] = P.root_motion_meta(traj - start)
    if contact is not None:
        m['contact_time'] = round(float(contact), 3)
    if meta:
        m.update(meta)
    P.save(name, mo, m)
    return mo, m


def blend_to_pose(mo, pose, weight, base=None):
    """Blend listed bones' local rotations toward an absolute pose (base idle frame + body-axis
    offsets / hinge entries) with per-frame weight (F,). In place, keeps the pelvis."""
    L, loc = mo.to_local()
    L0, loc0 = base if base is not None else base_pose()
    w = np.asarray(weight, float)
    zextra = {k.split(':')[1]: v for k, v in pose.items() if k.startswith('z:')}
    for ch, val in pose.items():
        if ch.startswith('z:'):
            continue
        if ch.startswith('hinge:'):
            bone = ch.split(':')[1]
            b = RIG.i(bone)
            tgt = M.qmul(axis_q(bone, hinge_axis(bone), val), L0[b])
        elif ch in zextra:
            b = RIG.i(ch)
            tgt = M.qmul(M.body_q(RIG, ch, 0, 0, zextra[ch]), M.qmul(M.body_q(RIG, ch, *val), L0[b]))
        else:
            b = RIG.i(ch)
            tgt = M.qmul(M.body_q(RIG, ch, *val), L0[b])
        L[:, b] = M.qslerp(L[:, b], np.repeat(tgt[None], mo.F, 0), w)
    m = M.Motion.from_local(RIG, L, loc, mo.fps)
    mo.dq = m.dq
    mo.pelvis = m.pelvis
    return mo
