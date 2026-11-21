"""Hand-keyed clips (registered into clips.CLIPS)."""
import numpy as np
import handkey as K
import mlib as M
import process as P
from clips import clip

# GK set position on top of the natural idle frame (body axes: X left, Y back, Z up; degrees)
GK_SET = {
    'pelvis_pos': (0, 0.02, -0.13), 'pelvis': (8, 0, 0),
    'spine_01': (8, 0, 0), 'spine_02': (6, 0, 0), 'neck_01': (-8, 0, 0), 'head': (-6, 0, 0),
    'upperarm_l': (-35, -12, 0), 'upperarm_r': (-35, 12, 0),
    'hinge:lowerarm_l': 25, 'hinge:lowerarm_r': 25,
    'hand_l': (0, 0, 0), 'hand_r': (0, 0, 0),
    'plant_l': 1, 'plant_r': 1,
}


def pose(*dicts, **kw):
    out = {}
    for d in dicts:
        out.update(d)
    out.update(kw)
    return out


def _dive_keys(low=False):
    """GK dive to the character's RIGHT (-X). Left version = mirror."""
    s = -1.0  # right
    if not low:
        h_apex, travel, z_land = -0.10, 1.45, -0.68
        k = [
            (0.00, pose(GK_SET)),
            # load: sink, weight onto the right (near) leg, arms gather
            (0.14, pose(GK_SET, pelvis_pos=(0.10 * s, 0.02, -0.20), pelvis=(10, 6 * s, 0),
                        spine_01=(10, 4 * s, 0), upperarm_l=(-25, -5, 0), upperarm_r=(-25, 5, 0), plant_l=1, plant_r=1)),
            # push-off from the right leg, left knee drives, arms swing up
            (0.30, pose(pelvis_pos=(0.38 * s, 0.0, 0.02), pelvis=(4, 30 * s, 0), spine_01=(0, 10 * s, 0), spine_02=(0, 8 * s, 0),
                        thigh_l=(-55, 10 * s, 0), calf_l=(70, 0, 0), thigh_r=(-5, 0, 0), calf_r=(10, 0, 0),
                        upperarm_l=(-50, -110, 0), upperarm_r=(-50, 115, 0), **{'hinge:lowerarm_l': 5, 'hinge:lowerarm_r': 5},
                        head=(0, 10 * s, 0), plant_l=0, plant_r=0.8)),
            # full stretch, airborne, body near horizontal at mid height, hands to the ball
            (0.48, pose(pelvis_pos=(0.95 * s, -0.02, h_apex), pelvis=(0, 78 * s, 0), spine_01=(-4, 6 * s, 0), spine_02=(-4, 6 * s, 0),
                        thigh_l=(-25, 0, 0), calf_l=(35, 0, 0), thigh_r=(5, 5 * s, 0), calf_r=(8, 0, 0),
                        upperarm_l=(-12, -165, 0), upperarm_r=(-8, 168, 0),
                        **{'hinge:lowerarm_l': -25, 'hinge:lowerarm_r': -25}, head=(-10, 15 * s, 0), neck_01=(0, 5 * s, 0),
                        plant_l=0, plant_r=0)),
            # touchdown on the right side (hip / forearm), ball pulled in
            (0.72, pose(pelvis_pos=(1.35 * s, 0.0, -0.55), pelvis=(0, 86 * s, 0), spine_01=(4, 0, 0), spine_02=(6, 0, 0),
                        thigh_l=(-40, -8 * s, 0), calf_l=(60, 0, 0), thigh_r=(-20, 0, 0), calf_r=(30, 0, 0),
                        upperarm_l=(-60, -100, 0), upperarm_r=(-50, 110, 0),
                        **{'hinge:lowerarm_l': 40, 'hinge:lowerarm_r': 40}, head=(5, 10 * s, 0), plant_l=0, plant_r=0)),
            # settle lying on the side, ball secured at the chest, knees drawn up a little
            (1.10, pose(pelvis_pos=(1.45 * s, 0.0, -0.70), pelvis=(-2, 88 * s, 0), spine_01=(10, 0, 0), spine_02=(10, 0, 0),
                        thigh_l=(-50, -5 * s, 0), calf_l=(80, 0, 0), thigh_r=(-40, 0, 0), calf_r=(70, 0, 0),
                        upperarm_l=(-70, -40, 0), upperarm_r=(-70, 40, 0),
                        **{'hinge:lowerarm_l': 95, 'hinge:lowerarm_r': 95}, head=(10, 8 * s, 0), plant_l=0, plant_r=0)),
        ]
    else:
        k = [
            (0.00, pose(GK_SET)),
            (0.10, pose(GK_SET, pelvis_pos=(0.06 * s, 0.02, -0.19), pelvis=(10, 4 * s, 0),
                        upperarm_l=(-25, -5, 0), upperarm_r=(-25, 5, 0))),
            # collapse: near leg folds out, body falls sideways, arms reach low toward the ball
            (0.26, pose(pelvis_pos=(0.35 * s, 0.0, -0.38), pelvis=(8, 40 * s, 0), spine_01=(4, 10 * s, 0), spine_02=(4, 8 * s, 0),
                        thigh_r=(-30, 25 * s, 0), calf_r=(60, 0, 0), thigh_l=(-20, -5 * s, 0), calf_l=(30, 0, 0),
                        upperarm_l=(-60, -60, 0), upperarm_r=(-50, 70, 0),
                        **{'hinge:lowerarm_l': 0, 'hinge:lowerarm_r': 0}, head=(0, 10 * s, 0), plant_l=1, plant_r=0)),
            # full stretch along the ground, hands at the ball near the post
            (0.44, pose(pelvis_pos=(0.85 * s, -0.02, -0.72), pelvis=(2, 84 * s, 0), spine_01=(0, 6 * s, 0), spine_02=(0, 6 * s, 0),
                        thigh_l=(-15, 0, 0), calf_l=(25, 0, 0), thigh_r=(-10, 5 * s, 0), calf_r=(20, 0, 0),
                        upperarm_l=(-25, -150, 0), upperarm_r=(-20, 155, 0),
                        **{'hinge:lowerarm_l': -20, 'hinge:lowerarm_r': -20}, head=(-6, 12 * s, 0),
                        plant_l=0, plant_r=0)),
            (0.70, pose(pelvis_pos=(0.95 * s, 0.0, -0.72), pelvis=(0, 88 * s, 0), spine_01=(8, 0, 0), spine_02=(8, 0, 0),
                        thigh_l=(-40, -5 * s, 0), calf_l=(60, 0, 0), thigh_r=(-30, 0, 0), calf_r=(50, 0, 0),
                        upperarm_l=(-60, -90, 0), upperarm_r=(-50, 95, 0),
                        **{'hinge:lowerarm_l': 60, 'hinge:lowerarm_r': 60}, head=(5, 8 * s, 0), plant_l=0, plant_r=0)),
            (1.00, pose(pelvis_pos=(1.0 * s, 0.0, -0.72), pelvis=(-2, 88 * s, 0), spine_01=(10, 0, 0), spine_02=(10, 0, 0),
                        thigh_l=(-50, -5 * s, 0), calf_l=(80, 0, 0), thigh_r=(-40, 0, 0), calf_r=(70, 0, 0),
                        upperarm_l=(-70, -40, 0), upperarm_r=(-70, 40, 0),
                        **{'hinge:lowerarm_l': 95, 'hinge:lowerarm_r': 95}, head=(10, 8 * s, 0), plant_l=0, plant_r=0)),
        ]
    return k


