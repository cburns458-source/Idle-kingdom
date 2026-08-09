import { itemAssetPath } from '../game/assets/itemAssets'
import type { ItemRow } from '../game/data/types'

/** Compact item glyph / art for inventory and equipment. */
export function ItemIcon({ item }: { item: ItemRow | undefined }) {
  const path = item ? itemAssetPath(item['Item ID']) : null
  if (path) {
    return (
      <span
        className="item-icon item-icon-art"
        style={{ backgroundImage: `url(${path})` }}
        aria-hidden
        title={item?.['Display Name']}
      />
    )
  }

  const key = (item?.['Internal Key'] ?? item?.Category ?? 'item').toLowerCase()
  const label = glyphFor(key, item?.Category, item?.Subtype)
  return (
    <span className="item-icon" aria-hidden title={item?.['Display Name']}>
      {label}
    </span>
  )
}

function glyphFor(
  key: string,
  category: string | null | undefined,
  subtype: string | null | undefined,
): string {
  if (key.includes('net') || key.includes('sling')) return 'N'
  if (key.includes('bow')) return 'B'
  if (key.includes('pickaxe') || key.includes('pick')) return 'P'
  if (key.includes('hatchet') || key.includes('axe')) return 'A'
  if (key.includes('sword') || key.includes('spear') || key.includes('dagger')) return 'W'
  if (key.includes('shield')) return 'S'
  if (key.includes('potato') || key.includes('berry') || key.includes('bread')) return 'F'
  if (key.includes('potion') || key.includes('vial')) return 'V'
  if (key.includes('ore') || key.includes('bar') || key.includes('coal')) return 'O'
  if (key.includes('hide') || key.includes('meat') || key.includes('feather')) return 'R'
  if (key.includes('helmet') || key.includes('hat')) return 'H'
  if (key.includes('chest') || key.includes('plate') || key.includes('mail')) return 'C'
  if (key.includes('boot')) return 'T'
  if (key.includes('glove')) return 'G'
  if (key.includes('ring')) return 'o'
  if (key.includes('necklace') || key.includes('amulet')) return '@'
  if (key.includes('rod') || key.includes('harpoon')) return 'L'

  const cat = (category ?? '').toLowerCase()
  if (cat.includes('food')) return 'F'
  if (cat.includes('weapon') || cat.includes('tool')) return 'W'
  if (cat.includes('armor')) return 'C'
  if (cat.includes('resource') || cat.includes('material')) return 'O'
  if ((subtype ?? '').toLowerCase().includes('potion')) return 'V'
  return '·'
}
