import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  canClaimLocationSearch,
  claimLocationSearch,
  locationSearchCooldownRemainingMs,
  locationSearchesAt,
} from './locationSearch'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('location search', () => {
  it('lists the Cave Entrance search spot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const spots = locationSearchesAt(launch, 'LOC-0010')
    expect(spots).toHaveLength(1)
    expect(spots[0]?.['Display Name']).toBe('Search around the entrance')
    expect(spots[0]?.['Reward Item ID']).toBe('ITEM-0109')
  })

  it('grants the reward on first search and starts a 24h cooldown', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const nowMs = Date.parse('2026-01-01T00:00:00.000Z')

    expect(
      canClaimLocationSearch(save, locationSearchesAt(launch, 'LOC-0010')[0]!, nowMs),
    ).toBe(true)

    const result = claimLocationSearch(launch, save, 'SRCH-0001', nowMs)
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.itemId).toBe('ITEM-0109')
    expect(result.itemName).toBe('Sling')
    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0109')?.quantity).toBe(1)
    expect(result.save.locationSearchClaims['SRCH-0001']).toBe(new Date(nowMs).toISOString())
  })

  it('blocks a second search before 24 hours have passed, and allows it after', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const firstMs = Date.parse('2026-01-01T00:00:00.000Z')
    const first = claimLocationSearch(launch, save, 'SRCH-0001', firstMs)
    expect(first.ok).toBe(true)
    if (!first.ok) return

    const search = locationSearchesAt(launch, 'LOC-0010')[0]!
    const almostADayLater = firstMs + 23 * 60 * 60 * 1000
    expect(canClaimLocationSearch(first.save, search, almostADayLater)).toBe(false)
    expect(locationSearchCooldownRemainingMs(first.save, search, almostADayLater)).toBe(
      60 * 60 * 1000,
    )
    const blocked = claimLocationSearch(launch, first.save, 'SRCH-0001', almostADayLater)
    expect(blocked.ok).toBe(false)
    // A blocked claim must not consume/reset the existing cooldown timestamp.
    expect(blocked.save.locationSearchClaims['SRCH-0001']).toBe(
      first.save.locationSearchClaims['SRCH-0001'],
    )

    const exactlyADayLater = firstMs + 24 * 60 * 60 * 1000
    expect(canClaimLocationSearch(first.save, search, exactlyADayLater)).toBe(true)
    const second = claimLocationSearch(launch, first.save, 'SRCH-0001', exactlyADayLater)
    expect(second.ok).toBe(true)
    if (!second.ok) return
    expect(second.save.inventory.find((stack) => stack.itemId === 'ITEM-0109')?.quantity).toBe(2)
  })

  it('does not consume the search or reset the cooldown when the inventory is full', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Fill every inventory slot with a non-stacking-relevant item so the Sling has no room.
    save = {
      ...save,
      inventory: Array.from({ length: 180 }, () => ({ itemId: 'ITEM-0002', quantity: 1 })),
    }
    const nowMs = Date.parse('2026-01-01T00:00:00.000Z')
    const result = claimLocationSearch(launch, save, 'SRCH-0001', nowMs)
    expect(result.ok).toBe(false)
    expect(result.save.locationSearchClaims['SRCH-0001']).toBeUndefined()
  })
})
