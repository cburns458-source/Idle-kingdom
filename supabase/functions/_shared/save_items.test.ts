// The server's half of the inventory rules, checked against the client's.
//
// `packages/ik_rules/lib/src/inventory` is what runs on the device and is the
// original; this file is here to make sure the copy the Bazaar reaches for did
// not drift from it in the ways that would matter. A server that merged stacks
// differently would hand back a save the client then disagrees with, and a
// server that took an enchanted item would destroy something one of a kind.

import { describe, expect, it } from 'vitest'

import {
  GOLD_CAP,
  GOLD_ITEM_ID,
  INVENTORY_SLOT_LIMIT,
  giveGold,
  giveItems,
  goldOf,
  isItemId,
  isTradableStack,
  stamped,
  takeGold,
  takeItems,
  tradableQuantity,
  type SavePayload,
  type Stack,
} from './save_items.ts'

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
