import type { PlayerSave } from '../save/types'

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
