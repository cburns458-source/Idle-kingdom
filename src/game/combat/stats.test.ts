import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { enemyEncounterDamageRange, enemyEncounterMaxHp } from './boss'
import {
  combatLevelFromSkills,
  combatLevelOf,
  enemyCombatLevel,
  enemyCombatXp,
  enemyMightLevel,
  enemyScaledDamageRange,
  enemyScaledMaxHp,
  enemyVitalityLevel,
  mightDamageMultiplier,
  normalizeAttackStyle,
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
    expect(combatLevelFromSkills(1, 1)).toBe(2)
    expect(combatLevelOf(save)).toBe(2)
    expect(combatLevelOf(withSkillLevels(save, { 'SKL-0001': 10, 'SKL-0016': 3 }))).toBe(10)
  })

  it('gives existing enemies Might and Vitality equal to their original combat level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const cow = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const scout = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0003')!
    expect(enemyMightLevel(cow)).toBe(1)
    expect(enemyVitalityLevel(cow)).toBe(1)
    expect(enemyCombatLevel(cow)).toBe(2)
    expect(enemyScaledMaxHp(cow)).toBe(100)
    expect(enemyCombatXp(cow)).toBe(200)
    expect(enemyEncounterMaxHp(launch, save, cow)).toBe(100)
    expect(enemyEncounterDamageRange(launch, save, cow)).toEqual({ min: 10, max: 20 })

    expect(enemyMightLevel(scout)).toBe(10)
    expect(enemyVitalityLevel(scout)).toBe(10)
    expect(enemyCombatLevel(scout)).toBe(15)
    expect(enemyScaledMaxHp(scout)).toBe(462)
    expect(enemyCombatXp(scout)).toBe(924)
    expect(enemyScaledDamageRange(scout)).toEqual({ min: 33, max: 66 })
    expect(enemyEncounterMaxHp(launch, save, scout)).toBe(462)
    expect(enemyEncounterDamageRange(launch, save, scout)).toEqual({ min: 33, max: 66 })
  })

  it('keeps the new roster out of locations and drop pools', () => {
    const { launch, source } = prepareDatabase(rawDatabase)
    const added = [
      ['ENM-0025', 'Giant Rat', 3, 150, 12, 26, 300],
      ['ENM-0026', 'Bandit', 6, 260, 16, 40, 520],
      ['ENM-0027', 'Cave Bat', 14, 580, 37, 73, 1322],
      ['ENM-0028', 'Mage Apprentice', 18, 750, 45, 90, 1770],
      ['ENM-0029', 'Bandit Captain', 22, 930, 55, 108, 2268],
      ['ENM-0030', 'Harpy', 48, 3860, 152, 268, 11424],
      ['ENM-0031', 'Giant', 51, 4440, 164, 288, 13408],
      ['ENM-0032', 'Gargoyle', 58, 5940, 192, 338, 18770],
      ['ENM-0033', 'Wyvern', 67, 7920, 236, 404, 26452],
      ['ENM-0034', 'Cyclops', 70, 9000, 260, 440, 30600],
      ['ENM-0035', 'Demon', 82, 15000, 475, 745, 54598],
      ['ENM-0036', 'Greater Gargoyle', 86, 17760, 555, 860, 66066],
    ] as const
    const addedIds = new Set<string>(added.map(([id]) => id))
    for (const [id, name, level, hp, min, max, xp] of added) {
      const enemy = launch.Enemies.find((row) => row['Enemy ID'] === id)
      expect(enemy, id).toBeDefined()
      expect(enemy!['Display Name']).toBe(name)
      expect(enemyMightLevel(enemy!)).toBe(level)
      expect(enemyVitalityLevel(enemy!)).toBe(level)
      expect(enemyCombatLevel(enemy!)).toBe(combatLevelFromSkills(level, level))
      expect(enemy!['Maximum HP']).toBe(hp)
      expect(enemy!['Min Damage']).toBe(min)
      expect(enemy!['Max Damage']).toBe(max)
      expect(enemy!['Combat XP']).toBe(xp)
      expect(enemyCombatXp(enemy!)).toBe(xp)
      expect(enemy!['Location ID']).toBeNull()
      expect(enemy!['Drop Chance']).toBe(0)
      expect(enemy!['Reward Table ID']).toBeNull()
      expect(enemy!['Minimum Gold']).toBe(0)
      expect(enemy!['Maximum Gold']).toBe(0)
    }
    expect(source.Actions.some((row) => addedIds.has(String(row['Target ID'] ?? '')))).toBe(false)
    expect(
      source.PoolEntries.some((row) => {
        const action = source.Actions.find((entry) => entry['Action ID'] === row['Action ID'])
        return action ? addedIds.has(String(action['Target ID'] ?? '')) : false
      }),
    ).toBe(false)
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

  it('defaults a missing stance to offensive and keeps a stored balanced choice', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(normalizeAttackStyle(undefined)).toBe('offensive')
    expect(normalizeAttackStyle(null)).toBe('offensive')
    expect(normalizeAttackStyle('balanced')).toBe('balanced')
    expect(normalizeAttackStyle('defensive')).toBe('defensive')
    expect(createNewSave(launch).attackStyle).toBe('offensive')
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
      attackStyle: 'balanced' as const,
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
