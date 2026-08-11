import { CITADEL_LOCATION_ID, CITADEL_PRESENCE_CHANNEL } from './types'
import { listPeersAtLocation } from './presence'
import type { ActivityPresence } from './types'

/**
 * Citadel is a reserved shared social hub.
 * Exact systems TBD; this module reserves IDs + presence listing for cosmetics showcase.
 */
export function citadelLocationId(): string {
  return CITADEL_LOCATION_ID
}

export function citadelPresenceChannel(): string {
  return CITADEL_PRESENCE_CHANNEL
}

export function listCitadelVisitors(): ActivityPresence[] {
  return listPeersAtLocation(CITADEL_LOCATION_ID, true)
}

export function citadelHubSummary(): {
  locationId: string
  channel: string
  visitorCount: number
  note: string
} {
  return {
    locationId: CITADEL_LOCATION_ID,
    channel: CITADEL_PRESENCE_CHANNEL,
    visitorCount: listCitadelVisitors().length,
    note: 'Shared social hub placeholder. Cosmetics showcase and guild presence land here later.',
  }
}
