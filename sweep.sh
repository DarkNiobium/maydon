#!/bin/bash
cd ~/maydon/game
for cfg in "reach=0.72 off=-0.05" "reach=0.9 off=-0.4" "reach=1.0 off=-0.8" "reach=0.6 off=0.3"; do
  r=$(timeout 600 godot --headless --path . res://tools/bench.tscn -- 5 3 240 x $cfg 2>&1 | grep -E "goals:|completion|interceptions:" | tr '\n' ' ')
  echo "$cfg => $r"
done
