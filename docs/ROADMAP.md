# MAYDON roadmap (living)

Done (2026-11-16):
- Sim core + rules (arena & full), team AI (incremental carrier decisions, shared intercepts), human controller with assists
- Match view: pitch shader, goals/nets, arena walls, ad boards, night floodlights (spots), venue (panel blocks, trees), billboard crowd (MultiMesh), TV cutaway, replay
- HUD, touch controls (context labels, safe-area aware), pause, quality presets, Android back/pause handling
- Menus: onboarding (lang → player → district/kit), main, quick match, Mahalla league (12 districts → national league), profile/card, settings, credits, results with XP/levels
- Tutorial (8 steps), LAN multiplayer (UDP discovery + ENet, host-authoritative snapshots), audio (212 CC0/CC-BY files)
- Android: signed release APK (tools: ~/maydon/export.sh), emulator test passes with GLES3 build (Vulkan present fails only in emulator)
- Tools: check.sh, compile.sh, shot.sh, bench/trace/prof/human_test/lan_test

Done (2026-11-17): 12 MPFB footballers (assets/chars/variants, ~9.9k tris, Body+Kit meshes, README.md),
mocap library (assets/chars/anims.glb, 36 clips), CharacterView integrated (loco blend + cadence, oneshots with
contact alignment + start offset, motion_scale per body, animation LOD), kit shader with numbers,
impostor trees (Poly Haven CC0 → tree_atlas.png), goal emotes (clap/dejected), intro flyover, celebration cam.
AI: 5v5 pass completion ~90%, goals ~4–9/4 min; 11v11 ~6 shots/90' (still low).

Next:
1. Integrate characters, verify visuals/animations in shots, tune kit shader
2. Crowd sprite atlas rendered from MPFB people (assets/gen/fans.png)
3. AI polish (5v5 completion ~50%, 11v11 few shots), GK feel
4. Perf on device (sim ~0.6–1.1 ms/tick desktop), arm64-only release build, AAB?
5. Store screenshots

2026-11-17 (later): spectator atlas (assets/gen/fans.png), 11v11 shooting (6–10 shots/90'), CINE camera clamped inside
arena, AAB build (./export.sh aab → build/MAYDON.aab, signed), store screenshots in docs/store/screens.
Open: playtest on a real phone (perf/controls feel), left-foot mirroring, head look-at, LAN client prediction.

2026-11-20 graphics pass: desktop = Forward+ (project.godot rendering_method + .mobile="mobile"), new ULTRA quality (3) on desktop:
SSAO (q>=2), SSIL + volumetric floodlight fog + MSAA4x/8k shadows (q3), TAA (q>=2), PCSS sun. Sky = shaders/sky_dome.gdshader
(upper-hemisphere panoramas assets/tex/sky/{day,night}.jpg from tools_py/hdri_sky.py; analytic ground, city glow at night).
Pitch shader: view-dependent mow stripes (+cross-mow in stadiums), patchy variation, wear/soil, grazing sheen, chalk lines, turf infill.
Stadium: roofs on all stands + fascia/trusses, back walls + corner blocks; fans recoloured per instance, distance-softened; DOF in CINE cam.
Skin: SSS (Forward+) + backlight; kit cloth sheen, glossy boots; hair alpha-to-coverage. shot.sh: RM=mobile|forward_plus MQ=0..3.
Open: real distant skyline around the arena, crowd geometry/LOD, higher-res character textures + hair cards.
