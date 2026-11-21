"""mlib.py -- MAYDON animation core: quaternion math, BVH/glTF source loading,
world-space retargeting onto the MPFB game_engine rig, leg IK, looping, in-place,
hand-key helpers and Blender action I/O.

Conventions
-----------
* Quaternions are numpy arrays (..., 4) in (w, x, y, z) order.
* Everything is in Blender world space: Z up, character faces -Y, its left is +X.
* A target "Motion" stores, per frame, the world-space *delta* rotation of every
  bone relative to its rest orientation (dq), plus the pelvis head position.
  posed_world_rot(b) = dq[b] * rest_q[b]
  local basis(b)     = rest_q[b]^-1 * dq[parent]^-1 * dq[b] * rest_q[b]
"""
import math
import os
import numpy as np

UP = np.array([0.0, 0.0, 1.0])
FWD = np.array([0.0, -1.0, 0.0])
LEFT = np.array([1.0, 0.0, 0.0])

# ============================================================== quaternions

def qn(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def qmul(a, b):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    aw, ax, ay, az = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    bw, bx, by, bz = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([aw * bw - ax * bx - ay * by - az * bz,
                     aw * bx + ax * bw + ay * bz - az * by,
                     aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw], -1)


def qinv(q):
    return np.asarray(q, float) * np.array([1.0, -1.0, -1.0, -1.0])


def qrot(q, v):
    q = np.asarray(q, float)
    v = np.asarray(v, float)
    u = q[..., 1:]
    w = q[..., :1]
    t = 2.0 * np.cross(u, v)
    return v + w * t + np.cross(u, t)


def qid(shape=()):
    q = np.zeros(tuple(shape) + (4,))
    q[..., 0] = 1.0
    return q


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def qaxis(axis, ang):
    axis = unit(axis)
    ang = np.asarray(ang, float)[..., None]
    return np.concatenate([np.cos(ang / 2) * np.ones(axis.shape[:-1] + (1,)), axis * np.sin(ang / 2)], -1)


def qbetween(u, v):
    """Minimal rotation taking direction u onto direction v."""
    u = unit(u)
    v = unit(v)
    d = np.sum(u * v, -1, keepdims=True)
    c = np.cross(u, v)
    q = np.concatenate([1.0 + d, c], -1)
    bad = (d[..., 0] < -0.99999)
    if np.any(bad):
        ub = u[bad]
        alt = np.where(np.abs(ub[:, :1]) < 0.9, np.array([[1.0, 0, 0]]), np.array([[0, 1.0, 0]]))
        ax = unit(np.cross(ub, alt))
        q[bad] = np.concatenate([np.zeros((ax.shape[0], 1)), ax], -1)
    return qn(q)


def qfrommat(M):
    M = np.asarray(M, float)
    shp = M.shape[:-2]
    M = M.reshape(-1, 3, 3)
    q = np.zeros((M.shape[0], 4))
    tr = M[:, 0, 0] + M[:, 1, 1] + M[:, 2, 2]
    for i in range(M.shape[0]):
        m = M[i]
        if tr[i] > 0:
            s = math.sqrt(tr[i] + 1.0) * 2
            q[i] = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
        elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
            s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
            q[i] = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
        elif m[1, 1] > m[2, 2]:
            s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
            q[i] = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
        else:
            s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
            q[i] = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    return qn(q).reshape(shp + (4,))


def qtomat(q):
    q = qn(np.asarray(q, float))
    w, x, y, z = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    return np.stack([np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], -1),
                     np.stack([2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], -1),
                     np.stack([2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)], -1)], -2)


def qframe(a1, b1, a2, b2):
    """Rotation mapping frame (primary a1, secondary b1) onto (a2, b2)."""
    def fr(a, b):
        x = unit(a)
        z = unit(np.cross(x, b))
        y = np.cross(z, x)
        return np.stack([x, y, z], -1)
    M = fr(a2, b2) @ np.swapaxes(fr(a1, b1), -1, -2)
    return qfrommat(M)


def qdot(a, b):
    return np.sum(a * b, -1)


def qslerp(a, b, t):
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    t = np.asarray(t, float)
    shape = np.broadcast_shapes(a.shape[:-1], b.shape[:-1], t.shape)
    a = np.broadcast_to(a, shape + (4,))
    b = np.broadcast_to(b, shape + (4,))
    t = np.broadcast_to(t, shape)
    d = qdot(a, b)
    b = np.where(d[..., None] < 0, -b, b)
    d = np.clip(np.abs(d), 0.0, 1.0)
    th = np.arccos(d)
    s = np.sin(th)
    small = s < 1e-6
    ss = np.where(small, 1.0, s)
    w1 = np.where(small, 1 - t, np.sin((1 - t) * th) / ss)
    w2 = np.where(small, t, np.sin(t * th) / ss)
    return qn(w1[..., None] * a + w2[..., None] * b)


def qcontinuous(q, axis=0):
    """Flip signs so consecutive quaternions along `axis` lie in the same hemisphere."""
    q = np.moveaxis(np.array(q, float), axis, 0)
    for i in range(1, q.shape[0]):
        d = qdot(q[i], q[i - 1])
        q[i] = np.where(d[..., None] < 0, -q[i], q[i])
    return np.moveaxis(q, 0, axis)


def qlog(q):
    q = qn(np.asarray(q, float))
    q = np.where(q[..., :1] < 0, -q, q)
    v = q[..., 1:]
    s = np.linalg.norm(v, axis=-1, keepdims=True)
    ang = 2 * np.arctan2(s, q[..., :1])
    return np.where(s > 1e-9, v / np.maximum(s, 1e-12) * ang, 2 * v)


def qexp(r):
    r = np.asarray(r, float)
    ang = np.linalg.norm(r, axis=-1, keepdims=True)
    ax = r / np.maximum(ang, 1e-12)
    return np.concatenate([np.cos(ang / 2), ax * np.sin(ang / 2)], -1)


def qangle(q):
    q = qn(q)
    return 2 * np.arccos(np.clip(np.abs(q[..., 0]), 0, 1))


def yaw_q(angle):
    return qaxis(UP, angle)


def heading_of(v):
    """Yaw angle (radians) of a horizontal direction measured from -Y (forward)."""
    return math.atan2(-v[0], -v[1]) * -1.0  # rotation about +Z that maps -Y onto v


def yaw_to(v_from, v_to):
    a = math.atan2(v_from[1], v_from[0])
    b = math.atan2(v_to[1], v_to[0])
    d = b - a
    return (d + math.pi) % (2 * math.pi) - math.pi


# ============================================================== filters

