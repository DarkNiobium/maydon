"""Clip definitions for the MAYDON animation library."""
import numpy as np
import process as P
import mlib as M

CLIPS = {}


def clip(fn):
    CLIPS[fn.__name__] = fn
    return fn


@clip
def walk():
    return P.process_loop('walk', 'accad/Male2/Male2_B3_Walk.bvh', (0.3, 4.3), 'fwd')


@clip
def jog():
    return P.process_loop('jog', 'cmu/35/35_17.bvh', (0.0, 1.39), 'fwd')


@clip
def run():
    return P.process_loop('run', 'cmu/102/102_05.bvh', (0.0, 0.91), 'fwd', tweak=_head_steady)


def _sprint_style(mo):
    # sprint styling on top of the athletic run: more forward lean, bigger arm pump
    M.scale_local(mo, ['upperarm_l', 'upperarm_r', 'lowerarm_l', 'lowerarm_r'], 1.25)
    M.scale_local(mo, ['neck_01', 'head'], 0.5)
    M.add_local(mo, {'spine_01': (5, 0, 0), 'spine_02': (4, 0, 0), 'neck_01': (-5, 0, 0)})


@clip
def sprint():
    # fastest real mocap run (102_05, 5.2 m/s) with quicker cadence and longer strides (IK)
    return P.process_loop('sprint', 'cmu/102/102_05.bvh', (0.0, 0.91), 'fwd', tscale=0.86, hscale=1.12,
                          tweak=_sprint_style, extra_meta={'notes': 'built from run 102_05: time x0.86, stride x1.12, lean+arm pump'})


@clip
def idle():
    return P.process_loop('idle', 'accad/Male2/Male2_A2_Sway.bvh', (0.2, 10.5), 'none', pick=('auto', 4.0))


@clip
def idle_ready():
    return P.process_loop('idle_ready', 'cmu/140/140_06.bvh', (10.0, 29.5), 'none', pick=('auto', 3.0))


def _strafe_style(mo):
    # basketball defensive slide -> football jockey: arms lower/closer, head steadier
    M.add_local(mo, {'upperarm_l': (0, 22, 0), 'upperarm_r': (0, -22, 0)})
    M.scale_local(mo, ['head'], 0.6)


def _head_steady(mo):
    M.scale_local(mo, ['neck_01', 'head'], 0.5)


def _jockey_style(mo):
    # sidestep -> defensive jockey: slightly crouched trunk, head steady
    M.add_local(mo, {'spine_01': (6, 0, 0), 'neck_01': (-4, 0, 0)})
    M.scale_local(mo, ['head'], 0.6)


@clip
def strafe_l():
    # 100STYLE neutral sidestep (clean planted feet), strides lengthened for jockeying speed
    return P.process_loop('strafe_l', '100style/100STYLE/Neutral/Neutral_SR.bvh', (7.2, 13.6), 'left', hscale=1.35,
                          tweak=_jockey_style, extra_meta={'notes': '100STYLE Neutral_SR sidestep, stride x1.35'})


@clip
def strafe_r():
    return P.process_loop('strafe_r', '100style/100STYLE/Neutral/Neutral_SR.bvh', (7.2, 13.6), 'right', mirror=True, hscale=1.35,
                          tweak=_jockey_style, extra_meta={'notes': 'mirror of strafe_l (100STYLE Neutral_SR)'})


@clip
def backpedal():
    return P.process_loop('backpedal', 'accad/Male2/Male2_C7_RunBackwards.bvh', (0.3, 2.55), 'back')


def _dribble_touch(mo):
    """Jog -> dribble: head/eyes on the ball, slight forward lean, and a right-foot touch
    (foot reaches ~9 cm further forward, toes down/out) just before the right foot lands."""
    F = mo.F
    ph = np.arange(F) / (F - 1)
    bump = np.exp(-0.5 * ((ph - 0.86) / 0.06) ** 2)
    bump[-1] = bump[0] = 0
    M.add_local(mo, {'spine_02': (5, 0, 0), 'neck_01': (8, 0, 0), 'head': (10, 0, 0)})
    M.add_local(mo, {'foot_r': (18, 0, -12)}, weight=bump)
    mo.ank_target['r'] = mo.ank_target['r'] + bump[:, None] * np.array([0.02, -0.09, 0.01])
    mo.meta['touch_phase'] = 0.86


