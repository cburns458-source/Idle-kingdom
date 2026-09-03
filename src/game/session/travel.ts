import { isDeathPaused } from '../combat/engine'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import type { QuestArrivalCompletion } from '../quests/quests'
import {
  applyHostileTravelArrival,
  hostileForceMessage,
  type HostileTravelArrivalResult,
} from '../world/hostility'
import { resolveSubMapTravelDestination } from '../world/submaps'
import { canTravelTo } from '../world/travel'

/** What a travel request turns into, once the rules have had their say. */
export type TravelPlan =
  /** The route is unavailable, or recovery from defeat is still locking travel. */
  | { kind: 'blocked' }
  /** Adjacent enough to arrive immediately; [arrival] has already happened. */
  | { kind: 'instant'; arrival: TravelArrival }

/** An arrival, with the hostility outcome already turned into one line of text. */
export interface TravelArrival {
  save: PlayerSave
  /** Set when a hostile area force-started combat on arrival. */
  forcedActivityId: string | null
  /** Set when the area is hostile but combat could not be forced. */
  blockedReason: string | null
  /** The hostility line to show, or null when the arrival was uneventful. */
  message: string | null
  /** Visit-complete quests that should show a reward popup. */
  questCompletions: QuestArrivalCompletion[]
}

function arrivalOf(db: GameDatabase, result: HostileTravelArrivalResult): TravelArrival {
  return {
    save: result.save,
    forcedActivityId: result.forcedActivityId,
    blockedReason: result.forceBlockedReason,
    message: hostileForceMessage(db, result),
    questCompletions: result.questCompletions ?? [],
  }
}

/**
 * Decides what travelling to [destinationId] does right now.
 *
 * Destinations open immediately. A client may play a walk animation first, but
 * the save only changes here — route check, activity stop, and arrival — so
 * every client lands the same way.
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

  return {
    kind: 'instant',
    arrival: arrivalOf(db, applyHostileTravelArrival(db, save, arrivalId, nowMs, random)),
  }
}
