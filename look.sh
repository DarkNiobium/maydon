#!/bin/bash
# Animation contact sheet: look.sh out.png mode speed [turn] [side|front|q]
cd ~/maydon/game
timeout 120 xvfb-run -a -s "-screen 0 1600x900x24" godot --display-driver x11 --rendering-driver vulkan --path . --resolution 1600x900 res://tools/anim_look.tscn -- "$@" 2>&1 | grep -E "saved|SCRIPT ERROR" | head -3
