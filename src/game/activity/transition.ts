import type { GameDatabase } from '../data/types'
import type { ActivityTransition, PlayerSave } from '../save/types'
import { isDeathPaused } from '../combat/engine'
import type { RandomFn } from './pools'
import { cancelProductionActivity, beginProductionQueue } from '../production/engine'
import { isStandardProductionActivity } from '../production/recipes'
import { unequipSlot } from '../equipment/loadout'
import { withRecalculatedVitals } from '../equipment/vitals'
import {
  beginActivitySave,
  clearActivitySave,
  generateNextAction,
  getActivity,
  isBlessingActivity,
  validateActivityStart,
} from './engine'
import { requirementsForEntity } from './requirements'
import {
  forcedHostileActivity,
  HOSTILE_ACTIVITY_LOCK_REASON,
  HOSTILE_ACTIVITY_START_REASON,
  locationIsHostileFor,
} from '../world/hostility'

export function clearActivityTransition(save: PlayerSave): PlayerSave {
  if (!save.activityTransition) return save
  return { ...save, activityTransition: null }
}

export function hasRunningPrimaryActivity(save: PlayerSave): boolean {
  return Boolean(save.currentActivityId || save.productionRecipeId)
}

/** Immediately stop the current Primary Activity (refunds remaining production materials). */
export function stopPrimaryActivityNow(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  // Death pause keeps the Primary Activity until recovery finishes.
  if (isDeathPaused(save, nowMs)) return save

  let next = clearActivityTransition(save)
  if (next.productionRecipeId) {
    next = cancelProductionActivity(db, next)
  } else if (next.currentActivityId) {
    next = clearActivitySave(next, nowMs)
  }
  return next
}

/**
 * Travel interrupt: hard-stop the current Primary Activity immediately.
 * No activity-change cooldown — death pause still blocks travel in the UI/hostility layer.
 */
export function beginTravelActivityChange(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): PlayerSave {
  if (isDeathPaused(save, nowMs)) return save
  if (!hasRunningPrimaryActivity(save) && !save.activityTransition) return save
  return stopPrimaryActivityNow(db, save, nowMs)
}

function startPoolActivityNow(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  nowMs: number,
  random: RandomFn,
): PlayerSave {
  const nowIso = new Date(nowMs).toISOString()
  const cleared = clearActivityTransition(save)
  const started = beginActivitySave(cleared, activityId, nowIso)
  const generated = generateNextAction(db, started, activityId, random, nowMs)
  return generated ? generated.save : started
}

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
  const queued = beginProductionQueue(db, started, activityId, recipeId, quantity, nowMs)
  if (!queued.ok) return queued
  return queued.save
}

function hostileStartBlocked(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): string | null {
  if (!locationIsHostileFor(db, save)) return null
  const threatened = forcedHostileActivity(db, save, save.currentLocationId)
  if (threatened && threatened['Activity ID'] === activityId) return null
  return HOSTILE_ACTIVITY_START_REASON
}

/** Unequip slots an activity requires empty before start validation. */
export function unequipEmptySlotRequirements(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  let next = save
  for (const requirement of requirementsForEntity(db, 'Activity', activityId)) {
    if (requirement['Requirement Type'] !== 'Empty Slot') continue
    const slotId = String(requirement['Reference ID / Value'] ?? '')
    if (!slotId) continue
    const equipped = next.equipment.slots[slotId]
    if (!equipped?.itemId || equipped.quantity <= 0) continue
    const result = unequipSlot(next, slotId)
    if (!result.ok) return result
    next = result.save
  }
  return { ok: true, save: next }
}

function restoreFullHealth(db: GameDatabase, save: PlayerSave): PlayerSave {
  const next = withRecalculatedVitals(db, save)
  return { ...next, currentHp: next.maxHp }
}

/** Start or replace a pool activity immediately. Death pause still blocks. */
export function requestActivityStart(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  nowMs: number = Date.now(),
  random: RandomFn = Math.random,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  const hostile = hostileStartBlocked(db, save, activityId)
  if (hostile) return { ok: false, reason: hostile }

  const unequipped = unequipEmptySlotRequirements(db, save, activityId)
  if (!unequipped.ok) return unequipped
  let next = unequipped.save

  const validation = validateActivityStart(db, next, activityId)
  if (!validation.ok) return validation

  if (
    next.currentActivityId === activityId &&
    !next.productionRecipeId &&
    !next.activityTransition
  ) {
    return { ok: true, save: clearActivityTransition(next) }
  }

  if (hasRunningPrimaryActivity(next) || next.activityTransition) {
    next = stopPrimaryActivityNow(db, next, nowMs)
  }

  if (isBlessingActivity(getActivity(db, activityId))) {
    return { ok: true, save: restoreFullHealth(db, next) }
  }

  return { ok: true, save: startPoolActivityNow(db, next, activityId, nowMs, random) }
}

/** Start Standard Production immediately, replacing any running Primary Activity. */
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
  if (locationIsHostileFor(db, save)) {
    return { ok: false, reason: HOSTILE_ACTIVITY_START_REASON }
  }

  const validation = validateActivityStart(db, save, activityId)
  if (!validation.ok) return validation

  let next = save
  if (hasRunningPrimaryActivity(save) || save.activityTransition) {
    next = stopPrimaryActivityNow(db, save, nowMs)
  }

  const started = startProductionNow(db, next, activityId, recipeId, quantity, nowMs)
  if ('ok' in started && started.ok === false) return started
  return { ok: true, save: started as PlayerSave }
}

/** Stop the current Primary Activity immediately. */
export function requestActivityStop(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  if (isDeathPaused(save, nowMs)) {
    return { ok: false, reason: 'Cannot change activities while recovering from defeat.' }
  }
  if (locationIsHostileFor(db, save)) {
    return { ok: false, reason: HOSTILE_ACTIVITY_LOCK_REASON }
  }
  if (!hasRunningPrimaryActivity(save) && !save.activityTransition) {
    return { ok: false, reason: 'No activity is running.' }
  }

  return { ok: true, save: stopPrimaryActivityNow(db, save, nowMs) }
}

function applyFollowUpStart(
  db: GameDatabase,
  save: PlayerSave,
  transition: ActivityTransition,
  nowMs: number,
  random: RandomFn,
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
    return save
  }

  return startPoolActivityNow(db, save, followUp, nowMs, random)
}

/**
 * Clear legacy activity-change delays from older saves (apply any follow-up immediately).
 * New gameplay no longer queues these transitions.
 */
export function resolveActivityTransitions(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
  random: RandomFn = Math.random,
): PlayerSave {
  const transition = save.activityTransition
  if (!transition) return save

  const next = stopPrimaryActivityNow(db, save, nowMs)
  if (transition.kind === 'starting') {
    return applyFollowUpStart(
      db,
      next,
      { ...transition, followUpActivityId: transition.activityId },
      nowMs,
      random,
    )
  }
  return applyFollowUpStart(db, next, transition, nowMs, random)
}
