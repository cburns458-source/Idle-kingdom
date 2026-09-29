import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { recipeFacilityIdForLookup, projectFacilityIdForLookup } from '../production/recipes'
import { specialProductionStationsAt } from '../projects/projects'
import { GIANT_CAMP_ID } from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function poolWeights(launch: ReturnType<typeof prepareDatabase>['launch'], poolId: string) {
  return launch.PoolEntries.filter((row) => row['Pool ID'] === poolId)
    .map((row) => `${row['Action ID']}:${row.Weight}`)
    .sort()
}

describe('map node activity batch three', () => {
  it('expands Badlands mining, hunting, and woodcutting', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0051')).toEqual([
      'ACN-0005:10',
      'ACN-0020:25',
      'ACN-0021:50',
      'ACN-0097:10',
      'ACN-0098:5',
    ])
    expect(poolWeights(launch, 'POOL-0075')).toEqual(['ACN-0112:30', 'ACN-0208:70'])
    expect(poolWeights(launch, 'POOL-0076')).toEqual(['ACN-0202:90', 'ACN-0221:10'])
  })

  it('adds Giant Camp kitchen, crafting, metallurgy, and smithing stations', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(recipeFacilityIdForLookup('FAC-0023')).toBe('FAC-0001')
    expect(recipeFacilityIdForLookup('FAC-0024')).toBe('FAC-0003')
    expect(recipeFacilityIdForLookup('FAC-0025')).toBe('FAC-0004')
    expect(projectFacilityIdForLookup('FAC-0026')).toBe('FAC-0005')
    const stations = specialProductionStationsAt(launch, GIANT_CAMP_ID)
    expect(stations.some((row) => row.facility['Facility ID'] === 'FAC-0026')).toBe(true)
    const acts = launch.Activities.filter((row) => row['Location ID'] === GIANT_CAMP_ID).map(
      (row) => row['Contextual Name'],
    )
    expect(acts).toEqual(
      expect.arrayContaining(['Raid the giant camp', 'Cook at the kitchen', 'Craft components', 'Refine metals']),
    )
  })

  it('rewrites Peak, Deep Mines combat, and abandoned-shaft fishing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0050')).toEqual(['ACN-0211:30', 'ACN-0219:70'])
    expect(poolWeights(launch, 'POOL-0077')).toEqual(['ACN-0238:70', 'ACN-0239:30'])
    expect(poolWeights(launch, 'POOL-0028')).toEqual([
      'ACN-0103:50',
      'ACN-0104:20',
      'ACN-0215:30',
    ])
  })
})
