import type { GameDatabase } from '../data/types'
import { getLocalBackend } from '../multiplayer/client'
import type { PlayerSave } from '../save/types'
import { turnInBounty } from './complete'
import { hourlyBountyBoard } from './rotation'
import type { BountyClaimRecord, BountyDefinition, HourlyBountyBoard } from './types'

export function currentBountyBoard(nowMs: number = Date.now()): HourlyBountyBoard {
  return hourlyBountyBoard(nowMs)
}

export function listBountyClaims(hourKey: string): BountyClaimRecord[] {
  return getLocalBackend().listBountyClaims(hourKey)
}

export function claimForBounty(hourKey: string, bountyId: string): BountyClaimRecord | null {
  return getLocalBackend().getBountyClaim(hourKey, bountyId)
}

/** Plaza notice-board claim / turn-in. */
export function tryClaimBounty(
  db: GameDatabase,
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
) {
  return turnInBounty(db, save, bounty, nowMs)
}
