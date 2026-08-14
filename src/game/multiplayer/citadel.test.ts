import { describe, expect, it } from 'vitest'
import { CITADEL_MARKET_ID, CITADEL_PLAZA_ID } from '../world/constants'
import {
  CITADEL_HUB_TAB_LABELS,
  citadelChatLocationId,
  citadelHubSummary,
  citadelHubTabsFor,
  citadelHubTitleFor,
  citadelLocalChannelKey,
  citadelLocationId,
} from './citadel'
import { CITADEL_CHAT_LOCATION_ID, CITADEL_LOCATION_ID, chatChannelKey } from './types'

describe('citadel hub', () => {
  it('points at the plaza and uses shared local:citadel chat', () => {
    expect(citadelLocationId()).toBe('LOC-0028')
    expect(CITADEL_LOCATION_ID).toBe('LOC-0028')
    expect(citadelChatLocationId()).toBe('citadel')
    expect(CITADEL_CHAT_LOCATION_ID).toBe('citadel')
    expect(citadelLocalChannelKey()).toBe('local:citadel')
    expect(chatChannelKey({ kind: 'local', locationId: CITADEL_CHAT_LOCATION_ID })).toBe(
      'local:citadel',
    )
    const summary = citadelHubSummary(3)
    expect(summary.locationId).toBe('LOC-0028')
    expect(summary.chatChannel).toBe('local:citadel')
    expect(summary.visitorCount).toBe(3)
  })

  it('keeps one board per district', () => {
    expect(citadelHubTabsFor(CITADEL_PLAZA_ID)).toEqual(['bounties'])
    expect(citadelHubTabsFor(CITADEL_MARKET_ID)).toEqual(['bazaar'])
    expect(citadelHubTabsFor('LOC-0001')).toEqual([])
    expect(citadelHubTitleFor(CITADEL_PLAZA_ID)).toBe('Citadel Plaza')
    expect(citadelHubTitleFor(CITADEL_MARKET_ID)).toBe('Message board')
    expect(CITADEL_HUB_TAB_LABELS.bounties).toBe('Hourly Bounties')
    expect(CITADEL_HUB_TAB_LABELS.bazaar).toBe('Message board')
  })
})
