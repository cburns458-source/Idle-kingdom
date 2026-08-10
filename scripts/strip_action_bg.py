#!/usr/bin/env python3
"""Strip near-solid backgrounds from generated action sprites -> RGBA."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image


def strip_background(path: Path) -> None:
    img = Image.open(path).convert('RGBA')
    # Fit to 256x256 canvas preserving aspect.
    img.thumbnail((256, 256), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    ox = (256 - img.width) // 2
    oy = (256 - img.height) // 2
    canvas.paste(img, (ox, oy), img)
    pixels = canvas.load()
    w, h = canvas.size

    # Sample corners to detect flat backdrop color.
    corners = [
        pixels[0, 0],
        pixels[w - 1, 0],
        pixels[0, h - 1],
        pixels[w - 1, h - 1],
    ]
    # Prefer the most common opaque corner color.
    opaque = [c for c in corners if c[3] > 200]
    if not opaque:
        canvas.save(path)
        return
    # Average corner RGB
    br = sum(c[0] for c in opaque) // len(opaque)
    bg = sum(c[1] for c in opaque) // len(opaque)
    bb = sum(c[2] for c in opaque) // len(opaque)

    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 8:
                continue
            dist = abs(r - br) + abs(g - bg) + abs(b - bb)
            # Soft fringe near backdrop
            if dist < 45:
                pixels[x, y] = (r, g, b, 0)
            elif dist < 75:
                fade = int(a * (dist - 45) / 30)
                pixels[x, y] = (r, g, b, fade)

    canvas.save(path)
    print(f'stripped {path.name}')


def main() -> None:
    paths = [Path(p) for p in sys.argv[1:]]
    if not paths:
        paths = sorted(Path('public/assets/actions').glob('*.png'))
    for path in paths:
        if path.exists():
            strip_background(path)


if __name__ == '__main__':
    main()
