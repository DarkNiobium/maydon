"""The 12 MAYDON footballer variants.

race = (asian, caucasian, african) MPFB macro weights. targets = MPFB detail targets (folder/name: weight);
keys containing 'x-' are expanded to both l- and r- sides. skin.tex = MakeHuman CC0 skin textures (blended),
tone/sat/val = colour grade. hair_paint = buzz/fade stubble painted into the skin texture (scalp mask);
beard = painted stubble/beard. hair_cards = MakeHuman hair asset (alpha-tested cards), scale = shrink
towards the scalp, keep_above_hz = remove side cards for fades, cut_below_z_rel = cut long hair.

Every variant gets ATHLETE + MASC defaults (real footballer shoulder/leg/neck mass and a male face
outline); per-variant targets override them.
"""

ASIAN = "young_asian_male/young_lightskinned_male_diffuse3.png"
ASIAN_MID = "middleage_asian_male/middleage_lightskinned_male_diffuse2.png"
CAUC = "young_caucasian_male/young_lightskinned_male_diffuse.png"
CAUC2 = "young_caucasian_male2/young_lightskinned_male_diffuse2.png"
CAUC_MID = "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png"
AFR = "young_african_male/young_darkskinned_male_diffuse.png"
AFR_MID = "middleage_african_male/middleage_darkskinned_male_diffuse.png"

BLACK = (0.045, 0.040, 0.036)
DARK_BROWN = (0.075, 0.055, 0.040)
BROWN = (0.13, 0.09, 0.06)
LIGHT_BROWN = (0.22, 0.15, 0.09)

UZ_SKIN = dict(tex=[ASIAN, CAUC2], blend=0.45, tone=(0.97, 0.93, 0.83), sat=0.85, val=0.97, ao=0.5)
UZ_TAN = dict(tex=[ASIAN, CAUC2], blend=0.35, tone=(0.92, 0.85, 0.72), sat=0.88, val=0.93, ao=0.5)

# Athletic silhouette. Applied to every variant, scaled by spec["athlete"].
ATHLETE = {
    "torso/torso-vshape-incr": 0.80,
    "torso/measure-shoulder-dist-incr": 0.62,
    "torso/torso-muscle-pectoral-incr": 0.48,
    "torso/torso-muscle-dorsi-incr": 0.38,
    "torso/torso-scale-depth-incr": 0.15,
    "hip/hip-scale-horiz-decr": 0.12,
    "neck/neck-scale-horiz-incr": 0.42,
    "neck/measure-neck-circ-incr": 0.24,
    "neck/neck-scale-vert-decr": 0.28,
    "arms/x-upperarm-muscle-incr": 0.58,
    "arms/x-lowerarm-muscle-incr": 0.40,
    "arms/x-upperarm-shoulder-muscle-incr": 0.35,
    "arms/x-upperarm-scale-horiz-incr": 0.13,
    "arms/x-lowerarm-scale-horiz-incr": 0.10,
    "hands/x-hand-scale-decr": 0.28,
    "hands/x-hand-fingers-length-decr": 0.38,
    "hands/x-hand-fingers-diameter-decr": 0.10,
    "legs/x-upperleg-muscle-incr": 0.65,
    "legs/x-lowerleg-muscle-incr": 0.58,
    "legs/x-upperleg-scale-horiz-incr": 0.13,
    "legs/x-lowerleg-scale-horiz-incr": 0.11,
    "legs/measure-thigh-circ-incr": 0.26,
    "legs/measure-calf-circ-incr": 0.32,
}

