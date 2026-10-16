// The narrow slice of the inventory rules the Bazaar needs, server side.
//
// The client's copy of these rules lives in `packages/ik_rules/lib/src/inventory`
// and is the one that runs everywhere else in the game. This is deliberately not
// that whole module: an exchange only ever has to take a plain stack out of a
// bag and put a plain stack back in, and a small file that says exactly what the
// server will do with a save is easier to trust than a port of the lot.
//
// What has to agree with the client, and does:
//   * 84 stacks in a bag, each stack one item id
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

export const INVENTORY_SLOT_LIMIT = 84
export const BANK_SLOT_LIMIT = 168
export const STACK_MAX = 9007199254740991
export const GOLD_CAP = 1000000000
export const GOLD_ITEM_ID = 'ITEM-0001'

/** Item ids as the game database writes them. */
export const ITEM_ID_PATTERN = /^ITEM-\d{3,6}$/

export function isItemId(value: unknown): value is string {
  return typeof value === 'string' && ITEM_ID_PATTERN.test(value)
}

/**
 * What the exchange needs to know about the items it may carry, built once
 * from the game database the function bundles.
 *
 * Mirrors `bazaarItemTradable` in `packages/ik_net/lib/src/market.dart`: an item
 * is carried when the runtime would load it (Launch rows only), a shop prices
 * it above 0, and its `Tradeable` column is not false. A missing or blank
 * `Tradeable` means true.
 */
export type ItemCatalog = {
  /** Base Sell Value by item id, for every Launch item. */
  sellValues: ReadonlyMap<string, number | null>
  /** Ids marked `Tradeable` false. */
  untradeable: ReadonlySet<string>
  /** Every Item ID in the bundled database, any Release Phase. */
  knownIds: ReadonlySet<string>
}

export const BOUND_ITEM_REFUSAL = "That stays with you; it can't be traded."
export const UNTRADABLE_ITEM_REFUSAL = 'Nobody at the Bazaar deals in that.'
export const UNKNOWN_ITEM_REFUSAL = 'That item is no longer in the game.'

export function itemCatalog(database: unknown): ItemCatalog {
  const rows =
    database && typeof database === 'object' && Array.isArray((database as { Items?: unknown }).Items)
      ? ((database as { Items: unknown[] }).Items as unknown[])
      : []
  const sellValues = new Map<string, number | null>()
  const untradeable = new Set<string>()
  const knownIds = new Set<string>()
  for (const entry of rows) {
    if (!entry || typeof entry !== 'object') continue
    const row = entry as Record<string, unknown>
    const id = row['Item ID']
    if (typeof id !== 'string') continue
    knownIds.add(id)
    if ('Release Phase' in row && row['Release Phase'] !== 'Launch') continue
    const value = row['Base Sell Value']
    sellValues.set(id, typeof value === 'number' && Number.isFinite(value) ? value : null)
    if (row.Tradeable === false) untradeable.add(id)
  }
  return { sellValues, untradeable, knownIds }
}

/** True unless the database marks [itemId] `Tradeable` false. */
export function isTradableItem(itemId: string, catalog?: ItemCatalog): boolean {
  return catalog == null || !catalog.untradeable.has(itemId)
}

/**
 * Why the exchange will not take [itemId] on either side, or null when it will.
 *
 * Checked before any escrow, for sell and buy orders alike, so a forged request
 * for a bound or deleted item moves no gold and no items.
 */
