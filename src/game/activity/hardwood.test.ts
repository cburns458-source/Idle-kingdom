import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('hardwood chopping', () => {
  it('adds a maple/mahogany activity on the Ancient Forest', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const activity = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0040')
    expect(activity?.['Contextual Name']).toBe('Chop down hardwood trees')
    expect(activity?.['Location ID']).toBe('LOC-0018')
    expect(activity?.['Pool ID']).toBe('POOL-0030')

    const explore = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0016')
    expect(explore?.['Pool ID']).toBe('POOL-0016')

    const hardwood = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0030')
    expect(hardwood).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ 'Action ID': 'ACN-0049', Weight: 70 }),
        expect.objectContaining({ 'Action ID': 'ACN-0050', Weight: 30 }),
      ]),
    )
    expect(hardwood).toHaveLength(2)

    const explorePool = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0016')
    expect(explorePool.map((row) => row['Action ID']).sort()).toEqual(
      ['ACN-0010', 'ACN-0011', 'ACN-0012', 'ACN-0051'].sort(),
    )

    const tool = launch.Requirements.find((row) => row['Requirement ID'] === 'REQ-0110')
    expect(tool).toMatchObject({
      'Entity ID': 'ACT-0040',
      'Requirement Type': 'Tool Capability',
      'Reference ID / Value': 'woodcutting_tool',
    })
  })
})
