"""Radiance .hdr -> upper-hemisphere LDR sky JPG for the game's sky shader.
Usage: hdri_sky.py in.hdr out.jpg exposure [width] [gamma_tint r,g,b]
Output is 2:1-cropped to the top half (horizon at the bottom row), sRGB, soft-clipped."""
import sys, numpy as np
from PIL import Image

def read_hdr(path):
    with open(path, 'rb') as f:
        data = f.read()
    i = data.index(b'\n\n') + 2
    j = data.index(b'\n', i)
    dims = data[i:j].split()
    h, w = int(dims[1]), int(dims[3])
    p = j + 1
    out = np.zeros((h, w, 4), np.uint8)
    for y in range(h):
        if data[p] == 2 and data[p+1] == 2:
            p += 4
            for c in range(4):
                x = 0
                row = out[y, :, c]
                while x < w:
                    n = data[p]; p += 1
                    if n > 128:
                        n -= 128
                        row[x:x+n] = data[p]; p += 1
                    else:
                        row[x:x+n] = np.frombuffer(data, np.uint8, n, p); p += n
                    x += n
        else:
            out[y] = np.frombuffer(data, np.uint8, w*4, p).reshape(w, 4); p += w*4
    e = out[..., 3].astype(np.float32)
    scale = np.where(e > 0, np.ldexp(1.0, (e - 136).astype(np.int32)), 0.0)
    return out[..., :3].astype(np.float32) * scale[..., None]

src, dst, expo = sys.argv[1], sys.argv[2], float(sys.argv[3])
width = int(sys.argv[4]) if len(sys.argv) > 4 else 4096
img = read_hdr(src)
h = img.shape[0]
top = img[: h // 2] * expo
top = top / (1.0 + np.maximum(top - 0.8, 0) * 0.6)          # soft shoulder above 0.8
srgb = np.where(top <= 0.0031308, top * 12.92, 1.055 * np.power(np.clip(top, 0, None), 1/2.4) - 0.055)
im = Image.fromarray((np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8))
im = im.resize((width, width // 4), Image.LANCZOS)
im.save(dst, quality=90)
print(dst, im.size, 'mean', np.asarray(im).mean(axis=(0, 1)))
