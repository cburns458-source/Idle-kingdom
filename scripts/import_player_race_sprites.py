#!/usr/bin/env python3
"""Import race/gender player sprites -> 256x256 lossless WebP in content/assets/player."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = Path('/home/ubuntu/.cursor/projects/workspace/assets')
DEST = ROOT / 'content/assets/player'

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


def strip_and_fit(src: Path, dest: Path) -> None:
    img = Image.open(src).convert('RGBA')
    img.thumbnail((256, 256), Image.Resampling.NEAREST)
    canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    ox = (256 - img.width) // 2
    oy = (256 - img.height) // 2
    canvas.paste(img, (ox, oy), img)
    pixels = canvas.load()
    w, h = canvas.size
    corners = [pixels[0, 0], pixels[w - 1, 0], pixels[0, h - 1], pixels[w - 1, h - 1]]
    opaque = [c for c in corners if c[3] > 200]
    if opaque:
        br = sum(c[0] for c in opaque) // len(opaque)
        bg = sum(c[1] for c in opaque) // len(opaque)
        bb = sum(c[2] for c in opaque) // len(opaque)
        for y in range(h):
            for x in range(w):
                r, g, b, a = pixels[x, y]
                if a < 10:
                    continue
                if abs(r - br) + abs(g - bg) + abs(b - bb) < 36:
                    pixels[x, y] = (r, g, b, 0)
    dest.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dest, 'WEBP', lossless=True)


def main() -> None:
    for stem, filename in MAPPING.items():
        src = SRC / filename
        if not src.exists():
            raise SystemExit(f'missing source {src}')
        strip_and_fit(src, DEST / f'player_{stem}.webp')
        print('wrote', DEST / f'player_{stem}.webp')


if __name__ == '__main__':
    main()
