import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import {
  applyTravelArrival,
  canTravelTo,
  locationsForMapView,
  resolveActiveMapId,
  travelDurationMs,
} from './travel'
import { DEFAULT_TRAVEL_DURATION_MS, MAIN_MAP_ID } from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('travel rules', () => {
  it('uses the owner-approved 5 second default duration', () => {
    expect(travelDurationMs(null)).toBe(DEFAULT_TRAVEL_DURATION_MS)
    expect(DEFAULT_TRAVEL_DURATION_MS).toBe(5000)
  })

  it('allows main-map node travel between Launch overworld locations', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0001', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0003', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0002', MAIN_MAP_ID)).toBe(false)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0011', MAIN_MAP_ID)).toBe(false)
    expect(canTravelTo(launch, 'LOC-0011', 'LOC-0002', MAIN_MAP_ID)).toBe(false)
  })

  it('lists main-map Launch locations and excludes Expansion', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const nodes = locationsForMapView(launch, MAIN_MAP_ID)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0002')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0018')).toBe(false)
  })

  it('stops primary activity on travel arrival', () => {
    const next = applyTravelArrival(
      {
        currentLocationId: 'LOC-0002',
        currentActivityId: 'ACT-0017',
        activityStartedAt: '2026-01-01T00:00:00.000Z',
      },
      'LOC-0001',
    )
    expect(next.currentLocationId).toBe('LOC-0001')
    expect(next.currentActivityId).toBeNull()
    expect(next.activityStartedAt).toBeNull()
  })

  it('opens cave sub-map from the cave entrance location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const entrance = launch.Locations.find((location) => location['Location ID'] === 'LOC-0010')!
    expect(resolveActiveMapId(entrance)).toBe('MAP-0002')
  })
})
