import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { BOTANY_PATCH_LOCATIONS } from '../timers/locationTimers'
import { forcedHostileActivity } from './hostility'
import { canTravelTo, locationsForMapView } from './travel'
import { isSubMapGateway, landingLocationIdFor, resolveSubMapTravelDestination } from './submaps'
import {
  BADLANDS_ID,
  GIANT_CAMP_ID,
  MAIN_MAP_ID,
  MOUNTAINS_GATEWAY_ID,
  MOUNTAINS_MAP_ID,
  THE_PEAK_ID,
  THE_SLOPES_ID,
} from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
) as unknown

function weights(
  launch: ReturnType<typeof prepareDatabase>['launch'],
  poolId: string,
): Record<string, number> {
  const out: Record<string, number> = {}
  for (const entry of launch.PoolEntries) {
    if (entry['Pool ID'] !== poolId) continue
    out[entry['Action ID']] = Number(entry.Weight)
  }
  return out
}

describe('Mountains sub-map', () => {
  it('is a world-map gateway onto The Slopes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const gate = launch.Locations.find((row) => row['Location ID'] === MOUNTAINS_GATEWAY_ID)!
    expect(gate['Display Name']).toBe('Mountains')
    expect(gate['Map ID']).toBe(MAIN_MAP_ID)
    expect(isSubMapGateway(gate)).toBe(true)
    expect(landingLocationIdFor(gate)).toBe(THE_SLOPES_ID)
    expect(gate['Hidden On Map IDs']).toBe(MOUNTAINS_MAP_ID)

    const slopes = launch.Locations.find((row) => row['Location ID'] === THE_SLOPES_ID)!
    expect(slopes['Display Name']).toBe('The Slopes')
    expect(slopes['Map ID']).toBe(MOUNTAINS_MAP_ID)
    expect(slopes['Parent Location ID']).toBe(MOUNTAINS_GATEWAY_ID)

    expect(
      locationsForMapView(launch, MAIN_MAP_ID).some(
        (row) => row['Location ID'] === MOUNTAINS_GATEWAY_ID,
      ),
    ).toBe(true)
    expect(
      locationsForMapView(launch, MOUNTAINS_MAP_ID).some(
        (row) => row['Location ID'] === MOUNTAINS_GATEWAY_ID,
      ),
    ).toBe(false)
    expect(locationsForMapView(launch, MOUNTAINS_MAP_ID).map((row) => row['Location ID'])).toEqual(
      expect.arrayContaining([THE_SLOPES_ID, 'LOC-0036', THE_PEAK_ID, BADLANDS_ID, GIANT_CAMP_ID]),
    )
  })

  it('keeps the old mountain work on The Slopes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const slopeActs = launch.Activities.filter((row) => row['Location ID'] === THE_SLOPES_ID).map(
      (row) => row['Activity ID'],
    )
    expect(slopeActs).toEqual(expect.arrayContaining(['ACT-0006', 'ACT-0027', 'ACT-0065']))
    expect(launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0003')!['Location ID']).toBe(
      THE_SLOPES_ID,
    )
    expect(launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0007')!['Location ID']).toBe(
      THE_SLOPES_ID,
    )
    expect(BOTANY_PATCH_LOCATIONS.has(THE_SLOPES_ID)).toBe(true)
    expect(BOTANY_PATCH_LOCATIONS.has(MOUNTAINS_GATEWAY_ID)).toBe(false)
  })

  it('writes Peak, Badlands, and Giant Camp pools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(weights(launch, 'POOL-0050')).toEqual({ 'ACN-0200': 70, 'ACN-0201': 30 })
    expect(weights(launch, 'POOL-0051')).toEqual({ 'ACN-0021': 50, 'ACN-0020': 50 })
    expect(weights(launch, 'POOL-0052')).toEqual({ 'ACN-0202': 60, 'ACN-0203': 40 })

    const peak = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0068')!
    expect(peak['Location ID']).toBe(THE_PEAK_ID)
    expect(peak['Danger Warning Combat Level']).toBe(72)
    const camp = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0070')!
    expect(camp['Location ID']).toBe(GIANT_CAMP_ID)
    expect(camp['Danger Warning Combat Level']).toBe(77)

    const save = createNewSave(launch)
    expect(forcedHostileActivity(launch, save, THE_PEAK_ID)?.['Activity ID']).toBe('ACT-0068')
    expect(forcedHostileActivity(launch, save, GIANT_CAMP_ID)?.['Activity ID']).toBe('ACT-0070')
    expect(forcedHostileActivity(launch, save, THE_SLOPES_ID)).toBeNull()
  })

  it('lands world-map travel on The Slopes and opens the highland nodes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(
      resolveSubMapTravelDestination(launch, MOUNTAINS_GATEWAY_ID, MAIN_MAP_ID, 'LOC-0009'),
    ).toBe(THE_SLOPES_ID)
    expect(canTravelTo(launch, THE_SLOPES_ID, THE_PEAK_ID, MOUNTAINS_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, THE_SLOPES_ID, BADLANDS_ID, MOUNTAINS_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, THE_SLOPES_ID, GIANT_CAMP_ID, MOUNTAINS_MAP_ID)).toBe(true)
    expect(canTravelTo(launch, THE_SLOPES_ID, 'LOC-0036', MOUNTAINS_MAP_ID)).toBe(true)
  })
})
