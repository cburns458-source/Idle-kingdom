import {
  baseSellValue,
  canAccessShop,
  currencyItemId,
  playerSellPrice,
  shopsAtLocation,
} from '../shops/shops'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { isFavoriteStack } from './favorites'

/** Off-shop / field sale: half of Base Sell Value. */
export const FIELD_SELL_MULT = 0.5

export function fieldSellPrice(db: GameDatabase, itemId: string): number | null {
  if (itemId === currencyItemId(db)) return null
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  const base = baseSellValue(item)
  if (base == null || base <= 0) return null
  return Math.max(0, Math.round(base * FIELD_SELL_MULT))
}

/**
 * Best unit price for selling at the current location.
 * Uses an accessible shop when it will buy the item; otherwise 50% field price.
 */
export function sellPriceAtLocation(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
): { unitPrice: number; shopId: string | null } | null {
  const shops = shopsAtLocation(db, save.currentLocationId)
  let best: { unitPrice: number; shopId: string } | null = null
  for (const shop of shops) {
    if (!canAccessShop(db, save, shop).ok) continue
    const price = playerSellPrice(db, shop, itemId)
    if (price == null) continue
    if (!best || price > best.unitPrice) {
      best = { unitPrice: price, shopId: shop['Shop ID'] }
    }
  }
  if (best) return best

  const field = fieldSellPrice(db, itemId)
  if (field == null) return null
  return { unitPrice: field, shopId: null }
}

export type SellInventoryResult =
  | { ok: true; save: PlayerSave; goldEarned: number; stacksSold: number; message: string }
  | { ok: false; reason: string }

/** Sell selected bag stacks at the current location (shop price or 50% field price). */
export function sellInventoryIndexes(
  db: GameDatabase,
  save: PlayerSave,
  indexes: Iterable<number>,
): SellInventoryResult {
  const unique = [
    ...new Set(
      [...indexes].filter(
        (index) => Number.isInteger(index) && index >= 0 && index < save.inventory.length,
      ),
    ),
  ].sort((a, b) => b - a)

  if (unique.length === 0) {
    return { ok: false, reason: 'Select at least one item to sell.' }
  }

  let goldEarned = 0
  let stacksSold = 0
  const remove = new Set<number>()

  for (const index of unique) {
    const stack = save.inventory[index]
    if (!stack) continue
    if (isFavoriteStack(stack)) {
      return { ok: false, reason: 'Favorited items cannot be sold. Unfavorite them first.' }
    }
    if (stack.enchantmentId) {
      return { ok: false, reason: 'Enchanted items cannot be sold from the bag.' }
    }
    const priced = sellPriceAtLocation(db, save, stack.itemId)
    if (!priced) {
      const name =
        db.Items.find((item) => item['Item ID'] === stack.itemId)?.['Display Name'] ?? 'That item'
      return { ok: false, reason: `${name} cannot be sold.` }
    }
    goldEarned += priced.unitPrice * stack.quantity
    stacksSold += 1
    remove.add(index)
  }

  if (stacksSold === 0) {
    return { ok: false, reason: 'Select at least one item to sell.' }
  }

  const inventory = save.inventory.filter((_, index) => !remove.has(index))
  const next: PlayerSave = {
    ...save,
    inventory,
    gold: save.gold + goldEarned,
    statistics: {
      values: {
        ...save.statistics.values,
        gold_earned: Number(save.statistics.values.gold_earned ?? 0) + goldEarned,
      },
    },
  }

  const shopsHere = shopsAtLocation(db, save.currentLocationId).some(
    (shop) => canAccessShop(db, save, shop).ok,
  )
  const rateNote = shopsHere ? 'shop rate' : '50% field rate'
  return {
    ok: true,
    save: next,
    goldEarned,
    stacksSold,
    message: `Sold ${stacksSold} stack${stacksSold === 1 ? '' : 's'} for ${goldEarned.toLocaleString()} gold (${rateNote}).`,
  }
}
