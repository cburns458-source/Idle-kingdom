import { recordItemsSoldAtLocation } from '../achievements/progress'
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
  const quantities: Record<number, number> = {}
  for (const index of indexes) {
    if (!Number.isInteger(index) || index < 0 || index >= save.inventory.length) continue
    quantities[index] = save.inventory[index].quantity
  }
  return sellInventoryQuantities(db, save, quantities)
}

/** Sells a chosen quantity from each selected bag stack. */
export function sellInventoryQuantities(
  db: GameDatabase,
  save: PlayerSave,
  quantitiesByIndex: Record<number, number>,
): SellInventoryResult {
  const unique = Object.keys(quantitiesByIndex)
    .map((key) => Number(key))
    .filter((index) => Number.isInteger(index) && index >= 0 && index < save.inventory.length)
    .sort((a, b) => b - a)

  if (unique.length === 0) {
    return { ok: false, reason: 'Select at least one item to sell.' }
  }

  let goldEarned = 0
  let stacksSold = 0
  const inventory = [...save.inventory]
  const soldAtShop: { itemId: string; quantity: number }[] = []

  for (const index of unique) {
    const stack = inventory[index]
    const quantity = Math.trunc(quantitiesByIndex[index] ?? 0)
    if (!Number.isInteger(quantity) || quantity < 1) {
      return { ok: false, reason: 'Choose how many to sell.' }
    }
    if (quantity > stack.quantity) {
      return { ok: false, reason: 'You do not have that many to sell.' }
    }
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
    goldEarned += priced.unitPrice * quantity
    stacksSold += 1
    if (priced.shopId) {
      soldAtShop.push({ itemId: stack.itemId, quantity })
    }
    if (quantity >= stack.quantity) inventory.splice(index, 1)
    else inventory[index] = { ...stack, quantity: stack.quantity - quantity }
  }

  let next: PlayerSave = {
    ...save,
    inventory,
    gold: save.gold + goldEarned,
  }
  if (soldAtShop.length > 0) {
    next = recordItemsSoldAtLocation(next, soldAtShop, save.currentLocationId)
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
