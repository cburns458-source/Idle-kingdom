#!/usr/bin/env python3
"""Give every item its own 32x32 WebP by recoloring the family silhouette.

Stems are Internal Key. Existing family files are left in place as fallbacks
and as bases; new files are written next to them. Run from the repo root.
"""

from __future__ import annotations

import colorsys
import json
import re
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'content/assets/icons/items'
DATABASE = ROOT / 'content/data/game-database.json'

PINNED = {
    'ITEM-0001': 'gold',
    'ITEM-0006': 'coal',
    'ITEM-0011': 'essence',
    'ITEM-0025': 'potato',
    'ITEM-0026': 'potato',
    'ITEM-0028': 'berries',
    'ITEM-0046': 'dragon_scale',
    'ITEM-0058': 'baked_potato',
    'ITEM-0103': 'fishing_tool',
    'ITEM-0108': 'net',
    'ITEM-0111': 'copper_pickaxe',
    'ITEM-0119': 'steel_pickaxe',
    'ITEM-0123': 'hammer',
    'ITEM-0169': 'backpack',
    'ITEM-0288': 'insignia',
    'ITEM-0295': 'spell',
    'ITEM-0296': 'cosmetic_outfit_travelers_tunic',
}

# Longest match first against "internal_key display_name".
# h is target hue (0-360). sat/val multiply the existing HSV.
MATERIALS: list[tuple[str, dict[str, float]]] = [
    ('reinforced steel', {'h': 218, 'sat': 0.55, 'val': 0.88}),
    ('ancient alloy', {'h': 88, 'sat': 0.7, 'val': 0.82}),
    ('plant-fiber', {'h': 95, 'sat': 0.75, 'val': 0.9}),
    ('plant_fiber', {'h': 95, 'sat': 0.75, 'val': 0.9}),
    ('moonhorn', {'h': 195, 'sat': 0.55, 'val': 0.95}),
    ('moonblossom', {'h': 210, 'sat': 0.7, 'val': 1.05}),
    ('starroot', {'h': 52, 'sat': 0.85, 'val': 1.05}),
    ('moonstone', {'h': 200, 'sat': 0.4, 'val': 1.1}),
    ('tungsten', {'h': 268, 'sat': 0.4, 'val': 0.58}),
    ('titanium', {'h': 196, 'sat': 0.22, 'val': 1.08}),
    ('mahogany', {'h': 8, 'sat': 0.8, 'val': 0.72}),
    ('poplar', {'h': 52, 'sat': 0.35, 'val': 1.08}),
    ('ancient', {'h': 92, 'sat': 0.45, 'val': 0.78}),
    ('corrupted', {'h': 308, 'sat': 0.7, 'val': 0.7}),
    ('bronze', {'h': 32, 'sat': 0.95, 'val': 0.9}),
    ('copper', {'h': 22, 'sat': 1.05, 'val': 0.95}),
    ('steel', {'h': 210, 'sat': 0.18, 'val': 1.02}),
    ('iron', {'h': 20, 'sat': 0.08, 'val': 0.68}),
    ('silver', {'h': 210, 'sat': 0.06, 'val': 1.12}),
    ('golden', {'h': 48, 'sat': 1.08, 'val': 1.06}),
    ('gold', {'h': 48, 'sat': 1.08, 'val': 1.06}),
    ('tin', {'h': 56, 'sat': 0.12, 'val': 1.06}),
    ('wooden', {'h': 32, 'sat': 0.72, 'val': 0.86}),
    ('cedar', {'h': 14, 'sat': 0.78, 'val': 0.86}),
    ('maple', {'h': 34, 'sat': 0.82, 'val': 0.92}),
    ('oak', {'h': 30, 'sat': 0.55, 'val': 0.82}),
    ('sapphire', {'h': 220, 'sat': 1.05, 'val': 1.0}),
    ('emerald', {'h': 132, 'sat': 1.05, 'val': 0.95}),
    ('ruby', {'h': 0, 'sat': 1.1, 'val': 0.95}),
    ('aether', {'h': 255, 'sat': 0.7, 'val': 1.05}),
    ('shade', {'h': 272, 'sat': 0.55, 'val': 0.55}),
    ('bone', {'h': 42, 'sat': 0.25, 'val': 1.08}),
    ('grave', {'h': 240, 'sat': 0.15, 'val': 0.55}),
    ('pirate', {'h': 15, 'sat': 0.7, 'val': 0.75}),
    ('leather', {'h': 24, 'sat': 0.65, 'val': 0.72}),
    ('luck', {'h': 285, 'sat': 0.9, 'val': 1.0}),
    ('speed', {'h': 188, 'sat': 0.95, 'val': 1.05}),
    ('strength', {'h': 6, 'sat': 1.05, 'val': 0.95}),
    ('poison', {'h': 118, 'sat': 1.0, 'val': 0.85}),
    ('masterwork', {'h': 46, 'sat': 1.1, 'val': 1.08}),
    ('trout', {'h': 145, 'sat': 0.45, 'val': 0.9}),
    ('salmon', {'h': 12, 'sat': 0.7, 'val': 0.9}),
    ('tuna', {'h': 210, 'sat': 0.35, 'val': 0.85}),
    ('shark', {'h': 210, 'sat': 0.08, 'val': 0.7}),
    ('crawfish', {'h': 8, 'sat': 0.85, 'val': 0.88}),
    ('squid', {'h': 300, 'sat': 0.4, 'val': 0.7}),
    ('duck', {'h': 38, 'sat': 0.55, 'val': 0.9}),
    ('rabbit', {'h': 28, 'sat': 0.3, 'val': 0.95}),
    ('pheasant', {'h': 18, 'sat': 0.7, 'val': 0.8}),
    ('beef', {'h': 4, 'sat': 0.7, 'val': 0.7}),
    ('venison', {'h': 16, 'sat': 0.55, 'val': 0.65}),
    ('boar', {'h': 22, 'sat': 0.4, 'val': 0.6}),
    ('carrot', {'h': 22, 'sat': 1.1, 'val': 1.0}),
    ('grape', {'h': 280, 'sat': 0.8, 'val': 0.75}),
    ('berry', {'h': 350, 'sat': 0.9, 'val': 0.75}),
    ('clay', {'h': 22, 'sat': 0.35, 'val': 0.75}),
    ('coal', {'h': 0, 'sat': 0.05, 'val': 0.35}),
    ('essence', {'h': 275, 'sat': 0.85, 'val': 1.05}),
    ('potato', {'h': 40, 'sat': 0.55, 'val': 0.85}),
    ('fern', {'h': 125, 'sat': 0.7, 'val': 0.8}),
    ('moss', {'h': 140, 'sat': 0.45, 'val': 0.6}),
    ('augur', {'h': 78, 'sat': 0.6, 'val': 0.75}),
    ('root', {'h': 28, 'sat': 0.5, 'val': 0.7}),
    ('stew', {'h': 28, 'sat': 0.8, 'val': 0.7}),
    ('butterfly', {'h': 300, 'sat': 0.7, 'val': 1.05}),
    ('elk', {'h': 30, 'sat': 0.35, 'val': 0.8}),
    ('bull', {'h': 20, 'sat': 0.25, 'val': 0.7}),
    ('goat', {'h': 40, 'sat': 0.2, 'val': 0.85}),
    ('stag', {'h': 32, 'sat': 0.3, 'val': 0.75}),
    ('troll', {'h': 100, 'sat': 0.25, 'val': 0.65}),
    ('ent', {'h': 95, 'sat': 0.5, 'val': 0.55}),
    ('sap', {'h': 70, 'sat': 0.8, 'val': 0.9}),
    ('bark', {'h': 25, 'sat': 0.4, 'val': 0.5}),
    ('heartwood', {'h': 18, 'sat': 0.65, 'val': 0.55}),
    ('wizard', {'h': 260, 'sat': 0.7, 'val': 0.85}),
    ('chef', {'h': 0, 'sat': 0.15, 'val': 1.1}),
    ('falcon', {'h': 25, 'sat': 0.55, 'val': 0.7}),
    ('beggar', {'h': 35, 'sat': 0.25, 'val': 0.55}),
    ('traveler', {'h': 38, 'sat': 0.55, 'val': 0.8}),
    ('lucky', {'h': 48, 'sat': 1.05, 'val': 1.05}),
    ('old', {'h': 30, 'sat': 0.25, 'val': 0.5}),
    ('enchanted', {'h': 270, 'sat': 0.85, 'val': 1.05}),
    ('goblin', {'h': 110, 'sat': 0.55, 'val': 0.7}),
    ('dwarven', {'h': 28, 'sat': 0.5, 'val': 0.75}),
    ('regular', {'h': 32, 'sat': 0.45, 'val': 0.8}),
    ('cloth', {'h': 210, 'sat': 0.15, 'val': 0.9}),
    ('chain', {'h': 45, 'sat': 0.15, 'val': 0.85}),
    ('clasp', {'h': 42, 'sat': 0.35, 'val': 0.8}),
    ('tablet', {'h': 265, 'sat': 0.4, 'val': 0.75}),
    ('spell', {'h': 0, 'sat': 0.9, 'val': 0.95}),
    ('abundance', {'h': 125, 'sat': 0.85, 'val': 1.0}),
    ('stolen', {'h': 45, 'sat': 0.9, 'val': 0.95}),
    ('minor', {'h': None, 'sat': 0.7, 'val': 0.85}),
    ('greater', {'h': None, 'sat': 1.15, 'val': 1.08}),
]


