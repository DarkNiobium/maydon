#!/usr/bin/env python3
"""Writes ~/maydon/game/assets/chars/README.md and variants/manifest.json from work/*/stats.json."""
import json, os, glob, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from variants import VARIANTS  # noqa: E402
import check_glb  # noqa: E402

OUT = os.path.expanduser("~/maydon/game/assets/chars")
stats = {}
for p in sorted(glob.glob(os.path.join(HERE, "work", "p*", "stats.json"))):
    s = json.load(open(p))
    stats[s["name"]] = s

rows = []
manifest = {}
bones = None
for name in sorted(VARIANTS):
    v = VARIANTS[name]
    s = stats.get(name)
    glb = os.path.join(OUT, "variants", name + ".glb")
    if not s or not os.path.exists(glb):
        continue
    chk = check_glb.check(glb)
    bones = chk.get("joints")
    per = {p["material"]: p["tris"] for p in chk["primitives"]}
    a, c, f = v["race"]
    look = "Central Asian" if a >= 0.4 else "African" if f > 0.5 else "Middle-Eastern" if (f > 0 or a > 0) else "European"
    hair = v.get("hair_cards", {}).get("asset", "-")
    hp = v.get("hair_paint", {})
    if hair == "short02" and v["hair_cards"].get("scale", 1) < 0.5:
        style = "buzz cut"
    elif (v["hair_cards"].get("taper") or (0, 0, 1))[2] < 0.35 or hp.get("fade_min", 1.0) < 0.35:
        style = "fade"
    elif v["hair_cards"].get("taper"):
        style = "short, tapered sides"
    elif hair == "afro01":
        style = "short afro / curly"
    elif hair == "short04" and v["hair_cards"].get("scale", 1) > 1.2:
        style = "longer, slicked back"
    elif hair == "short04":
        style = "slicked short"
    elif hair == "short01" and v["hair_cards"].get("scale", 1) > 1.15:
        style = "textured / voluminous"
    elif hair == "short02":
        style = "mushroom fringe"
    else:
        style = "short"
    beard = v.get("beard", {})
    bd = beard.get("density", 0)
    btxt = "-" if bd < 0.1 else ("light stubble" if bd < 0.3 else "stubble" if bd < 0.55 else beard.get("style", "beard"))
    sole = -chk["bbox_min"][1]
    rows.append("| %s | %s | %d | %.2f | %s | %s | %s | %s | %d | %d | %d | **%d** |" % (
        name, v.get("role", ""), v["age"], s["height"], look, style, btxt, v.get("eyes", "brown"),
        per.get("skin", 0), per.get("kit", 0), per.get("hair", 0), chk["tris"]))
    manifest[name] = dict(role=v.get("role"), age=v["age"], height_m=round(s["height"], 3), look=look,
                          hair=style, beard=btxt, tris=chk["tris"], tris_per_material=per,
                          boot_sole_below_ground_m=round(sole, 3), file="variants/%s.glb" % name)

with open(os.path.join(OUT, "variants", "manifest.json"), "w") as fh:
    json.dump(manifest, fh, indent=1)

