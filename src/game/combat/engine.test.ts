import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { addItemToInventory } from '../activity/rewards'
import {
  applyCombatDefeat,
  applyCombatVictory,
  beginCombatSave,
  isDeathPaused,
  resolveCombatRound,
} from './engine'
import { tryConsumeFoodAfterVictory } from './food'
import { applyMitigation, playerDamageRange } from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('combat engine', () => {
  it('lets the player attack first and can finish a cow in one strong hit path', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(save, action, enemy)

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
    const save = createNewSave(launch)
    expect(playerDamageRange(launch, save)).toEqual({ min: 10, max: 30 })
  })

  it('grants combat XP/gold on victory and can consume food when hurt', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0058', 2)
    save = {
      ...save,
      currentHp: 900,
      equipment: {
        ...save.equipment,
        slots: { ...save.equipment.slots, 'SLOT-0011': 'ITEM-0058' },
      },
    }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const victory = applyCombatVictory(launch, save, action, enemy, () => 0)
    expect(victory.xpGained).toBe(6000)
    expect(victory.save.skills.find((skill) => skill.skillId === 'SKL-0001')?.xp).toBe(6000)
    expect(victory.goldGained).toBeGreaterThan(0)
    expect(victory.foodConsumed).toBe(true)
    expect(victory.save.currentHp).toBeGreaterThan(900)
    expect(victory.save.statistics.values.monsters_killed).toBe(1)
  })

  it('does not eat food at full HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0058', 1)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: { ...save.equipment.slots, 'SLOT-0011': 'ITEM-0058' },
      },
    }
    const result = tryConsumeFoodAfterVictory(launch, save)
    expect(result.consumed).toBe(false)
    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(1)
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
