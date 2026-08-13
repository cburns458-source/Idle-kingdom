import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { syncBountyHour } from './progress'
import { hourlyBountyBoard } from './rotation'
import type { BountyClaimRecord, BountyDefinition } from './types'
import { bountyClaimedNotice, bountyRotationLine, bountyRowView, bountyRows } from './views'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)

const NOW = Date.parse('2026-08-12T13:15:00.000Z')

const BOUNTY: BountyDefinition = {
  id: 'BNT-TEST',
  title: 'Cut ten logs',
  description: 'The carpenters are short again.',
  kind: 'process',
  targetId: 'RCP-0001',
  amount: 10,
  rewardGold: 120,
  firstPlaceBonusGold: 60,
}

function claim(username: string): BountyClaimRecord {
  return {
    hourKey: hourlyBountyBoard(NOW).hourKey,
    bountyId: BOUNTY.id,
    userId: 'usr-1',
    username,
    claimedAt: new Date(NOW).toISOString(),
  }
}

function startedSave() {
  return syncBountyHour(createNewSave(launch, NOW), NOW)
}

describe('bounty rows', () => {
  it('counts what is done against what is asked', () => {
    const save = { ...startedSave(), bountyProgress: { [BOUNTY.id]: 4 } }
    const row = bountyRowView(save, BOUNTY, null, true, NOW)
    expect(row.progressLine).toBe('4 / 10 · 120 gold (+60 first)')
    expect(row.actionLabel).toBe('In progress')
    expect(row.canTurnIn).toBe(false)
    expect(row.firstCompleterLine).toBeNull()
  })

  it('never counts past the objective', () => {
    const save = { ...startedSave(), bountyProgress: { [BOUNTY.id]: 99 } }
    expect(bountyRowView(save, BOUNTY, null, true, NOW).progressLine).toBe(
      '10 / 10 · 120 gold (+60 first)',
    )
  })

  it('leaves the bonus out when a bounty has none', () => {
    const save = startedSave()
    const plain = { ...BOUNTY, firstPlaceBonusGold: 0 }
    expect(bountyRowView(save, plain, null, true, NOW).progressLine).toBe('0 / 10 · 120 gold')
  })

  it('offers the turn-in once the objective is met', () => {
    const save = { ...startedSave(), bountyProgress: { [BOUNTY.id]: 10 } }
    const row = bountyRowView(save, BOUNTY, null, true, NOW)
    expect(row.actionLabel).toBe('Turn in')
    expect(row.canTurnIn).toBe(true)
  })

  it('withholds the turn-in from a signed-out player', () => {
    const save = { ...startedSave(), bountyProgress: { [BOUNTY.id]: 10 } }
    const row = bountyRowView(save, BOUNTY, null, false, NOW)
    expect(row.actionLabel).toBe('Turn in')
    expect(row.canTurnIn).toBe(false)
  })

  it('says so once the player has claimed it', () => {
    const save = {
      ...startedSave(),
      bountyProgress: { [BOUNTY.id]: 10 },
      bountyClaimedIds: [BOUNTY.id],
    }
    const row = bountyRowView(save, BOUNTY, null, true, NOW)
    expect(row.actionLabel).toBe('Claimed')
    expect(row.canTurnIn).toBe(false)
  })

  it('names whoever got there first', () => {
    const row = bountyRowView(startedSave(), BOUNTY, claim('Rowan'), true, NOW)
    expect(row.firstCompleterLine).toBe('First completer: Rowan')
  })

  it('matches a claim to its own bounty and no other', () => {
    const board = hourlyBountyBoard(NOW)
    const first = board.bounties[0]!
    const claims: BountyClaimRecord[] = [{ ...claim('Rowan'), bountyId: first.id }]
    const rows = bountyRows(startedSave(), board, claims, true, NOW)
    expect(rows).toHaveLength(board.bounties.length)
    expect(rows[0]!.firstCompleterLine).toBe('First completer: Rowan')
    expect(rows.slice(1).every((row) => row.firstCompleterLine === null)).toBe(true)
  })
})

describe('bounty board wording', () => {
  it('puts the countdown the client formatted into the rotation line', () => {
    expect(bountyRotationLine('44m 5s')).toBe(
      'Rotates in 44m 5s. First turn-in earns a bonus; others can still claim the base reward.',
    )
  })

  it('celebrates a first turn-in and acknowledges the rest', () => {
    expect(bountyClaimedNotice(180, true)).toBe('First completer! +180 gold.')
    expect(bountyClaimedNotice(120, false)).toBe('Bounty claimed. +120 gold.')
  })
})
