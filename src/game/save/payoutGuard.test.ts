import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from './saveStore'
import { clientSaveRaisesPayouts, replaceUnauthorizedPayouts } from './payoutGuard'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-08-13T18:00:00.000Z')

describe('client payout guard', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('replaces inflated gold, a claimed bounty, and raised PvP counters', () => {
    const server = {
      ...createNewSave(launch, START_MS),
      gold: 40,
      bountyClaimedIds: [] as string[],
      rankedPvpWins: 1,
      rankedPvpLosses: 0,
      rankedPvpDayKey: '2026-08-13',
      rankedPvpFightsToday: 1,
    }
    const client = {
      ...server,
      gold: 40_000,
      bountyClaimedIds: ['BNT-0001'],
      rankedPvpWins: 9,
      rankedPvpLosses: 3,
      rankedPvpFightsToday: 5,
      motto: 'honest other progress',
    }
    expect(clientSaveRaisesPayouts(server, client)).toBe(true)
    const next = replaceUnauthorizedPayouts(server, client)
    expect(next.gold).toBe(40)
    expect(next.bountyClaimedIds).toEqual([])
    expect(next.rankedPvpWins).toBe(1)
    expect(next.rankedPvpLosses).toBe(0)
    expect(next.rankedPvpFightsToday).toBe(1)
    expect(next.motto).toBe('honest other progress')
  })

  it('keeps a client save that did not raise payouts', () => {
    const server = { ...createNewSave(launch, START_MS), gold: 80 }
    const client = { ...server, motto: 'still me' }
    expect(clientSaveRaisesPayouts(server, client)).toBe(false)
    expect(replaceUnauthorizedPayouts(server, client).gold).toBe(80)
  })
})