@clip
def dribble():
    mo, meta = P.process_loop('dribble', 'cmu/35/35_18.bvh', (0.0, 1.46), 'fwd', tweak=_dribble_touch,
                              extra_meta={'notes': 'jog 35_18 + hand-keyed right-foot touch and head-down layer'})
    return mo, meta


# ------------------------------------------------------------------ kicks
def kick_contact(t_guess, win=0.15):
    """Contact = peak speed of the right toe tip near the expected kick time."""
    def f(world, mo):
        T = world.tails()
        p = T[:, P.RIG.i('ball_r')]
        v = np.linalg.norm(np.gradient(p, axis=0), axis=-1) * P.FPS
        lo = max(0, int((t_guess - win) * P.FPS))
        hi = min(world.F, int((t_guess + win) * P.FPS))
        return (lo + int(np.argmax(v[lo:hi]))) / P.FPS
    return f


def bump(F, center_t, sigma_t, fps=30.0):
    t = np.arange(F) / fps
    return np.exp(-0.5 * ((t - center_t) / sigma_t) ** 2)


def kick(name, rel, t_kick, pre=0.8, post=0.9, tweak=None, meta=None, tstretch=1.0):
    t0, t1 = t_kick - pre, t_kick + post
    return P.process_oneshot(name, rel, (t0, t1), align=('vel', 'toe_r', t_kick), contact=kick_contact(pre),
                             tweak=tweak, extra_meta=dict(meta or {}, contact_kind='right_foot'))


@clip
def kick_shot():
    return kick('kick_shot', 'cmu/11/11_01.bvh', 3.37, meta={'notes': 'instep drive, one-step approach'})


def _long_style(mo):
    F = mo.F
    w = bump(F, 0.8, 0.25)
    M.add_local(mo, {'spine_01': (-6, 0, 0), 'spine_02': (-6, 0, 0)}, weight=w)


@clip
def kick_long():
    return kick('kick_long', 'cmu/10/10_06.bvh', 3.41, tweak=_long_style,
                meta={'notes': 'instep kick with extra lean-back around contact (lofted ball)'})


def _pass_style(mo):
    """Inside-foot pass: right leg externally rotated around contact (knee and toes turned out,
    inside of the foot facing the ball), hips open slightly, gentler arms."""
    F = mo.F
    w = bump(F, 0.8, 0.13)
    ww = bump(F, 0.8, 0.3)
    H = mo.heads()
    hip = H[:, P.RIG.i('thigh_r')]
    u = M.unit(mo.ank_target['r'] - hip)
    q = M.qaxis(u, np.radians(50.0) * w)
    mo.pole['r'] = M.qrot(q, mo.pole['r'])
    M.add_local(mo, {'foot_r': (0, 0, -55)}, weight=w)
    M.add_local(mo, {'pelvis': (0, 0, -12)}, weight=ww)
    M.scale_local(mo, ['upperarm_l', 'upperarm_r'], 0.7)
    # foot a little closer to the body line (side-foot swing passes under the hip)
    mo.ank_target['r'] = mo.ank_target['r'] + w[:, None] * np.array([0.06, 0.0, 0.02])


@clip
def kick_pass():
    return kick('kick_pass', 'cmu/10/10_01.bvh', 4.97, tweak=_pass_style,
                meta={'notes': 'instep kick source turned into a side-foot pass (leg external rotation layer)'})


def _volley_style(mo):
    F = mo.F
    w = bump(F, 0.8, 0.09)
    ww = bump(F, 0.8, 0.25)
    mo.ank_target['r'] = mo.ank_target['r'] + w[:, None] * np.array([0.0, -0.06, 0.34])
    M.add_local(mo, {'spine_01': (-8, 0, 4), 'spine_02': (-6, 0, 0), 'upperarm_l': (0, 15, 0)}, weight=ww)
    mo.pelvis[:, 2] -= 0.03 * ww


@clip
def volley():
    return kick('volley', 'cmu/10/10_03.bvh', 1.13, tweak=_volley_style,
                meta={'notes': 'instep kick with contact raised ~0.35 m and torso leaning back (no volley mocap exists)'})


