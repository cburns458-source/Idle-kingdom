import type { GameDatabase } from '../data/types'
import type { ActivityTransition, PlayerSave } from '../save/types'
import { isDeathPaused } from '../combat/engine'
import { cancelProductionActivity, beginProductionQueue } from '../production/engine'
import { isStandardProductionActivity } from '../production/recipes'
import { configNumber } from './gathering'
import {
  beginActivitySave,
  clearActivitySave,
  generateNextAction,
  getActivity,
  validateActivityStart,
} from './engine'

export function activityChangeDelayMs(db: GameDatabase): number {
  return Math.max(0, configNumber(db, 'activity_change_delay', 30) * 1000)
}

export function transitionRemainingMs(
  save: PlayerSave,
  nowMs: number = Date.now(),
): number {
  const transition = save.activityTransition
  if (!transition) return 0
  const started = Date.parse(transition.startedAt)
  if (!Number.isFinite(started)) return 0
  return Math.max(0, started + transition.durationMs - nowMs)
}

export function isActivityTransitionPending(save: PlayerSave, nowMs: number = Date.now()): boolean {
  return transitionRemainingMs(save, nowMs) > 0
}

export function clearActivityTransition(save: PlayerSave): PlayerSave {
  if (!save.activityTransition) return save
  return { ...save, activityTransition: null }
}

function makeTransition(
  db: GameDatabase,
  partial: Omit<ActivityTransition, 'startedAt' | 'durationMs'> & {
    startedAt?: string
    durationMs?: number
  },
  nowMs: number,
): ActivityTransition {
  return {
    kind: partial.kind,
    activityId: partial.activityId,
    followUpActivityId: partial.followUpActivityId ?? null,
    productionRecipeId: partial.productionRecipeId ?? null,
    productionQuantity: partial.productionQuantity ?? null,
    startedAt: partial.startedAt ?? new Date(nowMs).toISOString(),
    durationMs: partial.durationMs ?? activityChangeDelayMs(db),
  }
}

export function hasRunningPrimaryActivity(save: PlayerSave): boolean {
  return Boolean(save.currentActivityId || save.productionRecipeId)
}

function beginCancelTransition(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
  followUp: {
    followUpActivityId?: string | null
    productionRecipeId?: string | null
    productionQuantity?: number | null
  } = {},
): PlayerSave {
  return {
    ...save,
    activityTransition: makeTransition(
      db,
      {
        kind: 'stopping',
        activityId: save.currentActivityId ?? save.productionRecipeId ?? 'activity',
        followUpActivityId: followUp.followUpActivityId ?? null,
        productionRecipeId: followUp.productionRecipeId ?? null,
        productionQuantity: followUp.productionQuantity ?? null,
      },
      nowMs,
    ),
  }
}

/** Begin the start delay for a validated pool activity (or replace via cancel→start). */
export function requestActivityStart(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  if (isActivityTransitionPending(save, nowMs)) {
    return { ok: false, reason: 'Wait for the current start/stop delay to finish.' }
  }

  const validation = validateActivityStart(db, save, activityId)
  if (!validation.ok) return validation

  // Already running this activity with no production queue — nothing to do.
  if (
    save.currentActivityId === activityId &&
    !save.productionRecipeId &&
    !save.activityTransition
  ) {
    return { ok: true, save }
  }

  // Cancel any running Primary Activity first (including Replace without an explicit Stop).
  if (hasRunningPrimaryActivity(save) && save.currentActivityId !== activityId) {
    return {
      ok: true,
      save: beginCancelTransition(db, save, nowMs, {
        followUpActivityId: activityId,
        productionRecipeId: null,
        productionQuantity: null,
      }),
    }
  }

  return {
    ok: true,
    save: {
      ...save,
      activityTransition: makeTransition(
        db,
        {
          kind: 'starting',
          activityId,
          followUpActivityId: null,
          productionRecipeId: null,
          productionQuantity: null,
        },
        nowMs,
      ),
    },
  }
}

/**
 * Cancel the running Primary Activity with the normal delay, then let the UI open a
 * Standard Production picker for followUpActivityId.
 */
export function requestCancelForProductionPicker(
  db: GameDatabase,
  save: PlayerSave,
  productionActivityId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  if (isActivityTransitionPending(save, nowMs)) {
    return { ok: false, reason: 'Wait for the current start/stop delay to finish.' }
  }
  if (!hasRunningPrimaryActivity(save)) {
    return { ok: true, save }
  }
  // Already on this production activity with no queue — picker can open immediately.
  if (save.currentActivityId === productionActivityId && !save.productionRecipeId) {
    return { ok: true, save }
  }

  return {
    ok: true,
    save: beginCancelTransition(db, save, nowMs, {
      followUpActivityId: null,
      productionRecipeId: null,
      productionQuantity: null,
    }),
  }
}

