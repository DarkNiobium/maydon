#!/bin/bash
# Offscreen capture (Xvfb + NVIDIA Vulkan). Usage: shot.sh <scenario> <times...>  | shot.sh <scenario> seq <start> <secs> <fps>
# Env: OUT=dir, TMO=seconds, RM=mobile|forward_plus (renderer), MQ=0..3 (quality)
cd ~/maydon/game
OUT=${OUT:-$HOME/maydon/shots}
mkdir -p "$OUT"; rm -f "$OUT/.shot_done"
timeout ${TMO:-300} xvfb-run -a -s "-screen 0 1600x900x24" godot --display-driver x11 --rendering-driver vulkan ${RM:+--rendering-method $RM} --path . res://tools/shot.tscn -- "$OUT" "$@" > ../logs/shot.log 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
  if [ -f "$OUT/.shot_done" ]; then sleep 2; pkill -P $PID 2>/dev/null; pkill -f "res://tools/shot.tscn -- $OUT" 2>/dev/null; break; fi
  sleep 1
done
wait $PID 2>/dev/null
echo "exit $( [ -f "$OUT/.shot_done" ] && echo ok || echo fail)"
rm -f "$OUT/.shot_done"
grep -E "shot |seq done|SCRIPT ERROR" ../logs/shot.log | sort | uniq -c | head -20
grep -A2 "SCRIPT ERROR" ../logs/shot.log | grep "at:" | head -5
