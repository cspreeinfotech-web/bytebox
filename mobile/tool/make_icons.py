"""Generates Bytebox brand PNGs (theme A · Royal Violet).

Outputs into assets/icon/: icon.png (full), foreground.png (adaptive, safe-zone padded),
monochrome.png, splash.png, plus docs/store/icon-512.png when run from repo root.
Run: python3 mobile/tool/make_icons.py  (needs Pillow + Poppins-Bold.ttf in assets/fonts)
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "icon")
FONT = os.path.join(ROOT, "assets", "fonts", "Poppins-Bold.ttf")
PRIMARY, ACCENT, BG = (0x7C, 0x5C, 0xFF), (0xFF, 0x5C, 0xA8), (0x0A, 0x0A, 0x14)
S = 2048  # supersampled canvas


def gradient(size, a=PRIMARY, b=ACCENT):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return img


def mark_mask(size):
    """White mark: cloud with a bold 'B' monogram and a play triangle knocked out."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    u = size / 1000
    # cloud body
    for cx, cy, r in [(330, 560, 165), (500, 470, 225), (680, 560, 170)]:
        d.ellipse([(cx - r) * u, (cy - r) * u, (cx + r) * u, (cy + r) * u], fill=255)
    d.rounded_rectangle([170 * u, 560 * u, 850 * u, 760 * u], radius=100 * u, fill=255)
    # knock out 'B'
    font = ImageFont.truetype(FONT, int(330 * u))
    bbox = d.textbbox((0, 0), "B", font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    bx, by = 400 * u, 610 * u
    d.text((bx - w / 2 - bbox[0], by - h / 2 - bbox[1]), "B", font=font, fill=0)
    # knock out play triangle
    tx, ty, ts = 640 * u, 610 * u, 105 * u
    d.polygon([(tx - ts * 0.55, ty - ts), (tx - ts * 0.55, ty + ts), (tx + ts, ty)], fill=0)
    return m


def compose(size, mark_scale, rounded):
    big = gradient(S // 4).resize((S, S), Image.BICUBIC).convert("RGBA")
    mask = mark_mask(int(S * mark_scale))
    layer = Image.new("L", (S, S), 0)
    off = (S - mask.size[0]) // 2
    layer.paste(mask, (off, off))
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    big.paste(white, (0, 0), layer)
    if rounded:
        r = Image.new("L", (S, S), 0)
        ImageDraw.Draw(r).rounded_rectangle([0, 0, S, S], radius=int(S * 0.22), fill=255)
        big.putalpha(r)
    return big.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    compose(1024, 0.92, False).save(os.path.join(OUT, "icon.png"))
    # adaptive foreground: transparent background, mark inside 66% safe zone
    fg_mask = mark_mask(int(S * 0.62))
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    off = (S - fg_mask.size[0]) // 2
    fg.paste(Image.new("RGBA", fg_mask.size, (255, 255, 255, 255)), (off, off), fg_mask)
    fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "foreground.png"))
    fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "monochrome.png"))
    gradient(1024).save(os.path.join(OUT, "background.png"))
    compose(768, 0.92, True).save(os.path.join(OUT, "splash.png"))
    store = os.path.join(os.path.dirname(ROOT), "docs", "store")
    os.makedirs(store, exist_ok=True)
    compose(512, 0.92, False).convert("RGB").save(os.path.join(store, "icon-512.png"))


if __name__ == "__main__":
    main()
