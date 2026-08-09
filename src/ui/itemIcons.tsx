import { itemAssetPath } from '../game/assets/itemAssets'
import { slotAssetPath } from '../game/assets/slotAssets'
import type { ItemRow } from '../game/data/types'

/** Pixel item icon for inventory and filled equipment slots. */
export function ItemIcon({
  item,
  className = '',
}: {
  item: ItemRow | undefined
  className?: string
}) {
  return (
    <span
      className={`item-icon item-icon-art ${className}`.trim()}
      style={{ backgroundImage: `url(${itemAssetPath(item)})` }}
      aria-hidden
    />
  )
}

/** Pixel placeholder for an empty equipment slot. */
export function SlotGlyph({ slotId }: { slotId: string }) {
  return (
    <span
      className="item-icon item-icon-art item-icon-slot"
      style={{ backgroundImage: `url(${slotAssetPath(slotId)})` }}
      aria-hidden
    />
  )
}
