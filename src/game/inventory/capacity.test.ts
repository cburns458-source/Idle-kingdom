import { describe, expect, it } from 'vitest'
import {
  addItemToInventory,
  addItemToInventoryExact,
  addItemsToInventory,
} from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { prepareDatabase } from '../data/loadDatabase'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  INVENTORY_SLOT_LIMIT,
  INVENTORY_STACK_MAX,
  canFitItemQuantity,
  inventorySlotsFree,
  maxAddableQuantity,
} from './capacity'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('inventory capacity', () => {
  it('caps the bag at 180 slots and stacks to MAX_SAFE_INTEGER', () => {
    expect(INVENTORY_SLOT_LIMIT).toBe(180)
    expect(INVENTORY_STACK_MAX).toBe(Number.MAX_SAFE_INTEGER)

    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }

    for (let i = 0; i < INVENTORY_SLOT_LIMIT; i += 1) {
      save = addItemToInventory(save, `ITEM-fake-${i}`, 1)
    }
    expect(save.inventory).toHaveLength(180)
    expect(inventorySlotsFree(save)).toBe(0)
    expect(maxAddableQuantity(save, 'ITEM-fake-new')).toBe(0)

    const blocked = addItemsToInventory(save, 'ITEM-fake-new', 5)
    expect(blocked.added).toBe(0)
    expect(blocked.save.inventory).toHaveLength(180)
  })

  it('stops stacking before integer overflow', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [{ itemId: 'ITEM-0025', quantity: INVENTORY_STACK_MAX - 2 }],
    }
    expect(canFitItemQuantity(save, 'ITEM-0025', 2)).toBe(true)
    expect(canFitItemQuantity(save, 'ITEM-0025', 3)).toBe(false)

    const exact = addItemToInventoryExact(save, 'ITEM-0025', 3)
    expect(exact.ok).toBe(false)

    const partial = addItemsToInventory(save, 'ITEM-0025', 10)
    expect(partial.added).toBe(2)
    expect(partial.save.inventory[0]?.quantity).toBe(INVENTORY_STACK_MAX)
  })

  it('still accepts more of an item when the bag is full but a matching pile exists', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      inventory: [
        { itemId: 'ITEM-0025', quantity: 1, favorite: true },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `ITEM-fake-${index}`,
          quantity: 1,
        })),
      ],
    }
    expect(inventorySlotsFree(save)).toBe(0)
    expect(maxAddableQuantity(save, 'ITEM-0025')).toBe(INVENTORY_STACK_MAX - 1)
    expect(canFitItemQuantity(save, 'ITEM-0025', 4)).toBe(true)

    const added = addItemsToInventory(save, 'ITEM-0025', 4)
    expect(added.added).toBe(4)
    expect(added.save.inventory[0]?.quantity).toBe(5)
    expect(added.save.inventory[0]?.favorite).toBe(true)
    expect(added.save.inventory).toHaveLength(INVENTORY_SLOT_LIMIT)
  })
})