any_s = next(iter(stats.values()), {})
uv2 = any_s.get("uv2") or {}
readme = """# MAYDON footballer characters

12 rigged, kitted footballers for the match view (`variants/p01.glb` … `p12.glb`) plus `preview.png`
(EEVEE contact sheet: 12 front views in A-pose, face close-ups, back/side view with a UV2 number test).
Generated procedurally in Blender 5.2 (headless) with the MPFB2 add-on and CC0 MakeHuman assets.

## Regenerate

```sh
# all 12 variants (≈30 s each, GPU used for the AO bake), then preview + README
nice blender -b --python ~/maydon/blender/chars/build_chars.py
nice blender -b --python ~/maydon/blender/chars/build_chars.py -- p03 p07     # selected ones
nice blender -b --python ~/maydon/blender/chars/preview.py                    # -> assets/chars/preview.png
python3 ~/maydon/blender/chars/make_readme.py                                 # this file + manifest.json
python3 ~/maydon/blender/chars/check_glb.py ~/maydon/game/assets/chars/variants/*.glb   # validator
nice blender -b --python ~/maydon/blender/chars/posetest.py -- p03           # deformation check render
```

Sources in `~/maydon/blender/chars/`: `variants.py` (the 12 specs: macros, face targets, skin, hair,
beard), `mlib.py` (pipeline), `build_chars.py` (per-variant build + export), `preview.py`, `posetest.py`,
`check_glb.py`, `make_readme.py`. `masks_cache.json` holds per-vertex scalp/beard masks (deleted ⇒ recomputed).

## What is in each GLB

* Node tree: `Armature` → `Skeleton3D` with **`Body`** (skinned; surfaces `skin`, `hair`) and **`Kit`**
  (skinned; surface `kit`). Both share the one skin/skeleton. No animations, cameras or lights.
  The kit is a separate mesh so that `COLOR_0`/`UV2` exist only there (glTF importers multiply baseColor by
  `COLOR_0`; skin and hair therefore carry no vertex colours).
* Units metres, Y-up, character faces +Z (Blender glTF exporter default). Feet (bare soles) at y = 0;
  boot soles reach ≈1.7 cm below 0 (`manifest.json: boot_sole_below_ground_m`).
* Exactly three materials: `skin` (1024² JPEG albedo atlas: body + eyes + teeth, painted brows,
  stubble/beard, buzz/fade hair, baked AO), `kit` (512² PNG, neutral light grey, AO-shaded, boot details
  in the boot UV area), `hair` (512² PNG RGBA, alpha **MASK** cutoff 0.5, double-sided). Skin/kit are
  single-sided (`doubleSided=false`).
* Skin weights: ≤ 4 influences, normalised. Eyes and teeth are weighted to `head`.
* Rest pose: **MPFB default (MakeHuman base pose)** — arms down at ≈45° from horizontal, elbows slightly bent
  with the forearms pointing a bit forward, legs straight. Not a T-pose. The preview straightens the forearms
  with pose bones only (rest pose in the files is untouched). Bone rest transforms differ per variant (MPFB
  fits the rig to each body), names/hierarchy are identical.

### Triangle counts (≤ 10 000 incl. kit, hair, eyes, teeth)

| file | role | age | height m | look | hair | beard | eyes | skin tris | kit tris | hair tris | total |
|---|---|---|---|---|---|---|---|---|---|---|---|
""" + "\n".join(rows) + """

Skin tris include eyes (172, low-poly MakeHuman eyes) and teeth (~140). The tongue and the mouth cavity
are removed (game_engine has no jaw bone). Kit tris include both boots (~820).

## Kit encoding (for the recolour shader)

**COLOR_0** (only on the `Kit` mesh, VEC4 float, per-corner so borders are crisp):

| part | R | G | B | A |
|---|---|---|---|---|
| shirt body + sleeves | 1.0 | 0 | 0 | 0 |
| shirt trims: collar band (crew neck) + inner lip, sleeve cuffs (~2.2 cm) + sleeve rims | **0.5** | 0 | 0 | 0 |
| shorts (incl. hem rims) | 0 | 1.0 | 0 | 0 |
| socks (incl. top rim) | 0 | 0 | 1.0 | 0 |
| boots | 0 | 0 | 0 | 1.0 |

**UV2 / TEXCOORD_1** (shirt only; other kit parts have UV2 = (0,0)) — flat front/back projection in glTF
convention (v as stored in the file):
* front: `x = X / halfChestWidth` clamped to **[-1, 1]** (x grows towards the character's left = the viewer's
  right when looking at the chest);
* back: `x = 2 - X / halfChestWidth`, i.e. **[1, 3]** (x grows towards the viewer's right when looking at
  the back, so text reads correctly from behind);
* `y = 0` at the shirt's bottom hem (the shirt is worn untucked; hem ≈5 cm below the hip joint, over the
  shorts) and `y = 1` at the collar line (front collar height on the front, back collar height on the back).
  The shorts waistband (hidden under the shirt) is at y ≈ 0.22 on every variant; the collar band goes
  slightly above 1 (max ≈1.12). Sleeves/shoulders are clamped to the |x| ≤ 1 range of their side.
  Decimation interpolation can overshoot the ends by ≤ 0.002 (e.g. 3.0016); front ≤ 1.0 < back.
* Front/back is decided per face (front = face normal pointing forward, +Z in glTF space), so the side seam
  is a UV2 seam.
* The preview places a back number in x∈[1.45, 2.55], y∈[0.28, 0.83] and a chest number in
  x∈[0.18, 0.58], y∈[0.58, 0.80] — a working example of the convention.

UV0 of the kit is the MakeHuman body layout (kit pieces were made from body faces); boots use a rectangle
inside the (otherwise unused) head area of the kit texture.

## How the kit is built (summary)

Body faces of the full-resolution MakeHuman mesh are cut with implicit surfaces (sleeve plane at 47 % of
the upper arm, cuff 2.2 cm above, crew-neck curve around the neck axis, shirt hem / waistband planes relative
to the hip joint, shorts hem at 48 % of the thigh, sock top at 13 % of the calf), duplicated, pushed out along
the normals (shirt 1.1–1.8 cm with a cloth-like Laplacian drape constrained outside the body, shorts
0.8 cm → 2.8 cm flared hem, socks 0.3 cm + shin-guard bump), closed with inward rims welded to the skin
edge (no gaps, no z-fighting), and the hidden body faces are deleted. Weights are copied from the body.
Then the whole thing is decimated region by region (kit / head / hands / other skin) with the rim and
cut loops pinned.

## Bones (MPFB `game_engine` rig, unchanged, 53 bones)

""" + ", ".join("`%s`" % b for b in (bones or [])) + """

Hierarchy: `Root` → `pelvis` → `spine_01..03` → `neck_01` → `head`; `spine_03` → `clavicle_l/r` →
`upperarm` → `lowerarm` → `hand` → `thumb/index/middle/ring/pinky_01..03`; `pelvis` → `thigh_l/r` →
`calf` → `foot` → `ball`.

## Assets and licences

| asset | source | licence |
|---|---|---|
| base mesh, macro/detail targets, `game_engine` rig + weights | MPFB2 2.0.18 add-on data (MakeHuman) | CC0 (MakeHuman assets; the MPFB code itself is GPL but no code is shipped) |
| skins: young/middleage asian, caucasian, caucasian2, african male | MakeHuman system assets (`~/mh_assets_dl/extracted`, `makehuman_system_assets.json`) | CC0 |
| eyes low-poly + iris textures, teeth_base, eyebrow001–012 textures | MakeHuman system assets | CC0 |
| hair short01/02/04, afro01 (cards + textures) | MakeHuman system assets | CC0 |
| shoes05 / shoes02 (boot mesh, texture desaturated) | MakeHuman system assets | CC0 |
| kit geometry, beard/stubble/fade painting, AO, atlases, all scripts | made for MAYDON | own work (CC0-compatible) |

No other downloads were used. The MakeHuman watermark in the original skin textures lies outside all UV islands.

## Known limitations

* The face uses the MakeHuman photo skins → good at match distance, a bit smooth/plastic in extreme close-ups;
  no normal map on the skin.
* Hair is MakeHuman cards cut / shrunk; with alpha scissor and mipmaps it thins at distance (enable alpha
  antialiasing / alpha-to-coverage in Godot if available on the target).
* Boots are MakeHuman sneakers (no studs); the recolour shader should treat their luminance as detail.
* Cloth is skinned exactly like the body: extreme poses (arm raised over the head) stretch the sleeve; the
  shirt can show slight intersections in the armpit when the arm is fully lowered against the torso.
"""
open(os.path.join(OUT, "README.md"), "w").write(readme)
print("README written,", len(rows), "variants")
