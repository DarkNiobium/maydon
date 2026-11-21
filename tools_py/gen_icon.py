#!/usr/bin/env python3
"""App icon: night pitch green, white ball with pentagon pattern, MAYDON wordmark-free (reads at 48px)."""
from PIL import Image, ImageDraw, ImageFilter
import math, os, sys
S = 1024
out = sys.argv[1]
img = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    k = y / S
    c = (int(8 + 20 * (1 - k)), int(70 + 90 * (1 - k)), int(40 + 40 * (1 - k)), 255)
    d.line([(0, y), (S, y)], fill=c)
# mowing stripes
for i in range(0, S, 128):
    d.rectangle([i, 0, i + 63, S], fill=(255, 255, 255, 14))
# pitch arc
d.ellipse([S * 0.12, S * 0.62, S * 0.88, S * 1.38], outline=(255, 255, 255, 120), width=14)
# ball
cx, cy, r = S * 0.5, S * 0.46, S * 0.28
sh = Image.new("RGBA", (S, S))
sd = ImageDraw.Draw(sh)
sd.ellipse([cx - r * 0.9, cy + r * 0.85, cx + r * 0.9, cy + r * 1.15], fill=(0, 0, 0, 120))
sh = sh.filter(ImageFilter.GaussianBlur(18))
img.alpha_composite(sh)
d = ImageDraw.Draw(img)
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(246, 246, 244, 255))
def pent(x, y, rr, rot):
    pts = [(x + rr * math.cos(rot + i * 2 * math.pi / 5), y + rr * math.sin(rot + i * 2 * math.pi / 5)) for i in range(5)]
    d.polygon(pts, fill=(18, 22, 28, 255))
pent(cx, cy, r * 0.34, -math.pi / 2)
for i in range(5):
    a = -math.pi / 2 + i * 2 * math.pi / 5
    pent(cx + math.cos(a) * r * 0.9, cy + math.sin(a) * r * 0.9, r * 0.26, a + math.pi)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
ball = img.copy()
img2 = Image.new("RGBA", (S, S))
for y in range(S):
    k = y / S
    ImageDraw.Draw(img2).line([(0, y), (S, y)], fill=(int(8 + 20 * (1 - k)), int(70 + 90 * (1 - k)), int(40 + 40 * (1 - k)), 255))
img2.paste(ball, (0, 0), mask)
# re-draw background parts outside ball
bgimg = img.copy()
bgimg.paste(ball, (0, 0), mask)
# highlight
hl = Image.new("RGBA", (S, S))
ImageDraw.Draw(hl).ellipse([cx - r * 0.7, cy - r * 0.85, cx + r * 0.1, cy - r * 0.2], fill=(255, 255, 255, 70))
hl = hl.filter(ImageFilter.GaussianBlur(30))
bgimg.alpha_composite(Image.composite(hl, Image.new("RGBA", (S, S)), mask))
# accent bar
ImageDraw.Draw(bgimg).rectangle([S * 0.3, S * 0.84, S * 0.7, S * 0.87], fill=(40, 220, 122, 255))
bgimg.save(out)
bgimg.resize((432, 432), Image.LANCZOS).save(os.path.join(os.path.dirname(out), "icon_fg.png"))
print("ok")
