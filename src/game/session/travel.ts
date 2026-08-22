import { beginTravelActivityChange } from '../activity/transition'
import { isDeathPaused } from '../combat/engine'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import {
  applyHostileTravelArrival,
  hostileForceMessage,
  type HostileTravelArrivalResult,
} from '../world/hostility'
import { resolveSubMapTravelDestination } from '../world/submaps'
import { canTravelTo, findConnection, travelDurationMs } from '../world/travel'

/** What a travel request turns into, once the rules have had their say. */
export type TravelPlan =
  /** The route is unavailable, or recovery from defeat is still locking travel. */
  | { kind: 'blocked' }
  /** Adjacent enough to arrive with no journey; [arrival] has already happened. */
  | { kind: 'instant'; arrival: TravelArrival }
  /**
   * A journey the client animates. [save] has the current activity stopped, and
   * the client calls [arriveFromTravel] once [durationMs] has passed.
   */
  | { kind: 'timed'; save: PlayerSave; durationMs: number }

/** An arrival, with the hostility outcome already turned into one line of text. */
export interface TravelArrival {
  save: PlayerSave
  /** Set when a hostile area force-started combat on arrival. */
  forcedActivityId: string | null
  /** Set when the area is hostile but combat could not be forced. */
  blockedReason: string | null
  /** The hostility line to show, or null when the arrival was uneventful. */
  message: string | null
}

function arrivalOf(db: GameDatabase, result: HostileTravelArrivalResult): TravelArrival {
  return {
    save: result.save,
    forcedActivityId: result.forcedActivityId,
    blockedReason: result.forceBlockedReason,
    message: hostileForceMessage(db, result),
  }
}

/**
 * Decides what travelling to [destinationId] does right now.
 *
 * The journey itself is the client's to animate, but everything that touches the
 * save — the route check, stopping the current activity, and the arrival — is
 * decided here so every client behaves the same.
 */
export function planTravel(
  db: GameDatabase,
  save: PlayerSave,
  destinationId: string,
  browseMapId: string,
  nowMs: number = Date.now(),
  random: () => number = Math.random,
): TravelPlan {
  if (isDeathPaused(save, nowMs)) return { kind: 'blocked' }
  const arrivalId = resolveSubMapTravelDestination(
    db,
    destinationId,
    browseMapId,
    save.currentLocationId,
  )
  const destOk =
    destinationId === save.currentLocationId
      ? arrivalId !== destinationId
      : canTravelTo(db, save.currentLocationId, destinationId, browseMapId, save)
  if (!destOk) {
    return { kind: 'blocked' }
  }

  const durationMs = travelDurationMs(findConnection(db, save.currentLocationId, destinationId))
  if (durationMs <= 0) {
    return {
      kind: 'instant',
      arrival: arrivalOf(db, applyHostileTravelArrival(db, save, arrivalId, nowMs, random)),
    }
  }

  // Timed travel stops the current activity the moment the journey begins.
  return { kind: 'timed', save: beginTravelActivityChange(db, save, nowMs), durationMs }
}

/** Completes a timed journey started from a `timed` plan. */
export function arriveFromTravel(
  db: GameDatabase,
  save: PlayerSave,
  destinationId: string,
  nowMs: number = Date.now(),
  random: () => number = Math.random,
): TravelArrival {
  return arrivalOf(db, applyHostileTravelArrival(db, save, destinationId, nowMs, random))
}