@clip
def gk_dive_low_r():
    return K.process('gk_dive_low_r', _dive_keys(low=True), contact=0.44,
                     meta={'contact_kind': 'hands_full_stretch_low', 'notes': 'hand-keyed low collapse dive to the right'})


@clip
def gk_dive_low_l():
    return K.process('gk_dive_low_l', _dive_keys(low=True), contact=0.44, mirror=True,
                     meta={'contact_kind': 'hands_full_stretch_low', 'notes': 'mirror of gk_dive_low_r'})


@clip
def gk_dive_r():
    return K.process('gk_dive_r', _dive_keys(), contact=0.48,
                     meta={'contact_kind': 'hands_full_stretch', 'notes': 'hand-keyed lateral dive to the right, lands on right side'})


@clip
def gk_dive_l():
    return K.process('gk_dive_l', _dive_keys(), contact=0.48, mirror=True,
                     meta={'contact_kind': 'hands_full_stretch', 'notes': 'mirror of gk_dive_r'})


# =========================================================== more hand-keyed clips
IDLE = None


def _jog_base():
    return K.base_pose('jog', 0)


RUN_POSE = dict(pelvis_pos=(0, 0, -0.04), pelvis=(6, 0, 0), spine_01=(6, 0, 0), thigh_r=(-28, 0, 0), calf_r=(12, 0, 0),
                thigh_l=(28, 0, 0), calf_l=(75, 0, 0), foot_l=(25, 0, 0), upperarm_l=(-40, 0, 0), upperarm_r=(35, 0, 0),
                **{'hinge:lowerarm_l': 75, 'hinge:lowerarm_r': 75}, plant_r=1, plant_l=0)


