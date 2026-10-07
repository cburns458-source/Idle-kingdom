import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { beginActivitySave, generateNextAction } from '../activity/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { compareShadowSaves, runPhase1Shadow } from './shadow'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('phase 1 shadow', () => {
  it('matches an idle window the client already caught up', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const previous = {
      ...createNewSave(launch, START_MS),
      unattendedProgressAt: new Date(START_MS).toISOString(),
    }
    const later = START_MS + 180_000
    const current = {
      ...previous,
      playTimeMs: 180_000,
      unattendedProgressAt: new Date(later).toISOString(),
      updatedAt: new Date(later).toISOString(),
    }
    const result = runPhase1Shadow(rawDatabase, {
      previousClientSave: previous,
      currentClientSave: current,
      nowMs: later,
    })
    expect(result.phase).toBe(1)
    expect(result.replayMatched).toBe(true)
    expect(result.replay).toEqual([])
    expect(result.timing.effectiveElapsedMs).toBe(180_000)
  })

  it('names gold and bag diffs when the client invented wealth', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const previous = createNewSave(launch, START_MS)
    const current = { ...previous, gold: previous.gold + 999_999 }
    const diffs = compareShadowSaves(current, previous)
    expect(diffs.some((row) => row.field === 'gold')).toBe(true)
  })

  it('replays a gathering window without throwing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0009' }
    save = beginActivitySave(save, 'ACT-0012', new Date(START_MS).toISOString())
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0, START_MS)
    expect(generated).toBeTruthy()
    const previous = {
      ...generated!.save,
      unattendedProgressAt: new Date(START_MS).toISOString(),
    }
    const later = START_MS + 180_000
    const result = runPhase1Shadow(rawDatabase, {
      previousClientSave: previous,
      currentClientSave: previous,
      nowMs: later,
    })
    expect(result.timing.gatheringActions).toBeGreaterThan(0)
    expect(result.replay.some((row) => row.field === 'unattendedProgressAt')).toBe(true)
  })
})