# Male face structure: broad jaw, brow ridge, thinner lips, corners up (not the default MPFB pout).
MASC = {
    "head/head-square": 0.25,
    "head/head-scale-vert-decr": 0.12,
    "chin/chin-width-incr": 0.30,
    "chin/chin-bones-incr": 0.20,
    "chin/chin-prominent-incr": 0.24,
    "nose/nose-scale-depth-incr": 0.08,
    "cheek/x-cheek-bones-incr": 0.32,
    "ears/x-ear-scale-decr": 0.12,
    "ears/x-ear-wing-decr": 0.08,
    "eyebrows/eyebrows-trans-forward": 0.15,
    "eyes/x-eye-scale-decr": 0.12,
    "eyes/x-eye-corner2-up": 0.15,
    "mouth/mouth-angles-up": 0.34,
    "mouth/mouth-upperlip-volume-decr": 0.15,
    "mouth/mouth-lowerlip-volume-decr": 0.08,
    "mouth/mouth-scale-horiz-incr": 0.08,
    "nose/nose-scale-horiz-incr": 0.10,
}


def _expand(targets):
    out = {}
    for k, w in targets.items():
        if "/x-" in k:
            out[k.replace("/x-", "/l-")] = w
            out[k.replace("/x-", "/r-")] = w
        else:
            out[k] = w
    return out


def _v(**kw):
    t = dict(ATHLETE)
    t.update(MASC)
    ath = float(kw.pop("athlete", 1.0))
    for k, w in list(t.items()):
        t[k] = w * ath
    for k, w in kw.pop("targets", {}).items():
        t[k] = w  # per-variant explicit values win
    kw["targets"] = _expand(t)
    kw.setdefault("proportions", 0.55)
    kw.setdefault("boots", "shoes05")
    kw.setdefault("eyes", "brown")
    kw.setdefault("beard", {})
    kw.setdefault("brow", "eyebrow002")
    kw.setdefault("lashes", "eyelashes01")
    kw.setdefault("skin_size", 1536)
    return kw


