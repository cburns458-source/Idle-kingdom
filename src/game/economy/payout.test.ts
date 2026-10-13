import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { payReward } from './payout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('shared gold payout', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('adds gold and gold_earned for the gold reward kind', () => {
    const save = createNewSave(launch, Date.parse('2026-08-13T18:00:00.000Z'))
    const paid = payReward(save, { type: 'gold', amount: 1000 })
    expect(paid.paid).toBe(1000)
    expect(paid.save.gold).toBe(save.gold + 1000)
    expect(paid.save.statistics.values.gold_earned).toBe(1000)
  })
})
