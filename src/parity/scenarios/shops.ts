import {
  equipCosmetic,
  equippedCosmeticId,
  grantCosmetic,
  isCosmeticUnlocked,
} from '../../game/cosmetics/cosmetics'
import { fieldSellPrice, sellInventoryIndexes, sellPriceAtLocation } from '../../game/inventory/sell'
import type { PlayerSave } from '../../game/save/types'
import { parseShopQuantity } from '../../game/shops/quantity'
import {
  baseSellValue,
  canAccessShop,
  currencyItemId,
  getShop,
  isOreItem,
  playerBuyPrice,
  playerSellPrice,
  shopSellsItem,
  shopStockEntries,
  shopsAtLocation,
} from '../../game/shops/shops'
import { confirmShopOffer, type ShopOffer } from '../../game/shops/transactions'
import { actionsForSkill, projectsForSkill, skillMenuEntries } from '../../game/skills/skillActions'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave } from './saveFixtures'

type SaveKind =
  | 'base'
  | 'bare'
  | 'general'
  | 'mining'
  | 'mining-locked'
  | 'citadel'
  | 'citadel-bare'
  | 'wizard'
  | 'field'

/**
 * Drops the starter outfit a new character owns, so the first-unlock and
 * not-yet-owned paths are reachable from content that ships one cosmetic.
 */
function withoutCosmetics(save: PlayerSave): PlayerSave {
  return { ...save, cosmetics: { unlocked: [], equipped: {} } }
}

/**
 * At the General Store (SHP-0001) with a mix of stacks the counter treats
 * differently: plain sellables, a favorite, an enchanted piece, and currency.
 */
function generalStoreSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Trader',
    gold: 3_000,
    currentLocationId: 'LOC-0024',
    inventory: [
      { itemId: 'ITEM-0003', quantity: 10 },
      { itemId: 'ITEM-0031', quantity: 4, favorite: true },
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001' },
      { itemId: 'ITEM-0025', quantity: 6 },
      { itemId: 'ITEM-0001', quantity: 2 },
    ],
  }
}

/** At the Dwarven Mining Store (SHP-0002), past its Mining 40 gate. */
function miningStoreSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Miner',
    gold: 25_000,
    currentLocationId: 'LOC-0012',
    skills: base.skills.map((skill) =>
      skill.skillId === 'SKL-0002' ? { ...skill, level: 45, xp: 900_000 } : skill,
    ),
    inventory: [
      { itemId: 'ITEM-0005', quantity: 20 },
      { itemId: 'ITEM-0025', quantity: 5 },
    ],
  }
}

/** Standing in the same shop without the Mining level it demands. */
function miningLockedSave(): PlayerSave {
  return { ...miningStoreSave(), characterName: 'Apprentice', skills: baseSave(contentDatabase()).skills }
}

/** In the Market District, where the Market Hall and Supply Stall share a location. */
function citadelSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Citizen',
    gold: 5_000,
    currentLocationId: 'LOC-0029',
    inventory: [{ itemId: 'ITEM-0025', quantity: 3 }],
  }
}

/** At the Wizard's Shop, which sells Essence and buys nothing at all. */
function wizardSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Adept',
    gold: 200_000,
    currentLocationId: 'LOC-0007',
    inventory: [{ itemId: 'ITEM-0025', quantity: 3 }],
  }
}

/** Out in the Town with no shop counter, so sales fall back to the field rate. */
function fieldSave(): PlayerSave {
  const base = baseSave(contentDatabase())
  return {
    ...base,
    characterName: 'Wanderer',
    gold: 40,
    currentLocationId: 'LOC-0002',
    inventory: [
      { itemId: 'ITEM-0005', quantity: 8 },
      { itemId: 'ITEM-0011', quantity: 1 },
    ],
  }
}

