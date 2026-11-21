"""Morph (glTF blend shape) definitions for the MAYDON customizable footballer.

Every key is a weighted sum of MakeHuman/MPFB detail targets (data/targets/<group>/<name>.target.gz,
CC0). Names containing "x-" are expanded to both the l- and r- side. The weights are chosen so that a
blend-shape value of 1.0 gives a strong but still realistic face (checked with keysheet.py renders).

Body keys are differences between MPFB macro settings (muscle / weight), faded out on the head so they
stay independent from the face keys; the rig is not moved (deltas are small enough for skinning).
"""

# name: (description, [(target, weight), ...])
FACE = {
    "head_round": ("rounder, wider skull and face outline", [("head/head-round", 0.9), ("head/head-fat-incr", 0.15)]),
    "head_square": ("square, angular head outline with a broad jaw corner", [("head/head-square", 0.9), ("chin/chin-bones-incr", 0.25)]),
    "head_long": ("longer, narrower face and head", [("head/head-scale-vert-incr", 0.45), ("head/head-scale-horiz-decr", 0.25), ("chin/chin-height-incr", 0.4)]),
    "jaw_wide": ("wide, strong mandible (jaw angles pushed out)", [("chin/chin-bones-incr", 0.9), ("head/head-rectangular", 0.25)]),
    "jaw_narrow": ("narrow, tapered jaw", [("chin/chin-bones-decr", 1.0), ("head/head-invertedtriangular", 0.5)]),
    "chin_out": ("prominent, forward chin", [("chin/chin-prominent-incr", 0.9), ("chin/chin-prognathism-incr", 0.25)]),
    "chin_in": ("receding chin", [("chin/chin-prominent-decr", 0.9), ("chin/chin-prognathism-decr", 0.25)]),
    "chin_wide": ("broad, flat-fronted chin", [("chin/chin-width-incr", 1.3)]),
    "cheekbones_high": ("high, prominent cheekbones", [("cheek/x-cheek-bones-incr", 1.0), ("cheek/x-cheek-trans-up", 0.8)]),
    "cheeks_full": ("full, round cheeks (soft tissue)", [("cheek/x-cheek-volume-incr", 0.9), ("cheek/x-cheek-inner-incr", 0.4), ("head/head-fat-incr", 0.3)]),
    "cheeks_hollow": ("hollow, lean cheeks", [("cheek/x-cheek-volume-decr", 1.0), ("cheek/x-cheek-inner-decr", 0.8)]),
    "nose_wide": ("wide nose with broad nostrils", [("nose/nose-scale-horiz-incr", 0.6), ("nose/nose-flaring-incr", 0.7), ("nose/nose-nostrils-width-incr", 0.4)]),
    "nose_narrow": ("narrow, thin nose", [("nose/nose-scale-horiz-decr", 0.8), ("nose/nose-flaring-decr", 0.7), ("nose/nose-point-width-decr", 0.7)]),
    "nose_long": ("long nose with a lower tip", [("nose/nose-scale-vert-incr", 0.7), ("nose/nose-point-down", 0.4)]),
    "nose_short": ("short nose with a slightly upturned tip", [("nose/nose-scale-vert-decr", 0.8), ("nose/nose-point-up", 0.4)]),
    "nose_hump": ("convex bridge with a dorsal hump", [("nose/nose-hump-incr", 1.3), ("nose/nose-curve-convex", 0.5)]),
    "nose_flat": ("flat, low bridge, less projecting nose", [("nose/nose-scale-depth-decr", 0.7), ("nose/nose-greek-decr", 0.4), ("nose/nose-flaring-incr", 0.3)]),
    "eyes_big": ("larger eye openings", [("eyes/x-eye-scale-incr", 1.0)]),
    "eyes_small": ("smaller eye openings", [("eyes/x-eye-scale-decr", 1.0)]),
    "eyes_wide": ("eyes set further apart", [("eyes/x-eye-trans-out", 1.0)]),
    "eyes_close": ("eyes set closer together", [("eyes/x-eye-trans-in", 1.0)]),
    "eyes_slant_up": ("outer eye corners raised (upward canthal tilt)", [("eyes/x-eye-corner2-up", 1.2), ("eyes/x-eye-corner1-down", 0.7), ("eyes/x-eye-eyefold-angle-up", 0.4)]),
    "eyes_monolid": ("epicanthic fold / monolid upper eyelid (East / Central Asian)", [("eyes/x-eye-epicanthus-in", 1.0), ("eyes/x-eye-eyefold-down", 0.9), ("eyes/x-eye-height2-decr", 0.4)]),
    "brow_heavy": ("protruding brow ridge, deeper-set eyes", [("eyebrows/eyebrows-trans-forward", 0.5), ("forehead/forehead-nubian-incr", 0.15), ("eyebrows/eyebrows-angle-down", 0.3)]),
    "brow_high": ("brows sit higher above the eyes", [("eyebrows/eyebrows-trans-up", 0.8)]),
    "lips_full": ("full, thick lips", [("mouth/mouth-upperlip-volume-incr", 0.8), ("mouth/mouth-lowerlip-volume-incr", 0.8)]),
    "lips_thin": ("thin lips", [("mouth/mouth-upperlip-volume-decr", 0.8), ("mouth/mouth-lowerlip-volume-decr", 0.8)]),
    "mouth_wide": ("wider mouth", [("mouth/mouth-scale-horiz-incr", 0.8)]),
    "ears_big": ("larger ears", [("ears/x-ear-scale-incr", 0.8)]),
    "ears_out": ("protruding ears", [("ears/x-ear-wing-incr", 0.9)]),
    "forehead_high": ("taller forehead", [("forehead/forehead-scale-vert-incr", 0.6)]),
    "face_mature": ("older face shape: sagging cheeks and jowls, deeper folds", [("head/head-age-incr", 1.0), ("@age", 0.85)]),
}

# optional extra keys (not in the requested list): broad ethnic face shape from the MPFB race macro,
# head only. Useful for the selfie mapper; they overlap with the detail keys, use them sparingly.
EXTRA = {
    "ethnic_east_asian": ("MPFB race macro towards Asian (head only)", [("@race", dict(asian=1.0, caucasian=0.0, african=0.0))]),
    "ethnic_african": ("MPFB race macro towards African (head only)", [("@race", dict(asian=0.0, caucasian=0.0, african=1.0))]),
    "ethnic_european": ("MPFB race macro towards Caucasian (head only)", [("@race", dict(asian=0.0, caucasian=1.0, african=0.0))]),
}

# body keys: (description, macro changes relative to the base, strength)
BODY = {
    "body_muscular": ("athletic, more muscular body (MPFB muscle macro 0.5 -> 1.0)", dict(muscle=1.0), 1.0),
    "body_heavy": ("heavier body (MPFB weight macro 0.5 -> 1.0)", dict(weight=1.0), 1.0),
    "body_slim": ("slimmer, leaner body (MPFB weight macro 0.5 -> 0.0)", dict(weight=0.0), 1.0),
}

ORDER = list(FACE.keys()) + list(EXTRA.keys()) + list(BODY.keys())


def expand(targets):
    out = []
    for t, w in targets:
        if t.startswith("@"):
            out.append((t, w))
        elif "/x-" in t:
            out.append((t.replace("/x-", "/l-"), w))
            out.append((t.replace("/x-", "/r-"), w))
        else:
            out.append((t, w))
    return out
