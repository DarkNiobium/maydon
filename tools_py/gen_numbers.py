#!/usr/bin/env python3
"""Shirt number digit atlas: 10 digits in a row, white on transparent, with a soft dark outline."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys
F = os.path.expanduser("~/maydon/game/assets/fonts/Oswald.ttf")
W, H = 128, 192
img = Image.new("RGBA", (W * 10, H), (0, 0, 0, 0))
font = ImageFont.truetype(F, 190)
font.set_variation_by_axes([700])
for d in range(10):
    tile = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    bb = td.textbbox((0, 0), str(d), font=font)
    x = (W - (bb[2] - bb[0])) // 2 - bb[0]
    y = (H - (bb[3] - bb[1])) // 2 - bb[1]
    # outline channel in G, fill in R (shader colours them)
    ol = Image.new("L", (W, H), 0)
    ImageDraw.Draw(ol).text((x, y), str(d), font=font, fill=255, stroke_width=7, stroke_fill=255)
    fl = Image.new("L", (W, H), 0)
    ImageDraw.Draw(fl).text((x, y), str(d), font=font, fill=255)
    tile = Image.merge("RGBA", (fl, ol, Image.new("L", (W, H), 0), ol))
    img.paste(tile, (d * W, 0))
out = sys.argv[1]
img.save(out)
print("ok", out)
