# MAYDON footballer characters

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
| p01 | CM | 24 | 1.78 | Central Asian | fade | light stubble | brown | 4577 | 3667 | 1699 | **9943** |
| p02 | RW | 19 | 1.72 | Central Asian | short, tapered sides | - | brown | 4398 | 3547 | 1999 | **9944** |
| p03 | CB | 29 | 1.88 | Central Asian | buzz cut | beard | brownlight | 4697 | 3748 | 1499 | **9944** |
| p04 | LW | 22 | 1.74 | Central Asian | slicked short | - | brown | 4968 | 3925 | 1050 | **9943** |
| p05 | LB | 31 | 1.82 | Central Asian | textured / voluminous | stubble | brown | 4394 | 3547 | 1998 | **9939** |
| p06 | AM | 26 | 1.79 | Central Asian | longer, slicked back | stubble | brownlight | 4964 | 3925 | 1050 | **9939** |
| p07 | ST | 20 | 1.75 | Central Asian | fade | - | brown | 4575 | 3666 | 1699 | **9940** |
| p08 | GK | 34 | 1.91 | Central Asian | slicked short | goatee | brown | 4966 | 3925 | 1050 | **9941** |
| p09 | CB | 27 | 1.86 | European | short | light stubble | bluegreen | 4397 | 3544 | 1999 | **9940** |
| p10 | ST | 23 | 1.85 | African | short afro / curly | light stubble | brown | 4339 | 3506 | 2100 | **9945** |
| p11 | DM | 28 | 1.79 | Middle-Eastern | slicked short | beard | brown | 4972 | 3925 | 1050 | **9947** |
| p12 | CM | 18 | 1.70 | Central Asian | mushroom fringe | - | brown | 4394 | 3546 | 2000 | **9940** |

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

`Root`, `pelvis`, `spine_01`, `spine_02`, `spine_03`, `clavicle_l`, `upperarm_l`, `lowerarm_l`, `hand_l`, `index_01_l`, `index_02_l`, `index_03_l`, `middle_01_l`, `middle_02_l`, `middle_03_l`, `pinky_01_l`, `pinky_02_l`, `pinky_03_l`, `ring_01_l`, `ring_02_l`, `ring_03_l`, `thumb_01_l`, `thumb_02_l`, `thumb_03_l`, `clavicle_r`, `upperarm_r`, `lowerarm_r`, `hand_r`, `index_01_r`, `index_02_r`, `index_03_r`, `middle_01_r`, `middle_02_r`, `middle_03_r`, `pinky_01_r`, `pinky_02_r`, `pinky_03_r`, `ring_01_r`, `ring_02_r`, `ring_03_r`, `thumb_01_r`, `thumb_02_r`, `thumb_03_r`, `neck_01`, `head`, `thigh_l`, `calf_l`, `foot_l`, `ball_l`, `thigh_r`, `calf_r`, `foot_r`, `ball_r`

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
