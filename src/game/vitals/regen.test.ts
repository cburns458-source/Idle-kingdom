import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { playerMaxHp } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  applyNaturalHpRegen,
  NATURAL_HP_REGEN_BASE_PERCENT,
  NATURAL_HP_REGEN_IDLE_SECONDS,
  NATURAL_HP_REGEN_TRIGGER_MS,
  naturalHpRegenHealAmount,
  naturalHpRegenIdleMs,
  notePlayerDamaged,
} from './regen'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('natural HP regen', () => {
  it('waits 60s then heals 1% max HP per minute, doubling each streak step', () => {
    expect(NATURAL_HP_REGEN_IDLE_SECONDS).toBe(60)
    expect(NATURAL_HP_REGEN_BASE_PERCENT).toBe(1)
    expect(NATURAL_HP_REGEN_TRIGGER_MS).toBe(60_000)
    expect(naturalHpRegenIdleMs()).toBe(60_000)
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const save = { ...base, currentHp: 1 }
    const firstHeal = naturalHpRegenHealAmount(maxHp, 0)
    const minute = applyNaturalHpRegen(launch, save, 60_000, now)
    expect(minute.save.currentHp).toBe(1 + firstHeal)
    expect(minute.save.hpRegenStreak).toBe(1)
    expect(minute.remainderMs).toBe(0)

    const twoMinutes = applyNaturalHpRegen(launch, save, 120_000, now)
    const secondHeal = naturalHpRegenHealAmount(maxHp, 1)
    expect(twoMinutes.save.currentHp).toBe(1 + firstHeal + secondHeal)
    expect(twoMinutes.save.hpRegenStreak).toBe(2)
  })

  it('still regens in combat once the idle gate has passed', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const save = {
      ...base,
      currentHp: 1,
      combatEnemyId: 'ENM-0001',
      lastDamagedAt: new Date(now - 120_000).toISOString(),
    }
    const result = applyNaturalHpRegen(launch, save, 60_000, now)
    expect(result.save.currentHp).toBe(1 + naturalHpRegenHealAmount(maxHp, 0))
  })

  it('blocks regen for 60s after damage and resets the streak', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const damaged = notePlayerDamaged({ ...base, currentHp: 1, hpRegenStreak: 3 }, now - 30_000)
    expect(damaged.hpRegenStreak).toBe(0)
    const blocked = applyNaturalHpRegen(launch, damaged, 30_000, now)
    expect(blocked.save.currentHp).toBe(1)
    expect(blocked.remainderMs).toBe(0)

    const afterGate = applyNaturalHpRegen(launch, damaged, 90_000, now + 60_000)
    const maxHp = playerMaxHp(launch, base)
    expect(afterGate.save.currentHp).toBe(1 + naturalHpRegenHealAmount(maxHp, 0))
  })

  it('still regens during thievery and other non-combat work', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const save = {
      ...base,
      currentHp: 1,
      currentActivityId: 'ACT-0012',
      combatEnemyId: null,
    }
    const result = applyNaturalHpRegen(launch, save, 60_000, now)
    expect(result.save.currentHp).toBe(1 + naturalHpRegenHealAmount(maxHp, 0))
  })

  it('caps at max HP, clears streak, and keeps a remainder only while damaged', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const almost = applyNaturalHpRegen(launch, { ...base, currentHp: maxHp - 1 }, 60_000, now)
    expect(almost.save.currentHp).toBe(maxHp)
    expect(almost.save.hpRegenStreak).toBe(0)
    expect(almost.remainderMs).toBe(0)
    const partial = applyNaturalHpRegen(launch, { ...base, currentHp: 1 }, 2_500, now)
    expect(partial.save.currentHp).toBe(1)
    expect(partial.remainderMs).toBe(2_500)
  })

  it('leaves blessing surplus above max alone', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const surplus = maxHp + Math.floor(maxHp * 0.1)
    const now = Date.parse('2026-01-01T01:00:00.000Z')
    const result = applyNaturalHpRegen(launch, { ...base, currentHp: surplus }, 60_000, now)
    expect(result.save.currentHp).toBe(surplus)
    expect(result.remainderMs).toBe(0)
  })
})
