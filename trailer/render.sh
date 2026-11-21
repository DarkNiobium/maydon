#!/bin/bash
# Render one trailer shot: render.sh <shot>
# -> ~/maydon/trailer/clips/<shot>.mov  (1080p30, warm-up trimmed, game audio)
set -u
SHOT=$1; RES=${RES:-1920x1080}
W=${RES%x*}; H=${RES#*x}
T=~/maydon/trailer; OUT=$T/raw/$SHOT
rm -rf "$OUT"; mkdir -p "$OUT" $T/clips $T/logs
cd ~/maydon/game
START=$(date +%s)
timeout ${TMO:-3600} xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --rendering-method mobile --display-driver x11 --rendering-driver vulkan \
  --resolution $RES --fixed-fps 30 --write-movie "$OUT/mm.avi" \
  --path . res://tools/trailer/${DIRECTOR:-director}.tscn -- "$SHOT" "$OUT" > $T/logs/$SHOT.log 2>&1
echo "[$SHOT] godot exit $? in $(( $(date +%s) - START ))s"
grep -E "SCRIPT ERROR" -A3 $T/logs/$SHOT.log | head -8
DONE=$(grep -o "done frames=[0-9]* p0=[0-9]* pend=[0-9]*" $T/logs/$SHOT.log)
[ -z "$DONE" ] && { echo "[$SHOT] FAILED"; exit 1; }
FR=$(echo $DONE | sed 's/.*frames=\([0-9]*\).*/\1/'); P0=$(echo $DONE | sed 's/.*p0=\([0-9]*\).*/\1/')
# audio: movie frame k covers [k/30,(k+1)/30); the in-point is process frame P0 (movie counts from frame 1)
OFF=$(python3 -c "print(($P0-1)/30)")
ffmpeg -v error -y -framerate 30 -i "$OUT/f_%04d.png" -ss $OFF -i "$OUT/mm.avi" -map 0:v -map 1:a? -t $(python3 -c "print($FR/30)") \
  -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p -c:a pcm_s16le $T/clips/$SHOT.mov
echo "[$SHOT] clip $(ffprobe -v error -show_entries format=duration -of csv=p=0 $T/clips/$SHOT.mov)s offset=$OFF"
[ "${KEEP:-0}" = 1 ] || rm -f "$OUT"/f_*.png "$OUT/mm.avi"
