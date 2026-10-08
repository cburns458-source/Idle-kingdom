import { CITADEL_PLAZA_ID } from '../world/constants'
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

/** The Citadel bounty board, opened the way a shop is. */
export type CitadelHubTab = 'bounties'

export const CITADEL_HUB_TAB_LABELS: Record<CitadelHubTab, string> = {
  bounties: 'Hourly Bounties',
}

/**
 * Which boards stand at [locationId].
 *
 * The Plaza holds the hourly bounty board. The Market District is the
 * exchange, not a notice board. Anywhere else has neither.
 */
export function citadelHubTabsFor(locationId: string): CitadelHubTab[] {
  if (locationId === CITADEL_PLAZA_ID || locationId === CITADEL_LOCATION_ID) return ['bounties']
  return []
}

/** The heading above the bounty board link. Only the Plaza has one. */
export function citadelHubTitleFor(_locationId: string): string {
  return 'Citadel Plaza'
}

export interface CitadelHubSummary {
  locationId: string
  chatChannel: string
  visitorCount: number
  note: string
}

/** What the Citadel tab shows above its visitor list. */
export function citadelHubSummary(visitorCount: number): CitadelHubSummary {
  return {
    locationId: CITADEL_LOCATION_ID,
    chatChannel: citadelLocalChannelKey(),
    visitorCount,
    note: 'Shared Citadel hub. Local chat is one room across every Citadel district.',
  }
}
