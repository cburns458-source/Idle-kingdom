import { favoriteActivityAt } from '../activity/favorites'
import {
  beginActivitySave,
  generateNextAction,
  validateActivityStart,
} from '../activity/engine'
import type { RandomFn } from '../activity/pools'
import { clearActivityTransition } from '../activity/transition'
import { getSkillProgress } from '../activity/xp'
import { COMBAT_SKILL_ID } from '../combat/stats'
import type { ActivityRow, GameDatabase } from '../data/types'
import { raceBypassesForcedHostilityAt } from '../races/races'
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

/** The player is under-level for a danger-warning activity here. */
export function locationIsHostileFor(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string = save.currentLocationId,
): boolean {
  return forcedHostileActivity(db, save, locationId) != null
}

export const HOSTILE_ACTIVITY_LOCK_REASON =
  'Leave this area to stop. Hostile combat cannot be cancelled.'
export const HOSTILE_ACTIVITY_START_REASON =
  'Cannot start another action in a hostile area. Leave to escape.'

/** Hostile activity the player is under-level for at this location, if any. */
export function forcedHostileActivity(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): ActivityRow | null {
  if (raceBypassesForcedHostilityAt(db, save, locationId)) return null
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
  random: RandomFn = Math.random,
): HostileTravelArrivalResult {
  let next = applyTravelArrival(db, save, destinationLocationId, nowMs)
  next = clearActivityTransition(next)

  const threatened = forcedHostileActivity(db, next, destinationLocationId)
  if (!threatened) {
    return {
      save: startFavoriteActivity(db, next, destinationLocationId, nowMs, random),
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
  const generated = generateNextAction(db, started, threatened['Activity ID'], random, nowMs)

  return {
    save: generated ? generated.save : started,
    forcedActivityId: threatened['Activity ID'],
    forceBlockedReason: null,
    threatenedActivityId: threatened['Activity ID'],
  }
}

function startFavoriteActivity(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
  nowMs: number,
  random: RandomFn,
): PlayerSave {
  const favoriteId = favoriteActivityAt(save, locationId)
  if (!favoriteId) return save
  const validation = validateActivityStart(db, save, favoriteId)
  if (!validation.ok) return save
  const nowIso = new Date(nowMs).toISOString()
  const started = beginActivitySave(save, favoriteId, nowIso)
  return generateNextAction(db, started, favoriteId, random, nowMs)?.save ?? started
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
