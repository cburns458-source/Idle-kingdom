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

function isUnenchantedMatch(
  stack: PlayerSave['inventory'][number],
  itemId: string,
): boolean {
  return stack.itemId === itemId && !stack.enchantmentId
}

/**
 * Index of the unenchanted pile to grow. Hearted stacks win when both exist.
 * Enchanted items never merge. Returns -1 when a new slot is needed.
 */
export function mergeableStackIndex(
  inventory: PlayerSave['inventory'],
  itemId: string,
  enchantmentId: string | null = null,
): number {
  if (enchantmentId) return -1
  let unfavorited = -1
  for (let i = 0; i < inventory.length; i += 1) {
    const stack = inventory[i]
    if (!stack || !isUnenchantedMatch(stack, itemId)) continue
    if (stack.favorite === true) return i
    if (unfavorited < 0) unfavorited = i
  }
  return unfavorited
}

/** How many of this item can still be added without overflowing slots or stack max. */
export function maxAddableQuantity(
  save: Pick<PlayerSave, 'inventory'>,
  itemId: string,
  enchantmentId: string | null = null,
  _favorite = false,
): number {
  if (isGoldCurrencyItem(itemId) && !enchantmentId) {
    return INVENTORY_STACK_MAX
  }
  if (enchantmentId) {
    return inventorySlotsFree(save)
  }

  const existingIndex = mergeableStackIndex(save.inventory, itemId)
  const existing = existingIndex >= 0 ? save.inventory[existingIndex] : undefined
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
): boolean {
  const want = Math.floor(quantity)
  if (want <= 0) return true
  return maxAddableQuantity(save, itemId, enchantmentId, favorite) >= want
}
