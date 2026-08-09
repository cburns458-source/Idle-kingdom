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
  it('uses instant travel when Base Duration is unset', () => {
    expect(travelDurationMs(null)).toBe(DEFAULT_TRAVEL_DURATION_MS)
    expect(DEFAULT_TRAVEL_DURATION_MS).toBe(0)
  })

  it('allows main-map node travel between Launch overworld locations', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0001', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0003', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0002', MAIN_MAP_ID)).toBe(false)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0011', MAIN_MAP_ID)).toBe(false)
    // Sub-map locations may travel directly to world-map destinations.
    expect(canTravelTo(launch, 'LOC-0011', 'LOC-0002', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0017', 'LOC-0001', MAIN_MAP_ID)).toBe(true)
  })

  it('lists main-map Launch locations including Ancient Forest', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const nodes = locationsForMapView(launch, MAIN_MAP_ID)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0002')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0018')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0019')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0020')).toBe(true)
  })

  it('allows travel to Ancient Forest from the overworld', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0018', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0013', 'LOC-0018', MAIN_MAP_ID)).toBe(true)
  })

  it('treats west/east horizons as browse-only future gateways', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0019', MAIN_MAP_ID)).toBe(false)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0020', MAIN_MAP_ID)).toBe(false)
    expect(locationsForMapView(launch, 'MAP-0004')).toEqual([])
    expect(locationsForMapView(launch, 'MAP-0005')).toEqual([])
  })

  it('stops primary activity on travel arrival without clearing a pending change delay', () => {
    const transition = {
      kind: 'stopping' as const,
      activityId: 'ACT-0017',
      followUpActivityId: null,
      productionRecipeId: null,
      productionQuantity: null,
      startedAt: '2026-01-01T00:00:00.000Z',
      durationMs: 30_000,
    }
    const next = applyTravelArrival(
      {
        currentLocationId: 'LOC-0002',
        currentActivityId: 'ACT-0017',
        activityStartedAt: '2026-01-01T00:00:00.000Z',
        currentActionId: 'ACN-0105',
        actionStartedAt: '2026-01-01T00:00:00.000Z',
        actionDurationMs: 20000,
        activityTransition: transition,
      },
      'LOC-0001',
    )
    expect(next.currentLocationId).toBe('LOC-0001')
    expect(next.currentActivityId).toBeNull()
    expect(next.activityStartedAt).toBeNull()
    expect(next.currentActionId).toBeNull()
    expect(next.activityTransition).toEqual(transition)
  })

  it('blocks travel arrival during death pause', () => {
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const save = {
      currentLocationId: 'LOC-0002',
      currentActivityId: 'ACT-0001',
      activityStartedAt: '2026-01-01T00:00:00.000Z',
      deathPauseUntil: new Date(now + 30_000).toISOString(),
    }
    const next = applyTravelArrival(save, 'LOC-0001', now + 1000)
    expect(next).toEqual(save)
  })

  it('opens cave sub-map from the cave entrance location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const entrance = launch.Locations.find((location) => location['Location ID'] === 'LOC-0010')!
    expect(resolveActiveMapId(entrance)).toBe('MAP-0002')
  })
})
