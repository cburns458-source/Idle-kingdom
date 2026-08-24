import type { GameDatabase } from '../data/types'

/** Fallback currency item when Config has no `currency_item_id`. */
export const GOLD_ITEM_ID = 'ITEM-0001'

/** Gold item ID from Config, or [GOLD_ITEM_ID] when the row is missing. */
export function currencyItemId(db?: GameDatabase): string {
  if (!db) return GOLD_ITEM_ID
  const raw = db.Config.find((row) => row.Key === 'currency_item_id')?.Value
  return typeof raw === 'string' && raw.length > 0 ? raw : GOLD_ITEM_ID
}

/** Primary currency item — never stays in the bag; converts to `save.gold`. */
export function isGoldCurrencyItem(itemId: string, db?: GameDatabase): boolean {
  return itemId === currencyItemId(db)
}
