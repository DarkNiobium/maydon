"""Title overlay frames (RGBA PNG sequence) for the MAYDON trailer.
usage: python3 titles.py <lang uz|ru> <out_dir> [frames] [--only a-b]
"""
import sys, os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H, FPS = 1920, 1080, 30
FONT = os.path.expanduser("~/maydon/game/assets/fonts/Oswald.ttf")
YEL = (255, 200, 61)
B = 60 / 135 * 4  # bar, s

TXT = {
    "uz": {
        "t1": "SEN JAMOANI BOSHQARMAYSAN.",
        "t2": "SEN — BITTA FUTBOLCHISAN.",
        "t3a": "HAR BIR PAS. HAR BIR ZARBA.",
        "t3b": "SENING QARORING.",
        "tag_arena": "TUNGI ARENA · 5×5",
        "tag_stadium": "STADION · 11×11",
        "t5": "Oʻz futbolchingni yarat".upper(),
        "t6": "Doʻstlar bilan oʻyna".upper(),
        "tagline": "Bitta oʻyinchi — butun maydon".upper(),
        "soon": "TEZ KUNDA · ANDROID",
    },
    "ru": {
        "t1": "ТЫ НЕ УПРАВЛЯЕШЬ КОМАНДОЙ.",
        "t2": "ТЫ — ОДИН ИГРОК НА ПОЛЕ.",
        "t3a": "КАЖДЫЙ ПАС. КАЖДЫЙ УДАР.",
        "t3b": "ТВОЁ РЕШЕНИЕ.",
        "tag_arena": "НОЧНАЯ АРЕНА · 5×5",
        "tag_stadium": "СТАДИОН · 11×11",
        "t5": "СОЗДАЙ СВОЕГО ФУТБОЛИСТА",
        "t6": "ИГРАЙ С ДРУЗЬЯМИ",
        "tagline": "ОДИН ИГРОК — ВСЁ ПОЛЕ",
        "soon": "СКОРО НА ANDROID",
    },
}

# shot starts (output seconds) — must match edit.py
T_END = 46.208


def cues(L):
    t = TXT[L]
    return [
        # (kind, text, t_in, t_out, extra)
        ("center", t["t1"], 1.15, 4.15, {}),
        ("center", t["t2"], 5.35, 8.55, {}),
        ("center", t["t3a"], 9.55, 13.75, {"dy": -46}),
        ("center", t["t3b"], 11.35, 13.75, {"dy": 52, "color": YEL}),
        ("tag", t["tag_arena"], 14.45, 15.95, {}),
        ("tag", t["tag_stadium"], 18.0, 21.2, {}),
        ("side", t["t5"], 33.95, 37.25, {"x": 0.27}),
        ("side", t["t6"], 37.5, 40.8, {"x": 0.5, "y": 0.86}),
        ("big", "11×11", 40.875, 40.875 + B / 2, {}),
        ("big", "5×5", 40.875 + B / 2, 40.875 + B, {}),
        ("big", "3×3", 40.875 + B, 40.875 + 1.5 * B, {}),
        ("end", t, T_END, 99.0, {}),
    ]


_fonts = {}


def font(size, weight="Bold"):
    k = (size, weight)
    if k not in _fonts:
        f = ImageFont.truetype(FONT, size)
        f.set_variation_by_name(weight)
        _fonts[k] = f
    return _fonts[k]


def text_w(s, f, track):
    return sum(f.getlength(c) for c in s) + track * (len(s) - 1)


def draw_tracked(d, x, y, s, f, track, fill):
    for c in s:
        d.text((x, y), c, font=f, fill=fill)
        x += f.getlength(c) + track


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return 1 - (1 - x) ** 3


def layer_text(img, s, f, track, cx, cy, color, alpha, shadow=True, anchor="center"):
    """Draw tracked text centred at (cx, cy) with a soft shadow."""
    tw = text_w(s, f, track)
    asc, desc = f.getmetrics()
    th = asc + desc
    x = cx - tw / 2 if anchor == "center" else cx
    y = cy - th / 2
    if shadow:
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        draw_tracked(ImageDraw.Draw(sh), x + 3, y + 4, s, f, track, (0, 0, 0, int(200 * alpha)))
        sh = sh.filter(ImageFilter.GaussianBlur(9))
        img.alpha_composite(sh)
    t = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_tracked(ImageDraw.Draw(t), x, y, s, f, track, color + (int(255 * alpha),))
    img.alpha_composite(t)
    return x, y, tw, th


