#!/bin/bash
# Offscreen capture (Xvfb + NVIDIA Vulkan). Usage: shot.sh <scenario> <times...>  | shot.sh <scenario> seq <start> <secs> <fps>
cd ~/maydon/game
OUT=${OUT:-$HOME/maydon/shots}
timeout ${TMO:-300} xvfb-run -a -s "-screen 0 1600x900x24" godot --display-driver x11 --rendering-driver vulkan --path . res://tools/shot.tscn -- "$OUT" "$@" > ../logs/shot.log 2>&1
echo "exit $?"
grep -E "shot |seq done|SCRIPT ERROR" ../logs/shot.log | head -20
grep -A2 "SCRIPT ERROR" ../logs/shot.log | grep "at:" | head -5
