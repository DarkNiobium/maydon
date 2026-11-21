"""Writes assets/chars/custom/custom.json and README.md from catalog/morphs/hairstyles + work/build_stats.json.

    python3 ~/maydon/blender/custom/make_docs.py      (plain python, no Blender)
"""
import json, os, sys, types
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
OUT = os.path.expanduser("~/maydon/game/assets/chars/custom")
import morphs as MO
import catalog as CAT

# hairstyles.py imports bpy-side modules; read only its HAIR table
src = open(os.path.join(HERE, "hairstyles.py")).read()
i = src.index("HAIR = {"); j = src.index("\n}\n", i) + 3
ns = {}
exec(src[i:j], ns)
HAIR = {k: v for k, v in ns["HAIR"].items() if not k.startswith("_")}
stats = json.load(open(os.path.join(HERE, "work", "build_stats.json")))
tex = json.load(open(os.path.join(HERE, "work", "tex_info.json")))
M_ = stats["meshes"]


def carriers(key):
    return sorted(n for n, m in M_.items() if key in m["morphs"])


def glb_min_y(path):
    import struct
    d = open(path, "rb").read()
    cl = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + cl])
    out = {}
    for n in js["nodes"]:
        if "mesh" in n:
            a = js["accessors"][js["meshes"][n["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
            out[n["name"]] = a["min"][1]
    return out


def glb_meshes(path):
    """name -> dict(material, tris, verts, morphs) as stored in the GLB (what Godot imports)."""
    import struct
    d = open(path, "rb").read()
    cl = struct.unpack("<I", d[12:16])[0]
    js = json.loads(d[20:20 + cl])
    mats = [m.get("name") for m in js.get("materials", [])]
    out = {}
    for n in js["nodes"]:
        if "mesh" in n:
            me = js["meshes"][n["mesh"]]
            p_ = me["primitives"][0]
            out[n["name"]] = dict(material=mats[p_["material"]], tris=js["accessors"][p_["indices"]]["count"] // 3,
                                  verts=js["accessors"][p_["attributes"]["POSITION"]]["count"],
                                  morphs=me.get("extras", {}).get("targetNames", []))
    return out


MINY = glb_min_y(os.path.join(OUT, "base.glb"))
M_ = glb_meshes(os.path.join(OUT, "base.glb"))
morph_list = []
for k, (d, _) in MO.FACE.items():
    morph_list.append(dict(name=k, group="face", desc=d, meshes=carriers(k)))
for k, (d, _) in MO.EXTRA.items():
    morph_list.append(dict(name=k, group="extra_face", desc=d, meshes=carriers(k)))
for k, (d, ch, s) in MO.BODY.items():
    morph_list.append(dict(name=k, group="body", desc=d, meshes=carriers(k)))

BOOT_DESC = {"Boots_1": "classic laced boot (MakeHuman shoes02 last, shoes05 texture), 6 studs",
             "Boots_2": "speed boot: slimmer, lower, pointed toe (shoes02 last reshaped, shoes06 texture), 6 studs",
             "Boots_3": "classic leather boot, rounder toe (shoes01 last, shoes01 texture), 6 studs",
             "Boots_4": "mid-cut sock boot with ankle collar (shoes03 last, shoes03 texture), 6 studs"}
ACC_DESC = {"Acc_headband": "terry headband, low on the forehead, higher at the back",
            "Acc_wristband_l": "terry wristband, left forearm", "Acc_wristband_r": "terry wristband, right forearm",
            "Acc_gloves": "goalkeeper gloves (latex palm darker in the texture, wrist strap)",
            "Acc_armband": "captain armband on the left upper arm, sits on the short sleeve; 'C' in the texture",
            "Acc_undershirt_neck": "base-layer neck showing above the crew neck"}

doc = dict(
    file="base.glb",
    generator="~/maydon/blender/custom/build.py (Blender 5.2 + MPFB2, MakeHuman CC0 assets)",
    space=dict(units="metres", up="+Y", forward="+Z (character faces +Z)", ground="bare soles at y=0; boot studs reach 1-2.4 cm below 0 (boots.*.lowest_y_m)",
               rest_pose="MPFB/MakeHuman base pose (arms ~45 deg down, elbows slightly bent); identical to anims.glb rig, no rescale",
               height_m=1.80),
    skeleton=dict(name="Armature", bones=stats["bones"], note="MPFB game_engine rig, unchanged (same rest pose as ~/maydon/blender/anim/ref.blend)"),
    meshes={n: dict(material=m["material"], tris=m["tris"], verts=m["verts"], morphs=len(m["morphs"])) for n, m in sorted(M_.items())},
    budget=dict(limit=13000, example_worst_case=stats["budget_example"],
                note="Body + Kit + largest hair + largest boot pair. Gear extras: Sleeves_long 360, Socks_low 380, Acc_gloves 1100, bands 96-240."),
    materials=dict(
        skin=dict(meshes=["Body"], albedo=list(CAT.SKIN_TEX.values()), normal="skin_normal.jpg (tangent space, OpenGL/+Y, mild pores; optional)",
                  layout="MakeHuman body UV layout, 1024. Eyes in EYE_RECT, teeth in TEETH_RECT (same atlas)",
                  EYE_RECT_uv=tex["EYE_RECT"], TEETH_RECT_uv=tex["TEETH_RECT"],
                  note="UV rects are Blender UVs (v up); in glTF / Godot UV v is flipped: v_godot = 1 - v_blender"),
        kit=dict(meshes=["Kit", "Sleeves_long", "Socks_low"] + CAT.BOOT_IDS, albedo="kit.png (neutral grey + AO; boot details in 4 rects)",
                 COLOR_0={"shirt": [1, 0, 0, 0], "trim (collar, cuffs)": [0.5, 0, 0, 0], "shorts": [0, 1, 0, 0], "socks": [0, 0, 1, 0], "boots": [0, 0, 0, 1]},
                 UV2="TEXCOORD_1 on every kit mesh. Shirt + Sleeves_long: x -1..1 front, 1..3 back, y 0 hem -> 1 collar (as the p01-p12 variants); other parts (0,0).",
                 boot_rects_uv=dict(zip(CAT.BOOT_IDS, tex["BOOT_RECTS"]))),
        acc=dict(meshes=CAT.ACC_IDS, albedo="acc.png (512, neutral grey with luminance detail); no vertex colours",
                 rects_uv=tex["ACC_RECTS"], tint="albedo = acc_tint * texture (one tint per accessory instance)"),
        hair=dict(meshes=CAT.HAIR_IDS, albedo="hair_<id>.png per style (512 RGBA, light grey, alpha = strands)",
                  alpha="MASK, cutoff 0.5, double sided",
                  note="all hair materials are named 'hair' in the GLB but each style has its own texture (UVs of the hair asset)"),
    ),
    morph_targets=dict(
        list=morph_list,
        range="0..1 (opposites are separate keys; set only one of each pair)",
        note="Every mesh carries only the keys that move it (>0.2 mm); Body carries all. Set by name on every visible mesh and skip "
             "meshes where find_blend_shape_by_name() returns -1. Hair, eyes, teeth, headband and neck piece follow the head keys; "
             "Kit, boots, sleeves, socks, gloves, bands follow the body keys."),
    hair={h: dict(label=v.get("label"), texture=h + ".png", tris=M_.get(h, {}).get("tris"),
                  scalp_mask=v["scalp"][0], scalp_strength=v["scalp"][1]) for h, v in HAIR.items()},
    hair_none="bald = hide every hair_* mesh and use no scalp mask (or scalp_full at 0.15 for a shaved look)",
    masks=dict(
        format="1024 grayscale PNG in the skin UV layout, white = hair; tint in the skin shader: albedo = mix(albedo, colour, mask * strength)",
        beards={b: b + ".png" for b in CAT.BEARD_IDS}, brows={b: b + ".png" for b in CAT.BROW_IDS},
        scalp={"scalp_full": "scalp_full.png (whole hair-bearing scalp, grainy, soft hairline)",
               "scalp_fade": "scalp_fade.png (same, fading out on the sides/back: skin fade)"},
        iris="iris_mask.png (white = iris inside EYE_RECT; recolour: albedo = mix(albedo, luminance(albedo) * eye_colour * ~3, mask))",
        note="skin atlases contain no brows, beard or scalp hair; brows/beard/scalp come only from these masks"),
    skin_tone=dict(textures=CAT.SKIN_TEX, param="skin_tone 0..2: 0 light (European), 1 mid (Central Asian), 2 dark (African); blend the two neighbours"),
    boots={b: dict(desc=BOOT_DESC[b], tris=M_[b]["tris"], lowest_y_m=round(MINY.get(b, 0.0), 4)) for b in CAT.BOOT_IDS},
    accessories={a: dict(desc=ACC_DESC[a], tris=M_[a]["tris"]) for a in CAT.ACC_IDS},
    gear=dict(Kit="shirt (short sleeves) + shorts + high socks", Sleeves_long="forearm extension over the short-sleeve cuff, COLOR_0 R=1",
              Socks_low="scrunched low socks; when shown, hide the Kit's own socks (COLOR_0.b > 0.5): either discard in the kit shader "
                        "or push them inside the leg in vertex(): if (hide_socks && COLOR.b > 0.5) VERTEX -= NORMAL * 0.012;",
              calves="the Body keeps the calf skin under the high socks, so low socks show bare calves"),
    textures=sorted(f for f in os.listdir(OUT) if f.endswith((".png", ".jpg")) and f != "preview.png"
                    and not f.startswith("base_")),
    textures_note="the GLB embeds skin_mid/skin_normal/kit/acc/hair_* for a working default import; Godot extracts "
                  "those as base_*.png on import (generated, not part of the source set)",
    default=CAT.DEFAULT,
    colours=dict(hair=CAT.HAIR_COLORS, eyes=CAT.EYE_COLORS, note="linear RGB suggestions used by the preview"),
    caveats=[
        "Morph keys are not mutually normalised: stacking many at 1.0 can exaggerate; the selfie mapper should keep the sum of a pair <= 1.",
        "ethnic_* keys are optional extras (MPFB race macro, head only); they overlap with the detail keys.",
        "Body keys are mesh-only (joint shift <= 1.3 mm), the rig is not changed.",
        "Hair cards are MakeHuman assets: alpha-scissor thins at distance (alpha-to-coverage helps). Headband/hair do not compress each other.",
        "Wristbands are sized for bare wrists (they clip into Sleeves_long); the armband sits on the short sleeve.",
        "Boot soles and studs reach below y=0 (boots.*.lowest_y_m); animations were made for bare soles at y=0.",
        "hair_mohawk was tried and dropped (MakeHuman cards did not give a convincing crest).",
    ],
)
json.dump(doc, open(os.path.join(OUT, "custom.json"), "w"), indent=1)
print("custom.json written")


# ---------------------------------------------------------------------------------------------
# README.md
# ---------------------------------------------------------------------------------------------
def table(rows, head):
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


B = stats["budget_example"]
mesh_rows = [(n, m["material"], m["tris"], m["verts"], len(m["morphs"])) for n, m in sorted(M_.items())]
morph_rows = [("`%s`" % m["name"], m["group"], m["desc"]) for m in morph_list]
hair_rows = [("`%s`" % h, v.get("label"), M_.get(h, {}).get("tris"), "%s × %.2f" % (v["scalp"][0], v["scalp"][1])) for h, v in HAIR.items()]
readme = f"""# MAYDON customizable footballer (`base.glb`)

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

* Metres, **+Y up, character faces +Z**, bare soles at y = 0; boot studs reach {", ".join("%s %.1f cm" % (b, -MINY.get(b, 0) * 100) for b in CAT.BOOT_IDS)} below 0.
* One `Armature`, MPFB `game_engine` rig, 53 bones, **identical rest pose to `~/maydon/blender/anim/ref.blend`**
  (same MPFB macros: male, age 25, muscle/weight/proportions 0.5, race ⅓ each, height macro 0.56 → 1.80 m;
  checked bone-by-bone, max deviation 0.0 mm), so `anims.glb` plays without rescaling. No animations in the file.
* Every mesh is a skinned child of the armature (≤ 4 influences, normalised).

## Meshes and materials

{table(mesh_rows, ["mesh", "material", "tris", "verts", "morphs"])}

Budget (Body + Kit + largest hair + largest boots): **{B["total_worst"]} tris** (limit 13 000).
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

{table(hair_rows, ["id", "style", "tris", "recommended scalp mask × strength"])}

Bald = no hair mesh (optionally `scalp_full` × 0.15 for a shaved head). Textures are light grey: use
`albedo = hair_rgb * pow(tex, 1.5) * ~2` (keeps strand contrast) and alpha scissor 0.5 (alpha-to-coverage
helps at distance). `hair_buzz` / `hair_braids` are thin shells on the scalp (self-made procedural textures).
All hairstyles carry the head morphs that move them (head shape, forehead, ears, …), so they stay on the scalp.

## Blend shapes (glTF morph targets, 0..1)

{table(morph_rows, ["key", "group", "effect at 1.0"])}

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
"""
open(os.path.join(OUT, "README.md"), "w").write(readme)
print("README.md written")