@clip
def fall():
    """Tripped at running speed: trailing foot caught, body pitches forward, hands break the fall,
    lands face down (getup starts from this pose)."""
    k = [
        (0.00, pose(RUN_POSE)),
        (0.14, pose(pelvis_pos=(0, -0.38, -0.04), pelvis=(22, 0, 0), spine_01=(8, 0, 0), thigh_r=(30, 0, 0), calf_r=(55, 0, 0),
                    thigh_l=(-45, 0, 0), calf_l=(40, 0, 0), upperarm_l=(-55, -10, 0), upperarm_r=(-45, 10, 0),
                    **{'hinge:lowerarm_l': 40, 'hinge:lowerarm_r': 40}, plant_l=0, plant_r=0)),
        (0.32, pose(pelvis_pos=(0, -0.85, -0.30), pelvis=(45, 0, 0), spine_01=(8, 0, 0), head=(-25, 0, 0),
                    thigh_r=(20, 0, 0), calf_r=(40, 0, 0), thigh_l=(-12, 0, 0), calf_l=(30, 0, 0),
                    upperarm_l=(-100, -20, 0), upperarm_r=(-100, 20, 0), **{'hinge:lowerarm_l': 10, 'hinge:lowerarm_r': 10},
                    plant_l=0, plant_r=0)),
        (0.50, pose(pelvis_pos=(0, -1.30, -0.55), pelvis=(70, 0, 0), spine_02=(-4, 0, 0), head=(-35, 0, 0),
                    thigh_r=(6, 0, 0), calf_r=(20, 0, 0), thigh_l=(4, 0, 0), calf_l=(20, 0, 0),
                    upperarm_l=(-120, -28, 0), upperarm_r=(-120, 28, 0), **{'hinge:lowerarm_l': 40, 'hinge:lowerarm_r': 40},
                    plant_l=0, plant_r=0)),
        (0.72, pose(pelvis_pos=(0, -1.65, -0.76), pelvis=(88, 0, 0), spine_02=(-6, 0, 0), head=(-20, 0, 18),
                    thigh_r=(2, 0, 0), calf_r=(12, 0, 0), thigh_l=(0, -8, 0), calf_l=(10, 0, 0),
                    upperarm_l=(-140, -45, 0), upperarm_r=(-140, 45, 0), **{'hinge:lowerarm_l': 90, 'hinge:lowerarm_r': 90},
                    plant_l=0, plant_r=0)),
        (1.10, pose(pelvis_pos=(0, -1.75, -0.78), pelvis=(90, 0, 0), spine_02=(-4, 0, 0), head=(-15, 0, 35),
                    thigh_r=(0, 0, 0), calf_r=(8, 0, 0), thigh_l=(0, -10, 0), calf_l=(8, 0, 0),
                    upperarm_l=(-150, -50, 0), upperarm_r=(-150, 50, 0), **{'hinge:lowerarm_l': 100, 'hinge:lowerarm_r': 100},
                    plant_l=0, plant_r=0)),
    ]
    return K.process('fall', k, meta={'notes': 'hand-keyed tripped fall from a run, ends face down (matches getup start)'})


