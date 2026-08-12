import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { ActivePotionEffect } from '../save/types'
import {
  applyRelativeDropChance,
  equippedRelativeDropChanceBonusPercent,
  totalRelativeDropChanceBonusPercent,
} from './dropChance'

const NECKLACE_SLOT_ID = 'SLOT-0008'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('relative drop chance stacking', () => {
  it('applies Lucky Necklace +15% relative drop chance while equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    expect(equippedRelativeDropChanceBonusPercent(launch, save)).toBe(0)

    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          [NECKLACE_SLOT_ID]: { itemId: 'ITEM-0180', quantity: 1 },
        },
      },
    }
    expect(equippedRelativeDropChanceBonusPercent(launch, save)).toBe(15)
    expect(applyRelativeDropChance(20, 15)).toBe(23)
  })

  it('adds Lucky Necklace and luck potion bonuses together', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const potion: ActivePotionEffect = {
      scope: 'one_action',
      itemId: 'ITEM-0070',
      damageBonusPercent: null,
      enemyMaxHpDamagePercent: null,
      relativeDropChanceBonusPercent: 25,
      baseDurationReductionPercent: null,
    }
    const save = {
      ...base,
      activePotionEffect: potion,
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          [NECKLACE_SLOT_ID]: { itemId: 'ITEM-0180', quantity: 1 },
        },
      },
    }
    expect(totalRelativeDropChanceBonusPercent(launch, save)).toBe(40)
    expect(applyRelativeDropChance(50, 40)).toBe(70)
  })
})
