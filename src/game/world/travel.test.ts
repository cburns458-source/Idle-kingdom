import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { locationHasGuildHall } from '../guild/hall'
import { createNewSave } from '../save/saveStore'
import {
  applyTravelArrival,
  canTravelTo,
  locationsForMapView,
  resolveActiveMapId,
  travelDurationMs,
} from './travel'
import {
  DEFAULT_TRAVEL_DURATION_MS,
  MAIN_MAP_ID,
  CASTLE_MAP_ID,
  CAVE_MAP_ID,
  CITADEL_MAP_ID,
} from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('travel rules', () => {
  it('treats every Travel button as instant', () => {
    expect(travelDurationMs(null)).toBe(0)
    expect(DEFAULT_TRAVEL_DURATION_MS).toBe(0)
    const { launch } = prepareDatabase(rawDatabase)
    const connection = launch.TravelConnections.find((row) => typeof row['Base Duration'] === 'number')
    expect(travelDurationMs(connection)).toBe(0)
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

  it('stops primary activity on travel arrival and refunds production materials', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0023',
      currentActivityId: 'ACT-0017',
      activityStartedAt: '2026-01-01T00:00:00.000Z',
      currentActionId: 'ACN-0105',
      actionStartedAt: '2026-01-01T00:00:00.000Z',
      actionDurationMs: 20000,
      productionRecipeId: 'RCP-0001',
      productionQuantityTotal: 2,
      productionQuantityRemaining: 2,
      inventory: [],
    }
    const next = applyTravelArrival(launch, save, 'LOC-0001', now)
    expect(next.currentLocationId).toBe('LOC-0001')
    expect(next.currentActivityId).toBeNull()
    expect(next.productionRecipeId).toBeNull()
    expect(next.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity).toBe(2)
  })

  it('blocks travel arrival during death pause', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0002',
      currentActivityId: 'ACT-0001',
      activityStartedAt: '2026-01-01T00:00:00.000Z',
      deathPauseUntil: new Date(now + 30_000).toISOString(),
    }
    const next = applyTravelArrival(launch, save, 'LOC-0001', now + 1000)
    expect(next).toEqual(save)
  })

  it('opens cave sub-map from the cave entrance location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const entrance = launch.Locations.find((location) => location['Location ID'] === 'LOC-0010')!
    expect(resolveActiveMapId(launch, entrance)).toBe('MAP-0002')
  })

  it('opens town sub-map from The Town gateway', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const town = launch.Locations.find((location) => location['Location ID'] === 'LOC-0002')!
    expect(resolveActiveMapId(launch, town)).toBe('MAP-0006')
    const townNodes = locationsForMapView(launch, 'MAP-0006').map((row) => row['Location ID'])
    expect(townNodes).toEqual(
      expect.arrayContaining(['LOC-0002', 'LOC-0023', 'LOC-0024', 'LOC-0025']),
    )
    expect(townNodes).not.toContain('LOC-0026')
    const unlocked = locationsForMapView(launch, 'MAP-0006', {
      unlockedLocationIds: ['LOC-0026'],
    }).map((row) => row['Location ID'])
    expect(unlocked).toContain('LOC-0026')
  })

  it('lists castle and cave sub-map nodes including new content rooms', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const castleNodes = locationsForMapView(launch, CASTLE_MAP_ID).map((row) => row['Location ID'])
    expect(castleNodes).toEqual(expect.arrayContaining(['LOC-0015', 'LOC-0021']))
    const caveNodes = locationsForMapView(launch, CAVE_MAP_ID).map((row) => row['Location ID'])
    expect(caveNodes).toEqual(expect.arrayContaining(['LOC-0011', 'LOC-0022']))
  })

  it('opens citadel sub-map from The Citadel gateway', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const gateway = launch.Locations.find((location) => location['Location ID'] === 'LOC-0027')!
    expect(resolveActiveMapId(launch, gateway)).toBe(CITADEL_MAP_ID)
    const nodes = locationsForMapView(launch, CITADEL_MAP_ID).map((row) => row['Location ID'])
    expect(nodes).toEqual(
      expect.arrayContaining([
        'LOC-0027',
        'LOC-0028',
        'LOC-0029',
        'LOC-0030',
        'LOC-0031',
        'LOC-0032',
        'LOC-0033',
      ]),
    )
    expect(canTravelTo(launch, 'LOC-0027', 'LOC-0028', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0028', 'LOC-0029', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0028', 'LOC-0033', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0027', MAIN_MAP_ID)).toBe(true)
    const hall = launch.Locations.find((location) => location['Location ID'] === 'LOC-0033')
    expect(locationHasGuildHall(hall)).toBe(true)
    expect(locationHasGuildHall(gateway)).toBe(false)
  })
})
