import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function poolWeights(
  launch: ReturnType<typeof prepareDatabase>['launch'],
  poolId: string,
): Array<{ actionId: string; weight: number | null }> {
  return launch.PoolEntries.filter((row) => row['Pool ID'] === poolId).map((row) => ({
    actionId: row['Action ID'],
    weight: row.Weight == null ? null : Number(row.Weight),
  }))
}

describe('ore pool weights', () => {
  it('adds titanium and tungsten to the deep mines', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const weights = poolWeights(launch, 'POOL-0013')
    expect(weights).toEqual(
      expect.arrayContaining([
        { actionId: 'ACN-0022', weight: 35 },
        { actionId: 'ACN-0021', weight: 35 },
        { actionId: 'ACN-0097', weight: 15 },
        { actionId: 'ACN-0098', weight: 5 },
        { actionId: 'ACN-0026', weight: 5 },
        { actionId: 'ACN-0027', weight: 5 },
      ]),
    )
  })

  it('adds tin to the mountain side and keeps the trolls', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(poolWeights(launch, 'POOL-0006')).toEqual(
      expect.arrayContaining([
        { actionId: 'ACN-0021', weight: 35 },
        { actionId: 'ACN-0022', weight: 35 },
        { actionId: 'ACN-0005', weight: 15 },
        { actionId: 'ACN-0096', weight: 5 },
        { actionId: 'ACN-0020', weight: 10 },
      ]),
    )
  })

  it('keeps elder rock troll ore drops with swapped titanium/tungsten packages', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const titanium = launch.RewardEntries.find((entry) => entry['Reward Entry ID'] === 'RWE-0050')
    expect(titanium?.['Reward ID / Value']).toBe('ITEM-0009')
    expect(titanium?.Weight).toBe(35)
    expect(titanium?.['Minimum Quantity']).toBe(1)
    expect(titanium?.['Maximum Quantity']).toBe(2)

    const tungsten = launch.RewardEntries.find((entry) => entry['Reward Entry ID'] === 'RWE-0049')
    expect(tungsten?.['Reward ID / Value']).toBe('ITEM-0010')
    expect(tungsten?.Weight).toBe(25)
    expect(tungsten?.['Minimum Quantity']).toBe(3)
    expect(tungsten?.['Maximum Quantity']).toBe(5)
  })
})