@clip
def slide():
    """Slide tackle: drop onto the left hip, right leg extended along the ground into the ball, left arm
    behind for support, then get back up. ~1.4 s."""
    sit = dict(pelvis=(-42, 18, 0), spine_01=(8, 0, 0), spine_02=(5, 0, 0), head=(22, 0, 0),
               thigh_r=(-44, 0, 0), calf_r=(4, 0, 0), foot_r=(-15, 0, 0), thigh_l=(-44, -6, 0), calf_l=(2, 0, 0),
               upperarm_l=(25, -40, 0), upperarm_r=(-55, 30, 0), **{'hinge:lowerarm_l': -5, 'hinge:lowerarm_r': 35},
               plant_l=0, plant_r=0)
    k = [
        (0.00, pose(RUN_POSE)),
        (0.15, pose(pelvis_pos=(0, -0.45, -0.35), pelvis=(-18, 10, 0), spine_01=(10, 0, 0), thigh_r=(-55, 0, 0), calf_r=(20, 0, 0),
                    thigh_l=(-30, -5, 0), calf_l=(45, 0, 0), upperarm_l=(20, -30, 0), upperarm_r=(-45, 25, 0), plant_l=0, plant_r=0)),
        (0.32, pose(sit, pelvis_pos=(0, -1.0, -0.74))),
        (0.66, pose(sit, pelvis_pos=(0, -1.85, -0.74))),
        (0.95, pose(pelvis_pos=(0, -2.1, -0.48), pelvis=(-4, 8, 0), spine_01=(28, 0, 0), spine_02=(14, 0, 0), head=(6, 0, 0),
                    thigh_r=(-75, 0, 0), calf_r=(75, 0, 0), thigh_l=(-85, -5, 0), calf_l=(125, 0, 0),
                    upperarm_l=(10, -30, 0), upperarm_r=(-45, 25, 0), plant_l=0, plant_r=0)),
        (1.40, pose(pelvis_pos=(0, -2.25, -0.08), pelvis=(8, 0, 0), spine_01=(10, 0, 0), spine_02=(4, 0, 0),
                    thigh_r=(-12, 0, 0), calf_r=(18, 0, 0), thigh_l=(-14, 0, 0), calf_l=(20, 0, 0),
                    upperarm_l=(-8, -8, 0), upperarm_r=(-8, 8, 0), plant_l=1, plant_r=1,
                    foot_off_l=(0, -2.25, 0), foot_off_r=(0, -2.25, 0))),
    ]
    return K.process('slide', k, contact=0.45,
                     meta={'contact_kind': 'right_foot_ball', 'notes': 'hand-keyed slide tackle incl. getting up'})


