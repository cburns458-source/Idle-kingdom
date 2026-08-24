#!/usr/bin/env python3
"""Stand-in Castle Crypt plate and ghost sprite from existing art."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps

ROOT = Path(__file__).resolve().parents[1]
LOCATIONS = ROOT / 'content/assets/locations'
ENEMIES = ROOT / 'content/assets/enemies'


def paint_crypt() -> None:
    src = Image.open(LOCATIONS / 'loc_abandoned_mineshaft.webp').convert('RGB')
    darkened = ImageEnhance.Brightness(src).enhance(0.72)
    cooled = ImageOps.colorize(
        ImageOps.grayscale(darkened),
        black=(8, 10, 22),
        white=(168, 186, 210),
    ).convert('RGB')
    blended = Image.blend(darkened, cooled, 0.45)
    dest = LOCATIONS / 'loc_castle_crypt.webp'
    blended.save(dest, 'WEBP', quality=82, method=6)
    print('wrote', dest, blended.size)


def paint_ghost() -> None:
    src = Image.open(ENEMIES / 'enm_zombie.webp').convert('RGBA')
    pixels = src.load()
    w, h = src.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            glow = int((r + g + b) / 3)
            pixels[x, y] = (
                min(255, int(140 + glow * 0.35)),
                min(255, int(190 + glow * 0.25)),
                min(255, 255),
                min(255, int(a * 0.78)),
            )
    dest = ENEMIES / 'enm_ghost.webp'
    src.save(dest, 'WEBP', lossless=True)
    print('wrote', dest, src.size)


def paint_wand() -> None:
    import sys

    sys.path.insert(0, str(ROOT / 'scripts'))
    from paint_item_icons import paint_item

    dest = ROOT / 'content/assets/icons/items/item_mages_wand.webp'
    paint_item("Mage's Wand").save(dest, 'WEBP', lossless=True)
    print('wrote', dest)


def main() -> None:
    paint_crypt()
    paint_ghost()
    paint_wand()


if __name__ == '__main__':
    main()
