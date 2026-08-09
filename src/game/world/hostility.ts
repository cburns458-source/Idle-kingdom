import {
  beginActivitySave,
  generateNextAction,
  validateActivityStart,
} from '../activity/engine'
import { beginTravelActivityChange, clearActivityTransition } from '../activity/transition'
import { getSkillProgress } from '../activity/xp'
import { COMBAT_SKILL_ID } from '../combat/stats'
import type { ActivityRow, GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { applyTravelArrival } from './travel'

/** Activities marked hostile via Danger Warning Combat Level. */
export function hostileActivitiesAt(db: GameDatabase, locationId: string): ActivityRow[] {
  return db.Activities.filter((activity) => {
    if (activity['Location ID'] !== locationId) return false
    const warning = activity['Danger Warning Combat Level']
    return typeof warning === 'number' && Number.isFinite(warning) && warning > 0
  }).sort(
    (a, b) =>
      (a['Danger Warning Combat Level'] ?? 0) - (b['Danger Warning Combat Level'] ?? 0) ||
      a['Activity ID'].localeCompare(b['Activity ID']),
  )
}

/** Hostile activity the player is under-level for at this location, if any. */
export function forcedHostileActivity(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): ActivityRow | null {
  const combatLevel = getSkillProgress(save, COMBAT_SKILL_ID).level
  for (const activity of hostileActivitiesAt(db, locationId)) {
    const warning = activity['Danger Warning Combat Level']
    if (typeof warning === 'number' && combatLevel < warning) {
      return activity
    }
  }
  return null
}

export interface HostileTravelArrivalResult {
  save: PlayerSave
  forcedActivityId: string | null
  /** Set when the player is under-level but the hostile activity could not start. */
  forceBlockedReason: string | null
  threatenedActivityId: string | null
}

/**
 * Arrive at a destination. Stops any running Primary Activity immediately.
 * Under-level hostile arrivals force-start combat (death pause still blocks travel elsewhere).
 */
export function applyHostileTravelArrival(
  db: GameDatabase,
  save: PlayerSave,
  destinationLocationId: string,
  nowMs: number = Date.now(),
): HostileTravelArrivalResult {
  let next = beginTravelActivityChange(db, save, nowMs)
  next = applyTravelArrival(next, destinationLocationId, nowMs) as PlayerSave
  next = clearActivityTransition(next)

  const threatened = forcedHostileActivity(db, next, destinationLocationId)
  if (!threatened) {
    return {
      save: next,
      forcedActivityId: null,
      forceBlockedReason: null,
      threatenedActivityId: null,
    }
  }

  const validation = validateActivityStart(db, next, threatened['Activity ID'])
  if (!validation.ok) {
    return {
      save: next,
      forcedActivityId: null,
      forceBlockedReason: validation.reason,
      threatenedActivityId: threatened['Activity ID'],
    }
  }

  const nowIso = new Date(nowMs).toISOString()
  const started = beginActivitySave(next, threatened['Activity ID'], nowIso)
  const generated = generateNextAction(
    db,
    started,
    threatened['Activity ID'],
    Math.random,
    nowMs,
  )

  return {
    save: generated ? generated.save : started,
    forcedActivityId: threatened['Activity ID'],
    forceBlockedReason: null,
    threatenedActivityId: threatened['Activity ID'],
  }
}

export function hostileForceMessage(
  db: GameDatabase,
  result: HostileTravelArrivalResult,
): string | null {
  if (!result.threatenedActivityId) return null
  const activity = db.Activities.find(
    (row) => row['Activity ID'] === result.threatenedActivityId,
  )
  const label = activity?.['Contextual Name'] ?? 'hostile combat'
  const warning = activity?.['Danger Warning Combat Level']
  if (result.forcedActivityId) {
    return `Hostile area (Combat Level ${warning}+) — forced into ${label}.`
  }
  if (result.forceBlockedReason) {
    return `Hostile area (Combat Level ${warning}+) — ${result.forceBlockedReason}`
  }
  return null
}
