import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { FISHING_SKILL_ID } from '../skills/skillActions'
import { applySquidlingVictory, beginBossAddsEncounter, isSquidlingVictory } from './bossPhase'
import {
  bossProfile,
  enemyEncounterDamageRange,
  enemyEncounterMaxHp,
} from './boss'
import { applyCombatVictory, beginCombatSave, resolveCombatRound } from './engine'
import { fishingCombatDamageRange, playerBaseMaxHp } from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function saveAtDepths(db: ReturnType<typeof prepareDatabase>['launch']) {
  return {
    ...createNewSave(db),
    currentLocationId: 'LOC-0042',
    currentHp: 20_000,
    maxHp: 20_000,
    skills: createNewSave(db).skills.map((row) =>
      row.skillId === FISHING_SKILL_ID ? { ...row, level: 25 } : row,
    ),
  }
}

describe('mother squid boss', () => {
  it('parses squidling, ink, fishing damage, and player-base scaling notes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    expect(bossProfile(squid)).toMatchObject({
      squidlingsAt: 0.5,
      squidlingEnemyId: 'ENM-0024',
      squidlingCount: 3,
      inkAt: 0.25,
      inkChance: 0.35,
      damageMode: 'fishing',
      respawnSeconds: 30,
      sleepStart: 0,
      playerBaseHpScale: 2,
      playerBaseDamagePctMin: 8,
      playerBaseDamagePctMax: 12,
    })
  })

  it('scales encounter HP to 2× player base HP and damage to 8–12%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0178')!
    const save = saveAtDepths(launch)
    const baseHp = playerBaseMaxHp(launch, save)
    expect(baseHp).toBe(1000)
    expect(enemyEncounterMaxHp(launch, save, squid)).toBe(2000)
    expect(enemyEncounterDamageRange(launch, save, squid)).toEqual({ min: 80, max: 120 })

    const started = beginCombatSave(launch, save, action, squid)
    expect(started.combatEnemyHp).toBe(2000)
  })

  it('uses fishing ATR and level for damage instead of weapon range', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = saveAtDepths(launch)
    const range = fishingCombatDamageRange(launch, save)
    expect(range.min).toBeGreaterThan(1)
    expect(range.max).toBeGreaterThanOrEqual(range.min)
  })

  it('releases squidlings at half health and restores the boss afterward', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    const squidling = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0024')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0178')!
    let save = beginCombatSave(launch, saveAtDepths(launch), action, squid)
    const maxHp = enemyEncounterMaxHp(launch, save, squid)
    const half = maxHp * 0.5

    const range = fishingCombatDamageRange(launch, save)
    const triggerHp = half + range.min
    const trigger = resolveCombatRound(launch, save, squid, triggerHp, () => 0)
    expect(trigger.bossAddsTriggered).toBe(true)
    expect(trigger.bossPendingHp).toBeLessThanOrEqual(half)

    save = beginBossAddsEncounter(
      launch,
      { ...save, currentHp: trigger.playerHp },
      squid,
      bossProfile(squid)!,
      trigger.bossPendingHp!,
      new Date().toISOString(),
    )
    expect(save.combatEnemyId).toBe('ENM-0024')
    expect(save.combatBossAddsRemaining).toBe(3)
    expect(save.combatBossPendingHp).toBe(trigger.bossPendingHp)

    for (let i = 0; i < 3; i += 1) {
      expect(isSquidlingVictory(save, squidling)).toBe(true)
      const pendingHp = save.combatBossPendingHp!
      const result = applySquidlingVictory(
        launch,
        { ...save, combatEnemyHp: 0 },
        squidling,
        new Date().toISOString(),
      )
      save = result.save
      if (i < 2) {
        expect(result.bossResumed).toBe(false)
        expect(save.combatEnemyId).toBe('ENM-0024')
      } else {
        expect(result.bossResumed).toBe(true)
        expect(save.combatEnemyId).toBe('ENM-0023')
        expect(save.combatBossPendingHp).toBeNull()
        expect(save.combatEnemyHp).toBe(pendingHp)
      }
    }
  })

  it('halves fishing damage when ink procs below one quarter health', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0178')!
    const save = beginCombatSave(launch, saveAtDepths(launch), action, squid)
    const baseSave = { ...save, combatBossAddsTriggered: true }
    const quarterHp = enemyEncounterMaxHp(launch, save, squid) * 0.25 - 1

    const inked = resolveCombatRound(launch, baseSave, squid, quarterHp, () => 0)
    expect(inked.bossInkActive).toBe(true)

    let rolls = 0
    const noInk = resolveCombatRound(launch, baseSave, squid, quarterHp, () => {
      rolls += 1
      return rolls === 1 ? 0.99 : 0
    })
    expect(noInk.bossInkActive).toBe(false)
    expect(inked.playerHit).toBeLessThan(noInk.playerHit)
  })

  it('sets a respawn timer after the boss is defeated', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0178')!
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const victory = applyCombatVictory(launch, saveAtDepths(launch), action, squid, () => 0, now)
    expect(victory.save.bossRespawnUntilByEnemyId['ENM-0023']).toBe(
      new Date(now + 30_000).toISOString(),
    )
  })
})