def family_stem(item: dict) -> str:
    item_id = item['Item ID']
    pinned = PINNED.get(item_id)
    if pinned:
        return pinned
    category = (item.get('Category') or '').lower()
    subtype = (item.get('Subtype') or '').lower()
    blob = (
        f"{(item.get('Internal Key') or '').lower()} {category} {subtype} "
        f"{(item.get('Display Name') or '').lower()}"
    )
    if 'gold' in blob and ('currency' in category or 'coin' in blob):
        return 'gold'
    if 'essence' in blob:
        return 'essence'
    if 'coal' in blob:
        return 'coal'
    if 'potato' in blob or 'spud' in blob:
        return 'baked_potato' if 'baked' in blob else 'potato'
    if 'backpack' in blob or 'back item' in blob or 'back' in subtype:
        return 'backpack'
    if 'fishing' in blob or 'rod' in blob or 'harpoon' in blob:
        return 'fishing_tool'
    if 'warhammer' in blob or 'hammer' in blob:
        return 'hammer'
    if 'necklace' in blob or 'amulet' in blob:
        return 'necklace'
    if re.search(r'\bring\b', blob) or 'ring' in subtype:
        return 'ring'
    if any(word in blob for word in ('sapphire', 'emerald', 'ruby', 'gem')):
        return 'gem'
    if 'timber' in blob or 'plank' in blob:
        return 'timber'
    if any(
        word in blob
        for word in (
            'leather',
            'strap',
            'cloth',
            'component',
            'tablet',
            'chain',
            'clasp',
            'fiber',
        )
    ) or 'component' in category:
        return 'component'
    if 'net' in blob or 'sling' in blob:
        return 'net'
    if 'pickaxe' in blob or re.search(r'\bpick\b', blob):
        return 'pickaxe'
    if 'hatchet' in blob:
        return 'hatchet'
    if 'bow' in blob:
        return 'bow'
    if 'sword' in blob:
        return 'sword'
    if 'dagger' in blob:
        return 'dagger'
    if 'axe' in blob and 'pickaxe' not in blob:
        return 'axe'
    if 'shield' in blob or 'off-hand' in blob or 'offhand' in blob:
        return 'shield'
    if 'helmet' in blob or 'hat' in blob:
        return 'helmet'
    if 'leg' in blob or 'plateleg' in blob or 'plateleg' in subtype:
        return 'legs'
    if 'chest' in blob or 'plate' in blob or 'mail' in blob:
        return 'chest'
    if 'boot' in blob:
        return 'boots'
    if 'glove' in blob:
        return 'gloves'
    if 'potion' in blob or 'vial' in blob:
        return 'potion'
    if re.search(r'\bore\b', blob) or 'ore' in subtype or 'ore' in category:
        return 'ore'
    if 'bar' in blob or 'metal bar' in category:
        return 'bar'
    if 'log' in blob or 'wood' in blob:
        return 'log'
    if 'herb' in blob or 'fern' in blob or 'weed' in blob:
        return 'herb'
    if any(word in blob for word in ('hide', 'meat', 'feather', 'creature', 'bone')):
        return 'creature'
    if any(word in blob for word in ('berry', 'berrie', 'grape', 'carrot', 'clay', 'root')):
        return 'raw_food'
    if 'dragon' in blob and 'scale' in blob:
        return 'dragon_scale'
    if 'insignia' in blob:
        return 'insignia'
    if category == 'spell':
        return 'spell'
    if 'food' in category or 'food' in subtype:
        return 'food'
    if 'raw' in category:
        return 'raw_food'
    if 'weapon' in category or 'tool' in category:
        return 'sword'
    if 'armor' in category:
        return 'chest'
    return 'default'