@clip
def trap_chest():
    k = [
        (0.00, pose()),
        (0.30, pose(pelvis_pos=(0, 0.02, -0.05), spine_01=(-5, 0, 0), spine_02=(-7, 0, 0), spine_03=(-6, 0, 0), head=(-14, 0, 0),
                    upperarm_l=(-15, -45, 0), upperarm_r=(-15, 45, 0), **{'hinge:lowerarm_l': 20, 'hinge:lowerarm_r': 20})),
        (0.50, pose(pelvis_pos=(0, 0.05, -0.07), spine_01=(-9, 0, 0), spine_02=(-12, 0, 0), spine_03=(-10, 0, 0), head=(8, 0, 0),
                    upperarm_l=(-5, -60, 0), upperarm_r=(-5, 60, 0), **{'hinge:lowerarm_l': 25, 'hinge:lowerarm_r': 25})),
        (0.64, pose(pelvis_pos=(0, 0.04, -0.08), spine_01=(-5, 0, 0), spine_02=(-6, 0, 0), spine_03=(-3, 0, 0), head=(16, 0, 0),
                    upperarm_l=(-5, -55, 0), upperarm_r=(-5, 55, 0), **{'hinge:lowerarm_l': 25, 'hinge:lowerarm_r': 25})),
        (0.90, pose(pelvis_pos=(0, -0.01, -0.08), spine_01=(8, 0, 0), spine_02=(8, 0, 0), spine_03=(4, 0, 0), head=(22, 0, 0),
                    upperarm_l=(-10, -28, 0), upperarm_r=(-10, 28, 0), **{'hinge:lowerarm_l': 20, 'hinge:lowerarm_r': 20})),
        (1.25, pose(pelvis_pos=(0, 0.0, -0.04), spine_01=(5, 0, 0), spine_02=(4, 0, 0), head=(18, 0, 0),
                    upperarm_l=(-5, -10, 0), upperarm_r=(-5, 10, 0))),
        (1.60, pose(head=(8, 0, 0))),
    ]
    return K.process('trap_chest', k, contact=0.5,
                     meta={'contact_kind': 'ball_on_chest', 'notes': 'hand-keyed: chest out, arms wide, lean back, cushion, lean forward to drop the ball'})


@clip
def throw_in():
    k = [
        (0.00, pose(upperarm_l=(-30, 0, -20), upperarm_r=(-30, 0, 20), **{'hinge:lowerarm_l': 70, 'hinge:lowerarm_r': 70})),
        (0.35, pose(upperarm_l=(-165, -10, -20), upperarm_r=(-165, 10, 20), **{'hinge:lowerarm_l': 60, 'hinge:lowerarm_r': 60},
                    head=(-10, 0, 0))),
        (0.75, pose(pelvis_pos=(0, 0.04, -0.06), pelvis=(-4, 0, 0), spine_01=(-8, 0, 0), spine_02=(-10, 0, 0), spine_03=(-8, 0, 0),
                    upperarm_l=(-185, -12, -25), upperarm_r=(-185, 12, 25), **{'hinge:lowerarm_l': 115, 'hinge:lowerarm_r': 115},
                    head=(-6, 0, 0))),
        (1.00, pose(pelvis_pos=(0, -0.03, -0.05), pelvis=(4, 0, 0), spine_01=(8, 0, 0), spine_02=(8, 0, 0), spine_03=(4, 0, 0),
                    upperarm_l=(-125, -8, 0), upperarm_r=(-125, 8, 0), **{'hinge:lowerarm_l': 10, 'hinge:lowerarm_r': 10,
                                                                           'z:upperarm_l': -32, 'z:upperarm_r': 32},
                    head=(4, 0, 0))),
        (1.25, pose(pelvis_pos=(0, -0.04, -0.06), pelvis=(6, 0, 0), spine_01=(12, 0, 0), spine_02=(10, 0, 0),
                    upperarm_l=(-75, -5, 0), upperarm_r=(-75, 5, 0), **{'hinge:lowerarm_l': 10, 'hinge:lowerarm_r': 10,
                                                                         'z:upperarm_l': -25, 'z:upperarm_r': 25},
                    head=(8, 0, 0))),
        (1.80, pose(spine_01=(3, 0, 0))),
    ]
    return K.process('throw_in', k, contact=0.98,
                     meta={'contact_kind': 'ball_release_two_hands', 'notes': 'hand-keyed two-handed throw-in from behind the head, feet planted'})