# ------------------------------------------------------------------ goalkeeper (mocap)
def hands_meet(t_lo, t_hi):
    def f(world, mo):
        H = world.heads()
        d = np.linalg.norm(H[:, P.RIG.i('hand_l')] - H[:, P.RIG.i('hand_r')], axis=-1)
        lo, hi = int(t_lo * P.FPS), int(t_hi * P.FPS)
        return (lo + int(np.argmin(d[lo:hi]))) / P.FPS
    return f


def hands_touch(t_lo, t_hi, thr=0.16):
    """First frame the hands come together (ball arrives), fallback = closest frame."""
    def f(world, mo):
        H = world.heads()
        d = np.linalg.norm(H[:, P.RIG.i('hand_l')] - H[:, P.RIG.i('hand_r')], axis=-1)
        lo, hi = int(t_lo * P.FPS), int(t_hi * P.FPS)
        idx = np.where(d[lo:hi] < thr)[0]
        return (lo + (idx[0] if len(idx) else int(np.argmin(d[lo:hi])))) / P.FPS
    return f


def hands_apex(t_lo, t_hi):
    """Catch moment = hands (together) reach their highest point = ball arrival."""
    def f(world, mo):
        H = world.heads()
        z = 0.5 * (H[:, P.RIG.i('hand_l'), 2] + H[:, P.RIG.i('hand_r'), 2])
        lo, hi = int(t_lo * P.FPS), int(t_hi * P.FPS)
        return (lo + int(np.argmax(z[lo:hi]))) / P.FPS
    return f


def hand_peak(bone, t_lo, t_hi):
    def f(world, mo):
        T = world.tails()
        p = T[:, P.RIG.i(bone)]
        v = np.linalg.norm(np.gradient(p, axis=0), axis=-1) * P.FPS
        lo, hi = int(t_lo * P.FPS), int(t_hi * P.FPS)
        return (lo + int(np.argmax(v[lo:hi]))) / P.FPS
    return f


@clip
def gk_catch():
    return P.process_oneshot('gk_catch', 'cmu/143/143_20.bvh', (5.6, 7.6), align='start',
                             contact=hands_apex(0.5, 1.3), tweak=_catch_style,
                             extra_meta={'contact_kind': 'hands_at_chest', 'notes': 'CMU 143 is 60 Hz data (fps fixed)'})


@clip
def gk_throw():
    return P.process_oneshot('gk_throw', 'cologne/Ballwurf.bvh', (9.9, 12.2), align=('chest_at', 10.3),
                             contact=hand_peak('hand_r', 0.6, 1.5), extra_meta={'contact_kind': 'ball_release_right_hand'})

import handclips  # noqa: E402,F401  (registers hand-keyed clips)


HOLD_BALL = {'clavicle_l': (0, 0, 0), 'clavicle_r': (0, 0, 0), 'upperarm_l': (-35, 5, 0), 'upperarm_r': (-35, -5, 0),
             'z:upperarm_l': -42, 'z:upperarm_r': 42, 'hinge:lowerarm_l': 80, 'hinge:lowerarm_r': 80,
             'hand_l': (0, 0, 0), 'hand_r': (0, 0, 0)}


def _gk_kick_style(mo):
    import handkey as K
    F = mo.F
    t = np.arange(F) / P.FPS
    release = 0.8 - 0.32
    w = np.clip((release + 0.12 - t) / 0.24, 0, 1)
    w = w * w * (3 - 2 * w)
    K.blend_to_pose(mo, HOLD_BALL, w)
    wb = bump(F, 0.8, 0.09)
    mo.ank_target['r'] = mo.ank_target['r'] + wb[:, None] * np.array([0.0, -0.04, 0.22])
    _long_style(mo)


@clip
def gk_kick():
    return kick('gk_kick', 'cmu/10/10_06.bvh', 3.41, tweak=_gk_kick_style,
                meta={'notes': 'punt: kick_long source, ball held in both hands until ~0.3 s before contact, contact raised 0.22 m',
                      'events': {'ball_release': 0.48}})


