import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { beginCombatSave } from './engine'
import {
  massDropScale,
  massHealthMultiplier,
  massHpFor,
  massMinimumDamage,
} from './boss'
import {
  massEncounterHp,
  simulateMassFightTick,
} from './mass'
import { enemyScaledMaxHp, playerBaseMaxHp } from './stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('mass boss formulas', () => {
  it('adds 50% of solo HP per extra player', () => {
    expect(massHealthMultiplier(1)).toBe(1)
    expect(massHealthMultiplier(2)).toBe(1.5)
    expect(massHealthMultiplier(3)).toBe(2)
    expect(massHpFor(1000, 1)).toBe(1000)
    expect(massHpFor(1000, 2)).toBe(1500)
    expect(massHpFor(1000, 3)).toBe(2000)
  })

  it('keeps solo drop scale at 1× and uses 0.9 * health / n for groups', () => {
    expect(massDropScale(1)).toBe(1)
    expect(massDropScale(2)).toBeCloseTo(0.675)
    expect(massDropScale(3)).toBeCloseTo(0.6)
  })

  it('uses min(3%, 25%/n) of total HP as the reward floor', () => {
    expect(massMinimumDamage(1000, 1)).toBe(30)
    expect(massMinimumDamage(1000, 10)).toBe(25)
    expect(massMinimumDamage(1000, 100)).toBe(2.5)
  })

  it('scales dragon HP from the sheet and squid HP from average player base HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const squid = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0023')!
    const save = { ...createNewSave(launch), currentHp: 20_000, maxHp: 20_000 }
    const dragonSolo = enemyScaledMaxHp(dragon)
    const scaled = massEncounterHp(launch, dragon, 4, [playerBaseMaxHp(launch, save)])
    expect(scaled.soloHp).toBe(dragonSolo)
    expect(scaled.healthMultiplier).toBe(2.5)
    expect(scaled.totalHp).toBe(massHpFor(dragonSolo, 4))
    expect(scaled.dropScale).toBe(massDropScale(4))

    const low = 1000
    const high = 3000
    const squidHp = massEncounterHp(launch, squid, 2, [low, high])
    expect(squidHp.soloHp).toBe(Math.floor(((low + high) / 2) * 2.2))
    expect(squidHp.totalHp).toBe(massHpFor(squidHp.soloHp, 2))
  })

  it('keeps baby dragon and baby squid pet bases at 0.1%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!
    const squid = launch.Actions.find((row) => row['Action ID'] === 'ACN-0178')!
    expect(dragon['Secondary Drop Chance']).toBe(0.1)
    expect(dragon['Secondary Reward Table ID']).toBe('RWT-0180')
    expect(squid['Secondary Drop Chance']).toBe(0.1)
    expect(squid['Secondary Reward Table ID']).toBe('RWT-0203')
    const squidPet = launch.RewardEntries.filter((row) => row['Reward Table ID'] === 'RWT-0203')
    expect(squidPet).toHaveLength(1)
    expect(squidPet[0]?.['Reward ID / Value']).toBe('COS-0020')
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0443')?.Tradeable).toBe(false)
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0404')?.Tradeable).toBe(false)
  })
})

describe('simulateMassFightTick', () => {
  it('starts combat without dealing damage, then ignores early and duplicate clocks', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dragon = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!
    const startMs = Date.parse('2026-01-01T00:00:00.000Z')
    let save = {
      ...createNewSave(launch, startMs),
      currentLocationId: 'LOC-0021',
      currentHp: 20_000,
      maxHp: 20_000,
    }
    const started = simulateMassFightTick(launch, save, {
      nowMs: startMs,
      random: () => 0,
      encounterId: 'enc-1',
      enemyId: 'ENM-0006',
      sharedRemainingHp: 1000,
      healthMultiplier: 1,
      lockedIn: true,
      late: false,
      lastRoundStartedAt: null,
    })
    expect(started.started).toBe(true)
    expect(started.damageDealt).toBe(0)
    save = started.save
    expect(save.massEncounterId).toBe('enc-1')
    expect(save.combatEnemyId).toBe(dragon['Enemy ID'])

    const early = simulateMassFightTick(launch, save, {
      nowMs: startMs + 1000,
      random: () => 0,
      encounterId: 'enc-1',
      enemyId: 'ENM-0006',
      sharedRemainingHp: 1000,
      healthMultiplier: 1,
      lockedIn: true,
      late: false,
      lastRoundStartedAt: save.combatRoundStartedAt,
    })
    expect(early.early).toBe(true)
    expect(early.damageDealt).toBe(0)

    const due = Date.parse(save.combatRoundStartedAt!) + 6_000
    const first = simulateMassFightTick(launch, save, {
      nowMs: due,
      random: () => 0,
      encounterId: 'enc-1',
      enemyId: 'ENM-0006',
      sharedRemainingHp: 1000,
      healthMultiplier: 1,
      lockedIn: true,
      late: false,
      lastRoundStartedAt: null,
    })
    expect(first.early).toBe(false)
    expect(first.duplicate).toBe(false)
    expect(first.damageDealt).toBeGreaterThan(0)

    const dup = simulateMassFightTick(launch, save, {
      nowMs: due,
      random: () => 0,
      encounterId: 'enc-1',
      enemyId: 'ENM-0006',
      sharedRemainingHp: 1000,
      healthMultiplier: 1,
      lockedIn: true,
      late: false,
      lastRoundStartedAt: save.combatRoundStartedAt,
    })
    expect(dup.duplicate).toBe(true)
    expect(dup.damageDealt).toBe(0)
  })

  it('does not change shared HP for a late joiner', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const startMs = Date.parse('2026-01-01T00:00:00.000Z')
    const begun = beginCombatSave(
      launch,
      {
        ...createNewSave(launch, startMs),
        currentLocationId: 'LOC-0021',
        currentHp: 20_000,
        maxHp: 20_000,
        massEncounterId: 'enc-1',
      },
      launch.Actions.find((row) => row['Action ID'] === 'ACN-0092')!,
      launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0006')!,
      new Date(startMs).toISOString(),
      5000,
    )
    const due = Date.parse(begun.combatRoundStartedAt!) + 6_000
    const tick = simulateMassFightTick(launch, begun, {
      nowMs: due,
      random: () => 0,
      encounterId: 'enc-1',
      enemyId: 'ENM-0006',
      sharedRemainingHp: 5000,
      healthMultiplier: 1.5,
      lockedIn: false,
      late: true,
      lastRoundStartedAt: null,
    })
    expect(tick.damageDealt).toBe(0)
    expect(tick.early).toBe(false)
  })
})
