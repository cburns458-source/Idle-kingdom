import type { LocationRow } from '../data/types'

/** Citadel Plaza — the public arena. */
export const ARENA_PLAZA_LOCATION_ID = 'LOC-0028'
/** Combat Training Grounds — the same arena, next to PvE training. */
export const ARENA_COMBAT_LOCATION_ID = 'LOC-0032'

export const ARENA_LOCATION_IDS = [ARENA_PLAZA_LOCATION_ID, ARENA_COMBAT_LOCATION_ID] as const

export function locationHasArena(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return (ARENA_LOCATION_IDS as readonly string[]).includes(location['Location ID'])
}
