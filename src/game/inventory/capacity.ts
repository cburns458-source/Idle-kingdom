import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { isGoldCurrencyItem } from './gold'

/** Bag slot cap (each stack or enchanted item uses one slot). */
export const INVENTORY_SLOT_LIMIT = 180

/** Max quantity on a single non-enchanted stack. */
export const INVENTORY_STACK_MAX = Number.MAX_SAFE_INTEGER

export function inventorySlotCount(save: Pick<PlayerSave, 'inventory'>): number {
  return save.inventory.length
}

export function inventorySlotsFree(save: Pick<PlayerSave, 'inventory'>): number {
  return Math.max(0, INVENTORY_SLOT_LIMIT - inventorySlotCount(save))
}

function stackMatches(
  stack: PlayerSave['inventory'][number],
  itemId: string,
  enchantmentId: string | null,
  favorite: boolean,
): boolean {
  return (
    stack.itemId === itemId &&
    (stack.enchantmentId ?? null) === enchantmentId &&
    Boolean(stack.favorite) === favorite
  )
}

/** How many of this item can still be added without overflowing slots or stack max. */
export function maxAddableQuantity(
  save: Pick<PlayerSave, 'inventory'>,
  itemId: string,
  enchantmentId: string | null = null,
  favorite = false,
  db?: GameDatabase,
): number {
  if (isGoldCurrencyItem(itemId, db) && !enchantmentId) {
    return INVENTORY_STACK_MAX
  }
  if (enchantmentId) {
    return inventorySlotsFree(save)
  }

  const existing = save.inventory.find((stack) =>
    stackMatches(stack, itemId, null, favorite),
  )
  const stackRoom = existing
    ? Math.max(0, INVENTORY_STACK_MAX - existing.quantity)
    : inventorySlotsFree(save) > 0
      ? INVENTORY_STACK_MAX
      : 0
  return stackRoom
}

export function canFitItemQuantity(
  save: Pick<PlayerSave, 'inventory'>,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
  favorite = false,
  db?: GameDatabase,
): boolean {
  const want = Math.floor(quantity)
  if (want <= 0) return true
  return maxAddableQuantity(save, itemId, enchantmentId, favorite, db) >= want
}
