#!/bin/bash
cd ~/maydon/game
for spec in "arena5 1 11" "arena5 11 21" "arena5 21 31" "stadium 1 5" "stadium 5 9" "stadium 9 13" "arena3 1 9"; do
  set -- $spec
  (timeout 1500 godot --headless --path . res://tools/trailer/scan.tscn -- $1 $2 $3 2>&1 | grep -E "^GOAL|^DONE|SCRIPT ERROR" > ../trailer/scan/$1_$2.txt) &
done
wait
wc -l ../trailer/scan/*.txt