/** Begin the start delay for a confirmed Standard Production queue. */
export function requestProductionStart(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  recipeId: string,
  quantity: number,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  if (isActivityTransitionPending(save, nowMs)) {
    return { ok: false, reason: 'Wait for the current start/stop delay to finish.' }
  }

  const validation = validateActivityStart(db, save, activityId)
  if (!validation.ok) return validation

  // Always cancel a running Primary Activity / queue first (same station included).
  if (hasRunningPrimaryActivity(save)) {
    return {
      ok: true,
      save: beginCancelTransition(db, save, nowMs, {
        followUpActivityId: activityId,
        productionRecipeId: recipeId,
        productionQuantity: quantity,
      }),
    }
  }

  return {
    ok: true,
    save: {
      ...save,
      activityTransition: makeTransition(
        db,
        {
          kind: 'starting',
          activityId,
          followUpActivityId: null,
          productionRecipeId: recipeId,
          productionQuantity: quantity,
        },
        nowMs,
      ),
    },
  }
}

/** Begin the stop/cancel delay for the current primary activity. */
export function requestActivityStop(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  if (isActivityTransitionPending(save, nowMs)) {
    return { ok: false, reason: 'Wait for the current start/stop delay to finish.' }
  }
  if (!hasRunningPrimaryActivity(save)) {
    return { ok: false, reason: 'No activity is running.' }
  }

  return {
    ok: true,
    save: beginCancelTransition(db, save, nowMs),
  }
}

export function cancelActivityTransition(save: PlayerSave): PlayerSave {
  return clearActivityTransition(save)
}

function applyStartingTransition(
  db: GameDatabase,
  save: PlayerSave,
  transition: ActivityTransition,
  nowMs: number,
): PlayerSave {
  const activityId = transition.activityId
  const nowIso = new Date(nowMs).toISOString()
  let next = clearActivityTransition(save)

  if (transition.productionRecipeId && transition.productionQuantity) {
    const started = beginActivitySave(next, activityId, nowIso)
    const queued = beginProductionQueue(
      db,
      started,
      activityId,
      transition.productionRecipeId,
      transition.productionQuantity,
    )
    if (!queued.ok) {
      return { ...next, activityTransition: null }
    }
    return queued.save
  }

  const activity = getActivity(db, activityId)
  if (activity && isStandardProductionActivity(db, activity)) {
    // Production start without a queued recipe should not happen via transition.
    return next
  }

  const started = beginActivitySave(next, activityId, nowIso)
  const generated = generateNextAction(db, started, activityId, Math.random, nowMs)
  return generated ? generated.save : started
}

function applyStoppingTransition(
  db: GameDatabase,
  save: PlayerSave,
  transition: ActivityTransition,
  nowMs: number,
): PlayerSave {
  let next = clearActivityTransition(save)
  if (next.productionRecipeId) {
    next = cancelProductionActivity(db, next)
  } else {
    next = clearActivitySave(next, nowMs)
  }

  const followUp = transition.followUpActivityId
  if (!followUp) return next

  // Chain into a start delay for the replacement activity.
  return {
    ...next,
    activityTransition: makeTransition(
      db,
      {
        kind: 'starting',
        activityId: followUp,
        followUpActivityId: null,
        productionRecipeId: transition.productionRecipeId,
        productionQuantity: transition.productionQuantity,
      },
      nowMs,
    ),
  }
}

/**
 * Apply completed start/stop delays. Safe to call every frame and during AFK catch-up.
 * Chains stop→start follow-ups, resolving multiple completed steps within the window.
 */
export function resolveActivityTransitions(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  let current = save
  for (let step = 0; step < 4; step += 1) {
    const transition = current.activityTransition
    if (!transition) return current
    if (transitionRemainingMs(current, nowMs) > 0) return current

    const completedAt = Date.parse(transition.startedAt) + transition.durationMs
    const at = Number.isFinite(completedAt) ? Math.min(completedAt, nowMs) : nowMs

    if (transition.kind === 'starting') {
      current = applyStartingTransition(db, current, transition, at)
    } else {
      current = applyStoppingTransition(db, current, transition, at)
    }
  }
  return current
}
