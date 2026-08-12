import { getSession, isSignedIn } from '../multiplayer/auth'
import { getLocalBackend } from '../multiplayer/client'
import type { PlayerSave } from '../save/types'
import { isBountyReadyToClaim, syncBountyHour } from './progress'
import { hourlyBountyBoard } from './rotation'
import type { BountyClaimRecord, BountyDefinition, HourlyBountyBoard } from './types'

export function currentBountyBoard(nowMs: number = Date.now()): HourlyBountyBoard {
  return hourlyBountyBoard(nowMs)
}

export function listBountyClaims(hourKey: string): BountyClaimRecord[] {
  return getLocalBackend().listBountyClaims(hourKey)
}

export function claimForBounty(
  hourKey: string,
  bountyId: string,
): BountyClaimRecord | null {
  return getLocalBackend().getBountyClaim(hourKey, bountyId)
}

export function tryClaimBounty(
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
):
  | { ok: true; save: PlayerSave; claim: BountyClaimRecord; firstCompleter: boolean }
  | { ok: false; reason: string } {
  if (!isSignedIn()) return { ok: false, reason: 'Sign in to claim bounties.' }
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to claim bounties.' }

  let next = syncBountyHour(save, nowMs)
  const board = hourlyBountyBoard(nowMs)
  if (board.hourKey !== next.bountyHourKey) {
    return { ok: false, reason: 'This bounty board has rotated.' }
  }
  if (!board.bounties.some((row) => row.id === bounty.id)) {
    return { ok: false, reason: 'That bounty is not on the current board.' }
  }
  if ((next.bountyClaimedIds ?? []).includes(bounty.id)) {
    return { ok: false, reason: 'You already claimed this bounty.' }
  }
  if (!isBountyReadyToClaim(next, bounty, nowMs)) {
    return { ok: false, reason: 'Finish the bounty objective first.' }
  }

  const existing = getLocalBackend().getBountyClaim(board.hourKey, bounty.id)
  if (existing && existing.userId !== session.userId) {
    return {
      ok: false,
      reason: `Already claimed by ${existing.username}.`,
    }
  }

  const claimResult = getLocalBackend().claimBounty(session, board.hourKey, bounty.id)
  if (!claimResult.ok) return { ok: false, reason: claimResult.reason }

  const completed = Number(next.statistics.values.bounties_completed ?? 0) + 1
  next = {
    ...next,
    gold: next.gold + bounty.rewardGold,
    bountyClaimedIds: [...(next.bountyClaimedIds ?? []), bounty.id],
    statistics: {
      values: {
        ...next.statistics.values,
        bounties_completed: completed,
        gold_earned: Number(next.statistics.values.gold_earned ?? 0) + bounty.rewardGold,
      },
    },
  }

  return {
    ok: true,
    save: next,
    claim: claimResult.claim,
    firstCompleter: claimResult.firstCompleter,
  }
}
