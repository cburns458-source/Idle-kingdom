import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import {
  FOREST_MAP_ID,
  FOREST_PATH_ID,
  STARLIGHT_GLADE_ID,
  THE_DEPTHS_ID,
  THE_SHALLOWS_ID,
} from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('shallows and starlight content', () => {
  it('puts fishing and algae at The Shallows', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const acts = launch.Activities.filter((row) => row['Location ID'] === THE_SHALLOWS_ID)
    expect(acts.map((row) => row['Contextual Name']).sort()).toEqual([
      'Fish in the shallows',
      'Gather algae',
    ])
    const fishPool = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0034')
    expect(fishPool.map((row) => `${row['Action ID']}:${row.Weight}`).sort()).toEqual([
      'ACN-0101:40',
      'ACN-0102:60',
    ])
    const algae = launch.Actions.find((row) => row['Action ID'] === 'ACN-0180')!
    expect(algae['Proficiency Level']).toBe(40)
    expect(algae['Target ID']).toBe('ITEM-0319')
    expect(algae['XP Reward']).toBe(3000)
    expect(algae['Base Duration Seconds']).toBe(180)
  })

  it('puts clear vines on Forest Path and hunt/moonblossoms at Starlight Glade', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const vines = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0048')!
    expect(vines['Location ID']).toBe(FOREST_PATH_ID)
    const clear = launch.Actions.find((row) => row['Action ID'] === 'ACN-0179')!
    expect(clear['Proficiency Level']).toBe(40)
    expect(clear['Drop Chance']).toBe(0)
    expect(clear['XP Reward']).toBe(5000)

    const gladeActs = launch.Activities.filter((row) => row['Location ID'] === STARLIGHT_GLADE_ID)
    expect(gladeActs.map((row) => row['Contextual Name']).sort()).toEqual([
      'Hunt for the great stag',
      'Pick moonblossoms',
    ])
    const hunt = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0037')
    expect(hunt.map((row) => `${row['Action ID']}:${row.Weight}`).sort()).toEqual([
      'ACN-0014:60',
      'ACN-0113:40',
    ])
    const blossoms = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0038')
    expect(blossoms).toEqual([
      expect.objectContaining({ 'Action ID': 'ACN-0110', Weight: 100 }),
    ])
    expect(launch.Locations.find((row) => row['Location ID'] === STARLIGHT_GLADE_ID)?.['Map ID']).toBe(
      FOREST_MAP_ID,
    )
    expect(launch.Locations.find((row) => row['Location ID'] === THE_DEPTHS_ID)?.['Map ID']).toBe(
      'MAP-0009',
    )
  })
})
