# Unique item icons

Every Launch item has its own 32×32 WebP at
`content/assets/icons/items/item_<internal-key>.webp`, and `Icon Asset Key`
is set to that same Internal Key. Family files (`item_ore.webp`,
`item_bar.webp`, and so on) stay as fallbacks for any future row that has
not been keyed yet.

Icons are painted from each item's **Display Name** by
`scripts/paint_item_icons.py` (the docs entry point
`scripts/generate_item_icons.py` calls it):

```
python3 scripts/generate_item_icons.py
```

Do not copy files into `app_flutter/content`. The Flutter content tree is a
symlink to `content/`.

## Style

- 32×32 pixel art, **transparent background**, no UI chrome.
- Simple silhouettes, 3-color ramps, light from the top-left.
- No text. **No black outlines** — edges are a darker shade of the fill.
- Same pose per family; only the material color changes.

## Families and palettes

| Family | Shared pose | Color by display name |
| --- | --- | --- |
| Pickaxe / hatchet / axe / sword / dagger / rod / harpoon / hammer | One stamp each | Metal (copper, bronze, iron, steel, …) or wood when the name is wooden |
| Armor (helmet, chest, legs, boots, gloves, shield) | One stamp each | Same metal palette as the tools |
| Bows / logs / timber | One stamp each | Cedar, oak, poplar, maple, mahogany, ancient, regular/wooden |
| Ore / bar | One stamp each | Same metal palette, plus moonstone |
| Gems | Rough or cut diamond | Sapphire blue, emerald green, ruby red |
| Fish | Species silhouette | Trout green, salmon pink, tuna blue-gray, shark gray; cooked = browned |
| Hats / uniques | Named shape | Chef's hat, wizard's hat, and so on |

A copper pickaxe and a tungsten pickaxe keep the same pose; only the head
metal changes. Every copper-named item uses the same copper ramp.

## File and data contract

1. Stem = `Internal Key` snake_case, unique, e.g. `copper_ore`.
2. File = `content/assets/icons/items/item_<stem>.webp`.
3. Set `Items.Icon Asset Key` to that stem.
4. Family files and `_itemIcons` / `ITEM_ID_ICONS` stay as fallbacks.
5. Keep `item_default.webp` for unknown ids.

Resolver order (already shipped): row key → pinned id → name/category heuristic.

## How to replace one icon

1. Draw a 32×32 WebP in the style above, or recolor from a family plate.
2. Save it as `content/assets/icons/items/item_<internal-key>.webp`.
3. Keep that item's `Icon Asset Key` equal to `<internal-key>`.
4. Run `flutter test test/asset_audit_test.dart` and
   `npx vitest run src/game/assets/itemAssets.test.ts`.
