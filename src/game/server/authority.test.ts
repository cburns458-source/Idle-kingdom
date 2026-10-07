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
