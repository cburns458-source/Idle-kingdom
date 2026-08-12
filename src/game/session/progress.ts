import { restoreActiveActionState } from '../activity/engine'
import type { PlayerSave } from '../save/types'

/**
 * How far the timed action in progress has run, from 0 to 1.
 *
 * Covers gathering actions and standard production crafts, which both time out
 * of `actionStartedAt` / `actionDurationMs`. Combat has no bar of its own here:
 * the combat panel animates its round from `combatRoundStartedAt`.
 */
export function actionProgressAt(save: PlayerSave, nowMs: number): number {
  if (save.combatEnemyId) return 0
  const state = restoreActiveActionState(save)
  if (!state) return 0
  const elapsed = nowMs - state.startedAtMs
  return Math.min(1, Math.max(0, elapsed / Math.max(1, state.durationMs)))
}
