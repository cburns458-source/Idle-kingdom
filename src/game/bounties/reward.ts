import { payReward } from '../economy/payout'
import { inventoryCount } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import { isBountyReadyToClaim, syncBountyHour } from './progress'
import { hourlyBountyBoard } from './rotation'
import type { BountyDefinition } from './types'

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
  const payout = payReward(save, { type: 'gold', amount: goldGained })
  return {
    save: {
      ...payout.save,
      bountyClaimedIds: [...(save.bountyClaimedIds ?? []), bounty.id],
      statistics: {
        values: {
          ...payout.save.statistics.values,
          bounties_completed: Number(save.statistics.values.bounties_completed ?? 0) + 1,
        },
      },
    },
    goldGained: payout.paid,
  }
}
