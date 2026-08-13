import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { INVENTORY_SLOT_LIMIT } from './capacity'
import {
  depositToBank,
  locationHasBank,
  stackIsUnbankableGold,
  withdrawFromBank,
} from './bank'
import { GOLD_ITEM_ID } from './gold'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('bank storage', () => {
  const { launch, launchIndexes } = prepareDatabase(rawDatabase)

  it('is at Town, Castle, and Citadel — including their districts', () => {
    const byId = launchIndexes.locationsById
    expect(locationHasBank(byId.get('LOC-0002'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0013'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0027'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0024'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0014'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0028'))).toBe(true)
    expect(locationHasBank(byId.get('LOC-0009'))).toBe(false)
    expect(locationHasBank(undefined)).toBe(false)
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
    expect(gold.reason).toBe('Gold stays on you.')
    expect(stackIsUnbankableGold({ itemId: GOLD_ITEM_ID })).toBe(true)

    const withdrawn = withdrawFromBank(save, 0, 2)
    expect(withdrawn.ok).toBe(true)
    if (!withdrawn.ok) return
    expect(withdrawn.save.bank).toEqual([{ itemId: 'ITEM-0002', quantity: 1 }])
    expect(withdrawn.save.inventory).toEqual([{ itemId: 'ITEM-0002', quantity: 4 }])
  })

  it(`caps the chest at ${INVENTORY_SLOT_LIMIT} slots`, () => {
    const save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: 1 }],
      bank: Array.from({ length: INVENTORY_SLOT_LIMIT }, (_, index) => ({
        itemId: `ITEM-fake-${index}`,
        quantity: 1,
      })),
    }
    const blocked = depositToBank(save, 0, 1)
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return
    expect(blocked.reason).toBe(`Bank is full (${INVENTORY_SLOT_LIMIT} slots).`)
  })
})
