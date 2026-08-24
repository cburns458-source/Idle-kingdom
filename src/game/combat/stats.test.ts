import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  combatLevelBonusMultiplier,
  playerDamageRange,
  playerMaxHp,
} from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('combat level bonuses', () => {
  it('gives every fishing rod a 10-10 damage range', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const rodIds = [
      'ITEM-0103',
      'ITEM-0112',
      'ITEM-0222',
      'ITEM-0116',
      'ITEM-0120',
      'ITEM-0235',
      'ITEM-0248',
      'ITEM-0261',
      'ITEM-0274',
    ]
    for (const itemId of rodIds) {
      const save = {
        ...base,
        equipment: {
          slots: {
            ...base.equipment.slots,
            'SLOT-0001': { itemId, quantity: 1 },
          },
        },
      }
      expect(playerDamageRange(launch, save), itemId).toEqual({ min: 10, max: 10 })
    }
  })

  it('gives no bonus below Combat Level 10', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(combatLevelBonusMultiplier(save)).toBe(1)
    expect(playerMaxHp(launch, save)).toBe(1000)
  })

  it('adds 1% HP and damage per Combat Level from level 10 upward', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const at10 = {
      ...base,
      skills: base.skills.map((skill) =>
        skill.skillId === 'SKL-0001' ? { ...skill, level: 10, xp: 0 } : skill,
      ),
      equipment: {
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': null,
        },
      },
    }
    expect(combatLevelBonusMultiplier(at10)).toBeCloseTo(1.1)
    expect(playerMaxHp(launch, at10)).toBe(1100)
    expect(playerDamageRange(launch, at10)).toEqual({ min: 11, max: 33 })

    const at20 = {
      ...at10,
      skills: at10.skills.map((skill) =>
        skill.skillId === 'SKL-0001' ? { ...skill, level: 20, xp: 0 } : skill,
      ),
    }
    expect(combatLevelBonusMultiplier(at20)).toBeCloseTo(1.2)
    expect(playerMaxHp(launch, at20)).toBe(1200)
    expect(playerDamageRange(launch, at20)).toEqual({ min: 12, max: 36 })
  })

  it('adds an Arcana layer only on Staff of Power', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const withSkills = {
      ...base,
      skills: base.skills.map((skill) => {
        if (skill.skillId === 'SKL-0001') return { ...skill, level: 40 }
        if (skill.skillId === 'SKL-0013') return { ...skill, level: 50 }
        return skill
      }),
    }
    const power = {
      ...withSkills,
      equipment: {
        slots: {
          ...withSkills.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0306', quantity: 1 },
        },
      },
    }
    // 60–90 × combat-40 (1.40) × arcana-50 (1.50), floored once.
    expect(playerDamageRange(launch, power)).toEqual({ min: 125, max: 188 })

    const sparks = {
      ...power,
      equipment: {
        slots: {
          ...power.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0304', quantity: 1 },
        },
      },
    }
    expect(playerDamageRange(launch, sparks)).toEqual({ min: 42, max: 84 })
  })
})
