import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand, runPhase2Sync } from './authority'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('phase 2 authority', () => {
  it('creates a named character', () => {
    const created = applyGameCommand(rawDatabase, {
      command: 'create_character',
      args: { name: 'Vari', raceId: 'RACE-0001' },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(created.ok).toBe(true)
    if (!created.ok) return
    expect(created.save.characterName).toBe('Vari')
    expect(created.save.raceId).toBe('RACE-0001')
  })

  it('advances an idle save without inventing gold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch, START_MS),
      unattendedProgressAt: new Date(START_MS).toISOString(),
    }
    const later = START_MS + 180_000
    const result = runPhase2Sync(rawDatabase, {
      save,
      nowMs: later,
      rngState: 1,
    })
    expect(result.save.gold).toBe(save.gold)
    expect(result.effectiveElapsedMs).toBeGreaterThan(0)
  })

  it('starts meadow gathering from a command', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0009' }
    const started = applyGameCommand(rawDatabase, {
      command: 'start_activity',
      args: { activityId: 'ACT-0012' },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(started.ok).toBe(true)
    if (!started.ok) return
    expect(started.save.currentActivityId).toBe('ACT-0012')
  })

  it('gathers then sells from the hosted copy after time passes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0001' }
    const started = applyGameCommand(rawDatabase, {
      command: 'start_activity',
      args: { activityId: 'ACT-0021' },
      save,
      nowMs: START_MS,
      random: () => 0.1,
    })
    expect(started.ok).toBe(true)
    if (!started.ok) return

    const later = START_MS + 30_000
    const caughtUp = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: {},
      save: started.save,
      nowMs: later,
      random: () => 0.1,
    })
    expect(caughtUp.ok).toBe(true)
    if (!caughtUp.ok) return
    expect(caughtUp.save.inventory.length).toBeGreaterThan(0)

    const sold = applyGameCommand(rawDatabase, {
      command: 'sell_inventory',
      args: { indexes: caughtUp.save.inventory.map((_, index) => index) },
      save: caughtUp.save,
      nowMs: later,
      random: () => 0.1,
    })
    expect(sold.ok).toBe(true)
    if (!sold.ok) return
    expect(sold.save.gold).toBeGreaterThan(caughtUp.save.gold)
    expect(sold.save.inventory).toHaveLength(0)
  })

  it('keeps the hosted save on ranking and PvP publish commands', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), gold: 12 }
    for (const command of ['submit_leaderboard', 'save_pvp_equipment'] as const) {
      const result = applyGameCommand(rawDatabase, {
        command,
        save,
        nowMs: START_MS,
        random: () => 0,
      })
      expect(result.ok).toBe(true)
      if (!result.ok) return
      expect(result.save.gold).toBe(12)
    }
  })

  it('refuses an unknown command', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const refused = applyGameCommand(rawDatabase, {
      command: 'not_a_command',
      save: createNewSave(launch, START_MS),
      nowMs: START_MS,
      random: () => 0,
    })
    expect(refused.ok).toBe(false)
  })
})
