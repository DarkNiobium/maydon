#!/bin/bash
# Run the online server on this machine (no Docker): matchmaker on TCP 47900, matches on UDP 47910-47990.
# Players then set Settings → Online server = ws://<this-machine-ip>:47900
cd "$(dirname "$0")/../game"
exec godot --headless --path . res://scenes/server.tscn -- --mm port=47900 match_ports=47910-47990
