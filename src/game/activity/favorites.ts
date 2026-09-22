import type { GameDatabase } from '../data/types'
import { isStandardProductionActivity } from '../production/recipes'
import type { PlayerSave } from '../save/types'

/**
 * Whether [activityId] is the kind of work a star can start on arrival.
 *
 * Only work the world does to a schedule qualifies — a combat or gathering pool.
 * A station has nothing to run until the player picks a recipe, so starring one
 * would put the character at a bench doing nothing.
 */
export function canFavoriteActivity(db: GameDatabase, activityId: string): boolean {
  const activity = db.Activities.find((row) => row['Activity ID'] === activityId)
  if (!activity) return false
  return !isStandardProductionActivity(db, activity)
}

/** The starred activity at a location, if the player picked one. */
export function favoriteActivityAt(
  save: PlayerSave,
  locationId: string = save.currentLocationId,
): string | null {
  const id = save.favoriteActivityByLocationId[locationId]
  return id ? id : null
}

/** Stars [activityId] at [locationId], or clears the star when it is already set. */
export function toggleFavoriteActivity(
  save: PlayerSave,
  locationId: string,
  activityId: string,
): PlayerSave {
  const current = save.favoriteActivityByLocationId[locationId]
  const next = { ...save.favoriteActivityByLocationId }
  if (current === activityId) delete next[locationId]
  else next[locationId] = activityId
  return { ...save, favoriteActivityByLocationId: next }
}