export function itemRefusal(itemId: string, catalog: ItemCatalog): string | null {
  if (!catalog.knownIds.has(itemId)) return UNKNOWN_ITEM_REFUSAL
  if (!isTradableItem(itemId, catalog)) return BOUND_ITEM_REFUSAL
  if (itemId === GOLD_ITEM_ID) return UNTRADABLE_ITEM_REFUSAL
  const value = catalog.sellValues.get(itemId)
  if (value == null || value <= 0) return UNTRADABLE_ITEM_REFUSAL
  return null
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
 * the shops do. An item marked `Tradeable` false in [catalog] stays with
 * whoever earned it.
 */
export function isTradableStack(stack: Stack, catalog?: ItemCatalog): boolean {
  if (stack.itemId === GOLD_ITEM_ID) return false
  if (!isTradableItem(stack.itemId, catalog)) return false
  if (typeof stack.enchantmentId === 'string' && stack.enchantmentId.trim() !== '') return false
  if (stack.favorite === true) return false
  return stack.quantity > 0
}

/** How much of [itemId] the bag holds in stacks that may be listed. */
export function tradableQuantity(
  payload: SavePayload,
  itemId: string,
  catalog?: ItemCatalog,
): number {
  let total = 0
  for (const stack of inventoryOf(payload)) {
    if (stack.itemId === itemId && isTradableStack(stack, catalog)) {
      total += Math.floor(stack.quantity)
    }
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
  catalog?: ItemCatalog,
): SavePayload | null {
  const want = Math.floor(quantity)
  if (want <= 0) return null
  if (tradableQuantity(payload, itemId, catalog) < want) return null

  const inventory = inventoryOf(payload)
  let left = want
  const kept: Stack[] = []
  for (const stack of inventory) {
    if (left <= 0 || stack.itemId !== itemId || !isTradableStack(stack, catalog)) {
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

export type CollectBoxRow = {
  id?: unknown
  item_id?: unknown
  quantity?: unknown
  gold?: unknown
}

export type CollectNoRoom = {
  slotsNeeded: number
  slotsFree: number
}

export type CollectRowsResult = {
  payload: SavePayload
  taken: string[]
  items: number
  gold: number
  left: number
  rowsLeft: number
  noRoom: CollectNoRoom | null
  purseFull: boolean
}

function mergeableCollectIndex(inventory: Stack[], itemId: string): number {
  let index = -1
  for (let at = 0; at < inventory.length; at += 1) {
    const stack = inventory[at]
    if (stack.itemId !== itemId) continue
    if (typeof stack.enchantmentId === 'string' && stack.enchantmentId.trim() !== '') continue
    if (stack.favorite === true) return at
    if (index < 0) index = at
  }
  return index
}

function noRoomForCollectRows(
  payload: SavePayload,
  leftover: Array<{ itemId: string; quantity: number }>,
): CollectNoRoom {
  const inventory = inventoryOf(payload)
  const slotsFree = Math.max(0, INVENTORY_SLOT_LIMIT - inventory.length)
  const seen = new Set<string>()
  let needed = 0
  for (const grant of leftover) {
    if (grant.quantity <= 0 || seen.has(grant.itemId)) continue
    seen.add(grant.itemId)
    if (mergeableCollectIndex(inventory, grant.itemId) >= 0) continue
    needed += 1
  }
  return { slotsNeeded: Math.max(1, needed), slotsFree }
}

/** `No room in your bag. Free N slot(s) and try again.` — same copy as client `noRoomReason`. */
export function collectNoRoomReason(noRoom: CollectNoRoom): string {
  const short = Math.max(1, noRoom.slotsNeeded - noRoom.slotsFree)
  return `No room in your bag. Free ${short} slot${short === 1 ? '' : 's'} and try again.`
}

/**
 * Empties as much of the box into the save as will fit.
 *
 * Gold always collects. Each item row is taken whole or left in the box.
 * Rows whose item id is not in [catalog] are dropped without granting, so a
 * deleted item cannot re-enter a save through the collection box. [noRoom]
 * describes the leftover item rows when any stay behind.
 */
export function collectRows(
  payload: SavePayload,
  rows: ReadonlyArray<CollectBoxRow | Record<string, unknown>>,
  catalog?: ItemCatalog,
): CollectRowsResult {
  let next = payload
  const taken: string[] = []
  let items = 0
  let gold = 0
  const leftoverItems: Array<{ itemId: string; quantity: number }> = []
  let leftoverOther = 0
  let purseFull = false

  for (const row of rows) {
    const itemId = typeof row.item_id === 'string' ? row.item_id : null
    const quantity = Number(row.quantity ?? 0)
    const coin = Number(row.gold ?? 0)
    if (itemId != null && quantity > 0) {
      if (catalog != null && !catalog.knownIds.has(itemId)) {
        taken.push(String(row.id))
        continue
      }
      const applied = giveItems(next, itemId, quantity)
      if (applied == null) {
        leftoverItems.push({ itemId, quantity })
        continue
      }
      next = applied
      taken.push(String(row.id))
      items += quantity
      continue
    }
    const applied = giveGold(next, coin)
    if (applied == null) {
      leftoverOther += 1
      if (goldOf(next) >= GOLD_CAP) purseFull = true
      continue
    }
    next = applied
    taken.push(String(row.id))
    gold += coin
  }

  return {
    payload: next,
    taken,
    items,
    gold,
    left: leftoverItems.length + leftoverOther,
    rowsLeft: leftoverItems.length,
    noRoom: leftoverItems.length > 0 ? noRoomForCollectRows(next, leftoverItems) : null,
    purseFull,
  }
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
