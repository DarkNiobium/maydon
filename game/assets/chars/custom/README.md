# MAYDON customizable footballer (`base.glb`)

One rigged base body with blend shapes, interchangeable hair / boots / gear meshes and skin-space masks for
a PUBG-style character creator (and for the selfie → parameters mapper). Generated headless in Blender 5.2
with MPFB2 and CC0 MakeHuman assets by the scripts in `~/maydon/blender/custom/`. `preview.png` shows the
base look and 6 random looks rendered from the exported GLB (shader maths approximated in EEVEE: top row full
body, then face front / three-quarter / back). Machine-readable spec: `custom.json`.

## Rebuild

```sh
python3 ~/maydon/blender/custom/build.py              # resumable: runs only stale/missing stages
python3 ~/maydon/blender/custom/build.py --force      # everything (~6 min, CPU only: the GPU is left to Godot)
python3 ~/maydon/blender/custom/build.py --from=build # geometry + later stages
python3 ~/maydon/blender/custom/check_glb.py          # validator (plain python)
nice blender -b --python ~/maydon/blender/custom/preview.py -- out.png --mode=hair|beard|gear|keys|bodykeys
nice blender -b --python ~/maydon/blender/custom/keysheet.py -- [--zoom] # morph check on the full-res basemesh
```

Stages: `stage_deltas.py` (morph deltas, `work/deltas.npz`) → `stage_tex.py` (skins, masks, kit texture) →
`stage_build.py` (+ `hairstyles.py`, `ckit.py`; meshes, shape keys, GLB) → `check_glb.py` → `preview.py` →
`make_docs.py` (`custom.json`, this file). Definitions: `morphs.py` (key → MakeHuman targets + weights),
`catalog.py` (ids, default look, preview looks), `hairstyles.py` (per-style recipe). Logs: `work/logs/`.
No network access is needed (all sources are local).

## Space, rig

* Metres, **+Y up, character faces +Z**, bare soles at y = 0; boot studs reach Boots_1 2.4 cm, Boots_2 2.4 cm, Boots_3 0.9 cm, Boots_4 2.1 cm below 0.
* One `Armature`, MPFB `game_engine` rig, 53 bones, **identical rest pose to `~/maydon/blender/anim/ref.blend`**
  (same MPFB macros: male, age 25, muscle/weight/proportions 0.5, race ⅓ each, height macro 0.56 → 1.80 m;
  checked bone-by-bone, max deviation 0.0 mm), so `anims.glb` plays without rescaling. No animations in the file.
* Every mesh is a skinned child of the armature (≤ 4 influences, normalised).

## Meshes and materials

| mesh | material | tris | verts | morphs |
|---|---|---|---|---|
| Acc_armband | acc | 112 | 99 | 3 |
| Acc_gloves | acc | 1100 | 768 | 3 |
| Acc_headband | acc | 176 | 159 | 13 |
| Acc_undershirt_neck | acc | 240 | 193 | 14 |
| Acc_wristband_l | acc | 96 | 91 | 3 |
| Acc_wristband_r | acc | 96 | 91 | 3 |
| Body | skin | 8132 | 4693 | 38 |
| Boots_1 | kit | 1052 | 774 | 3 |
| Boots_2 | kit | 1052 | 776 | 3 |
| Boots_3 | kit | 1050 | 854 | 3 |
| Boots_4 | kit | 1050 | 1016 | 3 |
| Human.eyelashes01 | lash | 300 | 216 | 11 |
| Human.low-poly | eye | 172 | 96 | 7 |
| Human.teeth_base | teeth | 138 | 280 | 8 |
| Kit | kit | 4191 | 2949 | 4 |
| Sleeves_long | kit | 360 | 338 | 3 |
| Socks_low | kit | 380 | 404 | 3 |
| hair_afro | hair | 2192 | 2200 | 15 |
| hair_braids | hair | 1020 | 582 | 15 |
| hair_buzz | hair | 1020 | 582 | 15 |
| hair_crop | hair | 2400 | 1359 | 17 |
| hair_curly | hair | 2192 | 2200 | 15 |
| hair_long | hair | 2449 | 2299 | 11 |
| hair_man_bun | hair | 2450 | 2329 | 15 |
| hair_quiff | hair | 2399 | 1363 | 17 |
| hair_short_fade | hair | 2400 | 2383 | 15 |
| hair_side_part | hair | 1050 | 999 | 17 |
| hair_slick_back | hair | 1644 | 1112 | 15 |

Budget (Body + Kit + largest hair + largest boots): **15825 tris** (limit 13 000).
Show exactly one `hair_*` (or none = bald), one `Boots_*`, any accessories. All meshes are visible after import.

