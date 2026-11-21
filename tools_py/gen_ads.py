#!/usr/bin/env python3
"""Generate LED ad-board atlas with fictional local brands (no real trademarks)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, sys, os
OUT = sys.argv[1] if len(sys.argv) > 1 else "ads.png"
F = os.path.expanduser("~/maydon/game/assets/fonts/Oswald.ttf")
W, H = 4096, 128          # 8 ads of 512x128 (each = 4 m of board)
ads = [
    ("MAYDON", (12, 160, 90), (255, 255, 255)),
    ("FAIR PLAY", (245, 245, 245), (20, 30, 40)),
    ("#MAYDON", (20, 60, 170), (255, 255, 255)),
    ("PLAY HARD", (15, 15, 18), (255, 140, 30)),
    ("MAYDON ARENA", (12, 160, 90), (10, 20, 15)),
    ("RESPECT", (30, 30, 36), (255, 255, 255)),
    ("MAYDON", (255, 110, 20), (20, 20, 22)),
    ("NO LIMITS", (10, 90, 200), (255, 255, 255)),
]
img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
slot = W // len(ads)
for i, (txt, bg, fg) in enumerate(ads):
    x0 = i * slot
    # gradient background
    for y in range(H):
        k = 0.75 + 0.35 * (1 - y / H)
        d.line([(x0, y), (x0 + slot, y)], fill=tuple(min(255, int(c * k)) for c in bg))
    size = 100
    while True:
        font = ImageFont.truetype(F, size)
        font.set_variation_by_axes([700])
        bb = d.textbbox((0, 0), txt, font=font)
        if (bb[2] - bb[0] < slot - 60 and bb[3] - bb[1] < H - 34) or size < 20:
            break
        size -= 4
    bb = d.textbbox((0, 0), txt, font=font)
    tx = x0 + (slot - (bb[2] - bb[0])) // 2 - bb[0]
    ty = (H - (bb[3] - bb[1])) // 2 - bb[1]
    d.text((tx, ty), txt, font=font, fill=fg)
    d.rectangle([x0, 0, x0 + 3, H], fill=(10, 10, 10))
# LED pixel grid
grid = Image.new("L", (W, H), 255)
gd = ImageDraw.Draw(grid)
for x in range(0, W, 3):
    gd.line([(x, 0), (x, H)], fill=170)
for y in range(0, H, 3):
    gd.line([(0, y), (W, y)], fill=170)
img = Image.composite(img, Image.new("RGB", (W, H), (0, 0, 0)), grid)
img.save(OUT)
print("wrote", OUT)
