import type { LocationRow } from '../data/types'
import { GUILD_HALL_LOCATION_ID } from '../world/constants'

export function locationHasGuildHall(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return location['Location ID'] === GUILD_HALL_LOCATION_ID
}

/** Recruits cannot pay the hall debt. Member and every rank above can. */
export function canPayGuildDebt(role: string): boolean {
  return role === 'leader' || role === 'officer' || role === 'veteran' || role === 'member'
}

export const GUILD_HALL_DEBT_GOLD = 1_000_000

/** Item quantity the guild must contribute before the boxing ring opens. */
export const BOXING_RING_UNLOCK_ITEMS = 50

export const BOXING_RING_UNLOCK_ID = 'boxing_ring'

export function boxingRingUnlocked(itemsContributed: number, unlocks: string[]): boolean {
  return unlocks.includes(BOXING_RING_UNLOCK_ID) || itemsContributed >= BOXING_RING_UNLOCK_ITEMS
}
