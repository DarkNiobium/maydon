#!/bin/bash
# Compile check: runs the bench for 1 short match and prints script errors with source lines.
cd ~/maydon/game
timeout ${2:-60} godot --headless --path . res://tools/bench.tscn -- ${1:-5} 1 20 > ../logs/check.log 2>&1
echo "exit $?"
grep -E "SCRIPT ERROR|at: " ../logs/check.log | head -${3:-12} | while read -r line; do
  echo "$line"
  if [[ "$line" =~ \(res://([^:]+):([0-9]+)\) ]]; then
    f="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
    [ "$n" != "0" ] && echo "    >> $(sed -n "${n}p" "$f" | sed 's/^\s*//')"
  fi
done
tail -25 ../logs/check.log | grep -vE "SCRIPT ERROR|at: |^\s*$" | head -25
