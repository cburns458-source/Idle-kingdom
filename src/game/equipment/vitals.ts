import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { playerMaxHp } from '../combat/stats'

/**
 * Keep blessing surplus as an absolute extra when max HP changes.
 * 5500/5000 → max 4000 becomes 4500; 5250/5000 → max 4000 becomes 4250.
 * HP at or below the old max still clamps to the new max.
 */
export function currentHpAfterMaxChange(
  currentHp: number,
  previousMaxHp: number,
  nextMaxHp: number,
): number {
  const surplus = Math.max(0, currentHp - previousMaxHp)
  if (surplus > 0) return nextMaxHp + surplus
  return Math.min(Math.max(0, currentHp), nextMaxHp)
}

/** Recalculate max HP from gear and keep any blessing surplus. */
export function withRecalculatedVitals(db: GameDatabase, save: PlayerSave): PlayerSave {
  const maxHp = playerMaxHp(db, save)
  return {
    ...save,
    maxHp,
    currentHp: currentHpAfterMaxChange(save.currentHp, save.maxHp, maxHp),
  }
}
