import { describe, expect, it } from 'vitest'
import { createNewSave } from '../save/saveStore'
import { prepareDatabase } from '../data/loadDatabase'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  applyBountyDefeatProgress,
  applyBountyProcessProgress,
  bountyProgressFor,
  isBountyReadyToClaim,
  syncBountyHour,
} from './progress'
import { bountyHourKey, hourlyBountyBoard } from './rotation'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('bounty rotation', () => {
  it('is stable within the same UTC hour', () => {
    const now = Date.parse('2026-08-12T13:15:00.000Z')
    const a = hourlyBountyBoard(now)
    const b = hourlyBountyBoard(now + 60_000)
    expect(a.hourKey).toBe(bountyHourKey(now))
    expect(a.bounties.map((row) => row.id)).toEqual(b.bounties.map((row) => row.id))
    expect(a.bounties).toHaveLength(3)
  })

  it('changes across hour boundaries', () => {
    const a = hourlyBountyBoard(Date.parse('2026-08-12T13:59:00.000Z'))
    const b = hourlyBountyBoard(Date.parse('2026-08-12T14:00:00.000Z'))
    expect(a.hourKey).not.toBe(b.hourKey)
  })
})

describe('bounty progress', () => {
  it('tracks gather_deliver from inventory at turn-in time', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-08-12T13:15:00.000Z')
    const board = hourlyBountyBoard(now)
    const gather = board.bounties.find((row) => row.kind === 'gather_deliver')
    let save = syncBountyHour(createNewSave(launch), now)
    if (!gather) {
      expect(save.bountyHourKey).toBe(bountyHourKey(now))
      return
    }
    save = {
      ...save,
      inventory: [{ itemId: gather.targetId, quantity: gather.amount }],
    }
    expect(bountyProgressFor(save, gather, now)).toBe(gather.amount)
    expect(isBountyReadyToClaim(save, gather, now)).toBe(true)
  })

  it('tracks defeat and process objectives', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-08-12T10:00:00.000Z')
    let save = syncBountyHour(createNewSave(launch), now)
    const board = hourlyBountyBoard(now)
    const defeat = board.bounties.find((row) => row.kind === 'defeat')
    if (defeat) {
      for (let i = 0; i < defeat.amount; i += 1) {
        save = applyBountyDefeatProgress(save, defeat.targetId, 1, now)
      }
      expect(isBountyReadyToClaim(save, defeat, now)).toBe(true)
    }
    const process = board.bounties.find((row) => row.kind === 'process')
    if (process) {
      save = applyBountyProcessProgress(save, process.targetId, process.amount, now)
      expect(isBountyReadyToClaim(save, process, now)).toBe(true)
    }
  })
})
