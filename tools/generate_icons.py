#!/usr/bin/env python3
"""Draw the addon-list icons (64x64 TGA) for the three addons: python3 tools/generate_icons.py [--check]."""
import math
import struct
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
S = 512  # drawing size, reduced to 64
GOLD, GOLD_D, GOLD_L = (214, 168, 66), (122, 88, 30), (255, 226, 140)
STEEL, STEEL_D = (205, 214, 226), (96, 108, 126)
GREEN, WOOD = (96, 232, 120), (140, 92, 48)


def base():
    im = Image.new('RGBA', (S, S), (10, 18, 44, 255))
    d = ImageDraw.Draw(im)
    for i in range(0, 60):  # soft vignette
        c = 10 + i // 3
        d.rectangle([i, i, S - 1 - i, S - 1 - i], outline=(c, c + 8, c + 30, 255))
    return im


def frame(im):
    d = ImageDraw.Draw(im)
    d.rectangle([14, 14, S - 15, S - 15], outline=GOLD_D, width=22)
    d.rectangle([20, 20, S - 21, S - 21], outline=GOLD, width=14)
    d.line([20, 20, S - 21, 20], fill=GOLD_L, width=4)
    d.line([20, 20, 20, S - 21], fill=GOLD_L, width=4)


def ring(d, cx, cy, r, w, col):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=w)


def crosshair(d, cx, cy, r):
    ring(d, cx, cy, r, 18, GOLD_D)
    ring(d, cx, cy, r - 3, 10, GOLD)
    ring(d, cx, cy, r * 0.45, 12, GREEN)
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=GREEN)
    for a in (0, 90, 180, 270):
        x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
        d.line([cx + x * (r - 40), cy + y * (r - 40), cx + x * (r + 46), cy + y * (r + 46)], fill=GOLD_L, width=12)


def bow(d):
    pts = [(150 + 190 * math.sin(t / 40 * math.pi) ** 0.8 * 0.0 + 120 * math.sin(t / 40 * math.pi), 90 + 330 * t / 40) for t in range(41)]
    d.line(pts, fill=WOOD, width=26)
    d.line([pts[0], pts[-1]], fill=STEEL, width=5)
    d.line([(150, 255), (400, 255)], fill=STEEL, width=12)
    d.polygon([(430, 255), (385, 228), (385, 282)], fill=STEEL)
    d.polygon([(150, 255), (178, 235), (190, 255), (178, 275)], fill=GREEN)


def dagger(d, ang, col_poison=False):
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.polygon([(246, 60), (266, 60), (276, 300), (236, 300)], fill=STEEL)
    ld.polygon([(256, 60), (266, 60), (276, 300), (256, 300)], fill=STEEL_D)
    ld.rectangle([196, 300, 316, 326], fill=GOLD)
    ld.rectangle([240, 326, 272, 410], fill=WOOD)
    ld.ellipse([234, 404, 278, 448], fill=GOLD_D)
    if col_poison:
        ld.polygon([(256, 80), (266, 80), (272, 220), (240, 220)], fill=GREEN)
    return layer.rotate(ang, resample=Image.BICUBIC, center=(256, 256))


def emblem(kind):
    im = base()
    if kind == 'core':
        d = ImageDraw.Draw(im)
        crosshair(d, 256, 256, 140)
    elif kind == 'hunter':
        d = ImageDraw.Draw(im)
        crosshair(d, 290, 256, 110)
        bow(d)
    else:
        for ang, p in ((38, False), (-38, True)):
            im.alpha_composite(dagger(None, ang, p))
    frame(im)
    glow = im.filter(ImageFilter.GaussianBlur(1))
    return Image.blend(im, glow, 0.25).resize((64, 64), Image.LANCZOS).convert('RGBA')


def tga(img):
    px = img.load()
    rows = bytearray()
    for y in range(63, -1, -1):  # bottom-up, uncompressed 32-bit
        for x in range(64):
            r, g, b, a = px[x, y]
            rows += bytes((b, g, r, 255))
    return struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, 64, 64, 32, 8) + bytes(rows)


ICONS = {'BajtFightAssist': 'core', 'BajtFightAssist_Hunter': 'hunter', 'BajtFightAssist_Rogue': 'rogue'}

if __name__ == '__main__':
    check = '--check' in sys.argv
    for folder, kind in ICONS.items():
        img = emblem(kind)
        out = ROOT / folder / 'Artwork' / 'AddonIcon.tga'
        data = tga(img)
        if check:
            if not out.is_file() or out.read_bytes() != data:
                raise SystemExit('stale icon: ' + folder)
            continue
        out.parent.mkdir(exist_ok=True)
        out.write_bytes(data)
        art = ROOT / 'artwork' / folder
        art.mkdir(parents=True, exist_ok=True)
        img.save(art / 'icon-64.png')
        print(out)
