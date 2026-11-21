#!/bin/bash
# matchmaking end-to-end: server + 2 headless clients. usage: mm_e2e.sh [mode]
cd ~/maydon/game
M=${1:-3}
L=../logs; CF=/tmp/mm_code_$$.txt; rm -f $CF
timeout 120 godot --headless --path . res://scenes/server.tscn -- --mm port=47900 > $L/mm.log 2>&1 &
MMPID=$!
sleep 3
timeout 90 godot --headless --path . res://tools/mm_test.tscn -- A ws://127.0.0.1:47900 $M $CF > $L/mmA.log 2>&1 &
sleep 2
timeout 90 godot --headless --path . res://tools/mm_test.tscn -- B ws://127.0.0.1:47900 $M $CF > $L/mmB.log 2>&1
sleep 4
kill $MMPID 2>/dev/null
rm -f $CF
grep -E "^\[" $L/mm.log | head
echo ---; grep -E "^\[A\]|SCRIPT ERROR" -A1 $L/mmA.log | grep -v "queue {" | tail -6
echo ---; grep -E "^\[B\]|SCRIPT ERROR" -A1 $L/mmB.log | grep -v "queue {" | tail -6
