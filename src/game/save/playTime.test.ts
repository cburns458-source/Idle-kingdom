import { describe, expect, it } from 'vitest'
import { accruePlayTime, creditElapsedPlayTime, livePlayCreditMs } from './playTime'
import { createNewSave } from './saveStore'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('play time', () => {
  it('adds finite positive spans and ignores the rest', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source)
    expect(accruePlayTime(save, 1500).playTimeMs).toBe(1500)
    expect(accruePlayTime(save, 0)).toBe(save)
    expect(accruePlayTime(save, -20)).toBe(save)
    expect(accruePlayTime(save, Number.NaN)).toBe(save)
  })

  it('caps a live gap at the unattended window', () => {
    const hour = 3_600_000
    expect(livePlayCreditMs(1_000, 24 * hour)).toBe(1_000)
    expect(livePlayCreditMs(48 * hour, 24 * hour)).toBe(24 * hour)
    expect(livePlayCreditMs(-5, 24 * hour)).toBe(0)

    const { source } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(source), playTimeMs: 500 }
    expect(creditElapsedPlayTime(save, 48 * hour, 24 * hour).playTimeMs).toBe(500 + 24 * hour)
  })
})
