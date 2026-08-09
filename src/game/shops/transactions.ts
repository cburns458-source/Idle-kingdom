import { addItemToInventoryExact } from '../activity/rewards'
import { canFitItemQuantity } from '../inventory/capacity'
import { removeIngredients } from '../production/inventory'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import {
  canAccessShop,
  getShop,
  playerBuyPrice,
  playerSellPrice,
  shopSellsItem,
} from './shops'

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
    }
  | { ok: false; reason: string }

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
): ShopTransactionResult {
  const shop = getShop(db, shopId)
  if (!shop) return { ok: false, reason: 'Shop not found.' }

  const access = canAccessShop(db, save, shop)
  if (!access.ok) return access

  const buys = offer.buys ?? []
  const sells = offer.sells ?? []
  if (buys.length === 0 && sells.length === 0) {
    return { ok: false, reason: 'Add items to the offer first.' }
  }

  for (const line of buys) {
    if (!shopSellsItem(shop, line.itemId)) {
      return { ok: false, reason: 'The shop does not sell that item.' }
    }
  }

  const buyCost = lineTotal(buys, (itemId) => playerBuyPrice(db, shop, itemId))
  if (!buyCost.ok) return buyCost
  const sellCredit = lineTotal(sells, (itemId) => playerSellPrice(db, shop, itemId))
  if (!sellCredit.ok) return sellCredit

  const goldDelta = sellCredit.total - buyCost.total
  if (save.gold + goldDelta < 0) {
    return { ok: false, reason: 'Not enough gold for this purchase.' }
  }

  let next = save
  if (sells.length > 0) {
    const removed = removeIngredients(
      next,
      sells.map((line) => ({ itemId: line.itemId, quantity: Math.floor(line.quantity) })),
      1,
    )
    if (!removed) return { ok: false, reason: 'Missing items to sell.' }
    next = removed
  }

  next = { ...next, gold: next.gold + goldDelta }

  // Validate bag space after sells free slots, before committing buys.
  let spaceCheck = next
  for (const line of buys) {
    const qty = Math.floor(line.quantity)
    if (!canFitItemQuantity(spaceCheck, line.itemId, qty)) {
      return { ok: false, reason: 'Not enough inventory space (180 slots).' }
    }
    const staged = addItemToInventoryExact(spaceCheck, line.itemId, qty)
    if (!staged.ok) return { ok: false, reason: staged.reason }
    spaceCheck = staged.save
  }
  next = spaceCheck

  if (sellCredit.total > 0) {
    const earned = Number(next.statistics.values.gold_earned ?? 0) + sellCredit.total
    next = {
      ...next,
      statistics: {
        values: {
          ...next.statistics.values,
          gold_earned: earned,
        },
      },
    }
  }

  const parts: string[] = []
  if (buyCost.total > 0) parts.push(`spent ${buyCost.total.toLocaleString()} gold`)
  if (sellCredit.total > 0) parts.push(`received ${sellCredit.total.toLocaleString()} gold`)
  return {
    ok: true,
    save: next,
    goldDelta,
    message: parts.length > 0 ? `Trade complete — ${parts.join(', ')}.` : 'Trade complete.',
  }
}
