import type { GameDatabase } from '../data/types'
import { getSession, isSignedIn } from '../multiplayer/auth'
import { getLocalBackend } from '../multiplayer/client'
import type { PlayerSave } from '../save/types'
import { hourlyBountyBoard } from './rotation'
import { applyBountyReward, prepareBountyTurnIn } from './reward'
import type { BountyClaimRecord, BountyDefinition } from './types'

export { applyBountyReward, prepareBountyTurnIn } from './reward'
export type { BountyRewardResult, BountyTurnInCheck } from './reward'

export type BountyTurnInResult =
  | {
      ok: true
      save: PlayerSave
      claim: BountyClaimRecord
      firstCompleter: boolean
      goldGained: number
    }
  | { ok: false; reason: string }

/** Plaza notice-board turn-in, against the signed-in player's backend. */
export function turnInBounty(
  _db: GameDatabase,
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
): BountyTurnInResult {
  if (!isSignedIn()) return { ok: false, reason: 'Sign in to claim bounties.' }
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to claim bounties.' }

  const prepared = prepareBountyTurnIn(save, bounty, nowMs)
  if (!prepared.ok) return prepared

  const hourKey = hourlyBountyBoard(nowMs).hourKey
  const claimResult = getLocalBackend().claimBounty(session, hourKey, bounty.id)
  if (!claimResult.ok) return { ok: false, reason: claimResult.reason }

  const firstCompleter =
    claimResult.firstCompleter && claimResult.claim.userId === session.userId
  const rewarded = applyBountyReward(prepared.save, bounty, firstCompleter)

  return {
    ok: true,
    save: rewarded.save,
    claim: claimResult.claim,
    firstCompleter,
    goldGained: rewarded.goldGained,
  }
}