def material_for(item: dict) -> dict[str, float]:
    blob = f"{item.get('Internal Key') or ''} {item.get('Display Name') or ''}".lower()
    found: dict[str, float] = {'h': None, 'sat': 1.0, 'val': 1.0}
    for key, spec in MATERIALS:
        if key in blob:
            if spec['h'] is not None:
                found['h'] = spec['h']
            found['sat'] *= spec['sat']
            found['val'] *= spec['val']
            # Keep scanning so "minor luck" stacks sat from both tokens.
    uid = int(re.search(r'(\d+)$', item['Item ID']).group(1))
    if found['h'] is None:
        found['h'] = (uid * 47) % 360
    found['h'] = (found['h'] + ((uid * 13) % 17) - 8) % 360
    found['sat'] *= 0.94 + (uid % 5) * 0.02
    found['val'] *= 0.94 + (uid % 6) * 0.015
    return found


def is_background(r: int, g: int, b: int, a: int) -> bool:
    if a < 8:
        return True
    return max(r, g, b) < 14 and abs(r - g) < 8 and abs(g - b) < 8


def median_hue(img: Image.Image) -> float:
    hues: list[float] = []
    for r, g, b, a in img.getdata():
        if is_background(r, g, b, a):
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s > 0.12 and v > 0.22:
            hues.append(h)
    if not hues:
        return 0.05
    hues.sort()
    return hues[len(hues) // 2]


def recolor(src: Image.Image, spec: dict[str, float]) -> Image.Image:
    img = src.convert('RGBA')
    current = median_hue(img)
    target = spec['h'] / 360.0
    shift = target - current
    sat_m = spec['sat']
    val_m = spec['val']
    out = Image.new('RGBA', img.size)
    pixels = []
    for r, g, b, a in img.getdata():
        if is_background(r, g, b, a):
            pixels.append((0, 0, 0, 255 if a > 8 else 0))
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        h = (h + shift) % 1.0
        s = min(1.0, max(0.0, s * sat_m))
        v = min(1.0, max(0.0, v * val_m))
        nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
        pixels.append((int(nr * 255), int(ng * 255), int(nb * 255), 255))
    out.putdata(pixels)
    return out


def main() -> None:
    db = json.loads(DATABASE.read_text())
    items = db['Items']
    cache: dict[str, Image.Image] = {}
    written = 0
    copied = 0
    skipped = 0
    for item in items:
        stem = item['Internal Key']
        family = family_stem(item)
        src_path = ICONS / f'item_{family}.webp'
        if not src_path.exists():
            raise SystemExit(f'missing family icon {src_path}')
        dest = ICONS / f'item_{stem}.webp'
        item['Icon Asset Key'] = stem
        if dest.resolve() == src_path.resolve():
            skipped += 1
            continue
        if family not in cache:
            cache[family] = Image.open(src_path).convert('RGBA')
        if stem == family:
            skipped += 1
            continue
        # Dedicated unique bases that already match this item stay as a copy
        # when the family pin is already that item's own art.
        if PINNED.get(item['Item ID']) == family and dest.name != src_path.name:
            spec = material_for(item)
            # Still tint so golden_spud is not a raw potato, berries stay close.
            if family in {'potato', 'berries', 'baked_potato', 'gold', 'coal', 'essence'}:
                recolor(cache[family], spec).save(dest, 'WEBP', lossless=True)
                written += 1
                continue
            shutil.copyfile(src_path, dest)
            copied += 1
            continue
        recolor(cache[family], spec=material_for(item)).save(dest, 'WEBP', lossless=True)
        written += 1

    DATABASE.write_text(json.dumps(db, indent=2) + '\n')
    print(f'wrote {written} recolors, copied {copied}, kept {skipped} family files')
    print(f'set Icon Asset Key on {len(items)} items')


if __name__ == '__main__':
    main()
