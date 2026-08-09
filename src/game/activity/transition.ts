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

function makeStopTransition(
  db: GameDatabase,
  partial: Omit<ActivityTransition, 'startedAt' | 'durationMs' | 'kind'> & {
    startedAt?: string
    durationMs?: number
  },
  nowMs: number,
): ActivityTransition {
  return {
    kind: 'stopping',
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
    activityTransition: makeStopTransition(
      db,
      {
        activityId: save.currentActivityId ?? save.productionRecipeId ?? 'activity',
        followUpActivityId: followUp.followUpActivityId ?? null,
        productionRecipeId: followUp.productionRecipeId ?? null,
        productionQuantity: followUp.productionQuantity ?? null,
      },
      nowMs,
    ),
  }
}

/** Immediately begin a pool activity (no start delay). */
function startPoolActivityNow(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  nowMs: number,
): PlayerSave {
  const nowIso = new Date(nowMs).toISOString()
  const cleared = clearActivityTransition(save)
  const started = beginActivitySave(cleared, activityId, nowIso)
  const generated = generateNextAction(db, started, activityId, Math.random, nowMs)
  return generated ? generated.save : started
}

/** Immediately begin a Standard Production queue (no start delay). */
function startProductionNow(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  recipeId: string,
  quantity: number,
  nowMs: number,
): PlayerSave | { ok: false; reason: string } {
  const nowIso = new Date(nowMs).toISOString()
  const cleared = clearActivityTransition(save)
  const started = beginActivitySave(cleared, activityId, nowIso)
  const queued = beginProductionQueue(db, started, activityId, recipeId, quantity)
  if (!queued.ok) return queued
  return queued.save
}

/**
 * Start a pool activity immediately, or cancel a running activity first (30s stop delay)
 * then start the new one as soon as that stop completes — with no second start delay.
 */
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
    return { ok: false, reason: 'Wait for the current stop delay to finish.' }
  }

  const validation = validateActivityStart(db, save, activityId)
  if (!validation.ok) return validation

  if (
    save.currentActivityId === activityId &&
    !save.productionRecipeId &&
    !save.activityTransition
  ) {
    return { ok: true, save }
  }

  // Replace: 30s cancel only, then immediate start of the follow-up.
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

  return { ok: true, save: startPoolActivityNow(db, save, activityId, nowMs) }
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
    return { ok: false, reason: 'Wait for the current stop delay to finish.' }
  }
  if (!hasRunningPrimaryActivity(save)) {
    return { ok: true, save }
  }
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

/** Start Standard Production immediately, or after a 30s cancel if something is already running. */
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
    return { ok: false, reason: 'Wait for the current stop delay to finish.' }
  }

  const validation = validateActivityStart(db, save, activityId)
  if (!validation.ok) return validation

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

  const started = startProductionNow(db, save, activityId, recipeId, quantity, nowMs)
  if ('ok' in started && started.ok === false) return started
  return { ok: true, save: started as PlayerSave }
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
    return { ok: false, reason: 'Wait for the current stop delay to finish.' }
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

function applyFollowUpStart(
  db: GameDatabase,
  save: PlayerSave,
  transition: ActivityTransition,
  nowMs: number,
): PlayerSave {
  const followUp = transition.followUpActivityId
  if (!followUp) return save

  if (transition.productionRecipeId && transition.productionQuantity) {
    const started = startProductionNow(
      db,
      save,
      followUp,
      transition.productionRecipeId,
      transition.productionQuantity,
      nowMs,
    )
    if ('ok' in started && started.ok === false) return save
    return started as PlayerSave
  }

  const activity = getActivity(db, followUp)
  if (activity && isStandardProductionActivity(db, activity)) {
    // Picker opens from the UI after a plain cancel; nothing to auto-start.
    return save
  }

  return startPoolActivityNow(db, save, followUp, nowMs)
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

  // After stop completes: no second delay — start the follow-up immediately if any.
  return applyFollowUpStart(db, next, transition, nowMs)
}

/**
 * Apply completed stop delays. Safe to call every frame and during AFK catch-up.
 * Follow-up activities begin immediately when the stop delay finishes (no start cooldown).
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

    // Start transitions are no longer queued; ignore any legacy ones by applying immediately.
    if (transition.kind === 'starting') {
      current = applyFollowUpStart(
        db,
        clearActivityTransition(current),
        {
          ...transition,
          followUpActivityId: transition.activityId,
        },
        at,
      )
    } else {
      current = applyStoppingTransition(db, current, transition, at)
    }
  }
  return current
}
