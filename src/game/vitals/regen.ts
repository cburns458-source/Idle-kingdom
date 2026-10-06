import type { GameDatabase } from '../data/types'
import { playerMaxHp } from '../combat/stats'
import type { PlayerSave } from '../save/types'

/** Seconds without damage before natural regen can start (or resume). */
export const NATURAL_HP_REGEN_IDLE_SECONDS = 60

/** Base heal each regen trigger: 1% of max HP. Doubles each streak step. */
export const NATURAL_HP_REGEN_BASE_PERCENT = 1

/** Interval between regen triggers once the idle gate has passed. */
export const NATURAL_HP_REGEN_TRIGGER_MS = 60_000

export function naturalHpRegenIdleMs(): number {
  return NATURAL_HP_REGEN_IDLE_SECONDS * 1000
}

/** Heal amount for streak step `streak` (0 → 1% max, 1 → 2%, 2 → 4%, …). */
export function naturalHpRegenHealAmount(maxHp: number, streak: number): number {
  const step = Math.max(0, Math.floor(streak))
  const percent = NATURAL_HP_REGEN_BASE_PERCENT * 2 ** step
  return Math.max(1, Math.floor((maxHp * percent) / 100))
}

/**
 * Stamp that the player took non-PvP damage. Resets the regen streak and idle
 * carry so the 60s gate starts over.
 */
export function notePlayerDamaged(
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  return {
    ...save,
    lastDamagedAt: new Date(nowMs).toISOString(),
    hpRegenStreak: 0,
  }
}

/**
 * Natural HP regen: after 60s without damage, heal 1% max HP each minute,
 * doubling each consecutive trigger. Resets streak on damage or when full.
 * Runs during combat when the idle gate is met. Unattended catch-up OK.
 */
export function applyNaturalHpRegen(
  db: GameDatabase,
  save: PlayerSave,
  elapsedMs: number,
  nowMs: number = Date.now(),
): { save: PlayerSave; remainderMs: number } {
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) {
    return { save, remainderMs: 0 }
  }
  const maxHp = playerMaxHp(db, save)
  // Blessing may sit above max. Regen fills up to max and never cuts surplus.
  if (save.currentHp >= maxHp) {
    return {
      save: save.hpRegenStreak !== 0 ? { ...save, hpRegenStreak: 0 } : save,
      remainderMs: 0,
    }
  }

  const idleMs = naturalHpRegenIdleMs()
  const lastDamagedMs = save.lastDamagedAt
    ? Date.parse(save.lastDamagedAt)
    : Number.NEGATIVE_INFINITY
  const gateEndMs = Number.isFinite(lastDamagedMs) ? lastDamagedMs + idleMs : Number.NEGATIVE_INFINITY
  const windowStartMs = nowMs - elapsedMs
  // Time still inside the post-damage gate does not count toward a trigger.
  const eligibleStartMs = Math.max(windowStartMs, gateEndMs)
  const eligibleMs = Math.max(0, nowMs - eligibleStartMs)
  if (eligibleMs <= 0) {
    return { save, remainderMs: 0 }
  }

  const interval = NATURAL_HP_REGEN_TRIGGER_MS
  const triggers = Math.floor(eligibleMs / interval)
  const remainder = eligibleMs - triggers * interval
  if (triggers <= 0) {
    return { save, remainderMs: remainder }
  }

  let hp = save.currentHp
  let streak = Math.max(0, Math.floor(Number(save.hpRegenStreak ?? 0)))
  for (let i = 0; i < triggers; i += 1) {
    if (hp >= maxHp) break
    const heal = naturalHpRegenHealAmount(maxHp, streak)
    hp = Math.min(maxHp, hp + heal)
    streak += 1
  }
  if (hp >= maxHp) streak = 0

  return {
    save: {
      ...save,
      currentHp: hp,
      hpRegenStreak: streak,
    },
    remainderMs: hp >= maxHp ? 0 : remainder,
  }
}
