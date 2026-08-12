import { describe, expect, it } from 'vitest'
import {
  citadelChatLocationId,
  citadelHubSummary,
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
    const summary = citadelHubSummary()
    expect(summary.locationId).toBe('LOC-0028')
    expect(summary.chatChannel).toBe('local:citadel')
  })
})
