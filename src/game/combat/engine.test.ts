import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  applyCombatDefeat,
  applyCombatVictory,
  beginCombatSave,
  isDeathPaused,
  resolveCombatRound,
} from './engine'
import { tryConsumeFoodAfterVictory } from './food'
import { applyMitigation, playerDamageRange, staffSparksDamageRange } from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('combat engine', () => {
  it('lets the player attack first and can finish a cow in one strong hit path', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)

    // Force high player damage via stubbed random: first roll max-ish for player.
    const round = resolveCombatRound(launch, started, enemy, enemy['Maximum HP'], () => 0.999)
    expect(round.playerHit).toBeGreaterThan(0)
    if (round.outcome === 'ongoing') {
      expect(round.enemyHit).toBeGreaterThan(0)
      expect(round.playerHp).toBeLessThan(started.currentHp)
    }
  })

  it('applies damage floor after mitigation', () => {
    expect(applyMitigation(5, 100, 1)).toBe(1)
    expect(applyMitigation(20, 5, 1)).toBe(15)
  })

  it('uses unarmed damage when no weapon is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      equipment: {
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': null,
        },
      },
    }
    expect(playerDamageRange(launch, save)).toEqual({ min: 10, max: 30 })
  })

  it('grants combat XP/gold on victory and can consume food when hurt', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentHp: 900,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0058', quantity: 2 },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const victory = applyCombatVictory(launch, save, action, enemy, () => 0)
    expect(victory.xpGained).toBe(125)
    expect(victory.save.skills.find((skill) => skill.skillId === 'SKL-0001')?.xp).toBe(125)
    expect(victory.goldGained).toBe(0)
    expect(victory.foodConsumed).toBe(true)
    expect(victory.save.currentHp).toBeGreaterThan(900)
    expect(victory.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
    expect(victory.save.statistics.values.monsters_killed).toBe(1)
  })

  it('skips healing food after a one-hit kill that dealt no damage', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentHp: 900,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0058', quantity: 2 },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const victory = applyCombatVictory(launch, save, action, enemy, () => 0, Date.now(), {
      skipVictoryFood: true,
    })
    expect(victory.foodConsumed).toBe(false)
    expect(victory.save.currentHp).toBe(900)
    expect(victory.save.equipment.slots['SLOT-0011']?.quantity).toBe(2)
  })

  it('does not eat food at full HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0058', quantity: 1 },
        },
      },
    }
    const result = tryConsumeFoodAfterVictory(launch, save)
    expect(result.consumed).toBe(false)
    expect(result.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
  })

  it('reflects a percentage of incoming damage back at the enemy when Thorns is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      equipment: {
        ...base.equipment,
        // ITEM-0229 grants 1 Damage Reduction; enchanting it with Thorns keeps the math simple.
        slots: {
          ...base.equipment.slots,
          'SLOT-0004': { itemId: 'ITEM-0229', quantity: 1, enchantmentId: 'ENCH-0006' },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    // Both rolls land at their minimum: player hits for 10 (unarmed), enemy rolls 10 raw.
    const round = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], () => 0)
    expect(round.playerHit).toBe(10)
    expect(round.enemyHit).toBe(9) // 10 raw - 1 Damage Reduction from the chestplate.
    expect(round.thornsHit).toBe(1) // 10% of 9, rounded.
    // 100 max HP - 10 (player hit) - 1 (10% Thorns reflect) = 89.
    expect(round.enemyHp).toBe(89)
  })

  it('does not reflect damage when no Thorns enchantment is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const round = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], () => 0)
    expect(round.thornsHit).toBe(0)
    expect(round.enemyHp).toBe(90)
  })

  it('rolls a separate off-hand dagger hit with full damage and no crit', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0124', quantity: 1 }, // Wooden Sword 10-30
          'SLOT-0002': { itemId: 'ITEM-0125', quantity: 1 }, // Wooden Dagger 10-20
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    // Mainhand min 10, offhand min 10, enemy still alive → then enemy roll.
    const round = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], () => 0)
    expect(round.playerHit).toBe(10)
    expect(round.playerCrit).toBe(false)
    expect(round.offhandHit).toBe(10)
    expect(round.enemyHp).toBe(enemy['Maximum HP'] - 20)
  })

  it('applies 1.5× damage on critical strikes and adds crit chance across items', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0124', quantity: 1, enchantmentId: 'ENCH-0008' },
          'SLOT-0008': { itemId: 'ITEM-0170', quantity: 1, enchantmentId: 'ENCH-0008' },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    // damage roll → 0 (min 10), crit roll → 0 (< 20% succeeds)
    const critRound = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], () => 0)
    expect(critRound.playerCrit).toBe(true)
    expect(critRound.playerHit).toBe(15) // floor(10 * 1.5)

    // Fail the crit roll with a high second random value.
    let calls = 0
    const random = () => {
      calls += 1
      return calls === 1 ? 0 : 0.99
    }
    const miss = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], random)
    expect(miss.playerCrit).toBe(false)
    expect(miss.playerHit).toBe(10)
  })

  it('rolls a Staff of Sparks splat from Arcana level with no multipliers', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      skills: base.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 30 } : skill,
      ),
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0304', quantity: 1 },
        },
      },
    }
    expect(staffSparksDamageRange(30)).toEqual({ min: 27, max: 33 })
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const round = resolveCombatRound(launch, save, enemy, 200, () => 0)
    expect(round.playerHit).toBeGreaterThan(0)
    expect(round.staffHit).toBe(27)
    expect(round.offhandHit).toBeNull()
    expect(round.enemyHp).toBe(200 - round.playerHit - 27)
  })

  it("lets Mage's Wand spark while keeping an off-hand dagger", () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      skills: base.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 50 } : skill,
      ),
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0307', quantity: 1 },
          'SLOT-0002': { itemId: 'ITEM-0125', quantity: 1 },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const round = resolveCombatRound(launch, save, enemy, 400, () => 0)
    expect(round.staffHit).toBeGreaterThan(0)
    expect(round.offhandHit).toBeGreaterThan(0)
  })

  it('lets Staff of Sparks finish a kill before the enemy swings', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      skills: base.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 30 } : skill,
      ),
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0304', quantity: 1 },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const round = resolveCombatRound(launch, save, enemy, 40, () => 0)
    expect(round.staffHit).toBe(27)
    expect(round.outcome).toBe('victory')
    expect(round.enemyHit).toBeNull()
  })

  it('lets Staff of Binding skip the following enemy attack', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const save = {
      ...base,
      skills: base.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 40 } : skill,
      ),
      equipment: {
        ...base.equipment,
        slots: {
          ...base.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0305', quantity: 1 },
        },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    // Binding roll is the second random after the main-hand damage roll.
    const first = resolveCombatRound(launch, save, enemy, 400, () => 0)
    expect(first.skipNextEnemyAttack).toBe(true)
    expect(first.enemyHit).toBeGreaterThan(0)
    expect(first.outcome).toBe('ongoing')

    const second = resolveCombatRound(
      launch,
      { ...save, combatSkipEnemyAttack: true },
      enemy,
      first.enemyHp,
      () => 0,
    )
    expect(second.enemyHit).toBeNull()
    expect(second.playerHp).toBe(save.currentHp)
    expect(second.outcome).toBe('ongoing')
  })

  it('starts a death pause with no rewards on defeat', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const defeated = applyCombatDefeat(launch, { ...save, currentHp: 0 }, Date.parse('2026-01-01T00:00:00.000Z'))
    expect(defeated.currentHp).toBe(1000)
    expect(defeated.combatEnemyId).toBeNull()
    expect(isDeathPaused(defeated, Date.parse('2026-01-01T00:00:10.000Z'))).toBe(true)
    expect(isDeathPaused(defeated, Date.parse('2026-01-01T00:00:31.000Z'))).toBe(false)
  })
})
