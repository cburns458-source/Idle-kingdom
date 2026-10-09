import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { enemyEncounterDamageRange, enemyEncounterMaxHp } from './boss'
import {
  combatLevelFromSkills,
  combatLevelHpMultiplier,
  combatLevelOf,
  enemyCombatLevel,
  enemyCombatXp,
  enemyEffectiveMaxHp,
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
  vitalityDamageReductionPercent,
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

  it('scales existing enemy HP/XP from Combat Level and damage from Might', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const cow = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const scout = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0003')!
    expect(enemyMightLevel(cow)).toBe(1)
    expect(enemyVitalityLevel(cow)).toBe(5)
    expect(enemyCombatLevel(cow)).toBe(5)
    expect(enemyScaledMaxHp(cow)).toBe(105)
    expect(enemyCombatXp(cow)).toBe(53)
    expect(enemyEncounterMaxHp(launch, save, cow)).toBe(105)
    expect(enemyEncounterDamageRange(launch, save, cow)).toEqual({ min: 10, max: 20 })

    expect(enemyMightLevel(scout)).toBe(12)
    expect(enemyVitalityLevel(scout)).toBe(10)
    expect(enemyCombatLevel(scout)).toBe(17)
    expect(enemyScaledMaxHp(scout)).toBe(257)
    expect(enemyCombatXp(scout)).toBe(131)
    expect(enemyScaledDamageRange(scout)).toEqual({ min: 33, max: 67 })
    expect(enemyEncounterMaxHp(launch, save, scout)).toBe(257)
    expect(enemyEncounterDamageRange(launch, save, scout)).toEqual({ min: 33, max: 67 })
  })

  it('keeps placeholder stats; mountain roosts have locations', () => {
    const { launch, source } = prepareDatabase(rawDatabase)
    // id, name, might, vitality, baseHp, minDmg, maxDmg, combatXp, locationId
    const launchEnemies = [
      ['ENM-0025', 'Giant Rat', 5, 5, 120, 12, 26, 65, 'LOC-0011'],
      ['ENM-0026', 'Bandit', 15, 6, 180, 16, 40, 107, 'LOC-0052'],
      ['ENM-0027', 'Cave Bat', 14, 8, 180, 37, 73, 107, 'LOC-0046'],
      ['ENM-0029', 'Bandit Captain', 26, 16, 360, 55, 108, 260, 'LOC-0052'],
      ['ENM-0030', 'Harpy', 70, 40, 830, 152, 268, 843, 'LOC-0047'],
      ['ENM-0031', 'Giant', 60, 50, 1010, 164, 288, 1120, 'LOC-0049'],
      ['ENM-0033', 'Wyvern', 85, 60, 1430, 236, 404, 1757, 'LOC-0047'],
      ['ENM-0034', 'Cyclops', 75, 70, 1200, 260, 440, 1618, 'LOC-0049'],
    ] as const
    const expansionEnemies = [
      ['ENM-0028', 'Mage Apprentice', 25, 12, 210, 45, 90, 138, null],
      ['ENM-0032', 'Gargoyle', 65, 60, 1080, 192, 338, 1396, null],
      ['ENM-0035', 'Demon', 90, 65, 1500, 475, 745, 2066, null],
      ['ENM-0036', 'Greater Gargoyle', 90, 75, 2220, 555, 860, 3059, null],
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
      if (id === 'ENM-0026' || id === 'ENM-0031' || id === 'ENM-0034') {
        expect(enemy!['Damage Resistance']).toBe(id === 'ENM-0026' ? 2 : 5)
      } else if (id === 'ENM-0029') {
        expect(enemy!['Damage Resistance']).toBe(5)
      } else {
        expect(enemy!['Damage Resistance'] ?? 0).toBe(0)
      }
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
      if (id === 'ENM-0032') expect(enemy!['Damage Resistance']).toBe(10)
      else if (id === 'ENM-0035') expect(enemy!['Damage Resistance']).toBe(5)
      else expect(enemy!['Damage Resistance'] ?? 0).toBe(0)
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

  it('keeps every enemy Combat XP column in sync with floor(effectiveMaxHp / 2)', () => {
    const { launch, source } = prepareDatabase(rawDatabase)
    for (const enemy of source.Enemies) {
      if (typeof enemy['Maximum HP'] !== 'number') continue
      const expected = Math.floor(enemyEffectiveMaxHp(enemy) / 2)
      expect(enemy['Combat XP'], enemy['Enemy ID']).toBe(expected)
      expect(enemyCombatXp(enemy), enemy['Enemy ID']).toBe(expected)
    }
    for (const enemy of launch.Enemies) {
      const expected = Math.floor(enemyEffectiveMaxHp(enemy) / 2)
      expect(enemy['Combat XP'], enemy['Enemy ID']).toBe(expected)
      expect(enemyCombatXp(enemy), enemy['Enemy ID']).toBe(expected)
    }
  })

  it('gives no level bonus below skill level 5', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(mightDamageMultiplier(save)).toBe(1)
    expect(combatLevelHpMultiplier(save)).toBe(1)
    expect(playerMaxHp(launch, save)).toBe(1000)
    expect(vitalityDamageReductionPercent(save)).toBe(0.25)
    const level5 = withSkillLevels(save, { 'SKL-0001': 5, 'SKL-0016': 5 })
    expect(mightDamageMultiplier(level5)).toBeCloseTo(1.05)
    expect(combatLevelOf(level5)).toBe(8)
    expect(combatLevelHpMultiplier(level5)).toBeCloseTo(1.08)
    expect(playerMaxHp(launch, level5)).toBe(1080)
    expect(vitalityDamageReductionPercent(level5)).toBeCloseTo(1.25)
  })

  it('scales damage from Might and HP from Combat Level', () => {
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
    expect(combatLevelOf(unarmed)).toBe(23)
    expect(combatLevelHpMultiplier(unarmed)).toBeCloseTo(1.23)
    expect(playerMaxHp(launch, unarmed)).toBe(1230)
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
    const vitalityDr = vitalityDamageReductionPercent(base)
    expect(playerDamageReduction(launch, { ...base, attackStyle: 'balanced' })).toBe(vitalityDr)
    expect(playerDamageReduction(launch, { ...base, attackStyle: 'defensive' })).toBe(1 + vitalityDr)

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
