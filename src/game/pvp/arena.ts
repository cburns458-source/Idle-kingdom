import type { LocationRow } from '../data/types'

/** Citadel Plaza — the public arena. */
export const ARENA_PLAZA_LOCATION_ID = 'LOC-0028'

export const ARENA_LOCATION_IDS = [ARENA_PLAZA_LOCATION_ID] as const

export function locationHasArena(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return (ARENA_LOCATION_IDS as readonly string[]).includes(location['Location ID'])
}
