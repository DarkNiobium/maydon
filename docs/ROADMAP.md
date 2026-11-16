# MAYDON roadmap (living)

Done:
- Sim core: ball physics, footballer kinematics, actions (pass/lob/through/shot/header/tackle/slide/GK dive/throw), rules (arena + full: out, corners, goal kicks, offside, fouls, cards, penalties), ratings
- Team AI (shape, support, runs, press, mark, carrier decisions, GK), human controller w/ assists
- Match view (placeholder capsules), pitch shader, goals/nets, arena walls + ad boards, venue (blocks, crowd shader), HUD, touch controls, replay buffer
- Offline capture harness

Next:
1. Camera/lighting polish (TV cam inside arena, night look)
2. AI tuning via bench (pass completion ~75-85%, goals ~3-6 per 4-min arena match)
3. Characters: MPFB humans + kit shader + retargeted mocap (CMU/ACCAD/Quaternius) + AnimationTree
4. Menus: main, quick match, profile/character, club creation, Mahalla league (12 Tashkent districts), settings, results, tutorial; uz/ru/en
5. Audio integration (raw/audio/game/<cat> → assets/audio/<cat>)
6. Android export, emulator smoke test, perf (sim ms/tick on mobile), AAB + store assets
7. LAN multiplayer (hotspot), later
