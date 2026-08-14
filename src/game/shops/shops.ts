import { getSkillProgress } from '../activity/xp'
import { requirementsForEntity, unmetHardRequirements } from '../activity/requirements'
import { cosmeticByItemId, isCosmeticUnlocked } from '../cosmetics/cosmetics'
import type { GameDatabase, ItemRow, ShopRow } from '../data/types'
import type { PlayerSave } from '../save/types'

export const ESSENCE_ITEM_ID = 'ITEM-0011'
export const SHOP_BUY_MULT = 2
export const ESSENCE_BUY_MULT = 100
export const MINING_ORE_SELL_MULT = 1.5
export const GENERAL_SELL_MULT = 1

export interface ShopStockEntry {
  itemId: string
  /** Shop sells this item to the player. */
  mode: 'Sell'
}

export function currencyItemId(db: GameDatabase): string {
  const raw = db.Config.find((row) => row.Key === 'currency_item_id')?.Value
  return typeof raw === 'string' && raw.length > 0 ? raw : 'ITEM-0001'
}

export function shopStockEntries(shop: ShopRow): ShopStockEntry[] {
  const record = shop as ShopRow & Record<string, unknown>
  const out: ShopStockEntry[] = []
  for (let i = 1; i <= 40; i += 1) {
    const itemId = record[`Entry ${i} Item ID`]
    const mode = record[`Entry ${i} Mode`]
    if (typeof itemId !== 'string' || itemId.length === 0) continue
    if (typeof mode === 'string' && mode.toLowerCase() === 'buy') continue
    out.push({ itemId, mode: 'Sell' })
  }
  return out
}

export function getShop(db: GameDatabase, shopId: string): ShopRow | undefined {
  return db.Shops.find((shop) => shop['Shop ID'] === shopId)
}

export function shopsAtLocation(db: GameDatabase, locationId: string): ShopRow[] {
  return db.Shops.filter((shop) => shop['Location ID'] === locationId)
}

export function shopFacility(db: GameDatabase, shop: ShopRow) {
  return db.Facilities.find(
    (facility) =>
      facility['Location ID'] === shop['Location ID'] &&
      facility['Facility Type'] === 'Shop' &&
      (facility['Internal Key'] === shop['Internal Key'] ||
        facility['Display Name'] === shop['Display Name']),
  )
}

export function canAccessShop(
  db: GameDatabase,
  save: PlayerSave,
  shop: ShopRow,
): { ok: true } | { ok: false; reason: string } {
  if (shop['Location ID'] !== save.currentLocationId) {
    return { ok: false, reason: 'Travel to this shop first.' }
  }
  const facility = shopFacility(db, shop)
  if (!facility) return { ok: true }
  const unmet = unmetHardRequirements(
    db,
    save,
    requirementsForEntity(db, 'Facility', facility['Facility ID']),
  )
  if (unmet.length > 0) {
    const mining = getSkillProgress(save, 'SKL-0002').level
    if (facility['Facility ID'] === 'FAC-0009') {
      return { ok: false, reason: `Requires Mining level 40 (have ${mining}).` }
    }
    return { ok: false, reason: unmet[0] ?? 'Requirements not met.' }
  }
  return { ok: true }
}

export function baseSellValue(item: ItemRow | undefined): number | null {
  if (!item) return null
  const value = item['Base Sell Value']
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return null
  return value
}

/** Price the player pays to buy one unit from the shop. */
export function playerBuyPrice(db: GameDatabase, _shop: ShopRow, itemId: string): number | null {
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  const base = baseSellValue(item)
  if (base == null) return null
  if (itemId === ESSENCE_ITEM_ID) return Math.round(base * ESSENCE_BUY_MULT)
  return Math.round(base * SHOP_BUY_MULT)
}

export function isOreItem(item: ItemRow): boolean {
  const subtype = (item.Subtype ?? '').toLowerCase()
  const tags = String(item['Functional / Source Tags'] ?? '').toLowerCase()
  const name = item['Display Name'].toLowerCase()
  return subtype === 'ore' || tags.includes('ore') || name.endsWith(' ore')
}

/** Price the shop pays the player for one unit. Null = shop will not buy it. */
export function playerSellPrice(
  db: GameDatabase,
  shop: ShopRow,
  itemId: string,
): number | null {
  if (itemId === currencyItemId(db)) return null
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  const base = baseSellValue(item)
  if (base == null || base <= 0) return null

  const key = shop['Internal Key']
  if (key === 'dwarven_mining_store') {
    if (!item || !isOreItem(item)) return null
    return Math.round(base * MINING_ORE_SELL_MULT)
  }
  if (key === 'wizards_shop') {
    return null
  }
  // General store buys ordinary items at Base Sell Value.
  return Math.round(base * GENERAL_SELL_MULT)
}

export function shopSellsItem(shop: ShopRow, itemId: string): boolean {
  return shopStockEntries(shop).some((entry) => entry.itemId === itemId)
}

/** Stock the player can still buy — owned cosmetics stay off the counter. */
export function shopStockForPlayer(db: GameDatabase, save: PlayerSave, shop: ShopRow): ShopStockEntry[] {
  return shopStockEntries(shop).filter((entry) => {
    const cosmetic = cosmeticByItemId(db, entry.itemId)
    if (!cosmetic) return true
    return !isCosmeticUnlocked(save, cosmetic['Cosmetic ID'])
  })
}
