import { recordItemsSoldAtLocation } from '../achievements/progress'
import { addItemToInventoryExact } from '../activity/rewards'
import { grantCosmetic } from '../cosmetics/cosmetics'
import { applyQuestAutoStartOnSeed } from '../quests/progress'
import { noRoomFor, noRoomRefusal, type NoRoom } from '../inventory/fit'
import { isFavoriteStack } from '../inventory/favorites'
import type { GameDatabase } from '../data/types'
import type { InventoryStack, PlayerSave } from '../save/types'
import {
  canAccessShop,
  getShop,
  isPlazaShop,
  playerBuyPrice,
  playerSellPrice,
  recordShopPurchases,
  shopEnchantedSellMode,
  shopRemainingToday,
  shopSellsItem,
  syncShopPurchaseDay,
  type ShopEnchantedSellMode,
} from './shops'

/** Cosmetic ID(s) newly granted by a shop purchase (for the Wardrobe-unlock popup). */
export interface ShopCosmeticGrant {
  cosmeticId: string
  isFirstEver: boolean
}

export interface ShopOfferLine {
  itemId: string
  quantity: number
}

export interface ShopOffer {
  buys: ShopOfferLine[]
  sells: ShopOfferLine[]
}

export type ShopTransactionResult =
  | {
      ok: true
      save: PlayerSave
      goldDelta: number
      message: string
      cosmeticsGranted: ShopCosmeticGrant[]
    }
  | { ok: false; reason: string; code?: 'no_room'; noRoom?: NoRoom }

/**
 * A shop offer quantity must be a positive safe integer. Rejects non-numbers,
 * NaN, Infinity, fractions, 0, negatives and values above MAX_SAFE_INTEGER.
 * Mirrors `isValidOfferQuantity` in ik_rules (Dart).
 */
export function isValidOfferQuantity(quantity: unknown): quantity is number {
  return typeof quantity === 'number' && Number.isSafeInteger(quantity) && quantity >= 1
}

function lineTotal(
  lines: ShopOfferLine[],
  unitPrice: (itemId: string) => number | null,
): { ok: true; total: number } | { ok: false; reason: string } {
  let total = 0
  for (const line of lines) {
    const qty = Math.floor(line.quantity)
    if (qty <= 0) return { ok: false, reason: 'Offer quantities must be at least 1.' }
    const price = unitPrice(line.itemId)
    if (price == null) return { ok: false, reason: 'That item cannot be traded here.' }
    total += price * qty
  }
  return { ok: true, total }
}

