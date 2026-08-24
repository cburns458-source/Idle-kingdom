#!/usr/bin/env python3
"""Paint a 32x32 icon for every item from its display name.

Same tool/armor/weapon pose per family; metal, wood, and gem colors are
shared across every item that names that material. Transparent background,
no black outlines — edges are a darker shade of the fill.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'content/assets/icons/items'
DATABASE = ROOT / 'content/data/game-database.json'

# light, mid, dark — never #000000
METAL = {
    'copper': ((232, 154, 82), (184, 98, 42), (122, 58, 24)),
    'bronze': ((220, 162, 72), (180, 112, 36), (110, 64, 20)),
    'tin': ((226, 226, 214), (176, 178, 168), (112, 114, 106)),
    'iron': ((168, 170, 176), (110, 112, 118), (64, 66, 72)),
    'steel': ((198, 208, 218), (130, 142, 156), (70, 80, 92)),
    'reinforced steel': ((176, 192, 220), (92, 110, 148), (46, 56, 86)),
    'silver': ((236, 240, 244), (184, 190, 198), (110, 116, 124)),
    'gold': ((245, 214, 96), (204, 152, 28), (130, 92, 16)),
    'golden': ((245, 214, 96), (204, 152, 28), (130, 92, 16)),
    'titanium': ((226, 236, 240), (164, 184, 194), (88, 108, 118)),
    'tungsten': ((150, 136, 168), (86, 74, 104), (48, 40, 58)),
    'ancient alloy': ((176, 196, 86), (108, 132, 48), (58, 74, 28)),
    'aether': ((186, 230, 255), (88, 168, 220), (40, 88, 140)),
    'moonstone': ((220, 232, 246), (168, 196, 220), (96, 128, 160)),
}

WOOD = {
    'wooden': ((210, 154, 82), (150, 96, 46), (92, 56, 26)),
    'cedar': ((210, 118, 72), (160, 72, 40), (96, 40, 22)),
    'oak': ((196, 140, 72), (138, 90, 40), (82, 52, 22)),
    'poplar': ((230, 214, 150), (186, 168, 98), (120, 108, 58)),
    'maple': ((220, 148, 56), (176, 104, 32), (108, 60, 18)),
    'mahogany': ((168, 72, 48), (112, 40, 28), (68, 22, 16)),
    'ancient': ((132, 148, 64), (86, 98, 40), (50, 58, 22)),
    'regular': ((196, 140, 72), (138, 90, 40), (82, 52, 22)),
}

GEM = {
    'sapphire': ((110, 178, 255), (36, 92, 196), (16, 48, 120)),
    'emerald': ((96, 230, 140), (24, 148, 78), (12, 82, 44)),
    'ruby': ((255, 96, 120), (196, 28, 56), (112, 12, 28)),
}

HANDLE = WOOD['oak']
LEATHER = ((176, 118, 70), (124, 76, 42), (78, 46, 24))
CLOTH = ((236, 232, 220), (186, 180, 168), (118, 112, 102))
BONE = ((236, 224, 196), (198, 180, 140), (132, 114, 82))


def rgb(c: tuple[int, int, int]) -> tuple[int, int, int, int]:
    return (c[0], c[1], c[2], 255)


def has(name: str, *words: str) -> bool:
    n = name.lower()
    return any(re.search(rf'(?<![a-z]){re.escape(word)}(?![a-z])', n) for word in words)


def content_box(rows: list[str]) -> tuple[int, int, int, int]:
    xs: list[int] = []
    ys: list[int] = []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                xs.append(x)
                ys.append(y)
    if not xs:
        return 0, 0, 0, 0
    return min(xs), min(ys), max(xs), max(ys)


class Canvas:
    def __init__(self) -> None:
        self.p = [[(0, 0, 0, 0) for _ in range(32)] for _ in range(32)]

    def put(self, x: int, y: int, color: tuple[int, int, int]) -> None:
        if 0 <= x < 32 and 0 <= y < 32:
            self.p[y][x] = rgb(color)

    def stamp(self, ox: int, oy: int, rows: list[str], pal: dict[str, tuple[int, int, int]]) -> None:
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in pal:
                    self.put(ox + x, oy + y, pal[ch])

    def stamp_centered(self, rows: list[str], pal: dict[str, tuple[int, int, int]]) -> None:
        x0, y0, x1, y1 = content_box(rows)
        ox = (32 - (x1 - x0 + 1)) // 2 - x0
        oy = (32 - (y1 - y0 + 1)) // 2 - y0
        self.stamp(ox, oy, rows, pal)

    def image(self) -> Image.Image:
        img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
        img.putdata([px for row in self.p for px in row])
        return img


def fit_to_square(img: Image.Image, size: int = 32, margin: int = 1) -> Image.Image:
    """Scale the opaque art so it fills the item square, with a 1px gutter."""
    bbox = img.getbbox()
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if not bbox:
        return out
    cropped = img.crop(bbox)
    cw, ch = cropped.size
    target = max(1, size - 2 * margin)
    scale = min(target / cw, target / ch)
    nw = max(1, min(target, round(cw * scale)))
    nh = max(1, min(target, round(ch * scale)))
    scaled = cropped.resize((nw, nh), Image.Resampling.NEAREST)
    out.paste(scaled, ((size - nw) // 2, (size - nh) // 2), scaled)
    return out


def metal_of(name: str) -> tuple[tuple[int, int, int], ...] | None:
    n = name.lower()
    for key in sorted(METAL, key=len, reverse=True):
        if key in n:
            return METAL[key]
    return None


def wood_of(name: str) -> tuple[tuple[int, int, int], ...]:
    n = name.lower()
    for key in sorted(WOOD, key=len, reverse=True):
        if key in n:
            return WOOD[key]
    return WOOD['oak']


def gem_of(name: str) -> tuple[tuple[int, int, int], ...] | None:
    n = name.lower()
    for key, pal in GEM.items():
        if key in n:
            return pal
    return None


def mp(pal: tuple[tuple[int, int, int], ...]) -> dict[str, tuple[int, int, int]]:
    light, mid, dark = pal
    return {'m': light, 'M': mid, 'D': dark}


def hp(pal: tuple[tuple[int, int, int], ...] = HANDLE) -> dict[str, tuple[int, int, int]]:
    light, mid, dark = pal
    return {'h': light, 'H': mid, 'd': dark}


def wp(pal: tuple[tuple[int, int, int], ...]) -> dict[str, tuple[int, int, int]]:
    light, mid, dark = pal
    return {'W': mid, 'w': light, 'B': dark, 's': (220, 214, 196)}


def gp(pal: tuple[tuple[int, int, int], ...]) -> dict[str, tuple[int, int, int]]:
    return {'g': pal[0], 'G': pal[1], 'X': pal[2]}


# --- family stamps (same pose, recolored) ------------------------------------

PICKAXE = [
    '........mmmmm...........',
    '.......mMMMMMm..........',
    '......mMMMMMMMm.........',
    '.....mMMMMMMMMD.........',
    '....mMMMMMMMD...........',
    '...mMMMMMMD..HH.........',
    '...mMMMMD...hHH.........',
    '....mMMD...hHHd.........',
    '.....mD...hHHd..........',
    '.........hHHd...........',
    '........hHHd............',
    '.......hHHd.............',
    '......hHHd..............',
    '.....hHHd...............',
    '....hHHd................',
    '...hHHd.................',
    '..hHHd..................',
    '.hHHd...................',
    '.hHd....................',
    'HHd.....................',
]

HATCHET = [
    '..........mmmmMM........',
    '.........mMMMMMMD.......',
    '........mMMMMMMMMD......',
    '.......mMMMMMMMMD.......',
    '........mMMMMD.HH.......',
    '.........mMD..hHH.......',
    '..........D..hHHd.......',
    '............hHHd........',
    '...........hHHd.........',
    '..........hHHd..........',
    '.........hHHd...........',
    '........hHHd............',
    '.......hHHd.............',
    '......hHHd..............',
    '.....hHHd...............',
    '....hHd.................',
    '...HHd..................',
]

AXE = [
    '.........mmmmmmmM.......',
    '........mMMMMMMMMD......',
    '.......mMMMMMMMMMMD.....',
    '......mMMMMMMMMMMD......',
    '......mMMMMMMMD.HH......',
    '.......mMMMMD..hHH......',
    '........mMD...hHHd......',
    '.........D...hHHd.......',
    '............hHHd........',
    '...........hHHd.........',
    '..........hHHd..........',
    '.........hHHd...........',
    '........hHHd............',
    '.......hHHd.............',
    '......hHHd..............',
    '.....hHd................',
    '....HHd.................',
]

SWORD = [
    '...............m........',
    '..............mM........',
    '.............mMMD.......',
    '............mMMMD.......',
    '...........mMMMD........',
    '..........mMMMD.........',
    '.........mMMMD..........',
    '........mMMMD...........',
    '.......mMMMD............',
    '......mMMMD.............',
    '.....hhhhhhh............',
    '....hMMMMMMMh...........',
    '.....hhhhhhh............',
    '......HHHHH.............',
    '......ddddd.............',
]

DAGGER = [
    '...........m............',
    '..........mMD...........',
    '.........mMMD...........',
    '........mMMD............',
    '.......mMMD.............',
    '......mMMD..............',
    '.....mMMD...............',
    '....hhhhhhh.............',
    '...hMMMMMMMh............',
    '....hhhhhhh.............',
    '.....HHHHH..............',
    '.....ddddd..............',
]

BOW = [
    '.....WWW................',
    '....WWWww..s............',
    '...WWWw.....s...........',
    '..WWWw.......s..........',
    '.WWWw........s..........',
    '.WWw.........s..........',
    'WWw..........s..........',
    'WW...........s..........',
    'WWw..........s..........',
    '.WWw.........s..........',
    '.WWWw........s..........',
    '..WWWw.......s..........',
    '...WWWw.....s...........',
    '....WWWww..s............',
    '.....WWWBB..............',
    '......BBBB..............',
]

SHIELD = [
    '....mmmmmmmmm...........',
    '...mMMMMMMMMMm..........',
    '..mMMMMMMMMMMMm.........',
    '.mMMMMMMMMMMMMMD........',
    '.mMMMMMMMMMMMMMD........',
    '.mMMMMMMmmMMMMMD........',
    '.mMMMMMMMMMMMMMD........',
    '.mMMMMMMMMMMMMMD........',
    '..mMMMMMMMMMMMD.........',
    '...mMMMMMMMMMD..........',
    '....mMMMMMMMD...........',
    '.....mMMMMMD............',
    '......mMMMD.............',
    '.......mMD..............',
]

HELMET = [
    '......mmmmmmm...........',
    '.....mMMMMMMMm..........',
    '....mMMMMMMMMMD.........',
    '....mMMMMMMMMMD.........',
    '....mMMDDDDDMMd.........',
    '....mM......MD..........',
    '....mMMMMMMMMD..........',
    '....mMDDDDDDMD..........',
    '.....mMMMMMMD...........',
    '......DDDDDD............',
]

CHEST = [
    '...mmm.......mmm........',
    '..mMMMm.....mMMMD.......',
    '.mMMMMMMMMMMMMMMMD......',
    '.mMMMMMMMMMMMMMMMD......',
    '.mMMMMMMmmMMMMMMMD......',
    '.mMMMMMMMMMMMMMMMD......',
    '..mMMMMMMMMMMMMMD.......',
    '..mMMMMMMMMMMMMMD.......',
    '...mMMMMMMMMMMMD........',
    '....mMMMMMMMMMD.........',
    '.....DDDDDDDDD..........',
]

LEGS = [
    '...mmm....mmm...........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMMD..mMMMD..........',
    '..mMMD...mMMD...........',
    '..DDD....DDD............',
]

BOOTS = [
    '....mmm...mmm...........',
    '...mMMMD.mMMMD..........',
    '...mMMMD.mMMMD..........',
    '..mMMMMDmMMMMD..........',
    '.mMMMMMDmMMMMMD.........',
    'mMMMMMMDmMMMMMMD........',
    'DDDDDDDDDDDDDDD.........',
]

GLOVES = [
    '.....m....m.............',
    '....mM...mM.............',
    '...mMMD.mMMD............',
    '..mMMMMMMMMMD...........',
    '..mMMMMMMMMMD...........',
    '...mMMMMMMMMD...........',
    '....mMMMMMMD............',
    '.....DDDDDD.............',
]

ROD = [
    '...................mm...',
    '..................mMM...',
    '.................mMHH...',
    '................hHH.....',
    '...............hHH......',
    '..............hHH.......',
    '.............hHH........',
    '............hHH.........',
    '...........hHH..........',
    '..........hHH...........',
    '.........hHH............',
    '........hHH.............',
    '.......hHH..............',
    '......hHd...............',
    '.....hHd................',
    '....HHd.................',
    '...dd...................',
]

HARPOON = [
    '..................mmm...',
    '.................mMMD...',
    '................mMMD....',
    '...............mMMD.....',
    '..............mMD.......',
    '.............MHH........',
    '............hHH.........',
    '...........hHH..........',
    '..........hHH...........',
    '.........hHH............',
    '........hHH.............',
    '.......hHH..............',
    '......hHH...............',
    '.....hHd................',
    '....HHd.................',
]

HAMMER = [
    '...mmmmmmmmm............',
    '..mMMMMMMMMMD...........',
    '..mMMMMMMMMMD...........',
    '..mMMMMMMMMMD...........',
    '...mmmmmmmmm............',
    '.......HH...............',
    '.......HH...............',
    '.......HH...............',
    '.......HH...............',
    '.......HH...............',
    '.......Hd...............',
    '.......dd...............',
]

ORE = [
    '......DDDDD.............',
    '.....DMMMMMD............',
    '....DMmmmmMMD...........',
    '...DMMmMMmMMMD..........',
    '..DMMMMMMMMMMD..........',
    '..DMMMMMMMMMMD..........',
    '...DMMMMMMMMD...........',
    '....DMMMMMMD............',
    '.....DDDDDD.............',
]

BAR = [
    '...mmmmmmmmmmmmm........',
    '..mMMMMMMMMMMMMMD.......',
    '..mMMMMMMMMMMMMMD.......',
    '..mMMMMMMMMMMMMMD.......',
    '..mMMMMMMMMMMMMMD.......',
    '...DDDDDDDDDDDDD........',
]

LOG = [
    '......WWWWWW............',
    '.....WWwwwwWWB..........',
    '....WWwwwwwwWWB.........',
    '....WWwwwwwwWWB.........',
    '....WWwwwwwwWWB.........',
    '....WWwwwwwwWWB.........',
    '.....WWWWWWWWB..........',
    '......BBBBBBB...........',
]

TIMBER = [
    '...WWWWWWWWWWWWW........',
    '..WWwwwwwwwwwwwB........',
    '..WWwwwwwwwwwwwB........',
    '...BBBBBBBBBBBBB........',
    '........................',
    '...WWWWWWWWWWWWW........',
    '..WWwwwwwwwwwwwB........',
    '...BBBBBBBBBBBBB........',
]

GEM_STAMP = [
    '.........gg.........',
    '........gGGg........',
    '.......gGGGGg.......',
    '......gGGGGGGg......',
    '.....gGGGGGGGXg.....',
    '....gGGGGGGGGGXg....',
    '...gGGGGGGGGGGGXg...',
    '...GGGGGGGGGGGGXg...',
    '...GGGGGGGGGGGGX....',
    '....GGGGGGGGGGX.....',
    '.....GGGGGGGGX......',
    '......GGGGGGX.......',
    '.......GGGGX........',
    '........XXX.........',
]

CUT_GEM = [
    '......ggggggg.......',
    '.....gGGGGGGGg......',
    '....gGGGGGGGGGX.....',
    '....GGGgGGGGGGX.....',
    '....GGGGGGGGGGX.....',
    '....GGGGGGGGGX......',
    '.....GGGGGGGX.......',
    '......GGGGGX........',
    '.......XXXX.........',
]

RING = [
    '.....MMMMMMMM.....',
    '....MM......MM....',
    '...MM........MM...',
    '...M..........M...',
    '...M..........M...',
    '...MM........MM...',
    '....MM......MM....',
    '.....MMMMMMMM.....',
    '........GG........',
    '.......gGGX.......',
    '........XX........',
]

NECKLACE = [
    'MM...............MM',
    '.MM.............MM.',
    '..MM...........MM..',
    '...MM.........MM...',
    '....MM.......MM....',
    '.....MM.....MM.....',
    '......MM...MM......',
    '.......MMMMM.......',
    '.........GG........',
    '........gGGX.......',
    '.........XX........',
]

POTION = [
    '.......hhh.......',
    '.......HHH.......',
    '......mMMMm......',
    '.....mFFFFFm.....',
    '....mFFFFFFFm....',
    '....mFFFFFFFm....',
    '....mFFFFFFFm....',
    '....mFFFFFFFm....',
    '.....mFFFFFm.....',
    '......mFFFm......',
    '.......mmm.......',
]

COIN = [
    '......mmmmm......',
    '.....mMMMMMm.....',
    '....mMMmmMMMm....',
    '....mMMHHHMMm....',
    '....mMMMMMMMD....',
    '.....mMMMMMD.....',
    '......DDDDD......',
]


def tool_palette(name: str) -> dict[str, tuple[int, int, int]]:
    n = name.lower()
    metal = metal_of(name)
    if metal is None and 'wooden' in n:
        wood = wood_of(name)
        return {**mp(wood), **hp(wood)}
    if metal is None:
        return {**mp(METAL['iron']), **hp(wood_of(name))}
    return {**mp(metal), **hp(HANDLE)}


def tool(c: Canvas, stamp: list[str], name: str) -> None:
    c.stamp_centered(stamp, tool_palette(name))


def wood_body(c: Canvas, stamp: list[str], name: str) -> None:
    c.stamp_centered(stamp, wp(wood_of(name)))


def metal_body(c: Canvas, stamp: list[str], name: str) -> None:
    c.stamp_centered(stamp, mp(metal_of(name) or METAL['iron']))


def gem_body(c: Canvas, stamp: list[str], name: str) -> None:
    c.stamp_centered(stamp, gp(gem_of(name) or GEM['sapphire']))


def paint_fish(c: Canvas, kind: str, cooked: bool) -> None:
    if kind == 'trout':
        body = ((120, 168, 92), (72, 118, 58), (40, 72, 34)) if not cooked else ((196, 140, 72), (148, 92, 40), (92, 56, 22))
        rows = [
            '.................mm.m...',
            '.........mmmmmmmMMD.D...',
            '.......mMMMMMmMMMMDD....',
            '......mM.MMMMMMMMMMD....',
            '.....mMMMMMMMMMMMMD.D...',
            '......mMMMMMMMMMMD......',
            '.......mmmmmmmmm........',
        ]
        c.stamp_centered(rows, {'m': body[0], 'M': body[1], 'D': body[2]})
    elif kind == 'salmon':
        body = ((232, 132, 108), (196, 86, 64), (128, 48, 36)) if not cooked else ((188, 96, 56), (140, 64, 32), (88, 40, 20))
        rows = [
            '..................mm.m..',
            '.........mmmmmmmMMD.D...',
            '.......mMMMMMMMMMMDD....',
            '......mM.MMMMMMMMMMD....',
            '.....mMMMMMMMMMMMMD.D...',
            '......mMMMMMMMMMM.......',
            '.......mmmmmmmm.........',
        ]
        c.stamp_centered(rows, {'m': body[0], 'M': body[1], 'D': body[2]})
    elif kind == 'tuna':
        body = ((86, 128, 168), (48, 86, 124), (28, 48, 78)) if not cooked else ((168, 112, 64), (120, 72, 36), (76, 44, 20))
        rows = [
            '...............mmmm.m...',
            '.......mmmmMMMMMMMD.D...',
            '......mMMMMMMMMMMMMD....',
            '.....mM.MMMMMMMMMMMD....',
            '......mMMMMMMMMMMD.D....',
            '.......mmmmmmmmm........',
        ]
        c.stamp_centered(rows, {'m': body[0], 'M': body[1], 'D': body[2]})
    elif kind == 'shark':
        body = ((176, 184, 192), (120, 128, 136), (72, 78, 86)) if not cooked else ((168, 120, 72), (118, 78, 40), (72, 46, 22))
        rows = [
            '...............m........',
            '.........mmmmmmmMMD.....',
            '......mmMMMMMMMMMMD.....',
            '...mMMMMM.MMMMMMMMDD.m..',
            '.mMMMMMMMMMMMMMMMMD.D...',
            '......mMMMMMMMMMMD......',
            '.......mmmmmmmmm........',
        ]
        c.stamp_centered(rows, {'m': body[0], 'M': body[1], 'D': body[2]})
    else:
        paint_fish(c, 'trout', cooked)


def paint_crawfish(c: Canvas, cooked: bool) -> None:
    pal = ((220, 72, 56), (168, 40, 32), (104, 24, 20)) if cooked else ((196, 86, 64), (140, 52, 40), (88, 32, 24))
    rows = [
        'm.....m.............',
        '.m...m..............',
        '..m.m...............',
        '..MMM...............',
        '.mMMMm..............',
        'mMMMMMm.............',
        '.mMMMm.D............',
        '..MMM.D.............',
        '...DDD..............',
    ]
    c.stamp_centered(rows, {'m': pal[0], 'M': pal[1], 'D': pal[2]})


def paint_squid(c: Canvas, cooked: bool) -> None:
    pal = ((176, 120, 176), (128, 72, 140), (80, 40, 92)) if not cooked else ((168, 100, 72), (120, 64, 40), (76, 40, 24))
    rows = [
        '....mmmm............',
        '...mMMMMm...........',
        '...mMMMMD...........',
        '....MMDD............',
        '...m.m.m............',
        '..m.m.m.m...........',
        '.m.m.m.m.m..........',
    ]
    c.stamp_centered(rows, {'m': pal[0], 'M': pal[1], 'D': pal[2]})


def paint_chef_hat(c: Canvas) -> None:
    white, mid, shade = ((248, 246, 240), (214, 210, 200), (160, 156, 148))
    rows = [
        '.....mmmmmmm........',
        '....mMMMMMMMm.......',
        '...mMMMmmmmMMm......',
        '...mMMMMMMMMMMm.....',
        '...mMMMMMMMMMMD.....',
        '....mMMMMMMMMD......',
        '.....mmmmmmm........',
        '....mMMMMMMMm.......',
        '...mMMMMMMMMMD......',
        '...DDDDDDDDDD.......',
    ]
    c.stamp_centered(rows, {'m': white, 'M': mid, 'D': shade})


def paint_battle_staff(c: Canvas, gem: tuple[int, int, int], gem_shade: tuple[int, int, int]) -> None:
    c.stamp_centered(
        [
            '...ggg...',
            '..gGGGg..',
            '.gGGGGGg.',
            '..gGGGg..',
            '...HHH...',
            '...HHH...',
            '...HHH...',
            '...HHH...',
            '...HHH...',
            '...HHH...',
            '...HHH...',
            '...ddd...',
        ],
        {'g': gem, 'G': gem_shade, 'H': HANDLE[1], 'd': HANDLE[2]},
    )


def paint_wizard_hat(c: Canvas) -> None:
    cloth = ((92, 64, 168), (58, 36, 120), (32, 20, 72))
    rows = [
        '.........m..........',
        '........mM..........',
        '.......mMMD.........',
        '......mMMMMD........',
        '.....mMMMMMMD.......',
        '....mMMMMMMMMD......',
        '...mmmmmmmmmmm......',
        '..mMMMMMMMMMMMD.....',
        '..DDDDDDDDDDDD......',
    ]
    c.stamp_centered(rows, {'m': cloth[0], 'M': cloth[1], 'D': cloth[2]})
    c.put(16, 14, GEM['sapphire'][0])


def paint_bull_helm(c: Canvas) -> None:
    metal = METAL['iron']
    horn = BONE
    c.stamp_centered(HELMET, mp(metal))
    c.stamp(4, 8, ['mmD.', 'MD..', 'D...'], {'m': horn[0], 'M': horn[1], 'D': horn[2]})
    c.stamp(22, 8, ['.Dmm', '..DM', '...D'], {'m': horn[0], 'M': horn[1], 'D': horn[2]})


def paint_backpack(c: Canvas) -> None:
    rows = [
        '...s.....s..........',
        '..sMMMMMMMs.........',
        '.sMMMMMMMMMs........',
        '.sMMMmmmmMMMs.......',
        '.sMMMMMMMMMMs.......',
        '.sMMMMMMMMMMs.......',
        '..sMMMMMMMMs........',
        '...ssssssss.........',
    ]
    c.stamp_centered(rows, {'s': CLOTH[0], 'M': LEATHER[1], 'm': LEATHER[0]})


def paint_potion(c: Canvas, name: str) -> None:
    n = name.lower()
    if 'poison' in n:
        liquid = ((96, 196, 64), (48, 132, 36), (24, 78, 20))
    elif 'speed' in n:
        liquid = ((80, 210, 230), (32, 150, 186), (16, 86, 120))
    elif 'strength' in n:
        liquid = ((220, 64, 64), (168, 28, 32), (100, 16, 18))
    elif 'luck' in n:
        liquid = ((196, 96, 220), (140, 48, 176), (84, 24, 112))
    elif 'masterwork' in n or 'draught' in n:
        liquid = METAL['gold']
    else:
        liquid = GEM['sapphire']
    glass = METAL['silver']
    pal = {'h': HANDLE[0], 'H': HANDLE[1], 'm': glass[0], 'M': glass[1], 'F': liquid[1], 'f': liquid[0]}
    if 'minor' in n:
        pal['F'] = liquid[2]
    c.stamp_centered(POTION, pal)


def paint_bowl(c: Canvas, stew: str) -> None:
    bowl = ((168, 112, 64), (120, 72, 36), (76, 44, 20))
    fill = ((176, 92, 48), (128, 60, 28), (84, 36, 16))
    if 'pheasant' in stew:
        fill = ((180, 100, 48), (140, 68, 28), (88, 40, 16))
    rows = [
        '....ffffff..........',
        '...fFFFFFFFf........',
        '..mFFFFFFFFFFm......',
        '.mMMMMMMMMMMMMD.....',
        '..mMMMMMMMMMMD......',
        '...DDDDDDDDDD.......',
    ]
    c.stamp_centered(rows, {'f': fill[0], 'F': fill[1], 'm': bowl[0], 'M': bowl[1], 'D': bowl[2]})


def paint_meat(c: Canvas, name: str) -> None:
    n = name.lower()
    cooked = 'cooked' in n
    if 'rabbit' in n:
        pal = ((220, 176, 156), (176, 120, 100), (120, 72, 58)) if not cooked else ((188, 112, 64), (140, 72, 36), (88, 44, 20))
    elif 'pheasant' in n:
        pal = ((196, 140, 88), (148, 92, 48), (96, 56, 28))
    elif 'duck' in n:
        pal = ((196, 120, 72), (148, 80, 40), (96, 48, 24))
    elif 'boar' in n:
        pal = ((168, 96, 72), (120, 64, 44), (76, 40, 26))
    elif 'beef' in n:
        pal = ((168, 56, 48), (124, 36, 32), (80, 20, 18)) if not cooked else ((140, 72, 36), (100, 48, 20), (64, 28, 12))
    elif 'venison' in n:
        pal = ((148, 72, 48), (108, 48, 32), (68, 28, 18))
    else:
        pal = ((176, 96, 64), (128, 64, 40), (80, 40, 22))
    rows = [
        '...mmm..............',
        '..mMMMm.............',
        '.mMMMMMD............',
        'mMMMMMMD............',
        '.mMMMMD.............',
        '..mMMD..............',
        '...DD...............',
    ]
    c.stamp_centered(rows, {'m': pal[0], 'M': pal[1], 'D': pal[2]})


def paint_plant(c: Canvas, name: str) -> None:
    n = name.lower()
    if 'berry' in n or 'berrie' in n:
        leaf = ((72, 140, 56), (40, 96, 36))
        berry = ((168, 36, 64), (120, 20, 44), (220, 72, 96))
        c.stamp_centered(
            [
                '.....ggg............',
                '....gGGGg...........',
                '...gGGGGGg..........',
                '....gGGGg...........',
                '...rr.rr.rr.........',
                '..rRRrRRrRR.........',
                '.rRRRrRRRrR.........',
                '..rr.rr.rr..........',
            ],
            {'g': leaf[0], 'G': leaf[1], 'r': berry[0], 'R': berry[2]},
        )
        return
    if 'grape' in n:
        grape = ((128, 64, 160), (88, 36, 120), (176, 108, 196))
        c.stamp_centered(
            [
                '.......g............',
                '......gGg...........',
                '.....gGGGg..........',
                '....gGGGGGg.........',
                '...gGGGGGGGg........',
                '....GGGGGGG.........',
                '.....GGGGG..........',
                '......GGG...........',
            ],
            {'g': grape[2], 'G': grape[0]},
        )
        return
    if 'carrot' in n:
        c.stamp_centered(
            [
                '.....g.g.g..........',
                '....g.gGg.g.........',
                '......gGg...........',
                '.......mm...........',
                '.......MM...........',
                '.......MM...........',
                '.......DD...........',
                '.......DD...........',
                '........D...........',
            ],
            {'g': (72, 148, 52), 'G': (40, 100, 32), 'm': (240, 140, 48), 'M': (216, 108, 28), 'D': (160, 72, 16)},
        )
        return
    if 'potato' in n or 'spud' in n:
        pal = METAL['gold'] if 'gold' in n else ((196, 156, 88), (156, 116, 56), (108, 76, 32))
        if 'baked' in n:
            pal = ((164, 112, 56), (124, 80, 36), (80, 48, 20))
        c.stamp_centered(
            ['...mmm...', '..mMMMm..', '.mMMMMMD.', 'mMMMMMMD.', '.mMMMMD..', '..mMMD...', '...DD....'],
            {'m': pal[0], 'M': pal[1], 'D': pal[2]},
        )
        return
    if 'fern' in n:
        green = ((72, 160, 72), (36, 112, 48), (20, 68, 28))
        c.stamp_centered(
            [
                '....g.g.g...........',
                '...gGgGg............',
                '..g.gGg.g...........',
                '.g...G...g..........',
                '.....GG.............',
                '.....DD.............',
                '.....DD.............',
            ],
            {'g': green[0], 'G': green[1], 'D': green[2]},
        )
        return
    if 'moss' in n:
        green = ((88, 140, 72), (52, 100, 48), (28, 64, 32))
        c.stamp_centered(
            [
                '..g.gg.gg...........',
                '.gGGgGGgGG..........',
                'gGGGGGGGGGG.........',
                '.GGGGGGGGG..........',
                '..GGG.GGG...........',
            ],
            {'g': green[0], 'G': green[1]},
        )
        return
    if 'augur' in n or 'weed' in n or n in {'herb 1', 'herb 2'}:
        green = ((64, 140, 88), (36, 100, 60), (20, 64, 36)) if '1' in n else ((96, 156, 64), (56, 108, 40), (32, 68, 24))
        extra = 'gGg' if '2' in n else 'g.g'
        c.stamp_centered(
            [
                f'....g.{extra}...........',
                '....gGgGg...........',
                '...g.GGG.g..........',
                '..g...G...g.........',
                '......GG............',
                '......DD............',
                '......DD............',
            ],
            {'g': green[0], 'G': green[1], 'D': green[2]},
        )
        return
    if 'moonblossom' in n:
        c.stamp_centered(
            [
                '.....g.g.g..........',
                '....gGgGgGg.........',
                '.....gGGGg..........',
                '......gGg...........',
                '.......D............',
                '.......D............',
                '.......D............',
            ],
            {'g': (180, 220, 255), 'G': (120, 180, 230), 'D': (72, 120, 88)},
        )
        return
    if 'starroot' in n:
        c.stamp_centered(
            [
                '.....m.m............',
                '....mMmMm...........',
                '...mMMMMMm..........',
                '....mMMMm...........',
                '.....MMM............',
                '......D.............',
                '......D.............',
                '......D.............',
            ],
            {'m': (240, 220, 96), 'M': (212, 176, 40), 'D': (140, 100, 28)},
        )
        return
    if 'root' in n:
        c.stamp_centered(
            [
                '.d..d..d............',
                'dHd.HdHd............',
                '.HHdHHH.............',
                '..HHHH..............',
                '...HH...............',
                '...H................',
            ],
            {'d': HANDLE[2], 'H': HANDLE[1]},
        )
        return
    paint_plant(c, 'herb 1')


def paint_hide(c: Canvas, name: str) -> None:
    n = name.lower()
    if 'goat' in n:
        pal = ((216, 204, 180), (176, 160, 132), (120, 108, 84))
    elif 'stag' in n:
        pal = ((156, 112, 72), (112, 76, 44), (72, 48, 28))
    elif 'moonhorn' in n:
        pal = ((196, 208, 220), (140, 156, 176), (84, 96, 116))
    elif 'boar' in n:
        pal = ((132, 96, 72), (96, 64, 44), (60, 40, 28))
    else:
        pal = LEATHER
    c.stamp_centered(
        ['...mmm...', '..mMMMm..', '.mMMMMMD.', 'mMMMMMMD.', '.mMMMMD..', '..DDD....'],
        {'m': pal[0], 'M': pal[1], 'D': pal[2]},
    )


def paint_horn(c: Canvas, name: str) -> None:
    pal = BONE
    if 'elk' in name.lower() or 'antler' in name.lower():
        c.stamp_centered(
            [
                'mm.....mm...........',
                'MMm...mMM...........',
                '.MMm.mMM............',
                '..MMMMM.............',
                '...MMM..............',
                '...MM...............',
                '...DD...............',
            ],
            {'m': pal[0], 'M': pal[1], 'D': pal[2]},
        )
        return
    if 'moonhorn' in name.lower():
        pal = ((210, 226, 236), (160, 184, 204), (96, 120, 144))
    c.stamp_centered(
        [
            'mm.....mm...........',
            'MMm...mMM...........',
            '.MMD.DMM............',
            '..MD.DM.............',
            '...D.D..............',
            '....D...............',
        ],
        {'m': pal[0], 'M': pal[1], 'D': pal[2]},
    )


def paint_book(c: Canvas) -> None:
    cover = ((92, 48, 140), (64, 28, 100), (40, 16, 64))
    page = CLOTH
    c.stamp_centered(
        ['mmmmmmmm', 'mFFFFFFm', 'mFFFFFFm', 'mFFFFFFm', 'mFFFFFFm', 'mFFFFFFm', 'DDDDDDDD'],
        {'m': cover[0], 'F': page[0], 'D': cover[2]},
    )


def paint_spell(c: Canvas, name: str) -> None:
    if 'abundance' in name.lower():
        rune = ((96, 220, 120), (40, 160, 72), (16, 96, 40))
    else:
        rune = ((232, 80, 80), (180, 32, 36), (112, 16, 18))
    c.stamp_centered(
        ['..mmmmm..', '.mMMMMMm.', 'mMMgggMMm', 'mMMGGGMMD', '.mMMMMMD.', '..mmmmm..'],
        {'m': (236, 220, 160), 'M': (196, 168, 88), 'g': rune[0], 'G': rune[1], 'D': (156, 128, 64)},
    )


def paint_tablet(c: Canvas, name: str) -> None:
    stone = ((140, 132, 160), (96, 88, 120), (60, 52, 80)) if 'enchant' in name.lower() else ((168, 156, 132), (124, 112, 88), (80, 70, 52))
    c.stamp_centered(
        ['mmmmmmm', 'mMMMMMm', 'mMgggMm', 'mMMMMMm', 'mMgggMm', 'mMMMMMm', 'DDDDDDD'],
        {'m': stone[0], 'M': stone[1], 'D': stone[2], 'g': GEM['sapphire'][1]},
    )


def paint_component(c: Canvas, name: str) -> None:
    n = name.lower()
    if 'bowstring' in n:
        c.stamp_centered(['s'] * 20, {'s': (220, 214, 196)})
        c.put(14, 6, (180, 170, 150))
        c.put(14, 25, (180, 170, 150))
        return
    if 'strap' in n or 'grip' in n:
        c.stamp_centered(['LLLLLLLL', 'LllllllL', 'LllllllL', 'LLLLLLLL'], {'L': LEATHER[1], 'l': LEATHER[0]})
        return
    if 'chain' in n:
        metal = METAL['steel']
        rows = [
            'm.m.m.m.m.m.m',
            'MmMmMmMmMmMmM',
            'D.D.D.D.D.D.D',
        ]
        c.stamp_centered(rows, {'m': metal[0], 'M': metal[1], 'D': metal[2]})
        return
    if 'clasp' in n or 'setting' in n:
        metal_body(c, ['mmmmm', 'mMMMm', 'mMMMm', 'mMMMm', 'DDDDD'], name if metal_of(name) else 'gold')
        if 'setting' in n:
            c.put(16, 16, GEM['sapphire'][1])
        return
    if 'cloth' in n or 'wrap' in n or 'grave' in n:
        pal = CLOTH if 'grave' not in n else ((96, 92, 108), (64, 60, 76), (40, 36, 48))
        c.stamp_centered(
            ['mmmmmmm.', '.mMMMMMm', '..mMMMMMm', '...mMMMMm', '....mMMD.'],
            {'m': pal[0], 'M': pal[1], 'D': pal[2]},
        )
        return
    if 'fiber' in n or n.startswith('plant'):
        c.stamp_centered(
            [
                'g..g..g..',
                '.g.g.g.g.',
                '..gGgGg..',
                '...GGG...',
                '...GGG...',
                '...DDD...',
                '...DDD...',
            ],
            {'g': (120, 176, 72), 'G': (72, 128, 44), 'D': (44, 84, 28)},
        )
        return
    if 'spear' in n:
        tool(c, HARPOON, 'steel spear')
        return
    if 'shaft' in n:
        wood_body(c, ['WWW', 'WWW', 'WWW', 'WWW', 'WWW', 'WWW', 'WWW', 'WWW', 'WWW', 'BBB'], name)
        return
    if 'binding' in n:
        c.stamp_centered(
            ['WWWWWWWWWW', 'wwwwwwwwww', 'BBBBBBBBBB'],
            {'W': WOOD['ancient'][0], 'w': WOOD['ancient'][1], 'B': WOOD['ancient'][2]},
        )
        return
    if 'leather' in n:
        paint_hide(c, 'leather')
        return
    metal_body(c, BAR, name or 'iron')


def paint_unique(c: Canvas, name: str) -> bool:
    n = name.lower()
    if 'chef' in n and 'hat' in n:
        paint_chef_hat(c)
        return True
    if 'wizard' in n and 'hat' in n:
        paint_wizard_hat(c)
        return True
    if 'wizard' in n and 'tome' in n:
        paint_book(c)
        return True
    if 'bull horn helmet' in n:
        paint_bull_helm(c)
        return True
    if 'backpack' in n or "explorer" in n:
        paint_backpack(c)
        return True
    if 'beggar' in n and 'hood' in n:
        c.stamp_centered(
            ['..mmmmmm..', '.mMMMMMMm.', 'mMMMMMMMMm', 'mMM....MMm', 'mMMMMMMMMm', '.mMMMMMMm.', '..mmmmmm..'],
            {'m': (120, 96, 64), 'M': (86, 66, 42)},
        )
        return True
    if 'traveler' in n and 'tunic' in n:
        c.stamp_centered(CHEST, mp(((196, 156, 92), (148, 108, 56), (96, 68, 32))))
        return True
    if 'undying' in n:
        c.stamp_centered(
            ['...mmm...', '..mMMMm..', '.mMoooMm.', 'mMMMMMMD.', '.mMMMMD..', '..mMMD...', '...DD....'],
            {'m': (230, 236, 240), 'M': (186, 196, 204), 'D': (120, 128, 140), 'o': (40, 48, 56)},
        )
        return True
    if 'purse' in n:
        paint_backpack(c)
        c.stamp(11, 18, COIN[1:5], mp(METAL['gold']))
        return True
    if 'old boots' in n:
        c.stamp_centered(BOOTS, mp(LEATHER))
        return True
    if 'falconer' in n:
        c.stamp_centered(GLOVES, mp(LEATHER))
        c.put(22, 10, (196, 148, 72))
        c.put(23, 9, (168, 112, 56))
        return True
    if "mage's wand" in n or 'mages wand' in n:
        c.stamp_centered(
            [
                '...ggg...',
                '..gGGGg..',
                '.gGGGGGg.',
                '..gGGGg..',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...ddd...',
            ],
            {'g': GEM['emerald'][0], 'G': GEM['emerald'][2], 'H': WOOD['maple'][1], 'd': WOOD['maple'][2]},
        )
        return True
    if 'staff of sparks' in n:
        paint_battle_staff(c, (88, 176, 255), (40, 96, 196))
        return True
    if 'staff of binding' in n:
        paint_battle_staff(c, (92, 176, 88), (40, 96, 48))
        return True
    if 'staff of power' in n:
        paint_battle_staff(c, (220, 176, 72), (148, 72, 24))
        return True
    if 'goblin staff' in n:
        c.stamp_centered(
            [
                '...ggg...',
                '..gGGGg..',
                '.gGGGGGg.',
                '..gGGGg..',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...HHH...',
                '...ddd...',
            ],
            {'g': (120, 196, 72), 'G': (64, 132, 40), 'H': HANDLE[1], 'd': HANDLE[2]},
        )
        return True
    if 'boar spear' in n:
        tool(c, HARPOON, 'steel')
        return True
    if 'battleaxe' in n:
        tool(c, AXE, name)
        return True
    if 'warhammer' in n:
        tool(c, HAMMER, 'gold' if 'dwarven' in n else 'steel')
        return True
    if 'enchanted sword' in n:
        tool(c, SWORD, 'steel')
        c.put(20, 8, GEM['sapphire'][0])
        c.put(19, 9, (180, 120, 220))
        return True
    if 'aether' in n:
        metal_body(c, CHEST, 'aether')
        return True
    if 'leather gloves' in n:
        c.stamp_centered(GLOVES, mp(LEATHER))
        return True
    if 'lucky necklace' in n:
        c.stamp_centered(
            NECKLACE,
            {**mp(METAL['gold']), 'G': METAL['gold'][0], 'g': METAL['gold'][0], 'X': METAL['gold'][2]},
        )
        return True
    if 'pirate' in n or 'insignia' in n:
        c.stamp_centered(
            ['...m...', '..mMm..', '.mMMMm.', 'mMMMMMD', '.mMDMm.', '..mDm..', '...D...'],
            {'m': (220, 64, 64), 'M': (160, 28, 32), 'D': (96, 16, 18)},
        )
        return True
    if 'dragon scale' in n:
        c.stamp_centered(
            ['...m...', '..mMm..', '.mMMMm.', 'mMMMMMD', '.mMMMD.', '..mMD..', '...D...'],
            {'m': (72, 196, 92), 'M': (32, 140, 56), 'D': (16, 80, 32)},
        )
        return True
    if 'essence' in n:
        pal = ((196, 140, 230), (140, 72, 196), (84, 36, 128)) if 'shade' not in n else ((120, 96, 160), (72, 48, 112), (40, 24, 68))
        c.stamp_centered(
            ['...m...', '..mMm..', '.mMMMm.', 'mMMMMMm', '.mMMMD.', '..mMD..', '...D...', '...m...'],
            {'m': pal[0], 'M': pal[1], 'D': pal[2]},
        )
        return True
    if n == 'coal':
        c.stamp_centered(ORE, mp(((72, 72, 76), (44, 44, 48), (24, 24, 28))))
        return True
    if n == 'clay':
        c.stamp_centered(
            ['..mmmmm..', '.mMMMMMm.', 'mMMMMMMMD', '.mMMMMMD.', '..DDDDD..'],
            mp(((196, 140, 100), (156, 100, 64), (108, 68, 40))),
        )
        return True
    if n == 'gold':
        c.stamp_centered(COIN, mp(METAL['gold']))
        return True
    if 'rabbit' in n and 'foot' in n:
        c.stamp_centered(
            [
                '...mm.',
                '..mMM.',
                '..MMD.',
                '..MDD.',
                '..Dmmm',
                '..mmmm',
                '...mm.',
            ],
            {'m': (232, 220, 208), 'M': (200, 176, 156), 'D': (148, 120, 100)},
        )
        return True
    if 'feather' in n:
        c.stamp_centered(
            [
                '....mm',
                '...mMM',
                '..mMMD',
                '.mMMD.',
                'mMMD..',
                '.MMD..',
                '..MD..',
                '...D..',
            ],
            {'m': (220, 160, 64), 'M': (176, 96, 40), 'D': (120, 60, 24)},
        )
        return True
    if 'butterfly' in n:
        c.stamp_centered(
            ['mmm.mmm', 'mMgggMm', 'mMMMMMm', '.mMMMm.', '..mMm..', '...M...'],
            {'m': (220, 120, 200), 'M': (160, 64, 160), 'g': (240, 200, 80)},
        )
        return True
    if 'tusk' in n or 'tooth' in n or 'bone' in n:
        c.stamp_centered(
            [
                '....mm.',
                '...mMM.',
                '..mMMD.',
                '.mMMD..',
                'mMMD...',
                '.MMD...',
                '..MD...',
                '...D...',
            ],
            {'m': BONE[0], 'M': BONE[1], 'D': BONE[2]},
        )
        return True
    if 'tendon' in n:
        c.stamp_centered(['mmmmmmmmmm', 'MMMMMMMMMM', 'mmmmmmmmmm'], {'m': (220, 188, 160), 'M': (176, 136, 104)})
        return True
    # Whole-word sap only — never "sapphire".
    if n.endswith(' sap') or n in {'sap', 'ancient sap', 'corrupted sap'}:
        pal = ((180, 220, 72), (120, 160, 40), (72, 96, 20)) if 'corrupt' not in n else ((160, 64, 160), (112, 32, 120), (68, 16, 80))
        c.stamp_centered(
            ['...m...', '..mMm..', '.mMMMm.', 'mMMMMMm', '.mMMMD.', '..mMD..', '...D...'],
            {'m': pal[0], 'M': pal[1], 'D': pal[2]},
        )
        return True
    if 'bark' in n or 'heartwood' in n:
        w = WOOD['ancient'] if 'corrupt' not in n else ((96, 48, 88), (64, 28, 60), (40, 16, 36))
        c.stamp_centered(LOG, {'W': w[1], 'w': w[0], 'B': w[2]})
        return True
    return False


def compose_item(name: str) -> Image.Image:
    c = Canvas()
    n = name.lower()

    if paint_unique(c, name):
        return c.image()

    if 'crawfish' in n:
        paint_crawfish(c, 'cooked' in n)
        return c.image()
    if 'squid' in n:
        paint_squid(c, 'cooked' in n)
        return c.image()
    for kind in ('trout', 'salmon', 'tuna', 'shark'):
        if kind in n:
            paint_fish(c, kind, 'cooked' in n)
            return c.image()

    if 'stew' in n:
        paint_bowl(c, n)
        return c.image()
    if any(w in n for w in ('berry', 'berrie', 'grape', 'carrot', 'potato', 'spud', 'fern', 'moss', 'weed', 'herb', 'blossom', 'starroot', 'root')):
        paint_plant(c, name)
        return c.image()
    if any(w in n for w in ('hide', 'leather')) and 'glove' not in n and 'strap' not in n and 'grip' not in n:
        paint_hide(c, name)
        return c.image()
    if any(w in n for w in ('horn', 'antler')):
        paint_horn(c, name)
        return c.image()
    if any(w in n for w in ('meat', 'beef', 'venison', 'rabbit', 'pheasant', 'duck', 'boar')) and 'spear' not in n:
        paint_meat(c, name)
        return c.image()

    if 'potion' in n or 'draught' in n or 'vial' in n:
        paint_potion(c, name)
        return c.image()
    if 'spell' in n and 'tablet' not in n:
        paint_spell(c, name)
        return c.image()
    if 'tablet' in n:
        paint_tablet(c, name)
        return c.image()

    if 'pickaxe' in n:
        tool(c, PICKAXE, name)
        return c.image()
    if 'hatchet' in n:
        tool(c, HATCHET, name)
        return c.image()
    if 'battleaxe' in n or (n.endswith('axe') and 'pick' not in n):
        tool(c, AXE, name)
        return c.image()
    if 'sword' in n:
        tool(c, SWORD, name)
        return c.image()
    if 'dagger' in n:
        tool(c, DAGGER, name)
        return c.image()
    if n.endswith('bow') or ' bow' in n:
        wood_body(c, BOW, name)
        return c.image()
    if 'shield' in n:
        if 'wooden' in n:
            c.stamp_centered(SHIELD, mp(wood_of(name)))
        else:
            metal_body(c, SHIELD, name)
        return c.image()
    if 'plateleg' in n or n.endswith('legs'):
        metal_body(c, LEGS, name)
        return c.image()
    if 'chest' in n or 'tunic' in n:
        metal_body(c, CHEST, name)
        return c.image()
    if 'helmet' in n:
        metal_body(c, HELMET, name)
        return c.image()
    if 'boot' in n:
        metal_body(c, BOOTS, name)
        return c.image()
    if 'glove' in n:
        metal_body(c, GLOVES, name)
        return c.image()
    if 'fishing rod' in n or n.endswith('rod'):
        tool(c, ROD, name)
        return c.image()
    if 'harpoon' in n:
        tool(c, HARPOON, name)
        return c.image()
    if 'net' in n or n == 'sling':
        c.stamp_centered(
            ['s.s.s.s.s', '.s.s.s.s.', 's.s.s.s.s', '.s.s.s.s.', 's.s.s.s.s', '.s.s.s.s.', 's.s.s.s.s'],
            {'s': (196, 188, 168)},
        )
        if n == 'sling':
            c.stamp(13, 22, ['HHHH', 'dddd'], {'H': LEATHER[1], 'd': LEATHER[2]})
        return c.image()
    if 'hammer' in n:
        tool(c, HAMMER, name)
        return c.image()
    if 'necklace' in n:
        metal = metal_of(name) or METAL['silver']
        gem = gem_of(name)
        pal = {**mp(metal), 'G': (gem or metal)[1], 'g': (gem or metal)[0], 'X': (gem or metal)[2]}
        c.stamp_centered(NECKLACE, pal)
        return c.image()
    if n.endswith('ring') or ' ring' in n:
        metal = metal_of(name) or METAL['silver']
        gem = gem_of(name)
        pal = {**mp(metal), 'G': (gem or metal)[1], 'g': (gem or metal)[0], 'X': (gem or metal)[2]}
        c.stamp_centered(RING, pal)
        return c.image()
    if n.startswith('cut ') and gem_of(name):
        gem_body(c, CUT_GEM, name)
        return c.image()
    if gem_of(name) and 'ore' not in n:
        gem_body(c, GEM_STAMP, name)
        return c.image()
    if ' ore' in n or n.endswith('ore'):
        metal_body(c, ORE, name)
        return c.image()
    if n.endswith(' bar') or n.endswith('alloy') or ' bar' in n:
        metal_body(c, BAR, name)
        return c.image()
    if 'timber' in n:
        wood_body(c, TIMBER, name)
        return c.image()
    if n.endswith(' log') or n.endswith('log'):
        wood_body(c, LOG, name)
        return c.image()
    if any(w in n for w in ('component', 'strap', 'string', 'chain', 'clasp', 'wrap', 'fiber', 'shaft', 'grip', 'binding', 'setting', 'head', 'cloth', 'grave')):
        paint_component(c, name)
        return c.image()
    if n == 'gold':
        c.stamp_centered(COIN, mp(METAL['gold']))
        return c.image()

    paint_backpack(c)
    return c.image()


def paint_item(name: str) -> Image.Image:
    return fit_to_square(compose_item(name))


FAMILY_DEFAULTS = {
    'pickaxe': 'Copper Pickaxe',
    'hatchet': 'Copper Hatchet',
    'axe': 'Copper Axe',
    'sword': 'Iron Sword',
    'dagger': 'Iron Dagger',
    'bow': 'Regular Bow',
    'shield': 'Iron Shield',
    'helmet': 'Iron Helmet',
    'chest': 'Iron Chestplate',
    'legs': 'Iron Platelegs',
    'boots': 'Iron Boots',
    'gloves': 'Iron Gloves',
    'ore': 'Iron Ore',
    'bar': 'Iron Bar',
    'log': 'Oak Log',
    'timber': 'Oak Timber',
    'gem': 'Sapphire',
    'potion': 'Luck Potion',
    'default': 'Curiosity',
}


def main() -> None:
    db = json.loads(DATABASE.read_text())
    items = db['Items']
    written = 0
    for item in items:
        name = item.get('Display Name') or item.get('Internal Key') or 'Item'
        stem = item['Internal Key']
        dest = ICONS / f'item_{stem}.webp'
        paint_item(name).save(dest, 'WEBP', lossless=True)
        if item.get('Icon Asset Key') != stem:
            item['Icon Asset Key'] = stem
        written += 1

    if any(item.get('Icon Asset Key') != item['Internal Key'] for item in items):
        DATABASE.write_text(json.dumps(db, indent=2) + '\n')

    for stem, sample in FAMILY_DEFAULTS.items():
        paint_item(sample).save(ICONS / f'item_{stem}.webp', 'WEBP', lossless=True)
    aliases = {
        'gold': 'Gold',
        'coal': 'Coal',
        'essence': 'Essence',
        'potato': 'Potato',
        'baked_potato': 'Baked Potato',
        'berries': 'Wild berries',
        'fishing_tool': 'Wooden Fishing Rod',
        'net': 'Net',
        'hammer': 'Warhammer',
        'backpack': "Explorer's Backpack",
        'insignia': 'Pirate Insignia',
        'spell': 'Strength Spell',
        'necklace': 'Silver Necklace',
        'ring': 'Silver Ring',
        'component': 'Cloth Wrap',
        'creature': 'Leather',
        'herb': 'Herb 1',
        'food': 'Baked Potato',
        'raw_food': 'Raw Trout',
        'dragon_scale': 'Dragon Scale',
        'copper_pickaxe': 'Copper Pickaxe',
        'steel_pickaxe': 'Steel Pickaxe',
        'cosmetic_outfit_travelers_tunic': "Traveler's Tunic",
        'cosmetic_the_undying': 'The Undying',
    }
    for stem, sample in aliases.items():
        paint_item(sample).save(ICONS / f'item_{stem}.webp', 'WEBP', lossless=True)

    print(f'painted {written} item icons from display names')


if __name__ == '__main__':
    main()