def _catch_style(mo):
    """Bring the catch from face height down to the chest."""
    F = mo.F
    t = np.arange(F) / P.FPS
    w = np.clip((t - 0.45) / 0.3, 0, 1) * np.clip((1.75 - t) / 0.35, 0, 1)
    w = w * w * (3 - 2 * w)
    M.add_local(mo, {'upperarm_l': (22, 0, 0), 'upperarm_r': (22, 0, 0)}, weight=w)


# ------------------------------------------------------------------ header / getup / celebrations
def _header_nod(mo):
    """Head-ball contact layer: neck/head cock back before the apex, snap forward through it."""
    H = mo.heads()
    z = H[:, P.RIG.i('head'), 2]
    apex = int(np.argmax(z))
    t = (np.arange(mo.F) - apex) / P.FPS
    back = np.exp(-0.5 * ((t + 0.16) / 0.07) ** 2)
    fwd = np.exp(-0.5 * ((t - 0.03) / 0.06) ** 2)
    curl = np.exp(-0.5 * ((t + 0.02) / 0.12) ** 2)
    M.add_local(mo, {'neck_01': (-14, 0, 0), 'head': (-12, 0, 0)}, weight=back)
    M.add_local(mo, {'neck_01': (20, 0, 0), 'head': (16, 0, 0)}, weight=fwd)
    M.add_local(mo, {'spine_02': (-8, 0, 0), 'spine_03': (-6, 0, 0)}, weight=back)
    M.add_local(mo, {'spine_02': (10, 0, 0), 'spine_03': (6, 0, 0)}, weight=fwd)
    # arms out for balance/leverage around the jump
    M.add_local(mo, {'upperarm_l': (-20, -25, 0), 'upperarm_r': (-20, 25, 0)}, weight=curl)
    mo.meta['apex_frame'] = apex


@clip
def header():
    return P.process_oneshot('header', 'cmu/143/143_06.bvh', (3.4, 5.25), align='start', tweak=_header_nod,
                             contact=P.apex_time('head'),
                             extra_meta={'contact_kind': 'head_at_apex', 'notes': 'standing two-foot jump (CMU 143, 60 Hz) + hand-keyed head nod'})


@clip
def getup():
    return P.process_oneshot('getup', 'cmu/140/140_01.bvh', (1.6, 5.0), align='end',
                             extra_meta={'notes': 'from lying face down to standing'})


@clip
def celebrate_2():
    return P.process_oneshot('celebrate_2', 'cologne/Take2017-01-11_02.30.59PM.bvh', (3.5, 5.6), align='start',
                             extra_meta={'notes': 'jubilating jump, arms up, drops to the knees (ends kneeling)'})


@clip
def celebrate_3():
    return P.process_oneshot('celebrate_3', 'cologne/Take2017-01-11_02.30.32PM.bvh', (4.0, 7.6), align='start',
                             extra_meta={'notes': 'fist pumps up, then crouched pumping/stamping'})


ARMS_UP = {'clavicle_l': (0, 0, 0), 'clavicle_r': (0, 0, 0), 'upperarm_l': (-20, -150, 0), 'upperarm_r': (-20, 150, 0), 'hinge:lowerarm_l': -8, 'hinge:lowerarm_r': -8,
           'head': (-12, 0, 0)}


def _arms_up(mo):
    import handkey as K
    K.blend_to_pose(mo, ARMS_UP, np.full(mo.F, 1.0))


@clip
def celebrate_1():
    return P.process_loop('celebrate_1', 'cmu/35/35_17.bvh', (0.0, 1.39), 'fwd', tweak=_arms_up,
                          extra_meta={'notes': 'celebration run: jog 35_17 with both arms raised (hand-keyed arm layer)'})


# ------------------------------------------------------------------ left foot + running strike (2026-11-21)
@clip
def kick_run():
    return kick('kick_run', 'mixamo/bvh/kick_jog.bvh', 0.53, pre=0.45, post=0.72,
                meta={'notes': 'Mixamo "Strike Forward Jog": instep strike out of a jog (shots/long balls at speed)'})


