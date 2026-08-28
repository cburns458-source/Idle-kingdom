#!/usr/bin/env python3
"""Import race/gender player sprites -> 256x256 PNG in content/assets/player."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = Path('/home/ubuntu/.cursor/projects/workspace/assets')
DEST = ROOT / 'content/assets/player'

CANVAS = 256
FILL = 0.92  # fraction of the canvas the figure should occupy

# Feminine + androgynous share one plate per race; masculine is separate.
MAPPING: dict[str, str] = {
    'human_feminine': '01a03b3a-6f9d-75df-9119-170b2a863904.jpg',
    'human_masculine': '01a03b3a-5503-7700-b161-90a6be315a8b.jpg',
    'wood_elf_feminine': '01a03b3b-0424-7f16-8af5-4000011f56fa.jpg',
    'wood_elf_masculine': '01a03b3a-a4a4-7a9f-9c5f-388e4e1d885d.jpg',
    'high_elf_feminine': '01a03b3b-8edf-76c3-8715-d4a9bc3e7d41.jpg',
    'high_elf_masculine': '01a03b3b-2e68-7fd1-ba75-5591f2ff47f4.jpg',
    'orc_feminine': '01a03b3b-e811-718f-ad97-01748eecff64.jpg',
    'orc_masculine': '01a03b3b-c172-76d8-b1ea-b3a65e44b016.jpg',
    'goblin_feminine': '01a03b3c-41fc-775f-a322-2601dd52336b.jpg',
    'goblin_masculine': '01a03b3c-16c2-74bb-8d08-650347fb7067.jpg',
    'dwarf_feminine': '01a03b3c-be5e-7f7a-bb27-6f97cc48f27b.jpg',
    'dwarf_masculine': '01a03b3c-93a7-7b1f-ab16-004dd789e07d.jpg',
    'halfling_feminine': '01a03b3d-1e07-71d7-a7ff-e40b1a3bd788.jpg',
    'halfling_masculine': '01a03b3c-e69c-7110-88f8-a2ceba08c882.jpg',
}


def _bg_color(img: Image.Image) -> tuple[int, int, int]:
    pixels = img.load()
    w, h = img.size
    corners = [pixels[0, 0], pixels[w - 1, 0], pixels[0, h - 1], pixels[w - 1, h - 1]]
    opaque = [c for c in corners if c[3] > 200]
    if not opaque:
        return (255, 255, 255)
    return (
        sum(c[0] for c in opaque) // len(opaque),
        sum(c[1] for c in opaque) // len(opaque),
        sum(c[2] for c in opaque) // len(opaque),
    )


def _flood_clear_background(img: Image.Image, tolerance: int = 42) -> Image.Image:
    """Remove the flat backdrop connected to the image border."""
    img = img.convert('RGBA')
    pixels = img.load()
    w, h = img.size
    br, bg, bb = _bg_color(img)

    def matches_backdrop(r: int, g: int, b: int, a: int) -> bool:
        if a < 8:
            return True
        return abs(r - br) + abs(g - bg) + abs(b - bb) < tolerance

    seen = [[False] * w for _ in range(h)]
    queue: deque[tuple[int, int]] = deque()

    def try_seed(x: int, y: int) -> None:
        if seen[y][x]:
            return
        seen[y][x] = True
        r, g, b, a = pixels[x, y]
        if matches_backdrop(r, g, b, a):
            queue.append((x, y))

    for x in range(w):
        try_seed(x, 0)
        try_seed(x, h - 1)
    for y in range(h):
        try_seed(0, y)
        try_seed(w - 1, y)

    while queue:
        x, y = queue.popleft()
        r, g, b, a = pixels[x, y]
        dist = abs(r - br) + abs(g - bg) + abs(b - bb)
        if dist < tolerance:
            pixels[x, y] = (r, g, b, 0)
        elif dist < tolerance + 28:
            fade = int(a * (dist - tolerance) / 28)
            pixels[x, y] = (r, g, b, fade)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx]:
                seen[ny][nx] = True
                nr, ng, nb, na = pixels[nx, ny]
                if matches_backdrop(nr, ng, nb, na):
                    queue.append((nx, ny))

    return img


def _alpha_bbox(img: Image.Image, alpha_floor: int = 12) -> tuple[int, int, int, int]:
    pixels = img.load()
    w, h = img.size
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] > alpha_floor:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < min_x:
        return 0, 0, w, h
    return min_x, min_y, max_x + 1, max_y + 1


def strip_and_fit(src: Path, dest: Path) -> None:
    img = _flood_clear_background(Image.open(src))
    left, top, right, bottom = _alpha_bbox(img)
    cropped = img.crop((left, top, right, bottom))

    target = int(CANVAS * FILL)
    scale = min(target / cropped.width, target / cropped.height)
    new_w = max(1, int(round(cropped.width * scale)))
    new_h = max(1, int(round(cropped.height * scale)))
    scaled = cropped.resize((new_w, new_h), Image.Resampling.NEAREST)

    canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    ox = (CANVAS - new_w) // 2
    oy = (CANVAS - new_h) // 2
    canvas.paste(scaled, (ox, oy), scaled)
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest, 'PNG')


def main() -> None:
    for stem, filename in MAPPING.items():
        src = SRC / filename
        if not src.exists():
            raise SystemExit(f'missing source {src}')
        strip_and_fit(src, DEST / f'player_{stem}.png')
        print('wrote', DEST / f'player_{stem}.png')


if __name__ == '__main__':
    main()
