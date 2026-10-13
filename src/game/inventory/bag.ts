/**
 * Item taking shared by dialogue hand-ins and legacy quest turn-ins.
 *
 * Counts read the bag only, never the bank. Enchanted stacks do not count.
 * Hearted (favourited) stacks count everywhere; taking from one needs the
 * player's confirmation (`confirm_favourites`).
 */

import type { PlayerSave } from '../save/types'

/** Player-facing text for `confirm_favourites`; the UI asks Yes / No with it. */
export const CONFIRM_FAVOURITES_PROMPT = 'Some items are favourited. Do you still want to use them?'

export interface ItemDelta {
  itemId: string
  /** Positive when granted, negative when taken or handed in. */
  qty: number
}

/** Unenchanted bag quantity of [itemId]. */
export function bagCount(save: PlayerSave, itemId: string): number {
  let total = 0
  for (const stack of save.inventory) {
    if (stack.itemId === itemId && !stack.enchantmentId) total += stack.quantity
  }
  return total
}

/** Unenchanted bag quantity of [itemId] outside hearted (favourited) stacks. */
export function unfavouriteCount(save: PlayerSave, itemId: string): number {
  let total = 0
  for (const stack of save.inventory) {
    if (stack.itemId === itemId && !stack.enchantmentId && stack.favorite !== true) total += stack.quantity
  }
  return total
}

/** How much of taking [quantity] [itemId] from [save] would come out of hearted stacks. */
export function favouritesNeeded(save: PlayerSave, itemId: string, quantity: number): number {
  return Math.max(0, quantity - unfavouriteCount(save, itemId))
}

/** Adds [qty] of [itemId] to [lines], merging into an existing line. */
export function addFavouriteLine(lines: ItemDelta[], itemId: string, qty: number): void {
  if (qty <= 0) return
  const existing = lines.find((line) => line.itemId === itemId)
  if (existing) existing.qty += qty
  else lines.push({ itemId, qty })
}

/**
 * Removes [quantity] unenchanted [itemId] from the bag, unhearted stacks first.
 * Returns null when the bag holds fewer.
 */
export function takeFromBag(save: PlayerSave, itemId: string, quantity: number): PlayerSave | null {
  if (quantity <= 0) return save
  if (bagCount(save, itemId) < quantity) return null
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  let remaining = quantity
  for (const favoritePass of [false, true]) {
    for (const stack of inventory) {
      if (remaining <= 0) break
      if (stack.itemId !== itemId || stack.enchantmentId) continue
      if ((stack.favorite === true) !== favoritePass) continue
      const taken = Math.min(stack.quantity, remaining)
      stack.quantity -= taken
      remaining -= taken
    }
  }
  return { ...save, inventory: inventory.filter((stack) => stack.quantity > 0) }
}
