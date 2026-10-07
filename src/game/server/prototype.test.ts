import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { createNewSave } from '../save/saveStore'
import { prepareDatabase } from '../data/loadDatabase'
import { PHASE0_DEFAULT_AWAY_MS, runPhase0Prototype } from './prototype'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('phase 0 prototype', () => {
  it('times idle and gathering copies without needing a hosted save', () => {
    const result = runPhase0Prototype(rawDatabase)
    expect(result.phase).toBe(0)
    expect(result.awayMs).toBe(PHASE0_DEFAULT_AWAY_MS)
    expect(result.prepareDbMs).toBeGreaterThanOrEqual(0)
    expect(result.scenarios.map((row) => row.name)).toEqual(['idle', 'gathering'])

    const idle = result.scenarios[0]!
    expect(idle.advanceChanged).toBe(false)
    expect(idle.gatheringActions).toBe(0)
    expect(idle.effectiveElapsedMs).toBe(PHASE0_DEFAULT_AWAY_MS)

    const gathering = result.scenarios[1]!
    expect(gathering.gatheringActions).toBeGreaterThan(0)
    expect(gathering.unattendedChanged).toBe(true)
    expect(gathering.effectiveElapsedMs).toBe(PHASE0_DEFAULT_AWAY_MS)
  })

  it('times a hosted save copy as a third scenario', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hosted = createNewSave(launch, Date.parse('2026-01-01T00:00:00.000Z'))
    const result = runPhase0Prototype(rawDatabase, {
      hostedSave: hosted,
      awayMs: 60_000,
    })
    expect(result.awayMs).toBe(60_000)
    expect(result.scenarios.map((row) => row.name)).toEqual(['idle', 'gathering', 'hosted-copy'])
    expect(result.scenarios[2]!.name).toBe('hosted-copy')
  })
})