/** Confirm a buy/sell offer against a shop. Buys = shop→player, sells = player→shop. */
export function confirmShopOffer(
  db: GameDatabase,
  save: PlayerSave,
  shopId: string,
  offer: ShopOffer,
  nowMs: number = Date.now(),
): ShopTransactionResult {
  const shop = getShop(db, shopId)
  if (!shop) return { ok: false, reason: 'Shop not found.' }
  if (isPlazaShop(shop)) {
    return { ok: false, reason: 'Buy this with plaza points.' }
  }

  const access = canAccessShop(db, save, shop)
  if (!access.ok) return access

  const rawBuys: unknown = offer?.buys ?? []
  const rawSells: unknown = offer?.sells ?? []
  if (!Array.isArray(rawBuys) || !Array.isArray(rawSells)) {
    return { ok: false, reason: 'Add items to the offer first.' }
  }
  const buys = rawBuys as ShopOfferLine[]
  const sells = rawSells as ShopOfferLine[]
  if (buys.length === 0 && sells.length === 0) {
    return { ok: false, reason: 'Add items to the offer first.' }
  }
  for (const line of [...buys, ...sells]) {
    if (!line || typeof line !== 'object' || typeof line.itemId !== 'string') {
      return { ok: false, reason: 'That item cannot be traded here.' }
    }
    if (!isValidOfferQuantity(line.quantity)) {
      return { ok: false, reason: 'Offer quantities must be at least 1.' }
    }
  }

  let next = syncShopPurchaseDay(save, nowMs)
  const reserved = new Map<string, number>()
  for (const line of buys) {
    if (!shopSellsItem(shop, line.itemId)) {
      return { ok: false, reason: 'The shop does not sell that item.' }
    }
    const remaining = shopRemainingToday(next, shop, line.itemId, nowMs)
    if (remaining == null) continue
    const already = reserved.get(line.itemId) ?? 0
    const qty = Math.floor(line.quantity)
    if (already + qty > remaining) {
      const left = Math.max(0, remaining - already)
      return {
        ok: false,
        reason:
          left <= 0
            ? 'That item is sold out for today.'
            : `Only ${left} left in today's stock.`,
      }
    }
    reserved.set(line.itemId, already + qty)
  }

  const buyCost = lineTotal(buys, (itemId) => playerBuyPrice(db, shop, itemId))
  if (!buyCost.ok) return buyCost
  const enchantedMode = shopEnchantedSellMode(shop)
  const sellCredit = lineTotal(sells, (itemId) => {
    // Wizard's counter only prices enchanted gear, and only when the bag has it.
    // Generals use the plain rate for both (same Base Sell Value either way).
    if (enchantedMode === 'enchantedOnly') {
      const hasEnchanted = next.inventory.some(
        (stack) =>
          stack.itemId === itemId &&
          !isFavoriteStack(stack) &&
          Boolean(stack.enchantmentId && String(stack.enchantmentId).trim()),
      )
      if (!hasEnchanted) return null
      return playerSellPrice(db, shop, itemId, { enchanted: true })
    }
    return playerSellPrice(db, shop, itemId)
  })
  if (!sellCredit.ok) return sellCredit

  const goldDelta = sellCredit.total - buyCost.total
  if (next.gold + goldDelta < 0) {
    return { ok: false, reason: 'Not enough gold for this purchase.' }
  }

  if (sells.length > 0) {
    const removed = removeSellableInventory(next, sells, enchantedMode)
    if (!removed) {
      return {
        ok: false,
        reason: 'Missing items to sell (favorited items cannot be sold).',
      }
    }
    next = removed
  }

  next = { ...next, gold: next.gold + goldDelta }

  // Validate bag space after sells free slots, before committing buys.
  // Cosmetics bypass the bag entirely — they're unlocked into the Wardrobe's
  // always-owned collection instead, so they never need inventory space.
  const itemBuys = buys.filter((line) => !db.Cosmetics.some((row) => row['Item ID'] === line.itemId))
  const blocked = noRoomFor(
    next,
    itemBuys.map((line) => ({ itemId: line.itemId, quantity: Math.floor(line.quantity) })),
    db,
  )
  if (blocked) return noRoomRefusal(blocked)

  let spaceCheck = next
  const cosmeticGrants: ShopCosmeticGrant[] = []
  for (const line of buys) {
    const qty = Math.floor(line.quantity)
    const cosmetic = db.Cosmetics.find((row) => row['Item ID'] === line.itemId)
    if (cosmetic) {
      const granted = grantCosmetic(spaceCheck, cosmetic['Cosmetic ID'])
      spaceCheck = granted.save
      if (granted.granted) {
        cosmeticGrants.push({ cosmeticId: cosmetic['Cosmetic ID'], isFirstEver: granted.isFirstEver })
      }
      continue
    }
    const staged = addItemToInventoryExact(spaceCheck, line.itemId, qty)
    if (!staged.ok) return { ok: false, reason: staged.reason }
    spaceCheck = staged.save
  }
  next = spaceCheck

  if (sells.length > 0) {
    const shopLocation = String(shop['Location ID'] ?? save.currentLocationId)
    next = recordItemsSoldAtLocation(next, sells, shopLocation)
  }
  if (buys.length > 0) {
    next = recordShopPurchases(next, shopId, buys, nowMs)
    next = applyQuestAutoStartOnSeed(db, next)
  }

  const parts: string[] = []
  if (buyCost.total > 0) parts.push(`spent ${buyCost.total.toLocaleString()} gold`)
  if (sellCredit.total > 0) parts.push(`received ${sellCredit.total.toLocaleString()} gold`)
  return {
    ok: true,
    save: next,
    goldDelta,
    message: parts.length > 0 ? `Trade complete — ${parts.join(', ')}.` : 'Trade complete.',
    cosmeticsGranted: cosmeticGrants,
  }
}

function stackIsEnchanted(stack: InventoryStack): boolean {
  return Boolean(stack.enchantmentId && String(stack.enchantmentId).trim())
}

/**
 * Removes sold quantities from bag stacks this shop will take.
 * Favorites are always skipped. Enchanted stacks follow `mode`.
 */
function removeSellableInventory(
  save: PlayerSave,
  sells: ShopOfferLine[],
  mode: ShopEnchantedSellMode,
): PlayerSave | null {
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  for (const line of sells) {
    let need = Math.floor(line.quantity)
    if (need <= 0) return null

    const takeFrom = (accept: (stack: InventoryStack) => boolean) => {
      for (const stack of inventory) {
        if (need <= 0) return
        if (stack.itemId !== line.itemId) continue
        if (isFavoriteStack(stack) || !accept(stack)) continue
        const take = Math.min(stack.quantity, need)
        stack.quantity -= take
        need -= take
      }
    }

    if (mode === 'reject') {
      takeFrom((stack) => !stackIsEnchanted(stack))
    } else if (mode === 'preferPlain') {
      takeFrom((stack) => !stackIsEnchanted(stack))
      if (need > 0) takeFrom(stackIsEnchanted)
    } else {
      takeFrom(stackIsEnchanted)
    }
    if (need > 0) return null
  }
  return {
    ...save,
    inventory: inventory.filter((stack) => stack.quantity > 0),
  }
}
