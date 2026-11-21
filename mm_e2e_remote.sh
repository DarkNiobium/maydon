#!/bin/bash
# e2e against a running matchmaker. usage: mm_e2e_remote.sh ws://host:47900 [mode]
cd ~/maydon/game
U=${1:-ws://127.0.0.1:47900}; M=${2:-3}
L=../logs; CF=/tmp/mm_code_$$.txt; rm -f $CF
timeout 100 godot --headless --path . res://tools/mm_test.tscn -- A $U $M $CF > $L/mmA.log 2>&1 &
sleep 3
timeout 100 godot --headless --path . res://tools/mm_test.tscn -- B $U $M $CF > $L/mmB.log 2>&1
sleep 2; rm -f $CF
echo ---; grep -E "^\[A\]|SCRIPT ERROR" -A1 $L/mmA.log | grep -v "queue {" | tail -6
echo ---; grep -E "^\[B\]|SCRIPT ERROR" -A1 $L/mmB.log | grep -v "queue {" | tail -6