FLASHES = [30.208, 46.208]


def render_frame(L, fi):
    t = fi / FPS
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    any_ = False
    for fl in FLASHES:
        if fl - 0.5 / FPS <= t < fl + 0.12:
            k = 1.0 - (t - fl) / 0.12
            img = Image.new("RGBA", (W, H), (255, 255, 255, int(200 * max(0.0, min(1.0, k)))))
            any_ = True
    for kind, s, t0, t1, ex in cues(L):
        if not (t0 <= t < t1):
            continue
        any_ = True
        u = (t - t0) / max(t1 - t0, 1e-3)
        fin, fout = 0.27, 0.27
        a = min(ease((t - t0) / fin), ease((t1 - t) / fout)) if kind not in ("big", "end") else 1.0
        if kind == "center":
            f = font(84, "Bold")
            track = 3 + 5 * u                 # slow widening, cinematic
            cy = H * 0.5 + ex.get("dy", 0) - 12 * ease((t - t0) / 0.6)
            col = ex.get("color", (255, 255, 255))
            x, y, tw, th = layer_text(img, s, f, track, W / 2, cy + 12, col, a)
        elif kind == "tag":
            f = font(40, "SemiBold")
            slide = 30 * (1 - ease((t - t0) / 0.35))
            x0 = 96 - slide
            y0 = H - 150
            d = ImageDraw.Draw(img)
            d.rectangle([x0, y0 - 4, x0 + 7, y0 + 50], fill=YEL + (int(255 * a),))
            layer_text(img, s, f, 4, x0 + 24, y0 + 22, (255, 255, 255), a, anchor="left")
        elif kind == "side":
            f = font(70, "Bold")
            cx = W * ex.get("x", 0.5)
            cy = H * ex.get("y", 0.80) - 10 * ease((t - t0) / 0.5)
            x, y, tw, th = layer_text(img, s, f, 2 + 3 * u, cx, cy + 10, (255, 255, 255), a)
            bw = tw * ease((t - t0) / 0.5)
            d = ImageDraw.Draw(img)
            d.rectangle([cx - bw / 2, y + th + 8, cx + bw / 2, y + th + 14], fill=YEL + (int(255 * a),))
        elif kind == "big":
            k = ease((t - t0) / 0.13)
            f = font(int(250 * (1.12 - 0.12 * k)), "Bold")
            layer_text(img, s, f, 6, W / 2, H * 0.5, (255, 255, 255), 1.0)
        elif kind == "end":
            T = s
            te = t - t0
            fl = font(250, "Bold")
            track = 34 - 14 * ease(te / 1.2)
            al = ease(te / 0.25)
            x, y, tw, th = layer_text(img, "MAYDON", fl, track, W / 2, H * 0.43, (255, 255, 255), al)
            d = ImageDraw.Draw(img)
            bw = 280 * ease((te - 0.15) / 0.6)
            d.rectangle([W / 2 - bw / 2, H * 0.43 + 150, W / 2 + bw / 2, H * 0.43 + 158], fill=YEL + (int(255 * al),))
            a2 = ease((te - 0.55) / 0.5)
            layer_text(img, T["tagline"], font(46, "Regular"), 8, W / 2, H * 0.43 + 215, (235, 235, 235), a2)
            a3 = ease((te - 1.2) / 0.5)
            layer_text(img, T["soon"], font(40, "SemiBold"), 10, W / 2, H * 0.43 + 300, YEL, a3)
    return img if any_ else None


def main():
    L, out = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else int(round(50.9 * FPS))
    os.makedirs(out, exist_ok=True)
    blank = os.path.join(out, "blank.png")
    Image.new("RGBA", (W, H), (0, 0, 0, 0)).save(blank)
    only = None
    if "--only" in sys.argv:
        a, b = sys.argv[sys.argv.index("--only") + 1].split("-")
        only = (int(a), int(b))
    for fi in range(n):
        if only and not (only[0] <= fi < only[1]):
            continue
        p = os.path.join(out, "f_%05d.png" % fi)
        im = render_frame(L, fi)
        if os.path.lexists(p):
            os.remove(p)
        if im is None:
            os.symlink("blank.png", p)
        else:
            im.save(p, compress_level=1)


if __name__ == "__main__":
    main()
