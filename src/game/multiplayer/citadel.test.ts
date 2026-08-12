import { describe, expect, it } from 'vitest'
import { citadelHubSummary, citadelLocationId } from './citadel'
import { CITADEL_LOCATION_ID, chatChannelKey } from './types'

describe('citadel hub', () => {
  it('points at the plaza location and uses normal local chat keys', () => {
    expect(citadelLocationId()).toBe('LOC-0028')
    expect(CITADEL_LOCATION_ID).toBe('LOC-0028')
    expect(chatChannelKey({ kind: 'local', locationId: CITADEL_LOCATION_ID })).toBe(
      'local:LOC-0028',
    )
    const summary = citadelHubSummary()
    expect(summary.locationId).toBe('LOC-0028')
    expect(summary).not.toHaveProperty('channel')
  })
})
