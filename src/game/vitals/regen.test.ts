import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { playerMaxHp } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyNaturalHpRegen, NATURAL_HP_REGEN_PER_MINUTE, naturalHpRegenIntervalMs } from './regen'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('natural HP regen', () => {
  it('grants 1 HP every 6 seconds and 10 per minute', () => {
    expect(NATURAL_HP_REGEN_PER_MINUTE).toBe(10)
    expect(naturalHpRegenIntervalMs()).toBe(6_000)
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch), currentHp: 1 }
    const six = applyNaturalHpRegen(launch, save, 6_000)
    expect(six.save.currentHp).toBe(2)
    expect(six.remainderMs).toBe(0)
    const minute = applyNaturalHpRegen(launch, save, 60_000)
    expect(minute.save.currentHp).toBe(11)
  })

  it('skips regen in combat and drops leftover', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch), currentHp: 1, combatEnemyId: 'ENM-0001' }
    const result = applyNaturalHpRegen(launch, save, 60_000)
    expect(result.save.currentHp).toBe(1)
    expect(result.remainderMs).toBe(0)
  })

  it('still regens during thievery and other non-combat work', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentHp: 1,
      currentActivityId: 'ACT-0012',
      combatEnemyId: null,
    }
    const result = applyNaturalHpRegen(launch, save, 6_000)
    expect(result.save.currentHp).toBe(2)
  })

  it('caps at max HP and keeps a remainder only while damaged', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const maxHp = playerMaxHp(launch, base)
    const almost = applyNaturalHpRegen(launch, { ...base, currentHp: maxHp - 1 }, 12_000)
    expect(almost.save.currentHp).toBe(maxHp)
    expect(almost.remainderMs).toBe(0)
    const partial = applyNaturalHpRegen(launch, { ...base, currentHp: 1 }, 2_500)
    expect(partial.save.currentHp).toBe(1)
    expect(partial.remainderMs).toBe(2_500)
  })
})