@clip
def dejected():
    hands_on_head = dict(upperarm_l=(-140, -55, 0), upperarm_r=(-140, 55, 0),
                         **{'hinge:lowerarm_l': 135, 'hinge:lowerarm_r': 135})
    k = [
        (0.00, pose()),
        (0.55, pose(hands_on_head, head=(-18, 0, 0), spine_02=(-6, 0, 0), spine_03=(-4, 0, 0))),
        (1.20, pose(hands_on_head, head=(-10, 0, 0), spine_02=(-3, 0, 0))),
        (1.90, pose(hands_on_head, head=(22, 0, 0), neck_01=(8, 0, 0), spine_01=(6, 0, 0), spine_02=(6, 0, 0),
                    pelvis_pos=(0, 0, -0.02))),
        (2.80, pose(hands_on_head, head=(26, 0, 4), neck_01=(10, 0, 0), spine_01=(8, 0, 0), spine_02=(7, 0, 0),
                    pelvis_pos=(0, 0, -0.03))),
    ]
    return K.process('dejected', k, meta={'notes': 'hand-keyed: hands on head, looks up then drops the head (ends in hold pose)'})


@clip
def clap():
    apart = dict(upperarm_l=(-45, -6, -4), upperarm_r=(-45, 6, 4), **{'hinge:lowerarm_l': 70, 'hinge:lowerarm_r': 70})
    together = dict(upperarm_l=(-48, 0, -18), upperarm_r=(-48, 0, 18), **{'hinge:lowerarm_l': 77, 'hinge:lowerarm_r': 77})
    k = [(0.00, pose()), (0.35, pose(apart, head=(4, 0, 0)))]
    claps = []
    t = 0.35
    for i in range(5):
        k.append((t + 0.16, pose(together, head=(4, 0, 0))))
        claps.append(round(t + 0.16, 3))
        k.append((t + 0.32, pose(apart, head=(4, 0, 0))))
        t += 0.32
    k.append((t + 0.45, pose()))
    return K.process('clap', k, contact=claps[0], meta={'contact_kind': 'first_clap', 'events': {'claps': claps},
                                                        'notes': 'hand-keyed applause, 5 claps'})


@clip
def tackle():
    k = [
        (0.00, pose()),
        (0.22, pose(pelvis_pos=(0.04, -0.02, -0.08), spine_01=(8, 0, 0), upperarm_l=(-15, -20, 0), upperarm_r=(-15, 20, 0),
                    plant_l=1, plant_r=1)),
        (0.45, pose(pelvis_pos=(0.02, -0.28, -0.20), pelvis=(10, 0, 8), spine_01=(12, 0, 0), spine_02=(6, 0, 0), head=(10, 0, 0),
                    thigh_r=(-60, 0, 0), calf_r=(8, 0, 0), foot_r=(-12, 0, -35), upperarm_l=(-35, -45, 0), upperarm_r=(-10, 40, 0),
                    plant_l=1, plant_r=0, foot_off_l=(0, -0.15, 0))),
        (0.70, pose(pelvis_pos=(0.02, -0.15, -0.12), pelvis=(6, 0, 4), spine_01=(10, 0, 0), thigh_r=(-30, 0, 0), calf_r=(50, 0, 0),
                    upperarm_l=(-20, -25, 0), upperarm_r=(-10, 25, 0), plant_l=1, plant_r=0, foot_off_l=(0, -0.15, 0))),
        (1.00, pose(pelvis_pos=(0, -0.04, -0.04), spine_01=(4, 0, 0), plant_l=1, plant_r=1, foot_off_l=(0, -0.05, 0))),
        (1.25, pose(plant_l=1, plant_r=1)),
    ]
    return K.process('tackle', k, contact=0.45,
                     meta={'contact_kind': 'right_foot_ball', 'notes': 'hand-keyed standing poke tackle (lunging stab of the right leg)'})


