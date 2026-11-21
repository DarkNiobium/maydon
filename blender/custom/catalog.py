"""Ids, texture names, default look and preview looks of the customizable footballer (used by preview.py and
make_docs.py; custom.json is generated from this + build stats)."""
import random

HAIR_IDS = ["hair_buzz", "hair_short_fade", "hair_crop", "hair_side_part", "hair_slick_back", "hair_quiff",
            "hair_curly", "hair_afro", "hair_man_bun", "hair_long", "hair_braids"]
BEARD_IDS = ["beard_stubble", "beard_short", "beard_full", "beard_goatee", "beard_mustache", "beard_chinstrap"]
BROW_IDS = ["brows_thin", "brows_normal", "brows_thick"]
BOOT_IDS = ["Boots_1", "Boots_2", "Boots_3", "Boots_4"]
ACC_IDS = ["Acc_headband", "Acc_wristband_l", "Acc_wristband_r", "Acc_gloves", "Acc_armband", "Acc_undershirt_neck"]
GEAR_IDS = ["Kit", "Sleeves_long", "Socks_low"] + BOOT_IDS + ACC_IDS
SKIN_TEX = {"light": "skin_light.jpg", "mid": "skin_mid.jpg", "dark": "skin_dark.jpg"}

HAIR_COLORS = dict(black=(0.028, 0.025, 0.022), dark_brown=(0.055, 0.036, 0.024), brown=(0.10, 0.065, 0.040),
                   light_brown=(0.22, 0.15, 0.09), blond=(0.30, 0.21, 0.11), red=(0.30, 0.10, 0.04),
                   grey=(0.30, 0.29, 0.28))
EYE_COLORS = dict(dark_brown=(0.16, 0.09, 0.05), brown=(0.30, 0.17, 0.08), hazel=(0.36, 0.28, 0.12),
                  green=(0.20, 0.32, 0.18), blue=(0.22, 0.36, 0.55), grey=(0.40, 0.42, 0.44))

# skin_tone: 0 = skin_light, 1 = skin_mid, 2 = skin_dark (linear blend between neighbours)
DEFAULT = dict(skin_tone=1.0, morphs={}, hair="hair_crop", hair_color="black", beard=None,
               beard_density=0.0, brows="brows_normal", brow_color="black", eye_color="dark_brown",
               boots="Boots_1", sleeves="short", socks="high", acc=[])

PAIRS = [("head_round", "head_square", "head_long"), ("jaw_wide", "jaw_narrow"), ("chin_out", "chin_in"),
         ("chin_wide",), ("cheekbones_high",), ("cheeks_full", "cheeks_hollow"), ("nose_wide", "nose_narrow"),
         ("nose_long", "nose_short"), ("nose_hump", "nose_flat"), ("eyes_big", "eyes_small"),
         ("eyes_wide", "eyes_close"), ("eyes_slant_up",), ("eyes_monolid",), ("brow_heavy",), ("brow_high",),
         ("lips_full", "lips_thin"), ("mouth_wide",), ("ears_big",), ("ears_out",), ("forehead_high",),
         ("face_mature",), ("body_muscular",), ("body_heavy", "body_slim")]


def random_look(seed, **force):
    """A random but plausible look. force: fixed fields (skin_tone, hair, beard, ethnic=...)."""
    r = random.Random(seed)
    morphs = {}
    for group in PAIRS:
        if r.random() < 0.55:
            k = r.choice(group)
            morphs[k] = round(min(1.0, abs(r.gauss(0.45, 0.25))), 2)
    eth = force.pop("ethnic", None)
    if eth:
        morphs["ethnic_" + eth] = force.pop("ethnic_w", 0.8)
    look = dict(DEFAULT)
    look.update(
        skin_tone=round(r.uniform(0, 2), 2), morphs=morphs, hair=r.choice(HAIR_IDS + [None]),
        hair_color=r.choice(list(HAIR_COLORS)), beard=r.choice(BEARD_IDS + [None, None]),
        beard_density=round(r.uniform(0.7, 1.0), 2), brows=r.choice(BROW_IDS), eye_color=r.choice(list(EYE_COLORS)),
        boots=r.choice(BOOT_IDS), sleeves=r.choice(["short", "short", "long"]), socks=r.choice(["high", "high", "low"]),
        acc=r.sample(["Acc_headband", "Acc_wristband_l", "Acc_wristband_r", "Acc_armband", "Acc_undershirt_neck"],
                     r.randint(0, 2)))
    look.update(force)
    if look["sleeves"] == "long":      # wristbands are sized for bare wrists
        look["acc"] = [a for a in look["acc"] if not a.startswith("Acc_wristband")]
    look["brow_color"] = look.get("brow_color", look["hair_color"])
    return look


# the 6 preview looks: random seeds, a few fields forced so the sheet covers the range
PREVIEW = [
    ("base", dict(DEFAULT)),
    ("look1", random_look(11, skin_tone=2.0, ethnic="african", hair="hair_afro", hair_color="black",
                          beard="beard_short", eye_color="dark_brown", sleeves="short", socks="low",
                          acc=["Acc_headband", "Acc_wristband_r"])),
    ("look2", random_look(23, skin_tone=0.15, ethnic="european", hair="hair_side_part", hair_color="blond",
                          beard="beard_stubble", eye_color="blue", sleeves="short", acc=["Acc_armband"])),
    ("look3", random_look(37, skin_tone=0.9, ethnic="east_asian", hair="hair_crop", hair_color="black",
                          beard=None, eye_color="dark_brown", sleeves="long", acc=[])),
    ("look4", random_look(41, skin_tone=0.7, hair="hair_long", hair_color="dark_brown", beard="beard_full",
                          eye_color="hazel", acc=["Acc_undershirt_neck"])),
    ("look5", random_look(59, skin_tone=1.6, hair="hair_braids", hair_color="black", beard="beard_goatee",
                          eye_color="brown", acc=["Acc_gloves"], sleeves="long")),
    ("look6", random_look(67, skin_tone=0.45, ethnic="european", ethnic_w=0.4, hair="hair_man_bun",
                          hair_color="red", beard="beard_chinstrap", eye_color="green", sleeves="short",
                          acc=["Acc_wristband_l"])),
]
