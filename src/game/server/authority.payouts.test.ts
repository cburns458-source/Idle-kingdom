import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { applyBountyReward, prepareBountyTurnIn } from '../bounties/reward'
import { hourlyBountyBoard } from '../bounties/rotation'
import { prepareDatabase } from '../data/loadDatabase'
import { applyRankedPvpResult, RANKED_PVP_DAILY_CAP } from '../pvp/matchmaking'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { applyGameCommand } from './authority'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-08-12T21:00:00.000Z')

function command(
  save: PlayerSave,
  name: string,
  args: Record<string, unknown> = {},
  extra: Record<string, unknown> = {},
) {
  return applyGameCommand(rawDatabase, {
    command: name,
    args,
    save,
    nowMs: START_MS,
    random: () => 0,
    ...extra,
  })
}

function readyBountySave(launch: ReturnType<typeof prepareDatabase>['launch']): {
  save: PlayerSave
  bountyId: string
} {
  const board = hourlyBountyBoard(START_MS)
  const bounty = board.bounties.find((row) => row.kind === 'defeat') ?? board.bounties[0]!
  const base = createNewSave(launch, START_MS)
  return {
    bountyId: bounty.id,
    save: {
      ...base,
      bountyHourKey: board.hourKey,
      bountyProgress: { [bounty.id]: bounty.amount },
      inventory:
        bounty.kind === 'gather_deliver'
          ? [{ itemId: bounty.targetId, quantity: bounty.amount }]
          : base.inventory,
    },
  }
}

