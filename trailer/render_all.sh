#!/bin/bash
# Final 1080p renders of every trailer shot
T=~/maydon/trailer
for S in s01_aerial s02_hero s03_shoulder s04_net s05_celebrate s06_stadium_run s07_slide s08_save s09_volley \
         s10_screamer s11_stadium_party s14a_tv s14b_shoulder s14c_arena3 s14d_aerial_day s15_final; do
  [ -f $T/clips/$S.mov ] && [ "${FORCE:-0}" != 1 ] && continue
  $T/render.sh $S 2>&1 | grep -E "clip|FAILED|ERROR"
done
for S in s12_locker s13_lobby; do
  DIRECTOR=scene_dir $T/render.sh $S 2>&1 | grep -E "clip|FAILED|ERROR"
done
echo ALL DONE
