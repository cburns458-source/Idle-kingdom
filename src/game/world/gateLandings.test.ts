import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { CAVE_MOUTH_ID, MAIN_MAP_ID, TOWN_SQUARE_ID } from './constants'
import { isSubMapGateway, landingLocationIdFor, subMapIdForGateway } from './submaps'
import { locationsForMapView } from './travel'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('sub-map gateway landings', () => {
  const { launch } = prepareDatabase(rawDatabase)
  const gateways = launch.Locations.filter(isSubMapGateway)

  it('finds Launch gateways', () => {
    expect(gateways.length).toBeGreaterThan(0)
  })

  it.each(gateways.map((gate) => [gate['Location ID'], gate] as const))(
    '%s lands on a node of its own sub-map, open from the start',
    (_id, gate) => {
      const subMapId = subMapIdForGateway(launch, gate['Location ID'])
      expect(subMapId).not.toBeNull()
      expect(gate['Map ID']).toBe(MAIN_MAP_ID)
      const landingId = landingLocationIdFor(gate)
      expect(landingId).toBeTruthy()
      if (!landingId) return
      const landing = launch.Locations.find((row) => row['Location ID'] === landingId)
      expect(landing?.['Map ID']).toBe(subMapId)
      expect(landing?.['Parent Location ID']).toBe(gate['Location ID'])
      expect(
        locationsForMapView(launch, subMapId!, { unlockedLocationIds: [] }).some(
          (row) => row['Location ID'] === landingId,
        ),
      ).toBe(true)
    },
  )

  it.each(gateways.map((gate) => [gate['Location ID'], gate] as const))(
    '%s is hidden on its own sub-map',
    (_id, gate) => {
      const subMapId = subMapIdForGateway(launch, gate['Location ID'])!
      expect(
        locationsForMapView(launch, subMapId, { unlockedLocationIds: [] }).some(
          (row) => row['Location ID'] === gate['Location ID'],
        ),
      ).toBe(false)
    },
  )

  it('covers the #313 landings: Town Square and Cave Mouth', () => {
    const landings = gateways.map((gate) => landingLocationIdFor(gate))
    expect(landings).toContain(TOWN_SQUARE_ID)
    expect(landings).toContain(CAVE_MOUTH_ID)
  })
})
