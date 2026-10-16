// The server's half of the inventory rules, checked against the client's.
//
// `packages/ik_rules/lib/src/inventory` is what runs on the device and is the
// original; this file is here to make sure the copy the Bazaar reaches for did
// not drift from it in the ways that would matter. A server that merged stacks
// differently would hand back a save the client then disagrees with, and a
// server that took an enchanted item would destroy something one of a kind.

import { describe, expect, it } from 'vitest'

import database from '../../../content/data/game-database.json' with { type: 'json' }
import {
  BOUND_ITEM_REFUSAL,
  GOLD_CAP,
  GOLD_ITEM_ID,
  BANK_SLOT_LIMIT,
  INVENTORY_SLOT_LIMIT,
  UNTRADABLE_ITEM_REFUSAL,
  collectNoRoomReason,
  collectRows,
  giveGold,
  giveItems,
  goldOf,
  isItemId,
  isTradableItem,
  isTradableStack,
  itemCatalog,
  itemRefusal,
  stamped,
  takeGold,
  takeItems,
  tradableQuantity,
  type SavePayload,
  type Stack,
} from './save_items.ts'

// The same file `tools/bundle_game_edge.sh` copies to `_shared/game-database.json`
// for the deployed function.
const CATALOG = itemCatalog(database)

const MACHETE = 'ITEM-0406'
const EXCAVATORS_PICKAXE = 'ITEM-0313'
const STOLEN_COIN_PURSE = 'ITEM-0299'
const BEGGARS_HOOD = 'ITEM-0300'
const DWARVEN_WARHAMMER = 'ITEM-0123'
const HEARTHGUARD_HELM = 'ITEM-0427'
const HEARTHGUARD_CUIRASS = 'ITEM-0428'
const HEARTHGUARD_GREAVES = 'ITEM-0429'
const HEARTHGUARD_GAUNTLETS = 'ITEM-0430'
const HEARTHGUARD_BOOTS = 'ITEM-0431'
const GOLDEN_SPUD = 'ITEM-0026'
const CHEFS_HAT = 'ITEM-0165'
const PIRATE_INSIGNIA = 'ITEM-0288'
const IRON_ORE = 'ITEM-0005'

function save(inventory: Stack[], gold = 0): SavePayload {
  return { saveVersion: 7, updatedAt: '2026-01-01T00:00:00.000Z', gold, inventory }
}

/// The bag as it would be stored, not as `inventoryOf` reads it: what matters is
/// the JSON the client gets back, and an absent flag is not a null one.
function stacks(payload: SavePayload | null): unknown {
  expect(payload).not.toBeNull()
  return payload!.inventory
}

