import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { recipeFacilityIdForLookup } from '../production/recipes'
import { createNewSave } from '../save/saveStore'
import {
  COOKING_SKILL_ID,
  FISHING_SKILL_ID,
  HUNTING_SKILL_ID,
  THIEVERY_SKILL_ID,
  WOODCUTTING_SKILL_ID,
  HARVESTING_SKILL_ID,
} from '../skills/skillActions'
import { GOBLIN_CAMP_ID, KINGSROAD_ID, MAIN_MAP_ID, RIVERSIDE_MANOR_ID } from './constants'
import { skillIdsForLocation } from './locationSkills'
import { MAIN_MAP_NODE_LAYOUT } from './mapLayout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function poolWeights(launch: ReturnType<typeof prepareDatabase>['launch'], poolId: string) {
  return launch.PoolEntries.filter((row) => row['Pool ID'] === poolId)
    .map((row) => `${row['Action ID']}:${row.Weight}`)
    .sort()
}

describe('map node activity batch one', () => {
  it('adds Riverside Manor under the Citadel with the listed activity pools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const loc = launch.Locations.find((row) => row['Location ID'] === RIVERSIDE_MANOR_ID)!
    expect(loc['Display Name']).toBe('Riverside Manor')
    expect(loc['Map ID']).toBe(MAIN_MAP_ID)
    expect(loc['Parent Location ID']).toBeFalsy()
    expect(MAIN_MAP_NODE_LAYOUT[RIVERSIDE_MANOR_ID]).toEqual({ x: 46, y: 50 })

    const acts = launch.Activities.filter((row) => row['Location ID'] === RIVERSIDE_MANOR_ID)
    expect(acts.map((row) => row['Contextual Name']).sort()).toEqual([
      'Cook at the kitchen',
      'Fish the manor river',
      'Hunt the riverside',
      'Pick the locked storeroom',
      'Work the manor grounds',
    ])
    expect(poolWeights(launch, 'POOL-0065')).toEqual(['ACN-0100:30', 'ACN-0101:70'])
    expect(poolWeights(launch, 'POOL-0066')).toEqual([
      'ACN-0048:20',
      'ACN-0184:20',
      'ACN-0200:60',
    ])
    expect(poolWeights(launch, 'POOL-0067')).toEqual(['ACN-0013:80', 'ACN-0205:20'])
    expect(poolWeights(launch, 'POOL-0068')).toEqual(['ACN-0227:100'])
    expect(recipeFacilityIdForLookup('FAC-0022')).toBe('FAC-0001')

    const save = createNewSave(launch)
    const skills = skillIdsForLocation(launch, save, RIVERSIDE_MANOR_ID)
    expect(skills).toEqual(
      expect.arrayContaining([
        FISHING_SKILL_ID,
        WOODCUTTING_SKILL_ID,
        HARVESTING_SKILL_ID,
        HUNTING_SKILL_ID,
        THIEVERY_SKILL_ID,
        COOKING_SKILL_ID,
      ]),
    )
  })

  it('updates Goblin Camp fishing to trout, salmon, and algae', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0003')).toEqual([
      'ACN-0100:50',
      'ACN-0101:40',
      'ACN-0180:10',
    ])
    const save = createNewSave(launch)
    expect(skillIdsForLocation(launch, save, GOBLIN_CAMP_ID)).toEqual(
      expect.arrayContaining([FISHING_SKILL_ID, HARVESTING_SKILL_ID]),
    )
  })

  it('adds Kingsroad fishing and merchant-chest thievery', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const acts = launch.Activities.filter((row) => row['Location ID'] === KINGSROAD_ID)
    expect(acts.map((row) => row['Contextual Name']).sort()).toEqual([
      'Fight the bandits',
      'Fish the Kingsroad river',
      "Pick a merchant's chest",
    ])
    expect(poolWeights(launch, 'POOL-0063')).toEqual([
      'ACN-0101:30',
      'ACN-0102:50',
      'ACN-0103:20',
    ])
    expect(poolWeights(launch, 'POOL-0064')).toEqual(['ACN-0224:100'])
  })
})
