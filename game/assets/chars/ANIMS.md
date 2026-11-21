# MAYDON animation library

`anims.glb` — 40 clips on the MPFB `game_engine` rig (53 bones), 30 fps; metadata in `anims.json`
(speed/cycle for loops, contact time for one-shots, source range, foot-slide check). Built by `~/maydon/blender/anim/` scripts
(world-space rotation retarget with rest-pose correction, pelvis translation scaled by leg length, loops cut at right-foot contact).

| clip | source | licence |
|---|---|---|
| walk | accad/Male2/Male2_B3_Walk.bvh | ACCAD Open Motion Project, The Ohio State University — CC BY 3.0 |
| jog | cmu/35/35_17.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| run | cmu/102/102_05.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| sprint | cmu/102/102_05.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| idle | accad/Male2/Male2_A2_Sway.bvh | ACCAD Open Motion Project, The Ohio State University — CC BY 3.0 |
| idle_ready | cmu/140/140_06.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| strafe_l | 100style/Neutral/Neutral_SR.bvh (sidestep, stride x1.35) | 100STYLE dataset, Ian Mason et al. (zenodo 8127870) — CC BY 4.0 |
| strafe_r | mirror of strafe_l (100STYLE Neutral_SR) | 100STYLE dataset, Ian Mason et al. (zenodo 8127870) — CC BY 4.0 |
| backpedal | accad/Male2/Male2_C7_RunBackwards.bvh | ACCAD Open Motion Project, The Ohio State University — CC BY 3.0 |
| dribble | cmu/35/35_18.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| kick_shot | cmu/11/11_01.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| kick_long | cmu/10/10_06.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| kick_pass | cmu/10/10_01.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| volley | cmu/10/10_03.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| gk_catch | cmu/143/143_20.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| gk_throw | cologne/Ballwurf.bvh | Cologne Motion Capture Database, TH Köln — CC BY 4.0 |
| gk_dive_low_r | handkey | hand-keyed for MAYDON |
| gk_dive_low_l | handkey | hand-keyed for MAYDON |
| gk_dive_r | handkey | hand-keyed for MAYDON |
| gk_dive_l | handkey | hand-keyed for MAYDON |
| fall | handkey | hand-keyed for MAYDON |
| slide | handkey | hand-keyed for MAYDON |
| trap_chest | handkey | hand-keyed for MAYDON |
| throw_in | handkey | hand-keyed for MAYDON |
| dejected | handkey | hand-keyed for MAYDON |
| clap | handkey | hand-keyed for MAYDON |
| tackle | handkey | hand-keyed for MAYDON |
| stepover_r | handkey | hand-keyed for MAYDON |
| stepover_l | handkey | hand-keyed for MAYDON |
| drag_back | handkey | hand-keyed for MAYDON |
| gk_kick | cmu/10/10_06.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| header | cmu/143/143_06.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| getup | cmu/140/140_01.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| celebrate_2 | cologne/Take2017-01-11_02.30.59PM.bvh | Cologne Motion Capture Database, TH Köln — CC BY 4.0 |
| celebrate_3 | cologne/Take2017-01-11_02.30.32PM.bvh | Cologne Motion Capture Database, TH Köln — CC BY 4.0 |
| celebrate_1 | cmu/35/35_17.bvh | CMU Graphics Lab Motion Capture Database (free for use in commercial products; data not resold) |
| emote_wave | handkey | hand-keyed for MAYDON (player emote) |
| emote_point_sky | handkey | hand-keyed for MAYDON (player emote) |
| emote_arms_crossed | handkey | hand-keyed for MAYDON (player emote) |
| emote_flex | handkey | hand-keyed for MAYDON (player emote) |

Known weaknesses: kicks come from short CMU takes (contact ~0.8 s, the game skips the run-up);
header uses a jump with a keyed head nod; GK dives, slide, tackle, trap, throw-in, step-overs, clap and dejected are hand-keyed;
all actions are right-footed (no mirroring yet).

Runtime (src/view): exact cadence from the blend-space stride (character_view.gd stride_at), foot locking + procedural re-plant steps with two-bone IK (foot_planter.gd), spine lean / banking, head tracks the ball (LookAtModifier3D), upper-body emote layer.

## 2026-11-21 additions (Mixamo, left foot)

| clip | source | used for |
|---|---|---|
| kick_run (+ `_m`) | Mixamo "Strike Forward Jog" | shots / lobs at > 3.2 m/s, passes at > 4.5 m/s |
| kick_pass_m, kick_shot_m, kick_long_m, volley_m | mirror of the CMU clips | left-footed strikes (`act_data.foot == -1`) |
| slide_mx (+ `_m`) | Mixamo "Soccer Slide Tackle" (includes getting up) | SLIDE (`_m` for left-footed players) |
| fall_mx, getup_mx | Mixamo "Soccer Trip", "Standing Up From A Soccer Fall" | FALL → GETUP (chained cross-fade) |
| gk_dive_mx_l/r, gk_block_mx_l/r | Mixamo goalkeeper diving save / body block (include getting up) | GK_DIVE high / low (`"dive"` timing: full stretch at 0.45 s) |

Mixamo licence: free for use in games, raw files are not redistributed (`~/maydon/raw/anim/mixamo`, see `raw/anim/INDEX.md`).
Runtime (2026-11-21): locomotion phase-locked to `Footballer.gait`; dribble touches / strikes / receptions reach the ball with
`FootPlanter.reach_*` (+ body lean `_reach_shift`); actions go through a `main` transition (loco | slot 0 | slot 1) so chained
actions cross-fade pose to pose. Hand-keyed `slide/fall/gk_dive_*` stay in the library as fallbacks.
Audits: `tools/contact_audit.tscn` (foot–ball gap), `tools/anim_audit.tscn` (foot slide), `tools/act_look.tscn` (action sheets).
