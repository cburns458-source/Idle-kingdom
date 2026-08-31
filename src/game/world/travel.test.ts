import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { locationHasGuildHall } from '../guild/hall'
import { createNewSave } from '../save/saveStore'
import { planTravel } from '../session/travel'
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
  CAVE_MINING_STORE_ID,
  CITADEL_MAP_ID,
  CITADEL_GATEWAY_ID,
  CITADEL_PLAZA_ID,
  DEPTHS_MAP_ID,
  FOREST_GATEWAY_ID,
  FOREST_MAP_ID,
  FOREST_PATH_ID,
  OLD_ENT_GROVE_ID,
  STARLIGHT_GLADE_ID,
  SUNKEN_APPROACH_ID,
  THE_DEPTHS_ID,
  THE_SHALLOWS_ID,
  CASTLE_COURTYARD_ID,
  CASTLE_GATEWAY_ID,
  TOWN_GATEWAY_ID,
  TOWN_GENERAL_STORE_ID,
  TOWN_KITCHEN_ID,
  TOWN_MAP_ID,
} from './constants'
import { mapNodeLabel } from './mapLabel'
import {
  backToSubMapLabel,
  enterSubMapLabel,
  landingLocationIdFor,
  resolveSubMapTravelDestination,
} from './submaps'

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

  it('lists main-map Launch locations including Forest Gate', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const nodes = locationsForMapView(launch, MAIN_MAP_ID)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0002')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0039')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0041')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0018')).toBe(false)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0036')).toBe(true)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0019')).toBe(false)
    expect(nodes.some((location) => location['Location ID'] === 'LOC-0020')).toBe(false)
  })

  it('allows travel to Forest Gate and Sunken Approach from the overworld', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0039', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0013', 'LOC-0039', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0004', 'LOC-0041', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0018', MAIN_MAP_ID)).toBe(false)
  })

  it('allows travel to the Temple from the overworld', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0036', MAIN_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0013', 'LOC-0036', MAIN_MAP_ID)).toBe(true)
  })

  it('keeps west and east region maps empty after removing horizon gateways', () => {
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
      expect.arrayContaining(['LOC-0023', 'LOC-0024', 'LOC-0025']),
    )
    expect(townNodes).not.toContain('LOC-0002')
    expect(townNodes).not.toContain('LOC-0026')
    const unlocked = locationsForMapView(launch, 'MAP-0006', {
      unlockedLocationIds: ['LOC-0026'],
    }).map((row) => row['Location ID'])
    expect(unlocked).toContain('LOC-0026')
  })

  it('lists castle and cave sub-map nodes including new content rooms', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const castleNodes = locationsForMapView(launch, CASTLE_MAP_ID).map((row) => row['Location ID'])
    expect(castleNodes).toEqual(expect.arrayContaining(['LOC-0015', 'LOC-0021', 'LOC-0037']))
    expect(castleNodes).not.toContain(CASTLE_GATEWAY_ID)
    const caveNodes = locationsForMapView(launch, CAVE_MAP_ID).map((row) => row['Location ID'])
    expect(caveNodes).toEqual(expect.arrayContaining(['LOC-0011']))
    expect(caveNodes).not.toContain('LOC-0022')
    expect(caveNodes).not.toContain('LOC-0038')
    expect(caveNodes).not.toContain('LOC-0010')
    const standingInShaft = locationsForMapView(launch, CAVE_MAP_ID, {
      currentLocationId: 'LOC-0022',
    }).map((row) => row['Location ID'])
    expect(standingInShaft).toContain('LOC-0022')
    const unlockedShaft = locationsForMapView(launch, CAVE_MAP_ID, {
      unlockedLocationIds: ['LOC-0022'],
    }).map((row) => row['Location ID'])
    expect(unlockedShaft).toContain('LOC-0022')
    const leftTheShaft = locationsForMapView(launch, CAVE_MAP_ID, {
      currentLocationId: 'LOC-0011',
    }).map((row) => row['Location ID'])
    expect(leftTheShaft).not.toContain('LOC-0022')
    expect(canTravelTo(launch, 'LOC-0011', 'LOC-0022', CAVE_MAP_ID)).toBe(false)
    expect(
      canTravelTo(launch, 'LOC-0022', 'LOC-0011', CAVE_MAP_ID, { currentLocationId: 'LOC-0022' }),
    ).toBe(true)
  })

  it('opens citadel sub-map from The Citadel gateway', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const gateway = launch.Locations.find((location) => location['Location ID'] === 'LOC-0027')!
    expect(resolveActiveMapId(launch, gateway)).toBe(CITADEL_MAP_ID)
    const nodes = locationsForMapView(launch, CITADEL_MAP_ID).map((row) => row['Location ID'])
    expect(nodes).toEqual(
      expect.arrayContaining([
        'LOC-0028',
        'LOC-0029',
        'LOC-0030',
        'LOC-0031',
        'LOC-0032',
        'LOC-0033',
      ]),
    )
    expect(nodes).not.toContain('LOC-0027')
    expect(canTravelTo(launch, 'LOC-0027', 'LOC-0028', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0028', 'LOC-0029', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0028', 'LOC-0033', CITADEL_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0027', MAIN_MAP_ID)).toBe(true)
    const hall = launch.Locations.find((location) => location['Location ID'] === 'LOC-0033')
    expect(locationHasGuildHall(hall)).toBe(true)
    expect(locationHasGuildHall(gateway)).toBe(false)
  })

  it('labels a back button for submap interiors', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const kitchen = launch.Locations.find((row) => row['Location ID'] === TOWN_KITCHEN_ID)!
    const town = launch.Locations.find((row) => row['Location ID'] === TOWN_GATEWAY_ID)!
    const plaza = launch.Locations.find((row) => row['Location ID'] === CITADEL_PLAZA_ID)!
    expect(backToSubMapLabel(launch, kitchen)).toBe('Back to Town')
    expect(enterSubMapLabel(launch, kitchen)).toBeNull()
    expect(backToSubMapLabel(launch, town)).toBeNull()
    expect(enterSubMapLabel(launch, town)).toBe('Enter Town')
    expect(backToSubMapLabel(launch, plaza)).toBe('Back to Citadel')
  })

  it('labels town and castle gateways on their submaps', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const town = launch.Locations.find((row) => row['Location ID'] === TOWN_GATEWAY_ID)!
    const castle = launch.Locations.find((row) => row['Location ID'] === CASTLE_GATEWAY_ID)!
    expect(mapNodeLabel(town, TOWN_MAP_ID)).toBe('Town Gate')
    expect(mapNodeLabel(town, MAIN_MAP_ID)).toBe('The Town')
    expect(mapNodeLabel(castle, CASTLE_MAP_ID)).toBe('Castle Gate')
    expect(mapNodeLabel(castle, MAIN_MAP_ID)).toBe('Castle')
    expect(
      locationsForMapView(launch, CITADEL_MAP_ID).some(
        (row) => row['Location ID'] === CITADEL_GATEWAY_ID,
      ),
    ).toBe(false)
  })

  it('hides every gateway on its own child map', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(
      locationsForMapView(launch, TOWN_MAP_ID).some((row) => row['Location ID'] === TOWN_GATEWAY_ID),
    ).toBe(false)
    expect(
      locationsForMapView(launch, CAVE_MAP_ID).some((row) => row['Location ID'] === 'LOC-0010'),
    ).toBe(false)
    expect(
      locationsForMapView(launch, CASTLE_MAP_ID).some(
        (row) => row['Location ID'] === CASTLE_GATEWAY_ID,
      ),
    ).toBe(false)
    expect(
      locationsForMapView(launch, FOREST_MAP_ID).some(
        (row) => row['Location ID'] === FOREST_GATEWAY_ID,
      ),
    ).toBe(false)
    expect(
      locationsForMapView(launch, DEPTHS_MAP_ID).some(
        (row) => row['Location ID'] === SUNKEN_APPROACH_ID,
      ),
    ).toBe(false)
  })

  it('resolves world-map gateway travel to the written landing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const town = launch.Locations.find((row) => row['Location ID'] === TOWN_GATEWAY_ID)!
    const cave = launch.Locations.find((row) => row['Location ID'] === 'LOC-0010')!
    const castle = launch.Locations.find((row) => row['Location ID'] === CASTLE_GATEWAY_ID)!
    const citadel = launch.Locations.find((row) => row['Location ID'] === CITADEL_GATEWAY_ID)!
    expect(landingLocationIdFor(town)).toBe(TOWN_GENERAL_STORE_ID)
    expect(landingLocationIdFor(cave)).toBe(CAVE_MINING_STORE_ID)
    expect(landingLocationIdFor(castle)).toBe(CASTLE_COURTYARD_ID)
    expect(landingLocationIdFor(citadel)).toBe(CITADEL_PLAZA_ID)
    const forest = launch.Locations.find((row) => row['Location ID'] === FOREST_GATEWAY_ID)!
    const depths = launch.Locations.find((row) => row['Location ID'] === SUNKEN_APPROACH_ID)!
    expect(landingLocationIdFor(forest)).toBe(FOREST_PATH_ID)
    expect(landingLocationIdFor(depths)).toBe(THE_SHALLOWS_ID)
    expect(resolveSubMapTravelDestination(launch, TOWN_GATEWAY_ID, MAIN_MAP_ID, 'LOC-0009')).toBe(
      TOWN_GENERAL_STORE_ID,
    )
    expect(
      resolveSubMapTravelDestination(launch, TOWN_GENERAL_STORE_ID, TOWN_MAP_ID, TOWN_KITCHEN_ID),
    ).toBe(TOWN_GENERAL_STORE_ID)
  })

  it('lands planTravel on the gateway landing from the world map', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const fromMeadow = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }
    const toTown = planTravel(launch, fromMeadow, TOWN_GATEWAY_ID, MAIN_MAP_ID, now)
    expect(toTown.kind).toBe('instant')
    if (toTown.kind !== 'instant') return
    expect(toTown.arrival.save.currentLocationId).toBe(TOWN_GENERAL_STORE_ID)

    const onGateway = { ...createNewSave(launch), currentLocationId: TOWN_GATEWAY_ID }
    const enter = planTravel(launch, onGateway, TOWN_GATEWAY_ID, MAIN_MAP_ID, now)
    expect(enter.kind).toBe('instant')
    if (enter.kind !== 'instant') return
    expect(enter.arrival.save.currentLocationId).toBe(TOWN_GENERAL_STORE_ID)
  })

  it('opens the Ancient Forest and The Depths from their world-map gates', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const forestGate = launch.Locations.find((row) => row['Location ID'] === FOREST_GATEWAY_ID)!
    const sunken = launch.Locations.find((row) => row['Location ID'] === SUNKEN_APPROACH_ID)!
    expect(resolveActiveMapId(launch, forestGate)).toBe(FOREST_MAP_ID)
    expect(resolveActiveMapId(launch, sunken)).toBe(DEPTHS_MAP_ID)
    expect(enterSubMapLabel(launch, forestGate)).toBe('Enter Ancient Forest')
    expect(enterSubMapLabel(launch, sunken)).toBe('Enter The Depths')

    const forestNodes = locationsForMapView(launch, FOREST_MAP_ID).map((row) => row['Location ID'])
    expect(forestNodes).toEqual(
      expect.arrayContaining([FOREST_PATH_ID, STARLIGHT_GLADE_ID, OLD_ENT_GROVE_ID]),
    )
    expect(forestNodes).not.toContain(FOREST_GATEWAY_ID)
    expect(canTravelTo(launch, FOREST_PATH_ID, OLD_ENT_GROVE_ID, FOREST_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, FOREST_PATH_ID, STARLIGHT_GLADE_ID, FOREST_MAP_ID)).toBe(true)

    const depthNodes = locationsForMapView(launch, DEPTHS_MAP_ID).map((row) => row['Location ID'])
    expect(depthNodes).toEqual(expect.arrayContaining([THE_SHALLOWS_ID, THE_DEPTHS_ID]))
    expect(depthNodes).not.toContain(SUNKEN_APPROACH_ID)
    expect(canTravelTo(launch, SUNKEN_APPROACH_ID, THE_SHALLOWS_ID, DEPTHS_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, THE_SHALLOWS_ID, THE_DEPTHS_ID, DEPTHS_MAP_ID)).toBe(true)

    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const fromMeadow = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }
    const toForest = planTravel(launch, fromMeadow, FOREST_GATEWAY_ID, MAIN_MAP_ID, now)
    expect(toForest.kind).toBe('instant')
    if (toForest.kind !== 'instant') return
    expect(toForest.arrival.save.currentLocationId).toBe(FOREST_PATH_ID)

    const toDepths = planTravel(launch, fromMeadow, SUNKEN_APPROACH_ID, MAIN_MAP_ID, now)
    expect(toDepths.kind).toBe('instant')
    if (toDepths.kind !== 'instant') return
    expect(toDepths.arrival.save.currentLocationId).toBe(THE_SHALLOWS_ID)
  })
})
