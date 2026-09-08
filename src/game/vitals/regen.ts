import type { GameDatabase } from '../data/types'
import { playerMaxHp } from '../combat/stats'
import type { PlayerSave } from '../save/types'

/** Out-of-combat natural recovery. Thievery and other non-combat work still regen. */
export const NATURAL_HP_REGEN_PER_MINUTE = 10

export function naturalHpRegenIntervalMs(): number {
  return (60 * 1000) / NATURAL_HP_REGEN_PER_MINUTE
}

export function applyNaturalHpRegen(
  db: GameDatabase,
  save: PlayerSave,
  elapsedMs: number,
): { save: PlayerSave; remainderMs: number } {
  if (save.combatEnemyId) {
    return { save, remainderMs: 0 }
  }
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) {
    return { save, remainderMs: 0 }
  }
  const maxHp = playerMaxHp(db, save)
  if (save.currentHp >= maxHp) {
    return {
      save: save.currentHp === maxHp ? save : { ...save, currentHp: maxHp },
      remainderMs: 0,
    }
  }
  const interval = naturalHpRegenIntervalMs()
  const gained = Math.floor(elapsedMs / interval)
  const remainder = elapsedMs - gained * interval
  if (gained <= 0) {
    return { save, remainderMs: remainder }
  }
  const nextHp = Math.min(maxHp, save.currentHp + gained)
  return {
    save: { ...save, currentHp: nextHp },
    remainderMs: nextHp >= maxHp ? 0 : remainder,
  }
}
