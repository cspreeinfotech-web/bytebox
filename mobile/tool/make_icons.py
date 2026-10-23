"""Builds every Bytebox icon/splash PNG from the brand artwork (assets/brand/bytebox-icon-source.png).

Outputs (assets/icon/): icon.png (legacy, full artwork with wordmark), foreground.png (adaptive:
cloud + box mark only, inside the 66 % safe zone), background.png (navy), monochrome.png, splash.png;
plus docs/store/icon-512.png and admin/public/icon.png.
Run: python3 mobile/tool/make_icons.py
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REPO = os.path.dirname(ROOT)
SRC = os.path.join(ROOT, "assets", "brand", "bytebox-icon-source.png")
OUT = os.path.join(ROOT, "assets", "icon")
NAVY = (5, 10, 26)


def square_artwork():
    """Rounded square from the source, flattened onto navy so corners are full-bleed."""
    src = Image.open(SRC).convert("RGB")
    mask = src.convert("L").point(lambda v: 255 if v < 235 else 0)
    box = mask.getbbox()
    art = src.crop(box)
    m = mask.crop(box)
    sq = Image.new("RGB", art.size, NAVY)
    sq.paste(art, (0, 0), m)
    return sq


def mark(sq):
    """Cloud + box (no wordmark) with alpha derived from distance to the navy background."""
    w, h = sq.size
    crop = sq.crop((int(w * 0.18), int(h * 0.12), int(w * 0.84), int(h * 0.66)))
    rgba = crop.convert("RGBA")
    px = rgba.load()
    for y in range(crop.height):
        for x in range(crop.width):
            r, g, b, _ = px[x, y]
            d = max(abs(r - NAVY[0]), abs(g - NAVY[1]), abs(b - NAVY[2]))
            px[x, y] = (r, g, b, max(0, min(255, int((d - 18) * 4))))
    return rgba


def on_canvas(img, size, fraction, bg=None):
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    scale = size * fraction / max(img.size)
    im = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    sq = square_artwork()
    full = sq.resize((1024, 1024), Image.LANCZOS)
    full.save(os.path.join(OUT, "icon.png"))
    Image.new("RGB", (1024, 1024), NAVY).save(os.path.join(OUT, "background.png"))
    m = mark(sq)
    on_canvas(m, 1024, 0.62).save(os.path.join(OUT, "foreground.png"))
    mono = m.copy()
    white = Image.new("RGBA", mono.size, (255, 255, 255, 255))
    white.putalpha(mono.getchannel("A"))
    on_canvas(white, 1024, 0.62).save(os.path.join(OUT, "monochrome.png"))
    rounded = full.convert("RGBA")
    rm = Image.new("L", rounded.size, 0)
    ImageDraw.Draw(rm).rounded_rectangle([0, 0, 1024, 1024], radius=230, fill=255)
    rounded.putalpha(rm)
    rounded.resize((768, 768), Image.LANCZOS).save(os.path.join(OUT, "splash.png"))
    store = os.path.join(REPO, "docs", "store")
    os.makedirs(store, exist_ok=True)
    full.resize((512, 512), Image.LANCZOS).save(os.path.join(store, "icon-512.png"))
    pub = os.path.join(REPO, "admin", "public")
    os.makedirs(pub, exist_ok=True)
    rounded.resize((512, 512), Image.LANCZOS).save(os.path.join(pub, "icon.png"))


if __name__ == "__main__":
    main()
