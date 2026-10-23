#!/usr/bin/env python3
"""Turns raw emulator screenshots into Play-ready images + an E2E evidence folder.

usage: frame.py <raw_dir>
raw names: <device>_<name>.png where device ∈ phone|tablet7|tablet10 (from SHOT_PREFIX)
"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(ROOT, "mobile", "assets", "fonts", "Poppins-Bold.ttf")
STORE, E2E = os.path.join(ROOT, "docs", "store"), os.path.join(ROOT, "docs", "e2e")
BG, P, A = (5, 10, 26), (30, 140, 255), (25, 211, 255)
CAPTIONS = {
    "1-cloud": "Your private cloud", "2-plans": "15 GB free with an account", "3-explore": "Explore creator videos",
    "4-feed": "Newest from channels you follow", "5-channels": "Join channels you love", "6-profile": "Everything in one place",
}
SIZES = {"phone": (1080, 1920), "tablet7": (1200, 1920), "tablet10": (1600, 2560)}


def canvas(size):
    w, h = size
    img = Image.new("RGB", size, BG)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        c = tuple(int(BG[i] + ((P if t < .5 else A)[i] - BG[i]) * (0.35 * (1 - abs(t - .3)))) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    return img


def frame(src, device, caption):
    w, h = SIZES[device]
    img = canvas((w, h))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(w * 0.062))
    tw = d.textlength(caption, font=font)
    d.text(((w - tw) / 2, h * 0.045), caption, font=font, fill=(255, 255, 255))
    shot = Image.open(src).convert("RGB")
    top = int(h * 0.13)
    max_w, max_h = int(w * 0.86), h - top - int(h * 0.03)
    scale = min(max_w / shot.width, max_h / shot.height)
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.LANCZOS)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *shot.size], radius=int(w * 0.04), fill=255)
    img.paste(shot, ((w - shot.width) // 2, top), mask)
    return img


def main(raw):
    os.makedirs(STORE, exist_ok=True)
    os.makedirs(E2E, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(raw, "*.png"))):
        base = os.path.basename(path)[:-4]
        device, _, name = base.partition("_")
        if name.startswith("e2e-"):
            Image.open(path).save(os.path.join(E2E, f"{device}-{name}.png"))
            continue
        if name not in CAPTIONS or device not in SIZES:
            continue
        n = name.split("-")[0]
        out = f"phone-{n}.png" if device == "phone" else f"{device}-{n}.png"
        frame(path, device, CAPTIONS[name]).save(os.path.join(STORE, out))
        print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