def _stepover_keys():
    crouch = dict(pelvis_pos=(0, 0, -0.07), spine_01=(8, 0, 0))
    return [
        (0.00, pose(crouch)),
        (0.15, pose(crouch, pelvis_pos=(0.07, 0, -0.08), spine_01=(8, 4, 0), plant_r=0.6)),
        (0.33, pose(pelvis_pos=(0.06, -0.02, -0.06), spine_01=(8, 0, 0), thigh_r=(-45, -12, 0), calf_r=(55, 0, 0), foot_r=(10, 0, 10),
                    upperarm_l=(-10, -20, 0), upperarm_r=(-10, 25, 0), plant_r=0, plant_l=1)),
        (0.52, pose(pelvis_pos=(-0.06, -0.02, -0.09), spine_01=(8, -10, 0), spine_02=(4, -6, 0), thigh_r=(-35, 28, 0), calf_r=(50, 0, 0),
                    foot_r=(5, 0, -20), upperarm_l=(-10, -35, 0), upperarm_r=(-5, 40, 0), head=(6, -6, 0), plant_r=0, plant_l=1)),
        (0.72, pose(pelvis_pos=(-0.14, 0.0, -0.12), spine_01=(8, -12, 0), spine_02=(4, -8, 0), upperarm_l=(-10, -40, 0), upperarm_r=(-5, 35, 0),
                    plant_r=1, plant_l=1, foot_off_r=(-0.22, -0.05, 0))),
        (0.98, pose(pelvis_pos=(-0.02, 0.0, -0.10), spine_01=(8, 6, 0), plant_r=1, plant_l=1, foot_off_r=(-0.22, -0.05, 0))),
        (1.30, pose(crouch, plant_r=1, plant_l=1, foot_off_r=(-0.10, 0, 0))),
    ]


@clip
def stepover_r():
    return K.process('stepover_r', _stepover_keys(), contact=0.42,
                     meta={'contact_kind': 'right_foot_passes_over_ball', 'notes': 'hand-keyed step-over with the right foot (feint right)'})


@clip
def stepover_l():
    return K.process('stepover_l', _stepover_keys(), contact=0.42, mirror=True,
                     meta={'contact_kind': 'left_foot_passes_over_ball', 'notes': 'mirror of stepover_r'})


@clip
def drag_back():
    k = [
        (0.00, pose(pelvis_pos=(0, 0, -0.05))),
        (0.22, pose(pelvis_pos=(0.03, 0.02, -0.07), spine_01=(-3, 0, 0), foot_r=(-25, 0, 0), plant_r=1,
                    foot_off_r=(0.0, -0.32, 0.10), upperarm_l=(-10, -20, 0), upperarm_r=(-10, 20, 0))),
        (0.48, pose(pelvis_pos=(0.03, 0.06, -0.08), spine_01=(-5, 0, 0), foot_r=(-20, 0, 0), plant_r=1,
                    foot_off_r=(0.0, 0.02, 0.05), upperarm_l=(-10, -25, 0), upperarm_r=(-10, 25, 0))),
        (0.70, pose(pelvis_pos=(0.0, 0.10, -0.08), spine_01=(2, 0, 0), plant_r=1, foot_off_r=(0.0, 0.22, 0.0))),
        (1.20, pose(pelvis_pos=(0, 0.08, -0.04), plant_r=1, foot_off_r=(0.0, 0.20, 0.0), plant_l=1, foot_off_l=(0, 0.06, 0))),
    ]
    return K.process('drag_back', k, contact=0.22,
                     meta={'contact_kind': 'right_sole_on_ball', 'notes': 'hand-keyed drag-back: right sole pulls the ball back'})


