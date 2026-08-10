import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { POTION_SLOT_ID } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { beginCombatSave } from './engine'
import { tryConsumeCombatEncounterPotion } from './potion'
import { playerDamageRange } from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('combat encounter potions', () => {
  it('consumes a minor strength potion when combat starts and boosts damage', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          [POTION_SLOT_ID]: { itemId: 'ITEM-0211', quantity: 2 },
        },
      },
    }
    const baseline = playerDamageRange(launch, save)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)

    expect(started.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
    expect(started.combatPotionDamageBonusPercent).toBe(5)

    const boosted = playerDamageRange(launch, started)
    expect(boosted.min).toBe(Math.floor(baseline.min * 1.05))
    expect(boosted.max).toBe(Math.max(boosted.min, Math.floor(baseline.max * 1.05)))
  })

  it('does not consume non-encounter potions', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          [POTION_SLOT_ID]: { itemId: 'ITEM-0070', quantity: 1 }, // Luck Potion
        },
      },
    }
    const result = tryConsumeCombatEncounterPotion(launch, save)
    expect(result.consumed).toBe(false)
    expect(result.save.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
  })
})