VARIANTS = {
    # Uzbek central midfielder, skin fade + textured top, light stubble
    "p01": _v(role="CM", age=24, height=1.78, muscle=0.72, weight=0.48, race=(0.55, 0.45, 0.0),
              skin=UZ_SKIN, hair_color=BLACK, brow="eyebrow002",
              hair_paint=dict(density=0.9, fade_lo=-0.1, fade_hi=0.5, fade_min=0.4),
              hair_cards=dict(asset="short01", scale=0.95, taper=(0.35, 0.75, 0.25), max_tris=1700),
              beard=dict(density=0.22),
              targets={"nose/nose-hump-incr": 0.2, "chin/chin-width-incr": 0.2, "ears/x-ear-flap-incr": 0.2,
                       "eyebrows/eyebrows-angle-up": 0.2, "head/head-oval": 0.3}),
    # slim young winger, classic short cut
    "p02": _v(role="RW", age=19, height=1.72, muscle=0.62, weight=0.38, race=(0.62, 0.38, 0.0),
              athlete=0.82,
              skin=UZ_SKIN, hair_color=BLACK, brow="eyebrow004",
              hair_paint=dict(density=0.88, fade_lo=-0.1, fade_hi=0.45, fade_min=0.5),
              hair_cards=dict(asset="short01", scale=0.88, taper=(0.3, 0.7, 0.5), max_tris=2000),
              targets={"nose/nose-scale-horiz-decr": 0.2, "chin/chin-prominent-incr": 0.2,
                       "head/head-invertedtriangular": 0.3, "ears/x-ear-scale-incr": 0.2,
                       "cheek/x-cheek-bones-incr": 0.25}),
    # strong centre-back, buzz cut, full short beard
    "p03": _v(role="CB", age=29, height=1.88, muscle=0.90, weight=0.62, race=(0.45, 0.55, 0.0),
              athlete=1.12,
              skin=dict(tex=[ASIAN_MID, CAUC2], blend=0.4, tone=(0.95, 0.87, 0.77), sat=0.9, val=0.94, ao=0.5),
              hair_color=BLACK, brow="eyebrow009", eyes="brownlight", boots="shoes02",
              hair_paint=dict(density=0.93, fade_lo=-0.1, fade_hi=0.3, fade_min=0.55),
              hair_cards=dict(asset="short02", scale=0.32, max_tris=1500, alpha_boost=1.6),
              beard=dict(density=0.9, edge_lo=0.28, edge_hi=0.52),
              targets={"head/head-square": 0.5, "chin/chin-width-incr": 0.4, "nose/nose-volume-incr": 0.3,
                       "nose/nose-hump-incr": 0.3, "eyebrows/eyebrows-trans-down": 0.2,
                       "neck/neck-scale-horiz-incr": 0.3, "ears/x-ear-rot-backward": 0.3}),
    # quick winger, slicked side cut
    "p04": _v(role="LW", age=22, height=1.74, muscle=0.65, weight=0.42, race=(0.66, 0.34, 0.0),
              athlete=0.9,
              skin=UZ_SKIN, hair_color=BLACK, brow="eyebrow001",
              hair_paint=dict(density=0.8, fade_lo=0.0, fade_hi=0.45, fade_min=0.4),
              hair_cards=dict(asset="short04", scale=0.95, max_tris=1100),
              targets={"head/head-round": 0.3, "nose/nose-point-up": 0.2, "mouth/mouth-upperlip-volume-incr": 0.2,
                       "eyes/x-eye-epicanthus-in": 0.3, "cheek/x-cheek-bones-incr": 0.3}),
    # experienced full-back, short cut, heavy stubble
    "p05": _v(role="LB", age=31, height=1.83, muscle=0.78, weight=0.57, race=(0.5, 0.5, 0.0),
              skin=dict(tex=[ASIAN_MID, CAUC2], blend=0.35, tone=(0.95, 0.87, 0.77), sat=0.92, val=0.95, ao=0.5),
              hair_color=DARK_BROWN, brow="eyebrow003",
              hair_paint=dict(density=0.85),
              hair_cards=dict(asset="short01", scale=1.25, max_tris=2000),
              beard=dict(density=0.45),
              targets={"head/head-rectangular": 0.4, "nose/nose-flaring-incr": 0.3, "chin/chin-cleft-incr": 0.3,
                       "forehead/forehead-temple-incr": 0.2}),
    # attacking midfielder with longer slicked-back hair
    "p06": _v(role="AM", age=26, height=1.80, muscle=0.70, weight=0.47, race=(0.4, 0.6, 0.0),
              skin=UZ_SKIN, hair_color=DARK_BROWN, brow="eyebrow008", eyes="brownlight",
              hair_paint=dict(density=0.85),
              hair_cards=dict(asset="short04", scale=1.4, max_tris=1200),
              beard=dict(density=0.3),
              targets={"head/head-oval": 0.4, "nose/nose-scale-vert-incr": 0.3, "nose/nose-greek-incr": 0.2,
                       "chin/chin-prominent-incr": 0.3}),
    # Kazakh-looking striker, high fade
    "p07": _v(role="ST", age=20, height=1.75, muscle=0.68, weight=0.44, race=(0.78, 0.22, 0.0),
              athlete=0.88,
              skin=dict(tex=[ASIAN, CAUC2], blend=0.25, tone=(1.0, 0.93, 0.83), sat=0.9, val=0.97, ao=0.5),
              hair_color=BLACK, brow="eyebrow010", boots="shoes02",
              hair_paint=dict(density=0.9, fade_lo=0.05, fade_hi=0.6, fade_min=0.25),
              hair_cards=dict(asset="short01", scale=0.85, taper=(0.45, 0.85, 0.15), max_tris=1700),
              targets={"head/head-round": 0.4, "cheek/x-cheek-bones-incr": 0.5, "eyes/x-eye-epicanthus-in": 0.4,
                       "nose/nose-scale-depth-decr": 0.3, "ears/x-ear-flap-incr": 0.3}),
    # tall goalkeeper / veteran, short cut, goatee
    "p08": _v(role="GK", age=34, height=1.91, muscle=0.76, weight=0.64, race=(0.5, 0.5, 0.0),
              skin=dict(tex=[ASIAN_MID, CAUC_MID], blend=0.5, tone=(0.95, 0.87, 0.77), sat=0.9, val=0.95, ao=0.55),
              hair_color=BLACK, brow="eyebrow012",
              hair_paint=dict(density=0.88, fade_lo=-0.05, fade_hi=0.4, fade_min=0.45),
              hair_cards=dict(asset="short04", scale=0.85, max_tris=1100),
              beard=dict(density=0.7, style="goatee", edge_lo=0.3, edge_hi=0.55),
              targets={"head/head-square": 0.3, "nose/nose-hump-incr": 0.5, "nose/nose-scale-vert-incr": 0.2,
                       "chin/chin-height-incr": 0.3, "eyebrows/eyebrows-trans-down": 0.3}),
    # European (Slavic) centre-back
    "p09": _v(role="CB", age=27, height=1.86, muscle=0.80, weight=0.54, race=(0.0, 1.0, 0.0),
              skin=dict(tex=[CAUC, CAUC2], blend=0.5, tone=(1.0, 0.96, 0.93), sat=0.9, val=1.0, ao=0.5),
              hair_color=LIGHT_BROWN, brow="eyebrow002", brow_color=BROWN, eyes="bluegreen",
              hair_paint=dict(density=0.75),
              hair_cards=dict(asset="short01", scale=0.92, max_tris=2000),
              beard=dict(density=0.25),
              targets={"head/head-oval": 0.3, "nose/nose-point-width-decr": 0.3, "chin/chin-prominent-incr": 0.3,
                       "eyebrows/eyebrows-angle-down": 0.2}),
    # African forward, short curly afro
    "p10": _v(role="ST", age=23, height=1.85, muscle=0.84, weight=0.52, race=(0.0, 0.05, 0.95),
              athlete=1.05,
              skin=dict(tex=[AFR], tone=(1.0, 1.0, 1.0), sat=1.0, val=1.0, ao=0.45),
              hair_color=BLACK, brow="eyebrow004",
              hair_paint=dict(density=0.9),
              hair_cards=dict(asset="afro01", scale=0.72, max_tris=2100, alpha_boost=1.5),
              beard=dict(density=0.2),
              targets={"nose/nose-flaring-incr": 0.4, "nose/nose-scale-horiz-incr": 0.3,
                       "mouth/mouth-lowerlip-volume-incr": 0.3, "head/head-oval": 0.2, "chin/chin-width-incr": 0.2}),
    # Middle-Eastern defensive midfielder, full beard
    "p11": _v(role="DM", age=28, height=1.79, muscle=0.76, weight=0.54, race=(0.1, 0.8, 0.1),
              skin=dict(tex=[CAUC2, ASIAN], blend=0.3, tone=(0.88, 0.77, 0.64), sat=0.95, val=0.93, ao=0.5),
              hair_color=BLACK, brow="eyebrow009", boots="shoes02",
              hair_paint=dict(density=0.88, fade_lo=-0.05, fade_hi=0.4, fade_min=0.4),
              hair_cards=dict(asset="short04", scale=0.9, max_tris=1100),
              beard=dict(density=0.85, edge_lo=0.25, edge_hi=0.5),
              targets={"nose/nose-hump-incr": 0.6, "nose/nose-greek-incr": 0.2, "eyebrows/eyebrows-trans-down": 0.3,
                       "head/head-rectangular": 0.3, "chin/chin-width-incr": 0.2}),
    # 18-year-old academy talent, crew cut
    "p12": _v(role="CM", age=18, height=1.70, muscle=0.56, weight=0.38, race=(0.6, 0.4, 0.0),
              athlete=0.72,
              skin=UZ_SKIN, hair_color=BLACK, brow="eyebrow001",
              hair_paint=dict(density=0.85),
              hair_cards=dict(asset="short02", scale=0.8, max_tris=2000),
              targets={"head/head-invertedtriangular": 0.3, "nose/nose-scale-horiz-decr": 0.2,
                       "ears/x-ear-scale-incr": 0.3, "chin/chin-height-decr": 0.2}),
}
