# Unique item icons

267 items currently share 42 family icons (`content/assets/icons/items/item_*.webp`). Copper ore, iron ore, and ruby all look the same. Each item should have its own 32×32 WebP, even when that is only a recolor of the family silhouette.

The unused `Icon Asset Key` column is the hook. Dart and TypeScript now read it before the family heuristic. Filling that column plus dropping a matching file is enough to swap one item without touching code.

## Style (match the current set)

- 32×32 pixel art, solid black background, no UI chrome.
- Chunky 16-bit RPG silhouettes, 3–4 color ramps, light from the top-left.
- No text. Edges come from contrast against black, not a thick outline.
- Recolors keep the family shape and only change the material ramp (ore vein, bar metal, potion liquid, wood grain, gem hue).

Keep the existing family files as bases. Do not redraw from scratch unless the item has no family (quest oddities, unique cosmetics).

## Families and palettes

Use the current stem as the base, then tint:

| Family | Base file | Tint by |
| --- | --- | --- |
| Ore / bar | `item_ore`, `item_bar` | copper, tin, iron, steel, silver, gold, titanium, tungsten |
| Logs / timber | `item_log`, `item_timber` | cedar, oak, poplar, maple, mahogany, ancient |
| Gems | `item_gem` | sapphire, emerald, ruby, and lesser stones |
| Potions | `item_potion` | liquid hue (red, blue, green, gold, purple) |
| Food / raw food / herbs | `item_food`, `item_raw_food`, `item_herb`, `item_potato` | crop and dish color |
| Weapons / tools / armor | `item_sword`, `item_axe`, `item_pickaxe`, `item_chest`, … | metal or leather ramp by tier |
| Jewelry | `item_ring`, `item_necklace` | gem + metal combo |
| Creature / component | `item_creature`, `item_component` | hide, bone, cloth, fiber |

A steel sword and an iron sword keep the same pose; only the blade and fittings change color.

## File and data contract

1. Stem = `Internal Key` snake_case, unique, e.g. `copper_ore`.
2. File = `content/assets/icons/items/item_<stem>.webp`.
3. Set `Items.Icon Asset Key` to that stem.
4. Leave `_itemIcons` / `ITEM_ID_ICONS` as fallbacks until every Launch row has a key.
5. Keep `item_default.webp` for unknown ids.

Resolver order (already shipped): row key → pinned id → name/category heuristic.

## Order of work

Generate in batches so the bag improves before every row is done:

1. Launch **Confirmed** resources, bars, and food (the tiles players see first).
2. Launch tools, weapons, armor, jewelry.
3. Remaining Launch rows.
4. Expansion rows.

After each batch: encode WebP, fill `Icon Asset Key`, run `flutter test test/asset_paths_test.dart` and a visual pass on inventory / shop / recipe chips. Do not copy files into `app_flutter/content` (symlink).

## What this pass does not do

It does not generate the 267 images. That is a later art batch using this contract. Until a row has a key and a file, it still shows its family icon.