def mirrored(src, name):
    """Left-footed copy of a cached right-footed clip (mirror x -> -x, l <-> r)."""
    L, loc, meta = P.load_cached(src)
    mo = M.mirror_motion(M.Motion.from_local(P.RIG, L, loc, P.FPS))
    meta = dict(meta)
    meta['notes'] = 'mirror of %s (left foot)' % src
    if meta.get('contact_kind') == 'right_foot':
        meta['contact_kind'] = 'left_foot'
    rm = meta.get('root_motion')
    if rm:
        rm = dict(rm)
        rm['x'] = [-x for x in rm['x']]
        rm['total'] = [-rm['total'][0], rm['total'][1], rm['total'][2]]
        meta['root_motion'] = rm
    meta.pop('frames', None)
    meta.pop('fps', None)
    P.save(name, mo, meta)
    return mo, meta, None


@clip
def kick_pass_m():
    return mirrored('kick_pass', 'kick_pass_m')


@clip
def kick_shot_m():
    return mirrored('kick_shot', 'kick_shot_m')


@clip
def kick_long_m():
    return mirrored('kick_long', 'kick_long_m')


@clip
def volley_m():
    return mirrored('volley', 'volley_m')


@clip
def kick_run_m():
    return mirrored('kick_run', 'kick_run_m')


# ------------------------------------------------------------------ Mixamo replacements for hand-keyed actions (2026-11-21)
def hands_out_time(min_h=0.55, t_max=2.0):
    """Dive save moment: both hands furthest from the start point sideways while still in the air."""
    def f(world, mo):
        H = world.heads()
        hm = 0.5 * (H[:, P.RIG.i('hand_l')] + H[:, P.RIG.i('hand_r')])
        lat = np.abs(hm[:, 0] - hm[0, 0])
        lat[hm[:, 2] < min_h] = 0.0
        lat[int(t_max * P.FPS):] = 0.0
        return int(np.argmax(lat)) / P.FPS
    return f


@clip
def slide_mx():
    return P.process_oneshot('slide_mx', 'mixamo/bvh/slide_tackle.bvh', (0.2, 1.75), align='travel',
                             extra_meta={'notes': 'Mixamo "Soccer Slide Tackle": slide on the hip, right leg into the ball, gets up'})


@clip
def slide_mx_m():
    return mirrored('slide_mx', 'slide_mx_m')


@clip
def fall_mx():
    return P.process_oneshot('fall_mx', 'mixamo/bvh/trip.bvh', (0.0, 1.33), align='travel',
                             extra_meta={'notes': 'Mixamo "Soccer Trip": tripped by a tackle, tumbles and lands on the ground'})


@clip
def getup_mx():
    return P.process_oneshot('getup_mx', 'mixamo/bvh/getup_soccer.bvh', (0.25, 1.66), align='end',
                             extra_meta={'notes': 'Mixamo "Standing Up From A Soccer Fall"'})


@clip
def gk_dive_mx_l():
    return P.process_oneshot('gk_dive_mx_l', 'mixamo/bvh/gk_dive_save_l.bvh', (0.0, 3.4), align='start',
                             contact=hands_out_time(), extra_meta={'contact_kind': 'hands_full_stretch',
                                                                   'notes': 'Mixamo goalkeeper diving save (includes getting up)'})


@clip
def gk_dive_mx_r():
    return P.process_oneshot('gk_dive_mx_r', 'mixamo/bvh/gk_dive_save_r.bvh', (0.0, 3.2), align='start',
                             contact=hands_out_time(), extra_meta={'contact_kind': 'hands_full_stretch',
                                                                   'notes': 'Mixamo goalkeeper diving save (includes getting up)'})


@clip
def gk_block_mx_l():
    return P.process_oneshot('gk_block_mx_l', 'mixamo/bvh/gk_block_l.bvh', (0.0, 3.4), align='start',
                             contact=hands_out_time(0.15), extra_meta={'contact_kind': 'body_block',
                                                                       'notes': 'Mixamo goalkeeper low body block'})


@clip
def gk_block_mx_r():
    return P.process_oneshot('gk_block_mx_r', 'mixamo/bvh/gk_block_r.bvh', (0.0, 2.45), align='start',
                             contact=hands_out_time(0.15), extra_meta={'contact_kind': 'body_block',
                                                                       'notes': 'Mixamo goalkeeper low body block'})
