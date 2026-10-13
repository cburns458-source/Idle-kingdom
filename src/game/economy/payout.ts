import type { PlayerSave } from '../save/types'

/** Reward kinds the shared payout can pay. Plaza points (ECO-03) add a second kind later. */
export type RewardType = 'gold'

export type Reward = {
  type: RewardType
  amount: number
}

export type RewardPayout = {
  save: PlayerSave
  paid: number
}

function goldAmount(amount: number): number {
  return Math.max(0, Math.floor(Number(amount) || 0))
}

/**
 * Pays one reward into a save. Ranked PvP and bounty turn-in both go through
 * this so a later plaza-points swap only changes the gold kind.
 */
export function payReward(save: PlayerSave, reward: Reward): RewardPayout {
  if (reward.type === 'gold') {
    const paid = goldAmount(reward.amount)
    return {
      save: {
        ...save,
        gold: save.gold + paid,
        statistics: {
          values: {
            ...save.statistics.values,
            gold_earned: Number(save.statistics.values.gold_earned ?? 0) + paid,
          },
        },
      },
      paid,
    }
  }
  return { save, paid: 0 }
}