describe('what may be listed', () => {
  it('takes a plain stack', () => {
    expect(isTradableStack({ itemId: 'ITEM-0100', quantity: 4 })).toBe(true)
  })

  it('leaves gold, enchanted items, and favourites alone', () => {
    expect(isTradableStack({ itemId: GOLD_ITEM_ID, quantity: 500 })).toBe(false)
    expect(isTradableStack({ itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' })).toBe(
      false,
    )
    expect(isTradableStack({ itemId: 'ITEM-0100', quantity: 9, favorite: true })).toBe(false)
  })

  it('counts only the stacks it would take', () => {
    const payload = save([
      { itemId: 'ITEM-0100', quantity: 10 },
      { itemId: 'ITEM-0100', quantity: 5, favorite: true },
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' },
      { itemId: 'ITEM-0100', quantity: 7 },
    ])
    expect(tradableQuantity(payload, 'ITEM-0100')).toBe(17)
  })

  it('knows an item id when it sees one', () => {
    expect(isItemId('ITEM-0100')).toBe(true)
    expect(isItemId('ITEM-1')).toBe(false)
    expect(isItemId('SHOP-0001')).toBe(false)
    expect(isItemId(null)).toBe(false)
  })
})

describe('items the exchange will not carry', () => {
  it('reads the quest-only rewards as untradeable from the database', () => {
    expect([...CATALOG.untradeable].sort()).toEqual(
      [
        EXCAVATORS_PICKAXE,
        MACHETE,
        STOLEN_COIN_PURSE,
        BEGGARS_HOOD,
        DWARVEN_WARHAMMER,
        HEARTHGUARD_HELM,
        HEARTHGUARD_CUIRASS,
        HEARTHGUARD_GREAVES,
        HEARTHGUARD_GAUNTLETS,
        HEARTHGUARD_BOOTS,
      ].sort(),
    )
    expect(isTradableItem(MACHETE, CATALOG)).toBe(false)
    expect(isTradableItem(GOLDEN_SPUD, CATALOG)).toBe(true)
    // Without a catalog nothing is bound, as before the column existed.
    expect(isTradableItem(MACHETE)).toBe(true)
  })

  it('refuses a stack of an untradeable item', () => {
    expect(isTradableStack({ itemId: MACHETE, quantity: 1 }, CATALOG)).toBe(false)
    expect(isTradableStack({ itemId: EXCAVATORS_PICKAXE, quantity: 1 }, CATALOG)).toBe(false)
    expect(isTradableStack({ itemId: STOLEN_COIN_PURSE, quantity: 1 }, CATALOG)).toBe(false)
    expect(isTradableStack({ itemId: BEGGARS_HOOD, quantity: 1 }, CATALOG)).toBe(false)
    expect(isTradableStack({ itemId: GOLDEN_SPUD, quantity: 1 }, CATALOG)).toBe(true)
  })

  it('refuses sell and buy orders for Machete and Excavator’s Pickaxe with the bound copy', () => {
    // The refusal is side-independent and runs before the save is read, so a
    // buy order is turned away exactly like a sell order.
    expect(itemRefusal(MACHETE, CATALOG)).toBe(BOUND_ITEM_REFUSAL)
    expect(itemRefusal(EXCAVATORS_PICKAXE, CATALOG)).toBe(BOUND_ITEM_REFUSAL)
    expect(BOUND_ITEM_REFUSAL).toBe("That stays with you; it can't be traded.")
  })

  it('keeps Golden spud, Chef’s Hat, and Pirate insignia on the exchange', () => {
    expect(itemRefusal(GOLDEN_SPUD, CATALOG)).toBeNull()
    expect(itemRefusal(CHEFS_HAT, CATALOG)).toBeNull()
    expect(itemRefusal(PIRATE_INSIGNIA, CATALOG)).toBeNull()
    expect(itemRefusal(IRON_ORE, CATALOG)).toBeNull()
  })

  it('checks Base Sell Value the way the client does', () => {
    expect(itemRefusal(GOLD_ITEM_ID, CATALOG)).toBe(UNTRADABLE_ITEM_REFUSAL)
    expect(itemRefusal('ITEM-9999', CATALOG)).toBe(UNTRADABLE_ITEM_REFUSAL)
    // The Undying: a starter title worth nothing, so a shop would not price it.
    expect(itemRefusal('ITEM-0301', CATALOG)).toBe(UNTRADABLE_ITEM_REFUSAL)
    const catalog = itemCatalog({
      Items: [
        { 'Item ID': 'ITEM-0100', 'Base Sell Value': 0, 'Release Phase': 'Launch' },
        { 'Item ID': 'ITEM-0101', 'Base Sell Value': null, 'Release Phase': 'Launch' },
        { 'Item ID': 'ITEM-0102', 'Base Sell Value': 5, 'Release Phase': 'Post-Launch' },
        { 'Item ID': 'ITEM-0103', 'Base Sell Value': 5, 'Release Phase': 'Launch' },
        { 'Item ID': 'ITEM-0104', 'Base Sell Value': 5, 'Release Phase': 'Launch', Tradeable: '' },
        { 'Item ID': 'ITEM-0105', 'Base Sell Value': 5, 'Release Phase': 'Launch', Tradeable: null },
      ],
    })
    expect(itemRefusal('ITEM-0100', catalog)).toBe(UNTRADABLE_ITEM_REFUSAL)
    expect(itemRefusal('ITEM-0101', catalog)).toBe(UNTRADABLE_ITEM_REFUSAL)
    expect(itemRefusal('ITEM-0102', catalog)).toBe(UNTRADABLE_ITEM_REFUSAL)
    expect(itemRefusal('ITEM-0103', catalog)).toBeNull()
    expect(itemRefusal('ITEM-0104', catalog)).toBeNull()
    expect(itemRefusal('ITEM-0105', catalog)).toBeNull()
  })

  it('takes nothing out of the bag for a forged Machete listing', () => {
    // A request that skipped the client check still reaches escrow only through
    // these, and they leave the stored save alone.
    const payload = save([{ itemId: MACHETE, quantity: 1 }], 500)
    expect(tradableQuantity(payload, MACHETE, CATALOG)).toBe(0)
    expect(takeItems(payload, MACHETE, 1, CATALOG)).toBeNull()
    expect(payload.inventory).toEqual([{ itemId: MACHETE, quantity: 1 }])
    expect(payload.gold).toBe(500)
  })
})

describe('taking items out for an offer', () => {
  it('empties the first stack before the second', () => {
    const payload = takeItems(
      save([
        { itemId: 'ITEM-0100', quantity: 10 },
        { itemId: 'ITEM-0100', quantity: 7 },
      ]),
      'ITEM-0100',
      12,
    )
    expect(stacks(payload)).toEqual([{ itemId: 'ITEM-0100', quantity: 5 }])
  })

  it('drops a stack it empties rather than leaving a zero behind', () => {
    const payload = takeItems(save([{ itemId: 'ITEM-0100', quantity: 3 }]), 'ITEM-0100', 3)
    expect(stacks(payload)).toEqual([])
  })

  it('refuses when only untradable stacks would make up the number', () => {
    const payload = save([
      { itemId: 'ITEM-0100', quantity: 2 },
      { itemId: 'ITEM-0100', quantity: 40, favorite: true },
    ])
    expect(takeItems(payload, 'ITEM-0100', 10)).toBeNull()
  })

  it('leaves the favourite and the enchanted stack where they are', () => {
    const payload = takeItems(
      save([
        { itemId: 'ITEM-0100', quantity: 4, favorite: true },
        { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' },
        { itemId: 'ITEM-0100', quantity: 6 },
      ]),
      'ITEM-0100',
      6,
    )
    expect(stacks(payload)).toEqual([
      { itemId: 'ITEM-0100', quantity: 4, favorite: true },
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' },
    ])
  })

  it('never touches the bank, which is what makes withdrawing first a rule', () => {
    const payload: SavePayload = {
      ...save([]),
      bank: [{ itemId: 'ITEM-0100', quantity: 900 }],
    }
    expect(tradableQuantity(payload, 'ITEM-0100')).toBe(0)
    expect(takeItems(payload, 'ITEM-0100', 1)).toBeNull()
  })
})

describe('putting items back from the box', () => {
  it('merges into a plain stack of the same item', () => {
    const payload = giveItems(save([{ itemId: 'ITEM-0100', quantity: 4 }]), 'ITEM-0100', 6)
    expect(stacks(payload)).toEqual([{ itemId: 'ITEM-0100', quantity: 10 }])
  })

  it('prefers the favourited pile, as the client does', () => {
    const payload = giveItems(
      save([
        { itemId: 'ITEM-0100', quantity: 1 },
        { itemId: 'ITEM-0100', quantity: 2, favorite: true },
      ]),
      'ITEM-0100',
      5,
    )
    expect(stacks(payload)).toEqual([
      { itemId: 'ITEM-0100', quantity: 1 },
      { itemId: 'ITEM-0100', quantity: 7, favorite: true },
    ])
  })

  it('never merges into an enchanted stack', () => {
    const payload = giveItems(
      save([{ itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' }]),
      'ITEM-0100',
      3,
    )
    expect(stacks(payload)).toEqual([
      { itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENC-0001' },
      { itemId: 'ITEM-0100', quantity: 3 },
    ])
  })

  it('uses the bag slot cap of 84', () => {
    expect(INVENTORY_SLOT_LIMIT).toBe(84)
    expect(BANK_SLOT_LIMIT).toBe(168)
  })

  it('refuses a new stack when the bag is out of slots', () => {
    const full = save(
      Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, at) => ({
        itemId: `ITEM-${String(at + 1000)}`,
        quantity: 1,
      })),
    )
    expect(giveItems(full, 'ITEM-9999', 1)).toBeNull()
    // A full bag can still take more of something it already holds.
    expect(giveItems(full, 'ITEM-1000', 1)).not.toBeNull()
  })
})

describe('collection box rows', () => {
  const full = save(
    Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, at) => ({
      itemId: `ITEM-${String(at + 1000)}`,
      quantity: 1,
    })),
    10,
  )

  it('refuses when no item row fits and reports no_room', () => {
    const result = collectRows(full, [
      { id: 'row-1', item_id: 'ITEM-9999', quantity: 2, gold: 0 },
    ])
    expect(result.taken).toEqual([])
    expect(result.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
    expect(result.rowsLeft).toBe(1)
    expect(collectNoRoomReason(result.noRoom!)).toMatch(/Free 1 slot/)
  })

  it('always collects gold and leaves item rows with no_room', () => {
    const result = collectRows(full, [
      { id: 'gold-1', gold: 25 },
      { id: 'row-1', item_id: 'ITEM-9999', quantity: 1, gold: 0 },
    ])
    expect(result.taken).toEqual(['gold-1'])
    expect(result.gold).toBe(25)
    expect(result.items).toBe(0)
    expect(result.left).toBe(1)
    expect(result.rowsLeft).toBe(1)
    expect(result.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
    expect(goldOf(result.payload)).toBe(35)
  })

  it('collects a row that merges and leaves the rest with rowsLeft', () => {
    const result = collectRows(full, [
      { id: 'merge', item_id: 'ITEM-1000', quantity: 3, gold: 0 },
      { id: 'new', item_id: 'ITEM-9999', quantity: 1, gold: 0 },
    ])
    expect(result.taken).toEqual(['merge'])
    expect(result.items).toBe(3)
    expect(result.left).toBe(1)
    expect(result.rowsLeft).toBe(1)
    expect(result.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
  })

  it('drops rows whose item id is gone from the catalog, without granting them', () => {
    expect(CATALOG.knownIds.has(IRON_ORE)).toBe(true)
    expect(CATALOG.knownIds.has('ITEM-0135')).toBe(false)
    expect(CATALOG.knownIds.has('ITEM-0290')).toBe(false)
    const held = save([{ itemId: IRON_ORE, quantity: 10 }])
    const result = collectRows(
      held,
      [
        { id: 'bow', item_id: 'ITEM-0135', quantity: 1, gold: 0 },
        { id: 'binding', item_id: 'ITEM-0290', quantity: 2, gold: 0 },
        { id: 'ore', item_id: IRON_ORE, quantity: 3, gold: 0 },
      ],
      CATALOG,
    )
    expect(result.taken).toEqual(['bow', 'binding', 'ore'])
    expect(result.items).toBe(3)
    expect(result.left).toBe(0)
    expect(result.noRoom).toBeNull()
    expect(stacks(result.payload)).toEqual([{ itemId: IRON_ORE, quantity: 13 }])
  })

  it('consumes unknown collection rows even when the bag is full', () => {
    const result = collectRows(
      full,
      [{ id: 'bow', item_id: 'ITEM-0135', quantity: 1, gold: 0 }],
      CATALOG,
    )
    expect(result.taken).toEqual(['bow'])
    expect(result.items).toBe(0)
    expect(result.left).toBe(0)
    expect(result.noRoom).toBeNull()
    expect(stacks(result.payload)).toEqual(full.inventory)
  })
})

describe('gold', () => {
  it('takes what is there and refuses what is not', () => {
    expect(goldOf(takeGold(save([], 500), 200)!)).toBe(300)
    expect(takeGold(save([], 100), 101)).toBeNull()
  })

  it('will not put a save over the ceiling a cloud save is checked against', () => {
    expect(goldOf(giveGold(save([], GOLD_CAP - 10), 10)!)).toBe(GOLD_CAP)
    expect(giveGold(save([], GOLD_CAP - 10), 11)).toBeNull()
  })
})

describe('the rest of the save', () => {
  it('is carried through untouched, so nothing else is lost on the way', () => {
    const payload: SavePayload = {
      ...save([{ itemId: 'ITEM-0100', quantity: 5 }], 40),
      currentLocationId: 'LOC-0001',
      skills: [{ skillId: 'SKL-0001', xp: 1234 }],
    }
    const next = stamped(takeItems(takeGold(payload, 10)!, 'ITEM-0100', 5)!, '2026-02-02T00:00:00.000Z')
    expect(next.currentLocationId).toBe('LOC-0001')
    expect(next.skills).toEqual([{ skillId: 'SKL-0001', xp: 1234 }])
    expect(next.saveVersion).toBe(7)
    expect(next.updatedAt).toBe('2026-02-02T00:00:00.000Z')
    expect(next.gold).toBe(30)
  })
})