describe('ranked PvP and bounty authority', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('refuses a faked ranked win', () => {
    const save = createNewSave(launch, START_MS)
    const legacy = command(save, 'apply_ranked_pvp', { won: true })
    expect(legacy.ok).toBe(false)
    if (!legacy.ok) expect(legacy.reason).toBe('The server resolves ranked fights.')

    const faked = command(save, 'ranked_pvp_fight', { won: true }, { opponentSave: save })
    expect(faked.ok).toBe(false)
    if (!faked.ok) expect(faked.reason).toBe('The server resolves ranked fights.')
  })

  it('refuses an unknown or client-made fight id', () => {
    const save = createNewSave(launch, START_MS)
    const unknown = command(save, 'ranked_pvp_fight', { fightId: 'client-made-id' }, { opponentSave: save })
    expect(unknown.ok).toBe(false)
    if (!unknown.ok) expect(unknown.reason).toBe('Unknown ranked fight.')
  })

  it('pays a repeated fight id once', () => {
    const you = createNewSave(launch, START_MS)
    const them = createNewSave(launch, START_MS)
    const first = command(you, 'ranked_pvp_fight', {}, { opponentSave: them, issuedFightId: 'fight-1' })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    const goldAfterFirst = first.save.gold
    const replay = command(first.save, 'ranked_pvp_fight', { fightId: 'fight-1' }, {
      existingRankedFight: {
        fightId: 'fight-1',
        outcome: first.pvpOutcome ?? 'loss',
        goldGained: first.goldGained ?? 0,
        code: first.code,
        winsRemaining: first.winsRemaining,
        rounds: first.rounds ?? [],
        youMaxHp: first.youMaxHp ?? 0,
        themMaxHp: first.themMaxHp ?? 0,
      },
    })
    expect(replay.ok).toBe(true)
    if (!replay.ok) return
    expect(replay.save.gold).toBe(goldAfterFirst)
    expect(replay.goldGained).toBe(first.goldGained ?? 0)
    expect(replay.rounds).toEqual(first.rounds ?? [])
    expect(replay.code).toBe(first.code)
    expect(replay.winsRemaining).toBe(first.winsRemaining)
    expect(replay.youMaxHp).toBe(first.youMaxHp)
    expect(replay.themMaxHp).toBe(first.themMaxHp)
  })

  it('pays the sixth win nothing and returns daily_cap_reached', () => {
    const you = createNewSave(launch, START_MS)
    const them = {
      ...createNewSave(launch, START_MS),
      currentHp: 1,
    }
    let save = you
    let last = command(save, 'ranked_pvp_fight', {}, { opponentSave: them, issuedFightId: 'fight-0' })
    // Force five paid wins through the result helper if the simulated fight is a loss.
    if (!last.ok) return
    save = last.save
    while ((save.rankedPvpFightsToday ?? 0) < RANKED_PVP_DAILY_CAP) {
      save = applyRankedPvpResult(save, true, START_MS).save
    }
    const goldAtCap = save.gold
    const sixth = command(save, 'ranked_pvp_fight', {}, { opponentSave: them, issuedFightId: 'fight-6' })
    expect(sixth.ok).toBe(true)
    if (!sixth.ok) return
    if (sixth.pvpOutcome === 'win') {
      expect(sixth.goldGained).toBe(0)
      expect(sixth.code).toBe('daily_cap_reached')
      expect(sixth.save.gold).toBe(goldAtCap)
      expect(sixth.winsRemaining).toBe(0)
    } else {
      const forced = applyRankedPvpResult(save, true, START_MS)
      expect(forced.paid).toBe(false)
      expect(forced.code).toBe('daily_cap_reached')
      expect(forced.goldGained).toBe(0)
      expect(forced.save.gold).toBe(goldAtCap)
    }
  })

  it('pays again after midnight UTC once the daily win cap has reset', () => {
    const beforeMidnight = Date.parse('2026-08-13T23:59:59.000Z')
    const midnight = Date.parse('2026-08-14T00:00:00.000Z')
    let save = createNewSave(launch, beforeMidnight)
    while ((save.rankedPvpFightsToday ?? 0) < RANKED_PVP_DAILY_CAP) {
      save = applyRankedPvpResult(save, true, beforeMidnight).save
    }
    const goldAtCap = save.gold
    const sixth = applyRankedPvpResult(save, true, beforeMidnight)
    expect(sixth.paid).toBe(false)
    expect(sixth.code).toBe('daily_cap_reached')
    expect(sixth.winsRemaining).toBe(0)
    expect(sixth.save.gold).toBe(goldAtCap)

    const afterMidnight = applyRankedPvpResult(sixth.save, true, midnight)
    expect(afterMidnight.paid).toBe(true)
    expect(afterMidnight.code).toBeUndefined()
    expect(afterMidnight.winsRemaining).toBe(RANKED_PVP_DAILY_CAP - 1)
    expect(afterMidnight.save.gold).toBe(goldAtCap + 1000)
    expect(afterMidnight.save.rankedPvpFightsToday).toBe(1)
    expect(afterMidnight.save.rankedPvpDayKey).toBe('2026-08-14')
  })

  it('pays a bounty once and gives the first-place bonus only to the first claim', () => {
    const ready = readyBountySave(launch)
    const first = command(ready.save, 'bounty_turn_in', {
      bountyId: ready.bountyId,
      firstCompleter: true,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.firstCompleter).toBe(true)
    expect(first.goldGained).toBeGreaterThan(0)
    expect(first.save.bountyClaimedIds).toContain(ready.bountyId)

    const repeat = command(first.save, 'bounty_turn_in', {
      bountyId: ready.bountyId,
      firstCompleter: true,
    })
    expect(repeat.ok).toBe(false)
    if (!repeat.ok) expect(repeat.reason).toBe('You already claimed this bounty.')

    const later = command(ready.save, 'bounty_turn_in', {
      bountyId: ready.bountyId,
      firstCompleter: false,
    })
    expect(later.ok).toBe(true)
    if (!later.ok) return
    expect(later.firstCompleter).toBe(false)
    expect(later.goldGained).toBeLessThan(first.goldGained ?? 0)
  })

  it('keeps the first-place bonus off a second claimer through applyBountyReward', () => {
    const ready = readyBountySave(launch)
    const board = hourlyBountyBoard(START_MS)
    const bounty = board.bounties.find((row) => row.id === ready.bountyId)!
    const prepared = prepareBountyTurnIn(ready.save, bounty, START_MS)
    expect(prepared.ok).toBe(true)
    if (!prepared.ok) return
    const first = applyBountyReward(prepared.save, bounty, true)
    const later = applyBountyReward(prepared.save, bounty, false)
    expect(first.goldGained).toBe(later.goldGained + bounty.firstPlaceBonusGold)
    expect(first.goldGained).toBe(bounty.rewardGold + bounty.firstPlaceBonusGold)
  })
})
