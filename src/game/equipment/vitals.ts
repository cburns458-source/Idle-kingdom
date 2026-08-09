import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { playerMaxHp } from '../combat/stats'

/** Recalculate max HP from gear and clamp current HP. */
export function withRecalculatedVitals(db: GameDatabase, save: PlayerSave): PlayerSave {
  const maxHp = playerMaxHp(db, save)
  return {
    ...save,
    maxHp,
    currentHp: Math.min(Math.max(0, save.currentHp), maxHp),
  }
}
