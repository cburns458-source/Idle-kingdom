import { CITADEL_LOCATION_ID } from './types'
import { listPeersAtLocation } from './presence'
import type { ActivityPresence } from './types'

/**
 * Citadel Plaza helpers.
 * Chat uses the normal local channel (`local:{locationId}`) via ChatDrawer — no Citadel-specific chat.
 */
export function citadelLocationId(): string {
  return CITADEL_LOCATION_ID
}

export function listCitadelVisitors(): ActivityPresence[] {
  return listPeersAtLocation(CITADEL_LOCATION_ID, true)
}

export function citadelHubSummary(): {
  locationId: string
  visitorCount: number
  note: string
} {
  return {
    locationId: CITADEL_LOCATION_ID,
    visitorCount: listCitadelVisitors().length,
    note: 'Citadel Plaza hub. Local chat matches every other location.',
  }
}
