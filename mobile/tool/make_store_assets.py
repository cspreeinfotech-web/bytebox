"""Store artwork: 1024x500 feature graphic (and framing helper for screenshots, see frame_screens.py)."""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONTS = os.path.join(ROOT, "mobile", "assets", "fonts")
OUT = os.path.join(ROOT, "docs", "store")
P, A, BG = (0x7C, 0x5C, 0xFF), (0xFF, 0x5C, 0xA8), (0x0A, 0x0A, 0x14)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def feature():
    w, h = 1024, 500
    img = Image.new("RGB", (w, h), BG)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = x / w
            glow = max(0.0, 1 - ((x - 760) ** 2 + (y - 250) ** 2) ** 0.5 / 520)
            base = lerp(BG, lerp(P, A, t), 0.18 + 0.55 * glow)
            px[x, y] = base
    d = ImageDraw.Draw(img)
    bold = ImageFont.truetype(os.path.join(FONTS, "Poppins-Bold.ttf"), 64)
    med = ImageFont.truetype(os.path.join(FONTS, "Poppins-Medium.ttf"), 28)
    d.text((64, 120), "Your files,", font=bold, fill=(255, 255, 255))
    d.text((64, 196), "your own cloud.", font=bold, fill=(255, 255, 255))
    d.text((66, 300), "Private cloud for photos, videos & files", font=med, fill=(210, 205, 240))
    d.text((66, 342), "15 GB free when you create an account", font=med, fill=(210, 205, 240))
    icon = Image.open(os.path.join(OUT, "icon-512.png")).convert("RGBA").resize((300, 300), Image.LANCZOS)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 300, 300], radius=68, fill=255)
    img.paste(icon, (640, 100), mask)
    img.save(os.path.join(OUT, "feature-graphic-1024x500.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    feature()
