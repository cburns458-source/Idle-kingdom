import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { activityHasMixedCombatPool } from './hostility'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function poolWeights(launch: ReturnType<typeof prepareDatabase>['launch'], poolId: string) {
  return launch.PoolEntries.filter((row) => row['Pool ID'] === poolId)
    .map((row) => `${row['Action ID']}:${row.Weight}`)
    .sort()
}

describe('map node activity batch two', () => {
  it('rewrites docks, copper mine, meadow, and kingswoods pools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0004')).toEqual([
      'ACN-0103:35',
      'ACN-0173:5',
      'ACN-0215:50',
      'ACN-0216:10',
    ])
    expect(activityHasMixedCombatPool(launch, 'ACT-0004')).toBe(true)
    expect(poolWeights(launch, 'POOL-0005')).toEqual([
      'ACN-0018:60',
      'ACN-0019:20',
      'ACN-0020:20',
    ])
    expect(poolWeights(launch, 'POOL-0027')).toEqual(['ACN-0099:90', 'ACN-0100:10'])
    expect(poolWeights(launch, 'POOL-0069')).toEqual(['ACN-0013:100'])
    expect(poolWeights(launch, 'POOL-0011')).toEqual(['ACN-0015:50', 'ACN-0016:50'])
    expect(poolWeights(launch, 'POOL-0012')).toEqual(['ACN-0105:70', 'ACN-0106:30'])
    expect(poolWeights(launch, 'POOL-0009')).toEqual([
      'ACN-0014:40',
      'ACN-0017:40',
      'ACN-0204:10',
    ])
    expect(poolWeights(launch, 'POOL-0010')).toEqual([
      'ACN-0008:10',
      'ACN-0107:50',
      'ACN-0108:10',
      'ACN-0184:30',
    ])
  })

  it('updates courtyard, forest, lake, glade, grove, slopes, and temple', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0014')).toEqual(['ACN-0017:50', 'ACN-0106:50'])
    expect(poolWeights(launch, 'POOL-0070')).toEqual(['ACN-0014:70', 'ACN-0205:30'])
    expect(poolWeights(launch, 'POOL-0071')).toEqual([
      'ACN-0105:20',
      'ACN-0108:40',
      'ACN-0109:30',
    ])
    expect(poolWeights(launch, 'POOL-0072')).toEqual([
      'ACN-0048:30',
      'ACN-0049:40',
      'ACN-0179:30',
    ])
    expect(poolWeights(launch, 'POOL-0073')).toEqual([
      'ACN-0013:20',
      'ACN-0180:30',
      'ACN-0206:50',
    ])
    expect(poolWeights(launch, 'POOL-0074')).toEqual(['ACN-0100:30', 'ACN-0102:70'])
    expect(poolWeights(launch, 'POOL-0038')).toEqual([
      'ACN-0105:5',
      'ACN-0110:55',
      'ACN-0111:40',
    ])
    expect(poolWeights(launch, 'POOL-0016')).toEqual([
      'ACN-0010:50',
      'ACN-0011:20',
      'ACN-0012:30',
    ])
    expect(poolWeights(launch, 'POOL-0030')).toEqual([
      'ACN-0049:45',
      'ACN-0050:50',
      'ACN-0051:5',
    ])
    expect(poolWeights(launch, 'POOL-0006')).toEqual([
      'ACN-0020:10',
      'ACN-0021:30',
      'ACN-0022:50',
      'ACN-0238:10',
    ])
    expect(poolWeights(launch, 'POOL-0022')).toEqual(['ACN-0112:100'])
    expect(poolWeights(launch, 'POOL-0029')).toEqual(['ACN-0105:20', 'ACN-0109:80'])
  })
})
