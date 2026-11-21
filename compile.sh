#!/bin/bash
cd ~/maydon/game
timeout 120 godot --headless --path . res://tools/compile_all.tscn > ../logs/compile.log 2>&1
grep -E "compiled|FAILED" ../logs/compile.log; grep -c "SCRIPT ERROR" ../logs/compile.log | sed "s/^/errors: /"
grep -A1 "SCRIPT ERROR" ../logs/compile.log | grep -vE "^--$" | head -${1:-16}
