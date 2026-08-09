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
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('combat level bonuses', () => {
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
})
