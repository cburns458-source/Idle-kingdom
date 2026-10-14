import type { PlayerSave } from '../save/types'
import { plazaPointsOf } from './plaza'

/** Reward kinds the shared payout can pay. */
export type RewardType = 'gold' | 'plaza_points'

export type Reward = {
  type: RewardType
  amount: number
}

export type RewardPayout = {
  save: PlayerSave
  paid: number
}

function wholeAmount(amount: number): number {
  return Math.max(0, Math.floor(Number(amount) || 0))
}

/**
 * Pays one reward into a save. Ranked PvP and bounty turn-in both go through
 * this. Plaza points round down; gold is unchanged by a points payout.
 */
export function payReward(save: PlayerSave, reward: Reward): RewardPayout {
  const paid = wholeAmount(reward.amount)
  if (reward.type === 'gold') {
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
  if (reward.type === 'plaza_points') {
    const next = plazaPointsOf(save) + paid
    return {
      save: {
        ...save,
        plazaPoints: next,
        statistics: {
          values: {
            ...save.statistics.values,
            plaza_points_earned: Number(save.statistics.values.plaza_points_earned ?? 0) + paid,
          },
        },
      },
      paid,
    }
  }
  return { save, paid: 0 }
}
