import type { GameDatabase } from '../data/types'
import { getSession, isSignedIn } from '../multiplayer/auth'
import { getLocalBackend } from '../multiplayer/client'
import { submitLeaderboardFromSave } from '../multiplayer/leaderboards'
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

export type BountyTurnInResult =
  | {
      ok: true
      save: PlayerSave
      claim: BountyClaimRecord
      firstCompleter: boolean
      goldGained: number
    }
  | { ok: false; reason: string }

/**
 * Plaza notice-board turn-in.
 * Grants base gold to each eligible claimer; first server accept also gets first-place bonus.
 */
export function turnInBounty(
  db: GameDatabase,
  save: PlayerSave,
  bounty: BountyDefinition,
  nowMs: number = Date.now(),
): BountyTurnInResult {
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

  if (bounty.kind === 'gather_deliver') {
    const removed = consumeInventoryItems(next, bounty.targetId, bounty.amount)
    if (!removed.ok) return { ok: false, reason: removed.reason }
    next = removed.save
  }

  const claimResult = getLocalBackend().claimBounty(session, board.hourKey, bounty.id)
  if (!claimResult.ok) return { ok: false, reason: claimResult.reason }

  const bonus =
    claimResult.firstCompleter && claimResult.claim.userId === session.userId
      ? bounty.firstPlaceBonusGold
      : 0
  // If someone else already claimed first, still allow personal base reward.
  const goldGained = bounty.rewardGold + bonus
  const completed = Number(next.statistics.values.bounties_completed ?? 0) + 1
  next = {
    ...next,
    gold: next.gold + goldGained,
    bountyClaimedIds: [...(next.bountyClaimedIds ?? []), bounty.id],
    statistics: {
      values: {
        ...next.statistics.values,
        bounties_completed: completed,
        gold_earned: Number(next.statistics.values.gold_earned ?? 0) + goldGained,
      },
    },
  }

  void submitLeaderboardFromSave(db, next)

  return {
    ok: true,
    save: next,
    claim: claimResult.claim,
    firstCompleter: claimResult.firstCompleter && claimResult.claim.userId === session.userId,
    goldGained,
  }
}
