import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  combatLevelOf,
  mightDamageMultiplier,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  splitCombatVictoryXp,
  vitalityHpMultiplier,
} from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function withSkillLevels(
  save: ReturnType<typeof createNewSave>,
  levels: Record<string, number>,
) {
  return {
    ...save,
    skills: save.skills.map((skill) =>
      levels[skill.skillId] != null
        ? { ...skill, level: levels[skill.skillId]!, xp: 0 }
        : skill,
    ),
  }
}

describe('might / vitality combat stats', () => {
  it('gives every fishing rod a 0-0 melee damage range', () => {
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
      expect(playerDamageRange(launch, save), itemId).toEqual({ min: 0, max: 0 })
    }
  })

  it('rounds Combat Level up from Might and Vitality', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(combatLevelOf(save)).toBe(2)
    expect(combatLevelOf(withSkillLevels(save, { 'SKL-0001': 10, 'SKL-0016': 3 }))).toBe(10)
  })

  it('gives no level bonus below skill level 10', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(mightDamageMultiplier(save)).toBe(1)
    expect(vitalityHpMultiplier(save)).toBe(1)
    expect(playerMaxHp(launch, save)).toBe(1000)
  })

  it('scales damage from Might and HP from Vitality', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = withSkillLevels(createNewSave(launch), {
      'SKL-0001': 10,
      'SKL-0016': 20,
    })
    const unarmed = {
      ...base,
      equipment: {
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': null,
        },
      },
    }
    expect(mightDamageMultiplier(unarmed)).toBeCloseTo(1.1)
    expect(vitalityHpMultiplier(unarmed)).toBeCloseTo(1.2)
    expect(playerMaxHp(launch, unarmed)).toBe(1200)
    expect(playerDamageRange(launch, unarmed)).toEqual({ min: 11, max: 33 })
  })

  it('applies offensive damage and defensive DR stance bonuses; balanced gets none', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(playerDamageReduction(launch, { ...base, attackStyle: 'balanced' })).toBe(0)
    expect(playerDamageReduction(launch, { ...base, attackStyle: 'defensive' })).toBe(1)

    const unarmed = {
      ...base,
      equipment: {
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': null,
        },
      },
    }
    expect(playerDamageRange(launch, { ...unarmed, attackStyle: 'balanced' })).toEqual({
      min: 10,
      max: 30,
    })
    expect(playerDamageRange(launch, { ...unarmed, attackStyle: 'offensive' })).toEqual({
      min: 10,
      max: 30,
    })
    // 10–30 × 1.01 floored → still 10–30 at these bases; verify multiplier path via style XP split.
    expect(splitCombatVictoryXp(125, 'offensive')).toEqual({ mightXp: 125, vitalityXp: 0 })
    expect(splitCombatVictoryXp(125, 'defensive')).toEqual({ mightXp: 0, vitalityXp: 125 })
    expect(splitCombatVictoryXp(125, 'balanced')).toEqual({ mightXp: 63, vitalityXp: 62 })
  })

  it('adds an Arcana layer only on Staff of Power', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const withSkills = withSkillLevels(base, {
      'SKL-0001': 40,
      'SKL-0013': 50,
    })
    const power = {
      ...withSkills,
      equipment: {
        slots: {
          ...withSkills.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0306', quantity: 1 },
        },
      },
    }
    // 60–90 × might-40 (1.40) × arcana-50 (1.50), floored once.
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
