import { CITADEL_CHAT_LOCATION_ID, CITADEL_LOCATION_ID, chatChannelKey } from './types'
import { listPeersAtLocation } from './presence'
import type { ActivityPresence } from './types'

/** Stable Local-chat location key while anywhere on the Citadel sub-map (`local:citadel`). */
export function citadelChatLocationId(): string {
  return CITADEL_CHAT_LOCATION_ID
}

export function citadelLocationId(): string {
  return CITADEL_LOCATION_ID
}

export function citadelLocalChannelKey(): string {
  return chatChannelKey({ kind: 'local', locationId: CITADEL_CHAT_LOCATION_ID })
}

export function listCitadelVisitors(): ActivityPresence[] {
  return listPeersAtLocation(CITADEL_LOCATION_ID, true)
}

export function citadelHubSummary(): {
  locationId: string
  chatChannel: string
  visitorCount: number
  note: string
} {
  return {
    locationId: CITADEL_LOCATION_ID,
    chatChannel: citadelLocalChannelKey(),
    visitorCount: listCitadelVisitors().length,
    note: 'Shared Citadel hub. Local chat is one room across every Citadel district.',
  }
}
