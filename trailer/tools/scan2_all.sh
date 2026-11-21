#!/bin/bash
cd ~/maydon/game
for spec in "arena5 1 5" "arena5 5 9" "arena5 9 13" "arena5 21 26" "stadium 1 3" "stadium 3 5" "stadium 5 7"; do
  set -- $spec
  (timeout 900 godot --headless --path . res://tools/trailer/scan2.tscn -- $1 $2 $3 2>&1 | grep -E "^(SAVE|SLIDE|POST|BAR)|SCRIPT ERROR" > ../trailer/scan/ev_$1_$2.txt) &
done
wait
