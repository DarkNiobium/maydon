#!/usr/bin/env python3
"""Generate LED ad-board atlas with fictional local brands (no real trademarks)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random, sys, os
OUT = sys.argv[1] if len(sys.argv) > 1 else "ads.png"
F = os.path.expanduser("~/maydon/game/assets/fonts/Oswald.ttf")
W, H = 4096, 128          # 8 ads of 512x128 (each = 4 m of board)
ads = [
    ("MAYDON", (12, 160, 90), (255, 255, 255)),
    ("CHOYXONA 24", (180, 30, 40), (255, 230, 160)),
    ("TOSHKENT NON", (230, 160, 20), (40, 20, 0)),
    ("UZSPORT TV", (20, 60, 170), (255, 255, 255)),
    ("OSH MARKAZI", (240, 240, 240), (170, 40, 20)),
    ("SAMARQAND SUV", (0, 140, 200), (255, 255, 255)),
    ("NAVRO'Z BANK", (90, 20, 120), (255, 210, 80)),
    ("PAXTA KIYIM", (25, 25, 30), (120, 220, 255)),
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