| material | used by | textures | notes |
|---|---|---|---|
| `skin` | Body (+ eyes, teeth) | `skin_light.jpg`, `skin_mid.jpg` (default), `skin_dark.jpg`, `skin_normal.jpg` | MakeHuman UV layout, 1024. No brows/beard/scalp hair painted in. |
| `kit` | Kit, Sleeves_long, Socks_low, Boots_1..4 | `kit.png` | COLOR_0 masks + UV2, recolour shader as for p01–p12 |
| `acc` | Acc_* | `acc.png` (512) | neutral grey with luminance detail, **no vertex colours**; tint per instance |
| `hair` | hair_* | `hair_<id>.png` (512 RGBA) | each style has its own texture; alpha scissor 0.5, double sided |

### Skin (`Body`)

* Tone: blend the three aligned atlases, `t ∈ [0,2]`: `c = mix(light, mid, clamp(t,0,1)); c = mix(c, dark, clamp(t-1,0,1))`.
* Masks (1024 grayscale PNG in the same UV layout, white = hair), applied in this order with the hair colour:
  `scalp_full|scalp_fade` × per-style strength (see the hair table), `beard_*` × density, `brows_*`:
  `c = mix(c, hair_rgb, mask * strength)`.
* Eyes and teeth live in the same atlas: EYE_RECT = Blender UV (0.770, 0.875)–(0.885, 0.990),
  TEETH_RECT = (0.892, 0.902)–(0.980, 0.990). **In Godot UV.y is flipped** (v = 1 − v_blender), e.g. eyes:
  `UV.x ∈ [0.770, 0.885], UV.y ∈ [0.010, 0.125]`. Give that rect low roughness (~0.12) for glossy eyes.
* Eye colour: `iris_mask.png` (inside EYE_RECT). The atlas iris is neutral; `c = mix(c, luminance(c) * eye_rgb * 3.0, iris)`.
* `skin_normal.jpg`: mild pore / fine-detail tangent-space normal map (OpenGL convention, +Y), optional.

### Kit encoding (unchanged from the p01–p12 variants)

COLOR_0 (normalised): shirt `R=1`, trims (collar, cuffs) `R=0.5`, shorts `G=1`, socks `B=1`, boots `A=1`.
UV2 (TEXCOORD_1) on every kit mesh: shirt and `Sleeves_long` use the front/back projection (front x −1..1,
back x 1..3, y 0 at the hem → 1 at the collar); all other kit parts have UV2 = (0, 0).
Boots use 4 texture rects inside the (otherwise unused) head island of `kit.png` (custom.json → `boot_rects_uv`).

* `Kit` = shirt with short sleeves + shorts + high socks. `Sleeves_long` slides over the short-sleeve cuff
  (covers the R=0.5 trim) down to the wrist, R=1.
* **Low socks:** show `Socks_low` and hide the Kit's own socks. Two options in the kit shader (instance uniform
  `hide_socks` on the Kit node): `if (hide_socks && COLOR.b > 0.5) discard;` in `fragment()`, or, cheaper on mobile,
  in `vertex()`: `if (hide_socks && COLOR.b > 0.5) VERTEX -= NORMAL * 0.012;` (pushes the high socks inside the leg).
  The Body keeps its calf skin under the high socks for this.

### Accessories (`acc`)

`Acc_headband`, `Acc_wristband_l/_r`, `Acc_armband` (left upper arm, on the short sleeve, "C" in the texture),
`Acc_gloves` (GK gloves: darker latex palm and wrist strap in the texture), `Acc_undershirt_neck` (base-layer
neck above the crew neck). `albedo = tint * texture`. Wristbands are sized for bare wrists (they clip into
`Sleeves_long`).

### Hair (`hair`)

| id | style | tris | recommended scalp mask × strength |
|---|---|---|---|
| `hair_buzz` | buzz cut (scalp shell) | 1020 | scalp_full × 0.92 |
| `hair_short_fade` | short textured top, skin fade | 2400 | scalp_fade × 0.78 |
| `hair_crop` | textured crop with a short fringe | 2400 | scalp_full × 0.60 |
| `hair_side_part` | classic side part | 1050 | scalp_full × 0.60 |
| `hair_slick_back` | slicked back | 1644 | scalp_full × 0.55 |
| `hair_quiff` | quiff | 2399 | scalp_fade × 0.75 |
| `hair_curly` | short curly | 2192 | scalp_full × 0.70 |
| `hair_afro` | afro | 2192 | scalp_full × 0.70 |
| `hair_man_bun` | man bun | 2450 | scalp_full × 0.55 |
| `hair_long` | long, to the neck | 2449 | scalp_full × 0.55 |
| `hair_braids` | cornrows (scalp shell) | 1020 | scalp_full × 0.70 |