# ------------------------------------------------------------------ emotes (player-triggered, view only)
def _emote(name, hold, dur=2.4, t_in=0.35, t_out=0.45, wiggle=None, notes=''):
    """neutral -> hold pose (optionally alternating with `wiggle`) -> neutral."""
    k = [(0.00, pose()), (t_in, pose(hold))]
    t = t_in
    if wiggle:
        flip = True
        while t + 0.22 < dur - t_out:
            t += 0.22
            k.append((t, pose(hold, wiggle) if flip else pose(hold)))
            flip = not flip
    else:
        k.append((dur - t_out, pose(hold)))
    k.append((dur, pose()))
    return K.process(name, k, meta={'notes': notes or 'hand-keyed emote'})


@clip
def emote_wave():
    hold = dict(upperarm_r=(-100, 0, 0), **{'z:upperarm_r': -55, 'hinge:lowerarm_r': 70}, head=(-4, 0, 0), spine_02=(0, 0, 3))
    return _emote('emote_wave', hold, wiggle={'z:upperarm_r': -35, 'hinge:lowerarm_r': 85}, notes='wave with the right hand')


@clip
def emote_point_sky():
    hold = dict(upperarm_l=(-168, -18, 0), upperarm_r=(-168, 18, 0), **{'hinge:lowerarm_l': 6, 'hinge:lowerarm_r': 6},
                head=(-28, 0, 0), neck_01=(-8, 0, 0), spine_02=(-7, 0, 0), spine_03=(-4, 0, 0))
    return _emote('emote_point_sky', hold, dur=2.2, notes='both arms point to the sky, head up')


@clip
def emote_arms_crossed():
    hold = dict(upperarm_l=(-58, -6, -42), upperarm_r=(-58, 6, 42), **{'hinge:lowerarm_l': 122, 'hinge:lowerarm_r': 122},
                spine_01=(-4, 0, 0), spine_02=(-3, 0, 0), head=(-7, 0, 6), pelvis_pos=(0, 0, 0))
    return _emote('emote_arms_crossed', hold, dur=2.6, notes='arms crossed on the chest, chin up')


@clip
def emote_flex():
    hold = dict(upperarm_l=(-96, 0, 0), upperarm_r=(-96, 0, 0),
                **{'z:upperarm_l': 78, 'z:upperarm_r': -78, 'hinge:lowerarm_l': 105, 'hinge:lowerarm_r': 105},
                spine_02=(-5, 0, 0), head=(-6, 0, 0))
    return _emote('emote_flex', hold, dur=2.4, wiggle={'hinge:lowerarm_l': 122, 'hinge:lowerarm_r': 122},
                  notes='double biceps flex')


@clip
def lobby_idle():
    """Relaxed confident stand for the lobby / locker: upright, arms hanging,
    slow breathing, weight shifting from leg to leg (loops: last key = first)."""
    base = dict(upperarm_l=(9, -7, 0), upperarm_r=(9, 7, 0), **{'hinge:lowerarm_l': 14, 'hinge:lowerarm_r': 14},
                head=(-3, 0, 0), spine_03=(-2, 0, 0), plant_l=1, plant_r=1)
    k = [
        (0.0, pose(base)),
        (1.0, pose(base, pelvis_pos=(0.025, 0, -0.005), pelvis=(0, 0, 2), spine_02=(-1.5, 0, -1.5), head=(-4, 4, 0),
                   upperarm_l=(11, -7, 0), upperarm_r=(7, 9, 0))),
        (2.0, pose(base, spine_02=(-2.5, 0, 0), head=(-2, 0, 0))),
        (3.0, pose(base, pelvis_pos=(-0.025, 0, -0.005), pelvis=(0, 0, -2), spine_02=(-1.5, 0, 1.5), head=(-4, -5, 0),
                   upperarm_l=(7, -9, 0), upperarm_r=(11, 7, 0))),
        (4.0, pose(base)),
    ]
    return K.process('lobby_idle', k, meta={'notes': 'hand-keyed relaxed lobby stand (loop)', 'loop': True})
