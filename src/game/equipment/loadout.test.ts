import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { migrateSave } from '../save/migrations'
import type { PlayerSave } from '../save/types'
import { tryConsumeFoodAfterVictory } from '../combat/food'
import { gatheringDurationMs } from '../activity/gathering'
import {
  equipItemFromInventory,
  equipStackToSlot,
  FOOD_SLOT_ID,
  unequipSlot,
} from './loadout'
import { withRecalculatedVitals } from './vitals'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('equipment loadout', () => {
  it('moves the entire food stack out of inventory into the food slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0058', 5)
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0058')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    expect(equipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(equipped.save.equipment.slots[FOOD_SLOT_ID]).toEqual({
      itemId: 'ITEM-0058',
      quantity: 5,
    })
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

  it('blocks equipping gear below required skill level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0119', 1) // Steel Pickaxe, Mining 35
    const result = equipItemFromInventory(launch, save, 'ITEM-0119')
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/Mining level 35/i)
  })

  it('applies action time reduction from equipped tools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Clear starting Net so ATR is only from pickaxe.
    save = unequipSlot(save, 'SLOT-0001')
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe ATR 5
    const equipped = equipItemFromInventory(launch, save, 'ITEM-0111')
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return

    const digClay = launch.Actions.find((action) => action['Action ID'] === 'ACN-0019')!
    const base = Number(digClay['Base Duration Seconds'] ?? 0)
    const proficiency = Number(digClay['Proficiency Level'] ?? 1)
    const mult = 1 < proficiency ? 2 : 1
    const expected = Math.round(base * mult * 0.95 * 1000)
    expect(gatheringDurationMs(launch, equipped.save, digClay)).toBe(expected)
  })

  it('clamps current HP when max HP drops', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentHp: 1100,
      maxHp: 1100,
    }
    const next = withRecalculatedVitals(launch, save)
    expect(next.maxHp).toBe(1000)
    expect(next.currentHp).toBe(1000)
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
    expect(migrated.saveVersion).toBe(11)
    expect(migrated.activityTransition).toBeNull()
    expect(migrated.settings.showActivityRewards).toBe(true)
    expect(migrated.unlockedNpcIds).toEqual([])
    expect(typeof migrated.unattendedProgressAt).toBe('string')
    expect(migrated.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(migrated.equipment.slots[FOOD_SLOT_ID]).toEqual({ itemId: 'ITEM-0058', quantity: 5 })
    expect(migrated.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0108')
    expect(migrated.productionRecipeId).toBeNull()
    expect(migrated.productionQuantityTotal).toBeNull()
    expect(migrated.productionQuantityRemaining).toBeNull()
  })
})
