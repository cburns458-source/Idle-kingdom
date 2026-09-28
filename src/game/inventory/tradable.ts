import { cosmeticByItemId } from '../cosmetics/cosmetics'
import type { GameDatabase, ItemRow } from '../data/types'
import { currencyItemId } from './gold'

function itemHasTag(item: ItemRow | undefined, tag: string): boolean {
  return String(item?.['Functional / Source Tags'] ?? '')
    .split(/[;,]/)
    .map((part) => part.trim().toLowerCase())
    .includes(tag)
}

/** Default tradable. Untradable tags, cosmetics, and gold cannot be sold or destroyed. */
export function itemIsTradable(db: GameDatabase, itemId: string): boolean {
  if (itemId === currencyItemId(db)) return false
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  if (!item) return true
  if ((item.Category ?? '').toLowerCase() === 'cosmetic') return false
  if (cosmeticByItemId(db, itemId)) return false
  if (itemHasTag(item, 'untradable')) return false
  return true
}
