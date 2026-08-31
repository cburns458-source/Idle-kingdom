import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { bossRespawnWaitUntilMs, generateNextAction } from '../activity/engine'
import { applyCombatVictory, beginCombatSave, resolveCombatRound } from './engine'
import { bossProfile, isBossEnemy } from './boss'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function saveAtQueen(db: ReturnType<typeof prepareDatabase>['launch']) {
  return {
    ...createNewSave(db),
    currentLocationId: 'LOC-0021',
    currentHp: 20_000,
    maxHp: 20_000,
  }
}

describe('dragon boss', () => {
  it('tags the Queen\'s dragon as a sleeping boss', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    expect(isBossEnemy(dragon)).toBe(true)
    expect(bossProfile(dragon)).toEqual({
      sleepStart: 4,
      wakeHpRatio: 0.5,
      rampageHpRatio: 0.25,
      respawnSeconds: 10,
      squidlingsAt: null,
      squidlingEnemyId: null,
      squidlingCount: 3,
      inkAt: null,
      inkChance: 0.35,
      damageMode: null,
      playerBaseHpScale: null,
      playerBaseDamagePctMin: null,
      playerBaseDamagePctMax: null,
    })
  })

  it('sleeps for four rounds, halves incoming damage, and does not attack', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!
    let save = beginCombatSave(launch, saveAtQueen(launch), action, dragon)
    expect(save.combatBossSleepRoundsRemaining).toBe(4)

    for (let round = 0; round < 4; round += 1) {
      const result = resolveCombatRound(launch, save, dragon, save.combatEnemyHp!, () => 0)
      expect(result.enemyAsleep).toBe(true)
      expect(result.enemyHit).toBeNull()
      expect(result.playerHp).toBe(save.currentHp)
      expect(result.playerHit).toBe(5)
      save = {
        ...save,
        combatEnemyHp: result.enemyHp,
        combatBossSleepRoundsRemaining: result.bossSleepRoundsRemaining,
        combatSkipEnemyAttack: result.skipNextEnemyAttack,
      }
    }
    expect(save.combatBossSleepRoundsRemaining).toBe(0)

    const awake = resolveCombatRound(launch, save, dragon, save.combatEnemyHp!, () => 0)
    expect(awake.enemyAsleep).toBe(false)
    expect(awake.enemyHit).toBeGreaterThan(0)
    expect(awake.playerHp).toBeLessThan(save.currentHp)
  })

  it('wakes next round after crossing half health and does not attack the crossing round', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!
    const started = beginCombatSave(launch, saveAtQueen(launch), action, dragon)
    const crossing = resolveCombatRound(
      launch,
      { ...started, combatBossSleepRoundsRemaining: 3 },
      dragon,
      12_510,
      () => 0.999,
    )
    expect(crossing.enemyAsleep).toBe(true)
    expect(crossing.enemyHit).toBeNull()
    expect(crossing.enemyHp).toBeLessThanOrEqual(12_500)
    expect(crossing.bossSleepRoundsRemaining).toBe(0)

    const next = resolveCombatRound(
      launch,
      {
        ...started,
        combatBossSleepRoundsRemaining: crossing.bossSleepRoundsRemaining,
        combatSkipEnemyAttack: crossing.skipNextEnemyAttack,
      },
      dragon,
      crossing.enemyHp,
      () => 0,
    )
    expect(next.enemyAsleep).toBe(false)
    expect(next.enemyHit).toBeGreaterThan(0)
  })

  it('doubles outgoing damage while rampaging', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!
    const started = beginCombatSave(launch, saveAtQueen(launch), action, dragon)
    const calm = resolveCombatRound(
      launch,
      { ...started, combatBossSleepRoundsRemaining: 0 },
      dragon,
      20_000,
      () => 0,
    )
    const rage = resolveCombatRound(
      launch,
      { ...started, combatBossSleepRoundsRemaining: 0 },
      dragon,
      6_000,
      () => 0,
    )
    expect(calm.enemyRampage).toBe(false)
    expect(rage.enemyRampage).toBe(true)
    expect(rage.enemyHit).toBe(calm.enemyHit! * 2)
  })

  it('waits 10 seconds after a kill before the next fight can start', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const save = {
      ...saveAtQueen(launch),
      currentActivityId: 'ACT-0024',
    }
    const victory = applyCombatVictory(launch, save, action, dragon, () => 0, now)
    expect(victory.save.bossRespawnUntilByEnemyId['ENM-0006']).toBe(
      new Date(now + 10_000).toISOString(),
    )
    expect(bossRespawnWaitUntilMs(launch, victory.save, 'ACT-0024')).toBe(now + 10_000)

    const waiting = generateNextAction(launch, victory.save, 'ACT-0024', () => 0, now + 1_000)
    expect(waiting?.save.combatEnemyId).toBeNull()

    const ready = generateNextAction(launch, victory.save, 'ACT-0024', () => 0, now + 10_000)
    expect(ready?.save.combatEnemyId).toBe('ENM-0006')
    expect(ready?.save.combatBossSleepRoundsRemaining).toBe(4)
  })
})
