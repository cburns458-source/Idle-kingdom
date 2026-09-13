// The narrow slice of the inventory rules the Bazaar needs, server side.
//
// The client's copy of these rules lives in `packages/ik_rules/lib/src/inventory`
// and is the one that runs everywhere else in the game. This is deliberately not
// that whole module: an exchange only ever has to take a plain stack out of a
// bag and put a plain stack back in, and a small file that says exactly what the
// server will do with a save is easier to trust than a port of the lot.
//
// What has to agree with the client, and does:
//   * 180 stacks in a bag, each stack one item id
//   * enchanted items never merge and are never fungible
//   * gold is a number on the save, not a stack
//   * a cloud save is refused above a billion gold

/** A bag or bank entry. Matches `InventoryStack` in the save schema. */
export type Stack = {
  itemId: string
  quantity: number
  enchantmentId?: string | null
  favorite?: boolean | null
}

/** The save as it is stored, with only the parts this file reads named. */
export type SavePayload = Record<string, unknown> & {
  inventory?: unknown
  gold?: unknown
  updatedAt?: unknown
}

export const INVENTORY_SLOT_LIMIT = 180
export const STACK_MAX = 9007199254740991
export const GOLD_CAP = 1000000000
export const GOLD_ITEM_ID = 'ITEM-0001'

/** Item ids as the game database writes them. */
export const ITEM_ID_PATTERN = /^ITEM-\d{3,6}$/

export function isItemId(value: unknown): value is string {
  return typeof value === 'string' && ITEM_ID_PATTERN.test(value)
}

export function inventoryOf(payload: SavePayload): Stack[] {
  const raw = Array.isArray(payload.inventory) ? payload.inventory : []
  const stacks: Stack[] = []
  for (const entry of raw) {
    if (!entry || typeof entry !== 'object') continue
    const stack = entry as Record<string, unknown>
    const itemId = stack.itemId
    const quantity = stack.quantity
    if (typeof itemId !== 'string' || typeof quantity !== 'number') continue
    stacks.push({
      itemId,
      quantity,
      enchantmentId: typeof stack.enchantmentId === 'string' ? stack.enchantmentId : null,
      favorite: stack.favorite === true ? true : null,
    })
  }
  return stacks
}

export function goldOf(payload: SavePayload): number {
  const gold = payload.gold
  return typeof gold === 'number' && Number.isFinite(gold) ? Math.floor(gold) : 0
}

/**
 * True when a stack may be listed.
 *
 * Gold is the currency rather than a good; an enchanted item is one of a kind
 * and would lose that in a pile; a favourited stack is the flag a player sets
 * on the things they do not want sold, and the exchange honours it the same way
 * the shops do.
 */
export function isTradableStack(stack: Stack): boolean {
  if (stack.itemId === GOLD_ITEM_ID) return false
  if (typeof stack.enchantmentId === 'string' && stack.enchantmentId.trim() !== '') return false
  if (stack.favorite === true) return false
  return stack.quantity > 0
}

/** How much of [itemId] the bag holds in stacks that may be listed. */
export function tradableQuantity(payload: SavePayload, itemId: string): number {
  let total = 0
  for (const stack of inventoryOf(payload)) {
    if (stack.itemId === itemId && isTradableStack(stack)) total += Math.floor(stack.quantity)
  }
  return total
}

function withInventory(payload: SavePayload, inventory: Stack[]): SavePayload {
  return {
    ...payload,
    inventory: inventory.map((stack) => {
      const out: Record<string, unknown> = { itemId: stack.itemId, quantity: stack.quantity }
      if (typeof stack.enchantmentId === 'string' && stack.enchantmentId !== '') {
        out.enchantmentId = stack.enchantmentId
      }
      if (stack.favorite === true) out.favorite = true
      return out
    }),
  }
}

/**
 * The save with [quantity] of [itemId] taken out of the bag, or null when the
 * bag does not hold that much in stacks that may be listed.
 */
export function takeItems(
  payload: SavePayload,
  itemId: string,
  quantity: number,
): SavePayload | null {
  const want = Math.floor(quantity)
  if (want <= 0) return null
  if (tradableQuantity(payload, itemId) < want) return null

  const inventory = inventoryOf(payload)
  let left = want
  const kept: Stack[] = []
  for (const stack of inventory) {
    if (left <= 0 || stack.itemId !== itemId || !isTradableStack(stack)) {
      kept.push(stack)
      continue
    }
    const taken = Math.min(left, Math.floor(stack.quantity))
    left -= taken
    const remaining = stack.quantity - taken
    if (remaining > 0) kept.push({ ...stack, quantity: remaining })
  }
  if (left > 0) return null
  return withInventory(payload, kept)
}

/**
 * The save with [quantity] of [itemId] added, or null when it will not fit.
 *
 * All or nothing on purpose: the collection box hands over a row at a time, and
 * a row half taken would need somewhere to remember the other half.
 */
export function giveItems(
  payload: SavePayload,
  itemId: string,
  quantity: number,
): SavePayload | null {
  const want = Math.floor(quantity)
  if (want <= 0) return null

  const inventory = inventoryOf(payload)
  // Only a plain stack merges, and a favourited pile of the same item is the one
  // the client would have merged into, so it is the one used here too.
  let index = -1
  for (let at = 0; at < inventory.length; at += 1) {
    const stack = inventory[at]
    if (stack.itemId !== itemId) continue
    if (typeof stack.enchantmentId === 'string' && stack.enchantmentId.trim() !== '') continue
    if (stack.favorite === true) {
      index = at
      break
    }
    if (index < 0) index = at
  }

  if (index < 0) {
    if (inventory.length >= INVENTORY_SLOT_LIMIT) return null
    return withInventory(payload, [...inventory, { itemId, quantity: want }])
  }
  const merged = inventory[index].quantity + want
  if (merged > STACK_MAX) return null
  const next = [...inventory]
  next[index] = { ...inventory[index], quantity: merged }
  return withInventory(payload, next)
}

/** The save with [amount] gold taken, or null when the purse is short. */
export function takeGold(payload: SavePayload, amount: number): SavePayload | null {
  const want = Math.floor(amount)
  if (want <= 0) return null
  const gold = goldOf(payload)
  if (gold < want) return null
  return { ...payload, gold: gold - want }
}

/**
 * The save with [amount] gold added, or null when it would break the cap a
 * cloud save is validated against.
 */
export function giveGold(payload: SavePayload, amount: number): SavePayload | null {
  const want = Math.floor(amount)
  if (want <= 0) return null
  const gold = goldOf(payload)
  if (gold + want > GOLD_CAP) return null
  return { ...payload, gold: gold + want }
}

/** Stamps the save so the client and the stored row agree on which one this is. */
export function stamped(payload: SavePayload, iso: string): SavePayload {
  return { ...payload, updatedAt: iso }
}
