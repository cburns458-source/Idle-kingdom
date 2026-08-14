import type { GameDatabase } from '../data/types'
import { getSession, isSignedIn } from '../multiplayer/auth'
import { getLocalBackend } from '../multiplayer/client'
import { inventoryCount } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import { isBountyReadyToClaim, syncBountyHour } from './progress'
import { hourlyBountyBoard } from './rotation'
import type { BountyClaimRecord, BountyDefinition } from './types'

function consumeInventoryItems(
  save: PlayerSave,
  itemId: string,
  amount: number,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (inventoryCount(save, itemId) < amount) {
    return { ok: false, reason: 'Not enough items to deliver.' }
  }
  let remaining = amount
  const inventory = save.inventory
    .map((stack) => {
      if (stack.itemId !== itemId || remaining <= 0 || stack.enchantmentId) return stack
      const take = Math.min(stack.quantity, remaining)
      remaining -= take
      return { ...stack, quantity: stack.quantity - take }
    })
    .filter((stack) => stack.quantity > 0)
  if (remaining > 0) return { ok: false, reason: 'Not enough items to deliver.' }
  return { ok: true, save: { ...save, inventory } }
}

export type BountyTurnInCheck =
  | { ok: true; save: PlayerSave }
  | { ok: false; reason: string }

/**
 * Everything the turn-in decides locally: the board is current, the objective is
 * met, and any delivered items have left the bag. The returned save is what the
 * reward is applied to once a backend accepts the claim.
 */
export function prepareBountyTurnIn(
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number,
): BountyTurnInCheck {
  const next = syncBountyHour(save, nowMs)
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
  if (bounty.kind === 'gather_deliver') {
    return consumeInventoryItems(next, bounty.targetId, bounty.amount)
  }
  return { ok: true, save: next }
}

export interface BountyRewardResult {
  save: PlayerSave
  goldGained: number
}

/**
 * Pay out a bounty a backend has accepted. Everyone eligible earns the base
 * reward; only the claim the server recorded first adds the bonus.
 */
export function applyBountyReward(
  save: PlayerSave,
  bounty: BountyDefinition,
  firstCompleter: boolean,
): BountyRewardResult {
  const goldGained = bounty.rewardGold + (firstCompleter ? bounty.firstPlaceBonusGold : 0)
  return {
    save: {
      ...save,
      gold: save.gold + goldGained,
      bountyClaimedIds: [...(save.bountyClaimedIds ?? []), bounty.id],
      statistics: {
        values: {
          ...save.statistics.values,
          bounties_completed: Number(save.statistics.values.bounties_completed ?? 0) + 1,
          gold_earned: Number(save.statistics.values.gold_earned ?? 0) + goldGained,
        },
      },
    },
    goldGained,
  }
}

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