def gauss1d(x, sigma, axis=0, mode='nearest'):
    """Gaussian filter along axis (sigma in samples). mode: 'nearest' or 'wrap'."""
    if sigma <= 1e-6:
        return np.array(x, float)
    x = np.moveaxis(np.asarray(x, float), axis, 0)
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    n = x.shape[0]
    if mode == 'wrap':
        idx = np.arange(-r, n + r) % n
    else:
        idx = np.clip(np.arange(-r, n + r), 0, n - 1)
    xp = x[idx]
    out = np.zeros_like(x)
    for i, kv in enumerate(k):
        out += kv * xp[i:i + n]
    return np.moveaxis(out, 0, axis)


def smooth_quats(q, sigma, mode='nearest'):
    q = qcontinuous(q, 0)
    return qn(gauss1d(q, sigma, 0, mode))


# ============================================================== BVH

class BVH:
    pass


def load_bvh(path):
    with open(path, 'r', errors='replace') as f:
        txt = f.read()
    hi, mo = txt.split('MOTION', 1)
    tok = hi.split()
    names, parents, offsets, chans = [], [], [], []
    ends = {}
    stack = []
    cur = None
    i = 0
    while i < len(tok):
        t = tok[i]
        if t in ('ROOT', 'JOINT'):
            names.append(tok[i + 1])
            parents.append(stack[-1] if stack and stack[-1] >= 0 else (-1 if not stack else stack[-1]))
            offsets.append(np.zeros(3))
            chans.append([])
            cur = len(names) - 1
            i += 2
        elif t == 'End':
            cur = -2 - stack[-1]  # encode end site of joint stack[-1]
            i += 2
        elif t == '{':
            stack.append(cur)
            i += 1
        elif t == '}':
            stack.pop()
            i += 1
        elif t == 'OFFSET':
            o = np.array([float(tok[i + 1]), float(tok[i + 2]), float(tok[i + 3])])
            if cur is not None and cur >= 0:
                offsets[cur] = o
            elif cur is not None:
                ends[-2 - cur] = o
            i += 4
        elif t == 'CHANNELS':
            n = int(tok[i + 1])
            chans[cur] = tok[i + 2:i + 2 + n]
            i += 2 + n
        else:
            i += 1
    lines = mo.strip().split('\n')
    nf = int(lines[0].split(':')[1])
    dt = float(lines[1].split(':')[1])
    data = np.array(' '.join(lines[2:]).split(), dtype=float)
    nc = sum(len(c) for c in chans)
    nf = min(nf, data.size // nc)
    data = data[:nf * nc].reshape(nf, nc)
    b = BVH()
    b.names, b.parents, b.offsets, b.chans, b.ends = names, parents, np.array(offsets), chans, ends
    b.data, b.dt, b.path = data, dt, path
    return b


_AX = {'X': np.array([1.0, 0, 0]), 'Y': np.array([0, 1.0, 0]), 'Z': np.array([0, 0, 1.0])}
C_YUP = None  # set below


def bvh_fk(b, frames=None):
    """Return world positions (F,J,3) and world rotations (F,J,4) in BVH space,
    rest positions (J,3) and end-site world data {j: (rest(3,), traj(F,3))}."""
    data = b.data if frames is None else b.data[frames]
    F = data.shape[0]
    J = len(b.names)
    P = np.zeros((F, J, 3))
    Q = qid((F, J))
    RP = np.zeros((J, 3))
    col = 0
    for j in range(J):
        ch = b.chans[j]
        loc = np.repeat(b.offsets[j][None], F, 0)
        q = qid((F,))
        haspos = False
        for c in ch:
            v = data[:, col]
            col += 1
            if c.endswith('position'):
                if not haspos:
                    loc = loc.copy()
                    haspos = True
                loc[:, 'XYZ'.index(c[0])] = v
            else:
                q = qmul(q, qaxis(_AX[c[0]], np.radians(v)))
        p = b.parents[j]
        if p < 0:
            P[:, j] = loc
            Q[:, j] = q
            RP[j] = b.offsets[j]
        else:
            P[:, j] = P[:, p] + qrot(Q[:, p], loc)
            Q[:, j] = qmul(Q[:, p], q)
            RP[j] = RP[p] + b.offsets[j]
    E = {}
    for j, o in b.ends.items():
        E[j] = (RP[j] + o, P[:, j] + qrot(Q[:, j], np.repeat(o[None], F, 0)))
    return P, Q, RP, E


# ============================================================== generic source

class Source:
    """Source motion in Blender space (Z up). rot = world delta from source rest."""

    def __init__(self, names, parents, rest, pos, rot, fps, ends=None, label=''):
        self.names = list(names)
        self.parents = list(parents)
        self.rest = np.asarray(rest, float)
        self.pos = np.asarray(pos, float)
        self.rot = np.asarray(rot, float)
        self.fps = float(fps)
        self.ends = ends or {}
        self.label = label

    @property
    def F(self):
        return self.pos.shape[0]

    def idx(self, name):
        return self.names.index(name)

    def has(self, name):
        return name in self.names

    def P(self, name):
        if name in self.names:
            return self.pos[:, self.idx(name)]
        return self.ends[name][1]

    def RP(self, name):
        if name in self.names:
            return self.rest[self.idx(name)]
        return self.ends[name][0]

    def R(self, name):
        return self.rot[:, self.idx(name)]

    def copy_frames(self, sel):
        ends = {k: (v[0], v[1][sel]) for k, v in self.ends.items()}
        return Source(self.names, self.parents, self.rest, self.pos[sel], self.rot[sel], self.fps, ends, self.label)

    def sample(self, times, smooth_sigma_s=0.0):
        """Resample at arbitrary times (seconds from first frame) with optional pre-smoothing."""
        pos, rot = self.pos, self.rot
        ends = {k: v[1] for k, v in self.ends.items()}
        sig = smooth_sigma_s * self.fps
        if sig > 0.05:
            pos = gauss1d(pos, sig)
            rot = smooth_quats(rot, sig)
            ends = {k: gauss1d(v, sig) for k, v in ends.items()}
        else:
            rot = qcontinuous(rot, 0)
        x = np.asarray(times, float) * self.fps
        x = np.clip(x, 0, self.F - 1.000001)
        i0 = np.floor(x).astype(int)
        i1 = np.minimum(i0 + 1, self.F - 1)
        t = (x - i0)
        P = pos[i0] * (1 - t)[:, None, None] + pos[i1] * t[:, None, None]
        R = qslerp(rot[i0], rot[i1], np.repeat(t[:, None], rot.shape[1], 1))
        E = {k: (self.ends[k][0], v[i0] * (1 - t)[:, None] + v[i1] * t[:, None]) for k, v in ends.items()}
        return Source(self.names, self.parents, self.rest, P, R, 1.0 / max(np.median(np.diff(times)), 1e-6) if len(times) > 1 else self.fps, E, self.label)

    def transformed(self, yaw=0.0, shift=(0, 0, 0)):
        """Rotate about Z by yaw (radians) around the origin, then translate."""
        qy = yaw_q(yaw)
        sh = np.asarray(shift, float)
        pos = qrot(qy, self.pos) + sh
        rot = qmul(qy, self.rot)
        ends = {k: (v[0], qrot(qy, v[1]) + sh) for k, v in self.ends.items()}
        # rest pose stays (calibration is relative to rest, the delta absorbs yaw)
        return Source(self.names, self.parents, self.rest, pos, rot, self.fps, ends, self.label)


def source_from_bvh(path, skip_first=False, label=''):
    b = load_bvh(path)
    frames = slice(1, None) if skip_first else None
    P, Q, RP, E = bvh_fk(b, frames)
    c = qaxis([1.0, 0, 0], math.pi / 2)  # Y-up -> Z-up : (x,y,z)->(x,-z,y)
    P = qrot(c, P)
    RP = qrot(c, RP)
    Q = qmul(qmul(c, Q), qinv(c))
    ends = {}
    for j, (r, tr) in E.items():
        ends[b.names[j] + '_end'] = (qrot(c, r), qrot(c, tr))
    return Source(b.names, b.parents, RP, P, Q, 1.0 / b.dt, ends, label or os.path.basename(path))


# ============================================================== target rig

class Rig:
    def __init__(self, names, parents, head, tail, rest_q):
        self.names = list(names)
        self.parents = list(parents)
        self.head = np.asarray(head, float)
        self.tail = np.asarray(tail, float)
        self.rest_q = np.asarray(rest_q, float)
        self.ix = {n: i for i, n in enumerate(self.names)}
        self.B = len(self.names)
        self.children = {i: [] for i in range(self.B)}
        for i, p in enumerate(self.parents):
            if p >= 0:
                self.children[p].append(i)
        self.length = np.linalg.norm(self.tail - self.head, axis=-1)

    @staticmethod
    def from_blender(arm):
        bones = arm.data.bones
        # topological order = Blender's order is parent-first for MPFB rigs; enforce
        order = []
        seen = set()

        def visit(b):
            order.append(b.name)
            seen.add(b.name)
            for c in b.children:
                visit(c)
        for b in bones:
            if b.parent is None:
                visit(b)
        names = order
        parents = [names.index(bones[n].parent.name) if bones[n].parent else -1 for n in names]
        mw = np.array(arm.matrix_world)
        head = np.array([list(bones[n].head_local) for n in names])
        tail = np.array([list(bones[n].tail_local) for n in names])
        rq = qfrommat(np.array([[list(r) for r in bones[n].matrix_local.to_3x3()] for n in names]))
        return Rig(names, parents, head, tail, rq)

    def i(self, n):
        return self.ix[n]


class Motion:
    """Target motion: dq (F,B,4) world deltas, pelvis (F,3) pelvis head position."""

    def __init__(self, rig, dq, pelvis, fps=30.0):
        self.rig = rig
        self.dq = np.asarray(dq, float)
        self.pelvis = np.asarray(pelvis, float)
        self.fps = fps
        self.meta = {}

    @property
    def F(self):
        return self.dq.shape[0]

    def copy(self):
        m = Motion(self.rig, self.dq.copy(), self.pelvis.copy(), self.fps)
        m.meta = dict(self.meta)
        return m

    def heads(self):
        rig = self.rig
        H = np.zeros((self.F, rig.B, 3))
        pi = rig.i('pelvis')
        for b in range(rig.B):
            p = rig.parents[b]
            if b == pi:
                H[:, b] = self.pelvis
            elif p < 0:
                H[:, b] = rig.head[b]
            else:
                H[:, b] = H[:, p] + qrot(self.dq[:, p], rig.head[b] - rig.head[p])
        return H

    def tails(self, H=None):
        if H is None:
            H = self.heads()
        rig = self.rig
        return H + qrot(self.dq, (rig.tail - rig.head)[None])

    def point(self, bone, offset_rest, H=None):
        """World position of a point rigidly attached to bone (offset given in rest armature space, from head)."""
        if H is None:
            H = self.heads()
        b = self.rig.i(bone)
        return H[:, b] + qrot(self.dq[:, b], np.asarray(offset_rest, float)[None])

    def to_local(self):
        rig = self.rig
        L = qid((self.F, rig.B))
        for b in range(rig.B):
            p = rig.parents[b]
            dp = self.dq[:, p] if p >= 0 else qid((self.F,))
            L[:, b] = qmul(qmul(qinv(rig.rest_q[b])[None], qmul(qinv(dp), self.dq[:, b])), rig.rest_q[b][None])
        pi = rig.i('pelvis')
        # pelvis parent (Root) assumed at rest
        loc = qrot(qinv(rig.rest_q[pi])[None], self.pelvis - rig.head[pi])
        return qcontinuous(qn(L), 0), loc

    @staticmethod
    def from_local(rig, L, loc, fps=30.0):
        F = L.shape[0]
        dq = qid((F, rig.B))
        for b in range(rig.B):
            p = rig.parents[b]
            dp = dq[:, p] if p >= 0 else qid((F,))
            dq[:, b] = qmul(qmul(dp, rig.rest_q[b][None]), qmul(L[:, b], qinv(rig.rest_q[b])[None]))
        pi = rig.i('pelvis')
        pel = rig.head[pi] + qrot(rig.rest_q[pi][None], loc)
        return Motion(rig, qn(dq), pel, fps)

    def propagate_unmapped(self, mapped):
        """Unmapped bones keep their rest local rotation: dq = dq[parent]."""
        rig = self.rig
        for b in range(rig.B):
            if rig.names[b] in mapped:
                continue
            p = rig.parents[b]
            self.dq[:, b] = self.dq[:, p] if p >= 0 else qid((self.F,))

    def set_world(self, bone, dq_new, keep_children_world=False):
        """Set bone world delta; children by default keep their *local* rotation."""
        rig = self.rig
        b = rig.i(bone)
        if keep_children_world:
            self.dq[:, b] = dq_new
            return
        corr = qmul(dq_new, qinv(self.dq[:, b]))
        stack = [b]
        while stack:
            x = stack.pop()
            self.dq[:, x] = qn(qmul(corr, self.dq[:, x]))
            stack.extend(rig.children[x])


# ============================================================== skeleton specs

TARGET_CHAIN = ['pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'head',
                'clavicle_l', 'upperarm_l', 'lowerarm_l', 'hand_l',
                'clavicle_r', 'upperarm_r', 'lowerarm_r', 'hand_r',
                'thigh_l', 'calf_l', 'foot_l', 'ball_l',
                'thigh_r', 'calf_r', 'foot_r', 'ball_r']


def _arm(p, s):
    return p


SPEC = {
    'cmu': dict(
        hips=('RightUpLeg', 'LeftUpLeg'), pelvis_up='Spine',
        chest_lat=('RightArm', 'LeftArm'), chest_up=('Spine', 'Spine1'),
        spine=[('LowerBack', 'Spine'), ('Spine', 'Spine1')],
        neck=('Neck', 'Head'), head=('Head', 'Head_end'),
        arm={'l': ('LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'LeftHandIndex1_end'),
             'r': ('RightShoulder', 'RightArm', 'RightForeArm', 'RightHand', 'RightHandIndex1_end')},
        leg={'l': ('LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToeBase_end'),
             'r': ('RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToeBase_end')},
        hand_data=False),
    'accad': dict(
        hips=('RightUpLeg', 'LeftUpLeg'), pelvis_up='Spine',
        chest_lat=('RightArm', 'LeftArm'), chest_up=('Spine1', 'Neck'),
        spine=[('ToSpine', 'Spine'), ('Spine', 'Spine1')],
        neck=('Neck', 'Head'), head=('Head', 'Head_end'),
        arm={'l': ('LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'LeftHand_end'),
             'r': ('RightShoulder', 'RightArm', 'RightForeArm', 'RightHand', 'RightHand_end')},
        leg={'l': ('LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToeBase_end'),
             'r': ('RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToeBase_end')},
        hand_data=True),
    'cologne': dict(
        hips=('RightUpLeg', 'LeftUpLeg'), pelvis_up='Spine1',
        chest_lat=('RightArm', 'LeftArm'), chest_up=('Spine1', 'Neck'),
        spine=[('Spine', 'Spine1'), ('Spine', 'Spine1')],
        neck=('Neck', 'Head'), head=('Head', 'Head_end'),
        arm={'l': ('LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'LeftHand_end'),
             'r': ('RightShoulder', 'RightArm', 'RightForeArm', 'RightHand', 'RightHand_end')},
        leg={'l': ('LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToeBase_end'),
             'r': ('RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToeBase_end')},
        hand_data=True),
    '100style': dict(
        hips=('RightHip', 'LeftHip'), pelvis_up='Chest2',
        chest_lat=('RightShoulder', 'LeftShoulder'), chest_up=('Chest3', 'Neck'),
        spine=[('Chest', 'Chest2'), ('Chest2', 'Chest4')],
        neck=('Neck', 'Head'), head=('Head', 'Head_end'),
        arm={'l': ('LeftCollar', 'LeftShoulder', 'LeftElbow', 'LeftWrist', 'LeftWrist_end'),
             'r': ('RightCollar', 'RightShoulder', 'RightElbow', 'RightWrist', 'RightWrist_end')},
        leg={'l': ('LeftHip', 'LeftKnee', 'LeftAnkle', 'LeftToe', 'LeftToe_end'),
             'r': ('RightHip', 'RightKnee', 'RightAnkle', 'RightToe', 'RightToe_end')},
        hand_data=True),
    'mixamo': dict(
        hips=('RightUpLeg', 'LeftUpLeg'), pelvis_up='Spine',
        chest_lat=('RightArm', 'LeftArm'), chest_up=('Spine1', 'Neck'),
        spine=[('Spine', 'Spine1'), ('Spine1', 'Spine2')],
        neck=('Neck', 'Head'), head=('Head', 'HeadTop_End'),
        arm={'l': ('LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand', 'LeftHandMiddle1'),
             'r': ('RightShoulder', 'RightArm', 'RightForeArm', 'RightHand', 'RightHandMiddle1')},
        leg={'l': ('LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase', 'LeftToe_End'),
             'r': ('RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase', 'RightToe_End')},
        hand_data=True),
}
# compatibility helpers used by process.py
FRAME_REF = {k: {'hips': v['hips'], 'chest': v['chest_lat']} for k, v in SPEC.items()}
LEGS = {k: {s: v['leg'][s][:4] for s in 'lr'} for k, v in SPEC.items()}
MAPS = {k: {'spine_01': (v['spine'][0][0], v['spine'][0][1])} for k, v in SPEC.items()}


def rig_point(rig, spec):
    kind, bone = spec.split(':')
    return rig.head[rig.i(bone)] if kind == 'head' else rig.tail[rig.i(bone)]


def smoothstep(x, a, b):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def swing_to(dq, v_rest, v_target):
    """Pre-rotate world delta dq minimally so that dq*v_rest points along v_target."""
    return qn(qmul(qbetween(qrot(dq, v_rest), v_target), dq))


def leg_len_src(src, kind, side='l'):
    hip, knee, ank = SPEC[kind]['leg'][side][:3]
    return float(np.linalg.norm(src.RP(knee) - src.RP(hip)) + np.linalg.norm(src.RP(ank) - src.RP(knee)))


def leg_len_rig(rig, side='l'):
    return float(rig.length[rig.i('thigh_' + side)] + rig.length[rig.i('calf_' + side)])


# ============================================================== retarget

class TargetConst:
    """Rest-space reference vectors of the target rig."""

    def __init__(self, rig):
        h = lambda n: rig.head[rig.i(n)]
        t = lambda n: rig.tail[rig.i(n)]
        self.hc = 0.5 * (h('thigh_l') + h('thigh_r'))
        self.pel_lat = h('thigh_l') - h('thigh_r')
        self.pel_up = h('spine_02') - self.hc
        self.ch_lat = h('upperarm_l') - h('upperarm_r')
        self.ch_up = h('neck_01') - h('spine_03')
        self.sp = [h('spine_02') - h('spine_01'), h('spine_03') - h('spine_02')]
        self.neck = h('head') - h('neck_01')
        self.head = t('head') - h('head')
        self.arm = {}
        for s in 'lr':
            clav = h('upperarm_' + s) - h('clavicle_' + s)
            ua = h('lowerarm_' + s) - h('upperarm_' + s)
            fa = h('hand_' + s) - h('lowerarm_' + s)
            hd = h('middle_01_' + s) - h('hand_' + s)
            self.arm[s] = dict(clav=clav, ua=ua, fa=fa, hand=hd, hinge=unit(np.cross(ua, fa)))
        self.foot = {s: h('ball_' + s) - h('foot_' + s) for s in 'lr'}


def src_dirs(src, kind, F=None):
    """Per-frame direction vectors from source joint positions."""
    S = SPEC[kind]
    P = src.P
    d = {}
    hc = 0.5 * (P(S['hips'][0]) + P(S['hips'][1]))
    d['hc'] = hc
    d['pel_lat'] = P(S['hips'][1]) - P(S['hips'][0])
    d['pel_up'] = P(S['pelvis_up']) - hc
    d['ch_lat'] = P(S['chest_lat'][1]) - P(S['chest_lat'][0])
    d['ch_up'] = P(S['chest_up'][1]) - P(S['chest_up'][0])
    d['sp'] = [P(b) - P(a) for a, b in S['spine']]
    d['neck'] = P(S['neck'][1]) - P(S['neck'][0])
    d['head'] = P(S['head'][1]) - P(S['head'][0])
    for s in 'lr':
        cl, ua, fa, hd, he = S['arm'][s]
        d['clav_' + s] = P(ua) - P(cl)
        d['ua_' + s] = P(fa) - P(ua)
        d['fa_' + s] = P(hd) - P(fa)
        d['hand_' + s] = P(he) - P(hd)
    return d


def calib_frame_general(src, kind):
    """Frame whose pose is most 'neutral standing': arms hanging, torso upright."""
    d = src_dirs(src, kind)
    score = np.zeros(src.F)
    for s in 'lr':
        ua = unit(d['ua_' + s])
        score += np.degrees(np.arccos(np.clip(-ua[:, 2], -1, 1)))
    up = unit(d['ch_up'])
    score += 2 * np.degrees(np.arccos(np.clip(up[:, 2], -1, 1)))
    return int(np.argmin(score))


def calib_frame_foot(src, kind, side):
    hip, knee, ank, toe, toe_end = SPEC[kind]['leg'][side]
    A = src.P(ank)
    T = src.P(toe)
    vel = np.linalg.norm(np.gradient(A, axis=0), axis=-1) * src.fps + np.linalg.norm(np.gradient(T, axis=0), axis=-1) * src.fps
    za = A[:, 2]
    zt = T[:, 2]
    L = leg_len_src(src, kind)
    ok = (za < np.percentile(za, 15) + 0.01 * L) & (zt < np.percentile(zt, 15) + 0.01 * L)
    if ok.sum() < 1:
        ok = np.ones(src.F, bool)
    cand = np.where(ok)[0]
    return int(cand[np.argmin(vel[cand])])


class Calib:
    pass


def calibrate(src, rig, kind, c_gen=None, c_foot=None):
    """Calibration constants (yaw-invariant) from a natural frame of the full source take."""
    S = SPEC[kind]
    tc = TargetConst(rig)
    cal = Calib()
    cal.kind = kind
    cal.c_gen = calib_frame_general(src, kind) if c_gen is None else c_gen
    c = cal.c_gen
    d = src_dirs(src, kind)
    pick = lambda v: v[c]
    dpel = qframe(tc.pel_lat, tc.pel_up, pick(d['pel_lat']), pick(d['pel_up']))
    dch = qframe(tc.ch_lat, tc.ch_up, pick(d['ch_lat']), pick(d['ch_up']))
    # head
    dhead = swing_to(dch, tc.head, pick(d['head']))
    cal.K_head = qmul(qinv(src.R(S['head'][0])[c]), dhead)
    cal.K_ua, cal.M_hand, cal.W_c = {}, {}, {}
    for s in 'lr':
        cl, ua, fa, hd, he = S['arm'][s]
        a = tc.arm[s]
        dcl = swing_to(dch, a['clav'], pick(d['clav_' + s]))
        dua = swing_to(dcl, a['ua'], pick(d['ua_' + s]))
        dfa = swing_to(dua, a['fa'], pick(d['fa_' + s]))
        cal.K_ua[s] = qmul(qinv(src.R(ua)[c]), dua)
        Fs = src.R(fa)[c]
        Hs = src.R(hd)[c]
        cal.M_hand[s] = qmul(qinv(Fs), dfa)
        cal.W_c[s] = qmul(qinv(Fs), Hs)
    cal.c_foot, cal.K_foot, cal.K_toe = {}, {}, {}
    for s in 'lr':
        hip, knee, ank, toe, toe_end = S['leg'][s]
        cf = calib_frame_foot(src, kind, s) if not c_foot else c_foot[s]
        cal.c_foot[s] = cf
        hv = src.P(toe)[cf] - src.P(ank)[cf]
        tv = tc.foot[s]
        yaw = yaw_to(tv, hv)
        Y = yaw_q(yaw)
        cal.K_foot[s] = qmul(qinv(src.R(ank)[cf]), Y)
        cal.K_toe[s] = qmul(qinv(src.R(toe)[cf]), Y)
    # floor reference: ankle height while that foot is flat
    cal.ankle_flat = float(np.mean([src.P(S['leg'][s][2])[cal.c_foot[s], 2] for s in 'lr']))
    cal.ratio = leg_len_rig(rig) / leg_len_src(src, kind)
    return cal


def retarget(src, rig, kind, cal=None, floor=None, ik=True, hand_limit=50.0, wrist=True):
    """Hybrid world-space retarget. src may be yaw-rotated/resampled relative to the
    take used for `cal` (calibration constants are yaw invariant)."""
    S = SPEC[kind]
    if cal is None:
        cal = calibrate(src, rig, kind)
    tc = TargetConst(rig)
    F = src.F
    d = src_dirs(src, kind)
    dq = qid((F, rig.B))
    I = rig.i
    rep = lambda v: np.repeat(np.asarray(v, float)[None], F, 0)
    # torso frames from positions
    dpel = qframe(rep(tc.pel_lat), rep(tc.pel_up), d['pel_lat'], d['pel_up'])
    dch = qframe(rep(tc.ch_lat), rep(tc.ch_up), d['ch_lat'], d['ch_up'])
    dpel = qcontinuous(dpel)
    dch = qcontinuous(dch)
    dq[:, I('pelvis')] = dpel
    s1 = swing_to(qslerp(dpel, dch, np.full(F, 1 / 3.)), tc.sp[0], d['sp'][0])
    s2 = swing_to(qslerp(dpel, dch, np.full(F, 2 / 3.)), tc.sp[1], d['sp'][1])
    dq[:, I('spine_01')] = s1
    dq[:, I('spine_02')] = s2
    dq[:, I('spine_03')] = dch
    # head: rotation transfer relative to calibration frame, direction-locked
    dhead = qmul(src.R(S['head'][0]), cal.K_head[None])
    dhead = swing_to(dhead, tc.head, d['head'])
    dneck = swing_to(qslerp(dch, dhead, np.full(F, 0.5)), tc.neck, d['neck'])
    dq[:, I('neck_01')] = dneck
    dq[:, I('head')] = dhead
    # arms
    for s in 'lr':
        cl, ua, fa, hd, he = S['arm'][s]
        a = tc.arm[s]
        dcl = swing_to(dch, a['clav'], d['clav_' + s])
        drot = swing_to(qmul(src.R(ua), cal.K_ua[s][None]), a['ua'], d['ua_' + s])
        u = unit(d['ua_' + s])
        f = unit(d['fa_' + s])
        bend = np.degrees(np.arccos(np.clip(np.sum(u * f, -1), -1, 1)))
        hinge = np.cross(u, f)
        ok = np.linalg.norm(hinge, axis=-1) > 1e-6
        hinge = unit(np.where(ok[:, None], hinge, rep(a['hinge'])))
        dh = qframe(rep(a['ua']), rep(a['hinge']), d['ua_' + s], hinge)
        w = smoothstep(bend, 12.0, 30.0)
        dua = qslerp(qcontinuous(drot), qcontinuous(dh), w)
        dua = swing_to(dua, a['ua'], d['ua_' + s])
        dfa = swing_to(dua, a['fa'], d['fa_' + s])
        dhand = dfa
        if wrist and S['hand_data']:
            Fs = src.R(fa)
            Hs = src.R(hd)
            W = qmul(qinv(Fs), Hs)
            rel = qmul(qinv(cal.W_c[s])[None], W)
            Mh = cal.M_hand[s][None]
            X = qmul(qmul(qinv(Mh), rel), Mh)
            # clamp angle
            r = qlog(X)
            ang = np.linalg.norm(r, axis=-1, keepdims=True)
            lim = math.radians(hand_limit)
            r = np.where(ang > lim, r / np.maximum(ang, 1e-9) * lim, r)
            dhand = qmul(dfa, qexp(r))
        dq[:, I('clavicle_' + s)] = dcl
        dq[:, I('upperarm_' + s)] = dua
        dq[:, I('lowerarm_' + s)] = dfa
        dq[:, I('hand_' + s)] = dhand
    # feet & toes (relative to the flat calibration frame)
    for s in 'lr':
        hip, knee, ank, toe, toe_end = S['leg'][s]
        dq[:, I('foot_' + s)] = qmul(src.R(ank), cal.K_foot[s][None])
        dq[:, I('ball_' + s)] = qmul(src.R(toe), cal.K_toe[s][None])
    mo = Motion(rig, qn(dq), np.zeros((F, 3)), src.fps)
    mapped = set(['pelvis', 'spine_01', 'spine_02', 'spine_03', 'neck_01', 'head'] +
                 [b + '_' + s for b in ('clavicle', 'upperarm', 'lowerarm', 'hand', 'foot', 'ball', 'thigh', 'calf') for s in 'lr'])
    mo.propagate_unmapped(mapped)
    # ---- hips translation scaled by leg-length ratio
    ratio = cal.ratio
    t_ank = rig.head[rig.i('foot_l')][2]
    if floor is None:
        floor = cal.ankle_flat - t_ank / ratio
    def to_t(p):
        q = np.array(p, float)
        q[..., 2] = q[..., 2] - floor
        return q * ratio
    hc_t = to_t(d['hc'])
    pi = rig.i('pelvis')
    mo.pelvis = hc_t + qrot(mo.dq[:, pi], (rig.head[pi] - tc.hc)[None])
    mo.meta.update(ratio=ratio, floor=floor, kind=kind, src=src.label)
    mo.ank_target = {s: to_t(src.P(S['leg'][s][2])) for s in 'lr'}
    mo.toe_src = {s: to_t(src.P(S['leg'][s][3])) for s in 'lr'}
    # knee poles: source bend direction blended with the foot heading
    mo.pole = {}
    for s in 'lr':
        hip, knee, ank, toe, toe_end = S['leg'][s]
        H, K, A, T = src.P(hip), src.P(knee), src.P(ank), src.P(toe)
        ax = unit(A - H)
        kv = K - H
        kv = kv - np.sum(kv * ax, -1, keepdims=True) * ax
        mag = np.linalg.norm(kv, axis=-1) / leg_len_src(src, kind)
        ff = T - A
        ff = ff - np.sum(ff * ax, -1, keepdims=True) * ax
        w = smoothstep(mag, 0.03, 0.10)[:, None]
        mo.pole[s] = unit(w * unit(kv) + (1 - w) * unit(ff))
    # thighs/calves get a first guess so FK is sane even without IK
    for s in 'lr':
        hip, knee, ank = S['leg'][s][:3]
        th, ca = I('thigh_' + s), I('calf_' + s)
        mo.dq[:, th] = swing_to(dpel, rig.head[I('calf_' + s)] - rig.head[th], src.P(knee) - src.P(hip))
        mo.dq[:, ca] = swing_to(mo.dq[:, th], rig.head[I('foot_' + s)] - rig.head[ca], src.P(ank) - src.P(knee))
    if ik:
        for s in 'lr':
            leg_ik(mo, s, mo.ank_target[s])
    return mo


# ============================================================== leg IK

def leg_ik(mo, side, target, soft=0.985, keep_foot=True, pole=None):
    rig = mo.rig
    th, ca, ft = rig.i('thigh_' + side), rig.i('calf_' + side), rig.i('foot_' + side)
    H = mo.heads()
    hip = H[:, th]
    L1 = np.linalg.norm(rig.head[ca] - rig.head[th])
    L2 = np.linalg.norm(rig.head[ft] - rig.head[ca])
    d = target - hip
    dist = np.linalg.norm(d, axis=-1)
    lmax = L1 + L2
    ds = soft * lmax
    over = dist > ds
    dist2 = dist.copy()
    k = lmax - ds
    dist2[over] = ds + k * (1 - np.exp(-(dist[over] - ds) / k)) * 0.995
    dist2 = np.maximum(dist2, abs(L1 - L2) + 1e-3)
    u = d / np.maximum(dist, 1e-9)[:, None]
    T = hip + u * dist2[:, None]
    # pole: thigh's knee-forward axis
    tdir_r = unit(rig.head[ca] - rig.head[th])
    fwd_r = unit(FWD - np.dot(FWD, tdir_r) * tdir_r)
    if pole is None:
        pole = getattr(mo, 'pole', {}).get(side) if hasattr(mo, 'pole') else None
    if pole is None:
        pole = qrot(mo.dq[:, th], fwd_r[None])
    n = pole - np.sum(pole * u, -1, keepdims=True) * u
    fb = qrot(mo.dq[:, th], fwd_r[None])
    fb = fb - np.sum(fb * u, -1, keepdims=True) * u
    bad = np.linalg.norm(n, axis=-1) < 1e-4
    n = unit(np.where(bad[:, None], fb, n))
    a = (L1 ** 2 + dist2 ** 2 - L2 ** 2) / (2 * L1 * dist2)
    a = np.clip(a, -1, 1)
    K = hip + u * (L1 * a)[:, None] + n * (L1 * np.sqrt(1 - a ** 2))[:, None]
    ut = unit(K - hip)
    uc = unit(T - K)
    ft_dq = mo.dq[:, ft].copy()
    ball_dq = mo.dq[:, rig.i('ball_' + side)].copy()
    # thigh: direction + knee-forward in bend plane
    q_th = qframe(np.repeat(tdir_r[None], mo.F, 0), np.repeat(fwd_r[None], mo.F, 0), ut, n - np.sum(n * ut, -1, keepdims=True) * ut)
    cdir_r = unit(rig.head[ft] - rig.head[ca])
    cfwd_r = unit(FWD - np.dot(FWD, cdir_r) * cdir_r)
    q_ca = qframe(np.repeat(cdir_r[None], mo.F, 0), np.repeat(cfwd_r[None], mo.F, 0), uc, n - np.sum(n * uc, -1, keepdims=True) * uc)
    # keep calf twist relative to source a little: use frame result directly (clean hinge)
    mo.dq[:, th] = q_th
    mo.dq[:, ca] = q_ca
    if keep_foot:
        mo.dq[:, ft] = ft_dq
        mo.dq[:, rig.i('ball_' + side)] = ball_dq
    return T


SOLE = {  # rest-space offsets from the foot head (ankle) for sole points, and from ball head
    'heel': np.array([0.0, 0.045, -0.066]),
}


def sole_points(mo, side, H=None):
    rig = mo.rig
    if H is None:
        H = mo.heads()
    ft = rig.i('foot_' + side)
    bl = rig.i('ball_' + side)
    heel = H[:, ft] + qrot(mo.dq[:, ft], SOLE['heel'][None])
    ball = H[:, bl] + qrot(mo.dq[:, bl], np.array([0, 0, -0.008])[None])
    toe = H[:, bl] + qrot(mo.dq[:, bl], (rig.tail[bl] - rig.head[bl] + np.array([0, 0, -0.012]))[None])
    return heel, ball, toe


def ground_fix(mo, sides='lr', margin=0.0, iters=2, smooth=1.5):
    """Raise ankle IK targets so no sole point goes under the floor (z=0)."""
    for s in sides:
        for _ in range(iters):
            H = mo.heads()
            heel, ball, toe = sole_points(mo, s, H)
            low = np.minimum(np.minimum(heel[:, 2], ball[:, 2]), toe[:, 2])
            lift = np.maximum(margin - low, 0.0)
            if lift.max() < 1e-4:
                break
            lift = np.maximum(gauss1d(lift, smooth), lift)
            tgt = H[:, mo.rig.i('foot_' + s)].copy()
            tgt[:, 2] += lift
            leg_ik(mo, s, tgt, soft=0.999)


# ============================================================== contacts / in place / loops

def contacts(mo, side, vel_world=None, zth=0.03, vth=0.35):
    """Boolean contact flags per frame for a foot (ankle low & slow or ball low & slow)."""
    H = mo.heads()
    heel, ball, toe = sole_points(mo, side, H)
    dt = 1.0 / mo.fps
    off = np.zeros(3) if vel_world is None else np.asarray(vel_world)
    vh = np.linalg.norm((np.gradient(heel, axis=0) / dt + off)[:, :2], axis=-1)
    vb = np.linalg.norm((np.gradient(ball, axis=0) / dt + off)[:, :2], axis=-1)
    c_heel = (heel[:, 2] < zth) & (vh < vth)
    c_ball = (ball[:, 2] < zth) & (vb < vth)
    return c_heel | c_ball, c_heel, c_ball


def runs(flags):
    out = []
    i = 0
    n = len(flags)
    while i < n:
        if flags[i]:
            j = i
            while j < n and flags[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def remove_trend(mo, v):
    """Subtract v*t horizontally (v: (3,) per second, z ignored) from pelvis and IK targets."""
    t = np.arange(mo.F) / mo.fps
    sh = np.outer(t, np.array([v[0], v[1], 0.0]))
    mo.pelvis = mo.pelvis - sh
    for d in ('ank_target', 'toe_src'):
        if hasattr(mo, d):
            for s in getattr(mo, d):
                getattr(mo, d)[s] = getattr(mo, d)[s] - sh
    return sh


def loop_close(mo, n_blend=None):
    """Make frame F-1 equal frame 0 by distributing the mismatch (local rotations + pelvis)."""
    L, loc = mo.to_local()
    F = mo.F
    w = np.linspace(0, 1, F)
    if n_blend is not None:
        w = np.clip((np.arange(F) - (F - 1 - n_blend)) / n_blend, 0, 1)
        w = w * w * (3 - 2 * w)
    err = qmul(qinv(L[-1]), L[0])  # local correction to apply at end
    err = np.where(err[..., :1] < 0, -err, err)
    corr = qslerp(qid((F, err.shape[0])), err[None], w[:, None] * np.ones((1, err.shape[0])))
    L2 = qmul(L, corr)
    dl = loc[0] - loc[-1]
    loc2 = loc + w[:, None] * dl[None]
    m = Motion.from_local(mo.rig, L2, loc2, mo.fps)
    m.meta = dict(mo.meta)
    return m


# ============================================================== hand-key helpers

def body_q(rig, bone, rx=0.0, ry=0.0, rz=0.0, order='ZXY'):
    """Local basis rotation for `bone` given rotations (degrees) about body axes
    X (character left), Y (character back, i.e. +Y), Z (up), relative to the parent
    as it would be in the rest pose."""
    b = rig.i(bone)
    rq = rig.rest_q[b]
    q = qid()
    for ax in order:
        ang = {'X': rx, 'Y': ry, 'Z': rz}[ax]
        if abs(ang) > 1e-9:
            q = qmul(qaxis(_AX[ax], math.radians(ang)), q)
    # world-axis rotation (in rest frame) -> local
    return qmul(qmul(qinv(rq), q), rq)


# ============================================================== Blender I/O

def write_action(bpy, arm, name, L, loc, fps=30, bones=None, group_all=True):
    """Create an action with quaternion keys for all bones (every frame) + pelvis location."""
    import bpy_extras.anim_utils as au
    rig_names = [b.name for b in arm.data.bones]
    if name in bpy.data.actions:
        bpy.data.actions.remove(bpy.data.actions[name])
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = act.slots.new(id_type='OBJECT', name=arm.name)
    cb = au.action_ensure_channelbag_for_slot(act, slot)
    F = L.shape[0]
    frames = np.arange(F, dtype=float) + 0.0
    rig = Rig.from_blender(arm)
    for bi, bn in enumerate(rig.names):
        if bones is not None and bn not in bones:
            continue
        pb = arm.pose.bones[bn]
        pb.rotation_mode = 'QUATERNION'
        for c in range(4):
            fc = cb.fcurves.new('pose.bones["%s"].rotation_quaternion' % bn, index=c, group_name=bn)
            fc.keyframe_points.add(F)
            co = np.empty(F * 2)
            co[0::2] = frames
            co[1::2] = L[:, bi, c]
            fc.keyframe_points.foreach_set('co', co)
            fc.keyframe_points.foreach_set('interpolation', [1] * F)  # LINEAR
            fc.update()
        if bn == 'pelvis':
            for c in range(3):
                fc = cb.fcurves.new('pose.bones["%s"].location' % bn, index=c, group_name=bn)
                fc.keyframe_points.add(F)
                co = np.empty(F * 2)
                co[0::2] = frames
                co[1::2] = loc[:, c]
                fc.keyframe_points.foreach_set('co', co)
                fc.keyframe_points.foreach_set('interpolation', [1] * F)
                fc.update()
    act.frame_range = (0, F - 1)
    act.use_frame_range = True
    return act, slot


# ============================================================== motion edit helpers

def mirror_name(n):
    if n.endswith('_l'):
        return n[:-2] + '_r'
    if n.endswith('_r'):
        return n[:-2] + '_l'
    return n


def mirror_motion(mo):
    """Mirror left<->right across the YZ plane (x -> -x)."""
    rig = mo.rig
    dq = np.zeros_like(mo.dq)
    for b, n in enumerate(rig.names):
        mb = rig.i(mirror_name(n))
        dq[:, b] = mo.dq[:, mb] * np.array([1.0, 1.0, -1.0, -1.0])
    m = Motion(rig, dq, mo.pelvis * np.array([-1.0, 1.0, 1.0]), mo.fps)
    m.meta = dict(mo.meta)
    if hasattr(mo, 'plant_w'):
        m.plant_w = dict(mo.plant_w)
    for attr in ('ank_target', 'toe_src', 'pole'):
        if hasattr(mo, attr):
            d = getattr(mo, attr)
            setattr(m, attr, {('l' if s == 'r' else 'r'): v * np.array([-1.0, 1.0, 1.0]) for s, v in d.items()})
    return m


def add_local(mo, rots, weight=None, post=False):
    """Add rotations rots = {bone: (rx, ry, rz)} degrees about the body axes carried by the
    parent (X = character left, Y = character back, Z = up). Pre-multiplies the local basis
    (rotation in parent space) unless post=True. weight: optional (F,) curve. In place."""
    L, loc = mo.to_local()
    F = mo.F
    w = np.ones(F) if weight is None else np.asarray(weight, float)
    for bone, (rx, ry, rz) in rots.items():
        b = mo.rig.i(bone)
        qs = np.stack([body_q(mo.rig, bone, rx * wi, ry * wi, rz * wi) for wi in w])
        L[:, b] = qmul(L[:, b], qs) if post else qmul(qs, L[:, b])
    m = Motion.from_local(mo.rig, L, loc, mo.fps)
    mo.dq = m.dq
    mo.pelvis = m.pelvis
    return mo


def scale_local(mo, bones, k, ref=None):
    """Scale the deviation of local rotations from their clip mean (or ref quaternions) by k."""
    L, loc = mo.to_local()
    for bone in bones:
        b = mo.rig.i(bone)
        q = qcontinuous(L[:, b])
        mean = qn(q.mean(0)) if ref is None else ref
        dev = qlog(qmul(qinv(mean)[None], q))
        L[:, b] = qmul(mean[None], qexp(dev * k))
    m = Motion.from_local(mo.rig, L, loc, mo.fps)
    mo.dq = m.dq
    mo.pelvis = m.pelvis
    return mo


def reach_fix(mo, max_ratio=0.997, period=False, sides='lr'):
    """Lower the pelvis where an ankle target is out of reach, so IK never has to pull the
    planted foot (prevents foot slide and knee snapping on straight legs)."""
    rig = mo.rig
    H = mo.heads()
    dz = np.zeros(mo.F)
    for s in sides:
        th, ca, ft = rig.i('thigh_' + s), rig.i('calf_' + s), rig.i('foot_' + s)
        L = np.linalg.norm(rig.head[ca] - rig.head[th]) + np.linalg.norm(rig.head[ft] - rig.head[ca])
        R = max_ratio * L
        r = mo.ank_target[s] - H[:, th]
        rxy2 = np.sum(r[:, :2] ** 2, -1)
        ok = rxy2 < R * R
        need = np.where(ok, -np.sqrt(np.maximum(R * R - rxy2, 0)) - r[:, 2], 0.0)
        dz = np.maximum(dz, np.maximum(need, 0.0))
    if dz.max() <= 1e-5:
        return dz
    mode = 'wrap' if period else 'nearest'
    n = len(dz)
    dil = dz.copy()
    for k in (-2, -1, 1, 2):
        idx = (np.arange(n) + k) % n if period else np.clip(np.arange(n) + k, 0, n - 1)
        dil = np.maximum(dil, dz[idx])
    sm = gauss1d(dil, 1.5, mode=mode)
    sm = np.maximum(sm, dz)
    mo.pelvis = mo.pelvis.copy()
    mo.pelvis[:, 2] -= sm
    return sm


BODY_RADII = {'pelvis': 0.11, 'spine_01': 0.11, 'spine_02': 0.12, 'spine_03': 0.12, 'neck_01': 0.06, 'head': 0.09,
              'clavicle_l': 0.06, 'clavicle_r': 0.06, 'upperarm_l': 0.05, 'upperarm_r': 0.05,
              'lowerarm_l': 0.04, 'lowerarm_r': 0.04, 'hand_l': 0.025, 'hand_r': 0.025,
              'thigh_l': 0.07, 'thigh_r': 0.07, 'calf_l': 0.05, 'calf_r': 0.05}


def body_floor(mo, weight=None, smooth=1.0):
    """Lift the whole body (pelvis z) so no body segment (capsule approx.) goes below z=0."""
    H = mo.heads()
    T = mo.tails(H)
    rig = mo.rig
    need = np.zeros(mo.F)
    for bn, r in BODY_RADII.items():
        b = rig.i(bn)
        for a in (0.0, 0.5, 1.0):
            p = H[:, b] * (1 - a) + T[:, b] * a
            need = np.maximum(need, r - p[:, 2])
    if weight is not None:
        need = need * weight
    need = np.maximum(gauss1d(need, smooth), need)
    mo.pelvis = mo.pelvis.copy()
    mo.pelvis[:, 2] += need
    if hasattr(mo, 'ank_target'):
        pass
    return need
