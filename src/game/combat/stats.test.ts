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

  it('scales existing enemy HP/XP from Vitality and damage from Might', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const cow = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const scout = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0003')!
    expect(enemyMightLevel(cow)).toBe(2)
    expect(enemyVitalityLevel(cow)).toBe(3)
    expect(enemyCombatLevel(cow)).toBe(4)
    expect(enemyScaledMaxHp(cow)).toBe(100)
    expect(enemyCombatXp(cow)).toBe(200)
    expect(enemyEncounterMaxHp(launch, save, cow)).toBe(100)
    expect(enemyEncounterDamageRange(launch, save, cow)).toEqual({ min: 10, max: 20 })

    expect(enemyMightLevel(scout)).toBe(12)
    expect(enemyVitalityLevel(scout)).toBe(10)
    expect(enemyCombatLevel(scout)).toBe(17)
    expect(enemyScaledMaxHp(scout)).toBe(462)
    expect(enemyCombatXp(scout)).toBe(924)
    expect(enemyScaledDamageRange(scout)).toEqual({ min: 33, max: 67 })
    expect(enemyEncounterMaxHp(launch, save, scout)).toBe(462)
    expect(enemyEncounterDamageRange(launch, save, scout)).toEqual({ min: 33, max: 67 })
  })

  it('keeps placeholder stats; mountain roosts have locations', () => {
    const { launch, source } = prepareDatabase(rawDatabase)
    // id, name, might, vitality, baseHp, minDmg, maxDmg, combatXp, locationId
    const launchEnemies = [
      ['ENM-0025', 'Giant Rat', 5, 3, 150, 12, 26, 300, 'LOC-0011'],
      ['ENM-0026', 'Bandit', 15, 6, 260, 16, 40, 520, 'LOC-0052'],
      ['ENM-0027', 'Cave Bat', 14, 8, 580, 37, 73, 1160, 'LOC-0046'],
      ['ENM-0029', 'Bandit Captain', 26, 16, 930, 55, 108, 2156, 'LOC-0052'],
      ['ENM-0030', 'Harpy', 70, 40, 3860, 152, 268, 10808, 'LOC-0047'],
      ['ENM-0031', 'Giant', 60, 50, 4440, 164, 288, 13320, 'LOC-0049'],
      ['ENM-0033', 'Wyvern', 85, 60, 7920, 236, 404, 25344, 'LOC-0047'],
      ['ENM-0034', 'Cyclops', 75, 70, 9000, 260, 440, 30600, 'LOC-0049'],
    ] as const
    const expansionEnemies = [
      ['ENM-0028', 'Mage Apprentice', 25, 12, 750, 45, 90, 1680, null],
      ['ENM-0032', 'Gargoyle', 65, 60, 5940, 192, 338, 19008, null],
      ['ENM-0035', 'Demon', 90, 65, 15000, 475, 745, 49500, null],
      ['ENM-0036', 'Greater Gargoyle', 90, 75, 17760, 555, 860, 62160, null],
    ] as const
    const placeholderIds = new Set<string>([
      ...launchEnemies.map(([id]) => id),
      ...expansionEnemies.map(([id]) => id),
    ])
    const assignedIds = new Set<string>(launchEnemies.map(([id]) => id))
    for (const [id, name, might, vitality, hp, min, max, xp, locationId] of launchEnemies) {
      const enemy = launch.Enemies.find((row) => row['Enemy ID'] === id)
      expect(enemy, id).toBeDefined()
      expect(enemy!['Display Name']).toBe(name)
      expect(enemyMightLevel(enemy!)).toBe(might)
      expect(enemyVitalityLevel(enemy!)).toBe(vitality)
      expect(enemyCombatLevel(enemy!)).toBe(combatLevelFromSkills(might, vitality))
      expect(enemy!['Maximum HP']).toBe(hp)
      expect(enemy!['Min Damage']).toBe(min)
      expect(enemy!['Max Damage']).toBe(max)
      expect(enemy!['Combat XP']).toBe(xp)
      expect(enemyCombatXp(enemy!)).toBe(xp)
      expect(enemy!['Location ID']).toBe(locationId)
      if (id === 'ENM-0027') {
        expect(enemy!['Drop Chance']).toBe(25)
        expect(enemy!['Reward Table ID']).toBe('RWT-0186')
      } else if (id === 'ENM-0030') {
        expect(enemy!['Drop Chance']).toBe(25)
        expect(enemy!['Reward Table ID']).toBe('RWT-0188')
      } else if (id === 'ENM-0031') {
        expect(enemy!['Drop Chance']).toBe(20)
        expect(enemy!['Reward Table ID']).toBe('RWT-0190')
      } else if (id === 'ENM-0033') {
        expect(enemy!['Drop Chance']).toBe(25)
        expect(enemy!['Reward Table ID']).toBe('RWT-0189')
      } else if (id === 'ENM-0034') {
        expect(enemy!['Drop Chance']).toBe(10)
        expect(enemy!['Reward Table ID']).toBe('RWT-0187')
      } else {
        expect(enemy!['Drop Chance']).toBe(0)
        expect(enemy!['Reward Table ID']).toBeNull()
      }
      if (id === 'ENM-0026') {
        expect(enemy!['Minimum Gold']).toBe(1)
        expect(enemy!['Maximum Gold']).toBe(2)
      } else if (id === 'ENM-0029') {
        expect(enemy!['Minimum Gold']).toBe(5)
        expect(enemy!['Maximum Gold']).toBe(6)
      } else {
        expect(enemy!['Minimum Gold']).toBe(0)
        expect(enemy!['Maximum Gold']).toBe(0)
      }
    }
    for (const [id, name, might, vitality, hp, min, max, xp, locationId] of expansionEnemies) {
      expect(launch.Enemies.find((row) => row['Enemy ID'] === id)).toBeUndefined()
      const enemy = source.Enemies.find((row) => row['Enemy ID'] === id)
      expect(enemy, id).toBeDefined()
      expect(enemy!['Release Phase']).toBe('Expansion')
      expect(enemy!['Display Name']).toBe(name)
      expect(enemyMightLevel(enemy!)).toBe(might)
      expect(enemyVitalityLevel(enemy!)).toBe(vitality)
      expect(enemyCombatLevel(enemy!)).toBe(combatLevelFromSkills(might, vitality))
      expect(enemy!['Maximum HP']).toBe(hp)
      expect(enemy!['Min Damage']).toBe(min)
      expect(enemy!['Max Damage']).toBe(max)
      expect(enemy!['Combat XP']).toBe(xp)
      expect(enemyCombatXp(enemy!)).toBe(xp)
      expect(enemy!['Location ID']).toBe(locationId)
    }
    expect(
      source.Actions.some(
        (row) =>
          placeholderIds.has(String(row['Target ID'] ?? '')) &&
          !assignedIds.has(String(row['Target ID'] ?? '')),
      ),
    ).toBe(false)
    expect(
      source.PoolEntries.some((row) => {
        const action = source.Actions.find((entry) => entry['Action ID'] === row['Action ID'])
        const target = String(action?.['Target ID'] ?? '')
        return placeholderIds.has(target) && !assignedIds.has(target)
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
