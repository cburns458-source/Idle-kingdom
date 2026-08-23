import type { PlayerSave } from './types'

/**
 * Add elapsed character time. Negative, zero, and non-finite spans are ignored
 * so a clock jump backward cannot rewind the total.
 */
export function accruePlayTime(save: PlayerSave, elapsedMs: number): PlayerSave {
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) return save
  return { ...save, playTimeMs: save.playTimeMs + elapsedMs }
}

/**
 * How much of a live-session gap to credit. Short frames accrue in full;
 * longer gaps (background, a paused ticker) credit up to the unattended cap so
 * away time matches catch-up instead of dumping uncapped wall-clock hours.
 */
export function livePlayCreditMs(elapsedMs: number, awayCapMs: number): number {
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) return 0
  const cap = Number.isFinite(awayCapMs) && awayCapMs > 0 ? awayCapMs : 0
  return Math.min(elapsedMs, cap)
}

export function creditElapsedPlayTime(
  save: PlayerSave,
  elapsedMs: number,
  awayCapMs: number,
): PlayerSave {
  return accruePlayTime(save, livePlayCreditMs(elapsedMs, awayCapMs))
}