function saveFor(kind: SaveKind): PlayerSave {
  if (kind === 'base') return baseSave(contentDatabase())
  if (kind === 'bare') return withoutCosmetics(baseSave(contentDatabase()))
  if (kind === 'general') return generalStoreSave()
  if (kind === 'mining') return miningStoreSave()
  if (kind === 'mining-locked') return miningLockedSave()
  if (kind === 'citadel') return citadelSave()
  if (kind === 'citadel-bare') return withoutCosmetics(citadelSave())
  if (kind === 'wizard') return wizardSave()
  return fieldSave()
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

const SHOP_IDS = ['SHP-0001', 'SHP-0002', 'SHP-0003', 'SHP-0004', 'SHP-0005', 'SHP-9999']
const PRICED_ITEMS = ['ITEM-0001', 'ITEM-0011', 'ITEM-0003', 'ITEM-0025', 'ITEM-0100', 'ITEM-9999']
const SHOP_LOCATIONS = ['LOC-0024', 'LOC-0012', 'LOC-0007', 'LOC-0029', 'LOC-0002']
const MENU_SKILLS = ['SKL-0002', 'SKL-0007', 'SKL-0011', 'SKL-0012', 'SKL-0013', 'SKL-9999']

const QUANTITY_CASES: Array<[string, number | undefined]> = [
  ['1', undefined],
  ['25', undefined],
  ['0', undefined],
  ['-4', undefined],
  ['', undefined],
  ['   ', undefined],
  ['2.5', undefined],
  ['1e3', undefined],
  ['abc', undefined],
  ['007', undefined],
  ['9007199254740993', undefined],
  ['5', 10],
  ['11', 10],
  ['1', 0],
]

const OFFER_CASES: Array<{ name: string; save: SaveKind; shopId: string; offer: ShopOffer }> = [
  {
    name: 'buy-one',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0100', quantity: 2 }], sells: [] },
  },
  {
    name: 'sell-one',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0025', quantity: 4 }] },
  },
  {
    name: 'buy-and-sell',
    save: 'general',
    shopId: 'SHP-0001',
    offer: {
      buys: [{ itemId: 'ITEM-0100', quantity: 1 }],
      sells: [{ itemId: 'ITEM-0003', quantity: 10 }],
    },
  },
  {
    name: 'sell-favorite-blocked',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0031', quantity: 1 }] },
  },
  {
    name: 'sell-enchanted-blocked',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0100', quantity: 1 }] },
  },
  {
    name: 'sell-currency-blocked',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0001', quantity: 1 }] },
  },
  {
    name: 'sell-more-than-owned',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0025', quantity: 999 }] },
  },
  {
    name: 'empty-offer',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [], sells: [] },
  },
  {
    name: 'zero-quantity',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0100', quantity: 0 }], sells: [] },
  },
  {
    name: 'fractional-quantity',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0100', quantity: 2.7 }], sells: [] },
  },
  {
    name: 'unstocked-item',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0295', quantity: 1 }], sells: [] },
  },
  {
    name: 'unknown-shop',
    save: 'general',
    shopId: 'SHP-9999',
    offer: { buys: [{ itemId: 'ITEM-0100', quantity: 1 }], sells: [] },
  },
  {
    name: 'wrong-location',
    save: 'base',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0100', quantity: 1 }], sells: [] },
  },
  {
    name: 'too-expensive',
    save: 'general',
    shopId: 'SHP-0001',
    offer: { buys: [{ itemId: 'ITEM-0108', quantity: 5 }], sells: [] },
  },
  {
    name: 'mining-store-ore',
    save: 'mining',
    shopId: 'SHP-0002',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0005', quantity: 5 }] },
  },
  {
    name: 'mining-store-non-ore',
    save: 'mining',
    shopId: 'SHP-0002',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0025', quantity: 1 }] },
  },
  {
    name: 'mining-store-locked',
    save: 'mining-locked',
    shopId: 'SHP-0002',
    offer: { buys: [{ itemId: 'ITEM-0115', quantity: 1 }], sells: [] },
  },
  {
    name: 'essence-buy',
    save: 'wizard',
    shopId: 'SHP-0003',
    offer: { buys: [{ itemId: 'ITEM-0011', quantity: 1 }], sells: [] },
  },
  {
    name: 'wizard-sell-blocked',
    save: 'wizard',
    shopId: 'SHP-0003',
    offer: { buys: [], sells: [{ itemId: 'ITEM-0025', quantity: 1 }] },
  },
  {
    name: 'cosmetic-purchase',
    save: 'citadel-bare',
    shopId: 'SHP-0004',
    offer: { buys: [{ itemId: 'ITEM-0296', quantity: 1 }], sells: [] },
  },
  {
    name: 'cosmetic-already-owned',
    save: 'citadel',
    shopId: 'SHP-0004',
    offer: { buys: [{ itemId: 'ITEM-0296', quantity: 1 }], sells: [] },
  },
  {
    name: 'cosmetic-duplicate',
    save: 'citadel-bare',
    shopId: 'SHP-0004',
    offer: {
      buys: [
        { itemId: 'ITEM-0296', quantity: 1 },
        { itemId: 'ITEM-0296', quantity: 1 },
      ],
      sells: [],
    },
  },
  {
    name: 'stall-without-facility',
    save: 'citadel',
    shopId: 'SHP-0005',
    offer: { buys: [{ itemId: 'ITEM-0058', quantity: 2 }], sells: [] },
  },
]

