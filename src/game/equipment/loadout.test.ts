import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { migrateSave } from '../save/migrations'
import type { PlayerSave } from '../save/types'
import { tryConsumeFoodAfterVictory } from '../combat/food'
import {
  equipItemFromInventory,
  equipStackToSlot,
  FOOD_SLOT_ID,
  unequipSlot,
} from './loadout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('equipment loadout food stacks', () => {
  it('moves the entire food stack out of inventory into the food slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0058', 5)
    save = equipItemFromInventory(launch, save, 'ITEM-0058')

    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(save.equipment.slots[FOOD_SLOT_ID]).toEqual({ itemId: 'ITEM-0058', quantity: 5 })
  })

  it('consumes from the equipped food stack across multiple victories', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipStackToSlot(save, FOOD_SLOT_ID, 'ITEM-0058', 3)
    save = { ...save, currentHp: 900 }

    const first = tryConsumeFoodAfterVictory(launch, save)
    expect(first.consumed).toBe(true)
    expect(first.save.equipment.slots[FOOD_SLOT_ID]?.quantity).toBe(2)
    expect(first.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()

    const second = tryConsumeFoodAfterVictory(launch, { ...first.save, currentHp: 900 })
    expect(second.consumed).toBe(true)
    expect(second.save.equipment.slots[FOOD_SLOT_ID]?.quantity).toBe(1)

    const third = tryConsumeFoodAfterVictory(launch, { ...second.save, currentHp: 900 })
    expect(third.consumed).toBe(true)
    expect(third.save.equipment.slots[FOOD_SLOT_ID]).toBeNull()
  })

  it('returns the remaining food stack to inventory on unequip', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipStackToSlot(save, FOOD_SLOT_ID, 'ITEM-0058', 4)
    save = unequipSlot(save, FOOD_SLOT_ID)
    expect(save.equipment.slots[FOOD_SLOT_ID]).toBeNull()
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(4)
  })

  it('migrates v3 food item-id slots by pulling inventory into the equipped stack', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const legacy = {
      ...base,
      saveVersion: 3,
      inventory: [{ itemId: 'ITEM-0058', quantity: 5 }],
      equipment: {
        slots: {
          ...Object.fromEntries(
            Object.keys(base.equipment.slots).map((slotId) => [slotId, null as string | null]),
          ),
          [FOOD_SLOT_ID]: 'ITEM-0058',
        },
      },
    } as unknown as PlayerSave

    const migrated = migrateSave(legacy)
    expect(migrated.saveVersion).toBe(6)
    expect(migrated.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(migrated.equipment.slots[FOOD_SLOT_ID]).toEqual({ itemId: 'ITEM-0058', quantity: 5 })
    expect(migrated.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0108')
  })
})
