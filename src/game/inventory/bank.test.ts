import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { BANK_SLOT_LIMIT, INVENTORY_SLOT_LIMIT } from './capacity'
import {
  depositToBank,
  locationHasBank,
  stackIsUnbankableGold,
  withBankDepositBoxActivities,
  withdrawFromBank,
} from './bank'
import { GOLD_ITEM_ID } from './gold'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('bank storage', () => {
  const { launch, launchIndexes } = prepareDatabase(rawDatabase)

  it('is at Town Bank, Citadel Bank, and any future *_bank location', () => {
    const byId = launchIndexes.locationsById
    expect(locationHasBank(byId.get('LOC-0034'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0035'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0002'))).toBe(false)
    expect(locationHasBank(byId.get('LOC-0013'))).toBe(false)
    expect(locationHasBank(byId.get('LOC-0027'))).toBe(false)
    expect(locationHasBank(byId.get('LOC-0024'))).toBe(false)
    expect(locationHasBank(byId.get('LOC-0009'))).toBe(false)
    expect(locationHasBank(undefined)).toBe(false)
    const westBank = {
      ...byId.get('LOC-0034')!,
      'Location ID': 'LOC-9999',
      'Internal Key': 'west_bank',
      'Display Name': 'West Bank',
    }
    expect(locationHasBank(westBank)).toBe(true)

    const withFuture = withBankDepositBoxActivities({
      ...launch,
      Locations: [...launch.Locations, westBank],
    })
    expect(
      withFuture.Activities.some(
        (row) => row['Pool ID'] === 'POOL-0047' && row['Location ID'] === 'LOC-9999',
      ),
    ).toBe(true)
  })

  it('exposes deposit-box thievery at every bank location', () => {
    const depositActs = launch.Activities.filter((row) => row['Pool ID'] === 'POOL-0047')
    const bankLocs = launch.Locations.filter((row) => locationHasBank(row)).map(
      (row) => row['Location ID'],
    )
    for (const locId of bankLocs) {
      expect(depositActs.some((row) => row['Location ID'] === locId)).toBe(true)
    }
  })

  it('deposits and withdraws stacks, and refuses gold', () => {
    let save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: 5 }],
      bank: [] as { itemId: string; quantity: number }[],
    }

    const deposited = depositToBank(save, 0, 3)
    expect(deposited.ok).toBe(true)
    if (!deposited.ok) return
    save = deposited.save
    expect(save.inventory).toEqual([{ itemId: 'ITEM-0002', quantity: 2 }])
    expect(save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 3 }])
    expect(save.gold).toBe(createNewSave(launch).gold)

    const gold = depositToBank(
      { ...save, inventory: [{ itemId: GOLD_ITEM_ID, quantity: 10 }] },
      0,
      10,
    )
    expect(gold.ok).toBe(false)
    if (gold.ok) return
    expect(gold.reason).toBe('Gold cannot be deposited.')
    expect(stackIsUnbankableGold({ itemId: GOLD_ITEM_ID })).toBe(true)

    const compost = depositToBank(
      { ...createNewSave(launch), inventory: [{ itemId: 'ITEM-0377', quantity: 4 }], bank: [] },
      0,
      4,
    )
    expect(compost.ok).toBe(true)
    if (!compost.ok) return
    expect(compost.save.inventory).toEqual([])
    expect(compost.save.bank).toEqual([{ itemId: 'ITEM-0377', quantity: 4 }])

    const withdrawn = withdrawFromBank(save, 0, 2)
    expect(withdrawn.ok).toBe(true)
    if (!withdrawn.ok) return
    expect(withdrawn.save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 1 }])
    expect(withdrawn.save.inventory).toEqual([{ itemId: 'ITEM-0002', quantity: 4 }])
  })

  it(`caps the chest at ${BANK_SLOT_LIMIT} slots`, () => {
    const save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: 1 }],
      bank: Array.from({ length: BANK_SLOT_LIMIT }, (_, index) => ({
        itemId: `ITEM-fake-${index}`,
        quantity: 1,
      })),
    }
    const blocked = depositToBank(save, 0, 1)
    expect(blocked).toMatchObject({
      ok: false,
      code: 'no_room',
      reason: 'Your bank is full. Make room for 1 slot and try again.',
      noRoom: { target: 'bank', slotsNeeded: 1, slotsFree: 0 },
    })

    const almostFull = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: 1 }],
      bank: Array.from({ length: BANK_SLOT_LIMIT - 1 }, (_, index) => ({
        itemId: `ITEM-fake-${index}`,
        quantity: 1,
      })),
    }
    const accepted = depositToBank(almostFull, 0, 1)
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    expect(accepted.save.bank).toHaveLength(BANK_SLOT_LIMIT)
    expect(INVENTORY_SLOT_LIMIT).toBe(84)
  })

  it('refuses a new-stack withdraw with no_room and leaves bag and bank unchanged', () => {
    const save = {
      ...createNewSave(launch),
      inventory: Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, index) => ({
        itemId: `FILL-${index}`,
        quantity: 1,
      })),
      bank: [{ itemId: 'ITEM-0002', quantity: 3 }],
    }
    const blocked = withdrawFromBank(save, 0, 1)
    expect(blocked).toMatchObject({
      ok: false,
      code: 'no_room',
      reason: 'No room in your bag. Free 1 slot and try again.',
      noRoom: { slotsNeeded: 1, slotsFree: 0 },
    })
    expect(save.inventory).toHaveLength(INVENTORY_SLOT_LIMIT)
    expect(save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 3 }])
  })

  it('withdraws onto an existing stack when the bag is full', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: 'ITEM-0002', quantity: 2 },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `FILL-${index}`,
          quantity: 1,
        })),
      ],
      bank: [{ itemId: 'ITEM-0002', quantity: 4 }],
    }
    const withdrawn = withdrawFromBank(save, 0, 2)
    expect(withdrawn.ok).toBe(true)
    if (!withdrawn.ok) return
    expect(withdrawn.save.inventory.find((stack) => stack.itemId === 'ITEM-0002')?.quantity).toBe(4)
    expect(withdrawn.save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 2 }])
  })

  it('refuses an enchanted withdraw into a full bag that already holds a plain stack', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: 'ITEM-0100', quantity: 1 },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `FILL-${index}`,
          quantity: 1,
        })),
      ],
      bank: [{ itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001' }],
    }
    const blocked = withdrawFromBank(save, 0, 1)
    expect(blocked).toMatchObject({
      ok: false,
      code: 'no_room',
      reason: 'No room in your bag. Free 1 slot and try again.',
      noRoom: { slotsNeeded: 1, slotsFree: 0 },
    })
    if (blocked.ok) return
    expect(blocked.reason).not.toMatch(/Inventory is full/)
    expect(save.inventory).toHaveLength(INVENTORY_SLOT_LIMIT)
    expect(save.bank).toEqual([{ itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001' }])
  })

  it('refuses a stack-cap withdraw with stack_full and no slot count', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: Number.MAX_SAFE_INTEGER }],
      bank: [{ itemId: 'ITEM-0002', quantity: 2 }],
    }
    const blocked = withdrawFromBank(save, 0, 1)
    expect(blocked).toEqual({
      ok: false,
      code: 'no_room',
      reason: 'That stack cannot hold more of this item.',
      noRoom: { reason: 'stack_full' },
    })
    if (blocked.ok) return
    expect(blocked.noRoom).not.toHaveProperty('slotsNeeded')
    expect(blocked.noRoom).not.toHaveProperty('slotsFree')
    expect(save.inventory).toEqual([{ itemId: 'ITEM-0002', quantity: Number.MAX_SAFE_INTEGER }])
    expect(save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 2 }])
  })

  it('refuses a stack-cap deposit with stack_full and no slot count', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: 2 }],
      bank: [{ itemId: 'ITEM-0002', quantity: Number.MAX_SAFE_INTEGER }],
    }
    const blocked = depositToBank(save, 0, 1)
    expect(blocked).toEqual({
      ok: false,
      code: 'no_room',
      reason: 'That stack cannot hold more of this item.',
      noRoom: { reason: 'stack_full' },
    })
    expect(save.inventory).toEqual([{ itemId: 'ITEM-0002', quantity: 2 }])
    expect(save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: Number.MAX_SAFE_INTEGER }])
  })
})