const SELL_BAG_CASES: Array<{ name: string; save: SaveKind; indexes: number[] }> = [
  { name: 'ok', save: 'general', indexes: [0, 3] },
  { name: 'favorite-blocked', save: 'general', indexes: [1] },
  { name: 'enchanted-blocked', save: 'general', indexes: [2] },
  { name: 'currency-cannot-sell', save: 'general', indexes: [4] },
  { name: 'out-of-range', save: 'general', indexes: [99, -1, 1.5] },
  { name: 'duplicate-indexes', save: 'general', indexes: [0, 0, 3] },
  { name: 'field-rate', save: 'field', indexes: [0] },
  { name: 'field-currency', save: 'field', indexes: [1] },
  { name: 'mining-rate', save: 'mining', indexes: [0, 1] },
]

export const shopScenarios: ParityScenario[] = [
  scenario('shops/rows', 'stock-and-prices', { source: 'content', shopIds: SHOP_IDS }, () => {
    const db = contentDatabase()
    return {
      currencyItemId: currencyItemId(db),
      shops: db.Shops.map((shop) => ({
        shopId: shop['Shop ID'],
        stock: shopStockEntries(shop),
        buyPrices: PRICED_ITEMS.map((itemId) => playerBuyPrice(db, shop, itemId)),
        sellPrices: PRICED_ITEMS.map((itemId) => playerSellPrice(db, shop, itemId)),
        sellsFirstStock: shopSellsItem(shop, shopStockEntries(shop)[0]?.itemId ?? 'ITEM-9999'),
        sellsUnstocked: shopSellsItem(shop, 'ITEM-9999'),
      })),
      lookups: SHOP_IDS.map((shopId) => getShop(db, shopId)?.['Shop ID'] ?? null),
      baseValues: PRICED_ITEMS.map((itemId) =>
        baseSellValue(db.Items.find((row) => row['Item ID'] === itemId)),
      ),
      ore: db.Items.filter((item) => isOreItem(item)).map((item) => item['Item ID']),
    } as unknown as JsonValue
  }),

  ...(['base', 'general', 'mining', 'mining-locked', 'citadel', 'wizard'] as const).map((kind) =>
    scenario('shops/access', kind, withSave(kind, { locations: SHOP_LOCATIONS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byLocation: SHOP_LOCATIONS.map((locationId) => ({
          locationId,
          shops: shopsAtLocation(db, locationId).map((shop) => ({
            shopId: shop['Shop ID'],
            access: canAccessShop(db, save, shop),
          })),
        })),
      } as unknown as JsonValue
    }),
  ),

  scenario(
    'shops/quantity',
    'parse',
    {
      source: 'content',
      cases: QUANTITY_CASES.map(([raw, max]) => ({ raw, max: max ?? null })),
    },
    () =>
      ({
        results: QUANTITY_CASES.map(([raw, max]) => parseShopQuantity(raw, max)),
      }) as unknown as JsonValue,
  ),

  ...OFFER_CASES.map((entry) =>
    scenario(
      'shops/offer',
      entry.name,
      withSave(entry.save, { shopId: entry.shopId, offer: entry.offer as unknown as JsonValue }),
      () => {
        const result = confirmShopOffer(
          contentDatabase(),
          saveFor(entry.save),
          entry.shopId,
          entry.offer,
        )
        return (result.ok
          ? {
              ok: true,
              save: asJson(result.save),
              goldDelta: result.goldDelta,
              message: result.message,
              cosmeticsGranted: result.cosmeticsGranted,
            }
          : result) as unknown as JsonValue
      },
    ),
  ),

  ...(['general', 'mining', 'wizard', 'field'] as const).map((kind) =>
    scenario('shops/sell-price', kind, withSave(kind, { itemIds: PRICED_ITEMS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        field: PRICED_ITEMS.map((itemId) => fieldSellPrice(db, itemId)),
        atLocation: PRICED_ITEMS.map((itemId) => sellPriceAtLocation(db, save, itemId)),
      } as unknown as JsonValue
    }),
  ),

  ...SELL_BAG_CASES.map((entry) =>
    scenario('shops/sell-bag', entry.name, withSave(entry.save, { indexes: entry.indexes }), () => {
      const result = sellInventoryIndexes(contentDatabase(), saveFor(entry.save), entry.indexes)
      return (result.ok
        ? {
            ok: true,
            save: asJson(result.save),
            goldEarned: result.goldEarned,
            stacksSold: result.stacksSold,
            message: result.message,
          }
        : result) as unknown as JsonValue
    }),
  ),

  ...([
    { name: 'empty-wardrobe', save: 'bare' as const },
    { name: 'starter-owned', save: 'base' as const },
  ]).map((entry) =>
  scenario('cosmetics/wardrobe', entry.name, withSave(entry.save), () => {
    const db = contentDatabase()
    const base = saveFor(entry.save)
    const first = grantCosmetic(base, 'COS-0001')
    const second = grantCosmetic(first.save, 'COS-9999')
    const again = grantCosmetic(second.save, 'COS-0001')
    const equipped = equipCosmetic(db, second.save, 'CSLOT-0001', 'COS-0001')
    return {
      first: { save: asJson(first.save), granted: first.granted, isFirstEver: first.isFirstEver },
      second: { granted: second.granted, isFirstEver: second.isFirstEver },
      again: { granted: again.granted, isFirstEver: again.isFirstEver },
      equipped: equipped.ok ? { ok: true, save: asJson(equipped.save) } : equipped,
      unknownCosmetic: equipCosmetic(db, second.save, 'CSLOT-0001', 'COS-9999'),
      wrongSlot: equipCosmetic(db, second.save, 'CSLOT-0002', 'COS-0001'),
      locked: equipCosmetic(db, base, 'CSLOT-0001', 'COS-0001'),
      unequipped: (() => {
        const result = equipCosmetic(db, equipped.ok ? equipped.save : second.save, 'CSLOT-0001', null)
        return result.ok ? { ok: true, save: asJson(result.save) } : result
      })(),
      unlocked: [
        isCosmeticUnlocked(first.save, 'COS-0001'),
        isCosmeticUnlocked(base, 'COS-0001'),
      ],
      equippedId: [
        equippedCosmeticId(equipped.ok ? equipped.save : base, 'CSLOT-0001'),
        equippedCosmeticId(base, 'CSLOT-0001'),
      ],
    } as unknown as JsonValue
  }),
  ),

  scenario('skills/menu', 'entries', { source: 'content', skillIds: MENU_SKILLS }, () => {
    const db = contentDatabase()
    return {
      bySkill: MENU_SKILLS.map((skillId) => ({
        skillId,
        actions: actionsForSkill(db, skillId),
        projects: projectsForSkill(db, skillId),
        combined: skillMenuEntries(db, skillId).map((entry) => entry.id),
      })),
    } as unknown as JsonValue
  }),
]
