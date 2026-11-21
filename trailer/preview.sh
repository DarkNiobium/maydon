#!/bin/bash
# Low-res previews + contact sheets: preview.sh shot1 shot2 ...
T=~/maydon/trailer; mkdir -p $T/preview
for S in "$@"; do
  RES=960x540 TR_PREVIEW=1 KEEP=1 $T/render.sh $S > $T/logs/prev_$S.txt 2>&1
  tail -2 $T/logs/prev_$S.txt
  mv -f $T/clips/$S.mov $T/preview/$S.mov 2>/dev/null
  # contact sheet: 12 frames evenly spaced
  N=$(ls $T/raw/$S/f_*.png 2>/dev/null | wc -l)
  [ "$N" -gt 0 ] && python3 - "$T/raw/$S" "$T/preview/$S.jpg" "$S" <<'PY'
import sys, glob
from PIL import Image, ImageDraw
fs = sorted(glob.glob(sys.argv[1] + "/f_*.png")); n = len(fs)
pick = [fs[min(n - 1, round(i * (n - 1) / 11))] for i in range(12)]
W, H = 480, 270
sheet = Image.new("RGB", (W * 4, H * 3), "black")
d = ImageDraw.Draw(sheet)
for i, p in enumerate(pick):
    im = Image.open(p).convert("RGB").resize((W, H))
    sheet.paste(im, ((i % 4) * W, (i // 4) * H))
    d.text(((i % 4) * W + 6, (i // 4) * H + 4), "%s %s" % (sys.argv[3], p.split("_")[-1][:4]), fill="yellow")
sheet.save(sys.argv[2], quality=85)
PY
  rm -rf $T/raw/$S
done