Bald = no hair mesh (optionally `scalp_full` × 0.15 for a shaved head). Textures are light grey: use
`albedo = hair_rgb * pow(tex, 1.5) * ~2` (keeps strand contrast) and alpha scissor 0.5 (alpha-to-coverage
helps at distance). `hair_buzz` / `hair_braids` are thin shells on the scalp (self-made procedural textures).
All hairstyles carry the head morphs that move them (head shape, forehead, ears, …), so they stay on the scalp.

## Blend shapes (glTF morph targets, 0..1)

| key | group | effect at 1.0 |
|---|---|---|
| `head_round` | face | rounder, wider skull and face outline |
| `head_square` | face | square, angular head outline with a broad jaw corner |
| `head_long` | face | longer, narrower face and head |
| `jaw_wide` | face | wide, strong mandible (jaw angles pushed out) |
| `jaw_narrow` | face | narrow, tapered jaw |
| `chin_out` | face | prominent, forward chin |
| `chin_in` | face | receding chin |
| `chin_wide` | face | broad, flat-fronted chin |
| `cheekbones_high` | face | high, prominent cheekbones |
| `cheeks_full` | face | full, round cheeks (soft tissue) |
| `cheeks_hollow` | face | hollow, lean cheeks |
| `nose_wide` | face | wide nose with broad nostrils |
| `nose_narrow` | face | narrow, thin nose |
| `nose_long` | face | long nose with a lower tip |
| `nose_short` | face | short nose with a slightly upturned tip |
| `nose_hump` | face | convex bridge with a dorsal hump |
| `nose_flat` | face | flat, low bridge, less projecting nose |
| `eyes_big` | face | larger eye openings |
| `eyes_small` | face | smaller eye openings |
| `eyes_wide` | face | eyes set further apart |
| `eyes_close` | face | eyes set closer together |
| `eyes_slant_up` | face | outer eye corners raised (upward canthal tilt) |
| `eyes_monolid` | face | epicanthic fold / monolid upper eyelid (East / Central Asian) |
| `brow_heavy` | face | protruding brow ridge, deeper-set eyes |
| `brow_high` | face | brows sit higher above the eyes |
| `lips_full` | face | full, thick lips |
| `lips_thin` | face | thin lips |
| `mouth_wide` | face | wider mouth |
| `ears_big` | face | larger ears |
| `ears_out` | face | protruding ears |
| `forehead_high` | face | taller forehead |
| `face_mature` | face | older face shape: sagging cheeks and jowls, deeper folds |
| `ethnic_east_asian` | extra_face | MPFB race macro towards Asian (head only) |
| `ethnic_african` | extra_face | MPFB race macro towards African (head only) |
| `ethnic_european` | extra_face | MPFB race macro towards Caucasian (head only) |
| `body_muscular` | body | athletic, more muscular body (MPFB muscle macro 0.5 -> 1.0) |
| `body_heavy` | body | heavier body (MPFB weight macro 0.5 -> 1.0) |
| `body_slim` | body | slimmer, leaner body (MPFB weight macro 0.5 -> 0.0) |

* Built from MakeHuman/MPFB targets (`morphs.py` lists target + weight per key); opposites are separate keys —
  set at most one of each pair. 1.0 is strong but realistic (checked with `keysheet.py` and `preview.py --mode=keys`).
* `ethnic_*` are optional extras (MPFB race macro, head only, size-normalised) — useful as a prior for the
  selfie mapper; they overlap with the detail keys.
* Body keys are MPFB macro differences (muscle 0.5→1, weight 0.5→1 / 0.5→0) faded out on the head; joints
  move ≤ 1.3 mm, so the rig is untouched.
* Each mesh carries only the keys that move it (Body carries all): set keys by name on every visible mesh and
  skip `-1` from `find_blend_shape_by_name()`.

## Licences

| asset | source | licence |
|---|---|---|
| base mesh, targets (face/body), macro shapes, `game_engine` rig + weights | MPFB2 add-on data (MakeHuman) | CC0 (only data is used, no MPFB code ships) |
| skins young caucasian / caucasian2 / asian / african male (scalp hair removed, recoloured) | MakeHuman system assets | CC0 |
| eyes low-poly + brown_eye texture, teeth, eyebrow005/012/009 (as masks) | MakeHuman system assets | CC0 |
| hair short01/02/04, afro01, ponytail01, long01 (reshaped, greyscaled) | MakeHuman system assets | CC0 |
| shoes01/02/03 meshes, shoes05/06/01/03 textures (desaturated) | MakeHuman system assets | CC0 |
| kit / sleeves / socks / accessories / studs geometry, beard & scalp masks, buzz & braid textures, scripts | made for MAYDON | own work |

## Known limitations

* MakeHuman photo skins: fine at match distance, a little smooth in extreme close-ups.
* Hair is card-based MakeHuman hair; cards do not react to the headband; long hair rests on the collar.
* `hair_mohawk` was attempted and dropped (no convincing crest from the available cards).
* Cloth is skinned like the body (no simulation); extreme arm poses stretch sleeves.
