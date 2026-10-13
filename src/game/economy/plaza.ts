import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { CITADEL_PLAZA_ID } from '../world/constants'

/** Ranked PvP win purse. Replaces the old 1,000 gold payout. */
export const RANKED_PVP_WIN_POINTS = 25

export const PLAZA_SHOP_ID = 'SHP-0011'
export const PLAZA_SHOP_KEY = 'hearthguard_shop'

export const HEARTHGUARD_HELM_ID = 'ITEM-0427'
export const HEARTHGUARD_CUIRASS_ID = 'ITEM-0428'
export const HEARTHGUARD_GREAVES_ID = 'ITEM-0429'
export const HEARTHGUARD_GAUNTLETS_ID = 'ITEM-0430'
export const HEARTHGUARD_BOOTS_ID = 'ITEM-0431'

export const HEARTHGUARD_SET_SIZE = 5
export const HEARTHGUARD_SET_MAX_HP_PERCENT = 10
/** Exact set-bonus copy when all five pieces are worn. */
export const HEARTHGUARD_SET_BONUS_TEXT = 'Hearthguard (5/5): +10% max HP.'

export const PLAZA_SHOP_INSUFFICIENT_POINTS = 'Not enough plaza points.'
export const PLAZA_SHOP_UNKNOWN_ITEM = 'The plaza shop does not sell that item.'
export const PLAZA_SHOP_TRAVEL_FIRST = 'Travel to the Citadel Plaza first.'

export type PlazaShopStockEntry = {
  itemId: string
  points: number
}

/** Server catalog. Client-supplied prices are ignored. */
export const PLAZA_SHOP_STOCK: readonly PlazaShopStockEntry[] = [
  { itemId: HEARTHGUARD_CUIRASS_ID, points: 210 },
  { itemId: HEARTHGUARD_GREAVES_ID, points: 170 },
  { itemId: HEARTHGUARD_HELM_ID, points: 150 },
  { itemId: HEARTHGUARD_GAUNTLETS_ID, points: 120 },
  { itemId: HEARTHGUARD_BOOTS_ID, points: 120 },
]

export const HEARTHGUARD_ITEM_IDS: readonly string[] = [
  HEARTHGUARD_HELM_ID,
  HEARTHGUARD_CUIRASS_ID,
  HEARTHGUARD_GREAVES_ID,
  HEARTHGUARD_GAUNTLETS_ID,
  HEARTHGUARD_BOOTS_ID,
]

export function plazaPointsOf(save: Pick<PlayerSave, 'plazaPoints'> | { plazaPoints?: unknown }): number {
  return Math.max(0, Math.floor(Number((save as { plazaPoints?: unknown }).plazaPoints) || 0))
}

export function plazaShopPrice(itemId: string): number | null {
  const row = PLAZA_SHOP_STOCK.find((entry) => entry.itemId === itemId)
  return row ? row.points : null
}

export function equippedItemIds(save: PlayerSave): string[] {
  const ids: string[] = []
  for (const stack of Object.values(save.equipment?.slots ?? {})) {
    if (stack && typeof stack.itemId === 'string' && stack.itemId.length > 0) {
      ids.push(stack.itemId)
    }
  }
  return ids
}

export function hearthguardEquippedCount(save: PlayerSave): number {
  const worn = new Set(equippedItemIds(save))
  let count = 0
  for (const itemId of HEARTHGUARD_ITEM_IDS) {
    if (worn.has(itemId)) count += 1
  }
  return count
}

export function hearthguardSetBonusText(save: PlayerSave): string | null {
  return hearthguardEquippedCount(save) >= HEARTHGUARD_SET_SIZE ? HEARTHGUARD_SET_BONUS_TEXT : null
}

export function hearthguardSetMaxHpBonusPercent(save: PlayerSave): number {
  return hearthguardEquippedCount(save) >= HEARTHGUARD_SET_SIZE ? HEARTHGUARD_SET_MAX_HP_PERCENT : 0
}

export type PlazaShopPurchaseResult =
  | { ok: true; save: PlayerSave; pointsSpent: number; plazaPoints: number }
  | { ok: false; reason: string }

/**
 * Buy one Hearthguard piece. Catalog price wins; any client `points` / `amount`
 * / `gold` argument is ignored.
 */
export function purchasePlazaShopItem(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
  _clientAmount?: unknown,
): PlazaShopPurchaseResult {
  const price = plazaShopPrice(itemId)
  if (price == null) return { ok: false, reason: PLAZA_SHOP_UNKNOWN_ITEM }
  if (save.currentLocationId !== CITADEL_PLAZA_ID) {
    return { ok: false, reason: PLAZA_SHOP_TRAVEL_FIRST }
  }
  const points = plazaPointsOf(save)
  if (points < price) return { ok: false, reason: PLAZA_SHOP_INSUFFICIENT_POINTS }
  const added = addItemToInventoryExact(save, itemId, 1, null, false, db)
  if (!added.ok) return { ok: false, reason: added.reason }
  const nextPoints = points - price
  return {
    ok: true,
    save: { ...added.save, plazaPoints: nextPoints },
    pointsSpent: price,
    plazaPoints: nextPoints,
  }
}
