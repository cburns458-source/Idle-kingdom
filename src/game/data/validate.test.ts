import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import type { RequirementRow } from './types'
import { prepareDatabase } from './loadDatabase'
import { filterLaunchContent, validateDatabase } from './validate'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('database loading', () => {
  it('parses and validates the compact database without errors', () => {
    const loaded = prepareDatabase(rawDatabase)
    const errors = loaded.issues.filter((issue) => issue.severity === 'error')

    expect(errors).toEqual([])
    expect(loaded.sourceIndexes.locationsById.has('LOC-0002')).toBe(true)
    expect(loaded.launchIndexes.configByKey.get('primary_activity_slots')?.Value).toBe(1)
  })

  it('filters Expansion content without mutating source tables', () => {
    const loaded = prepareDatabase(rawDatabase)
    const launch = filterLaunchContent(loaded.source)

    expect(loaded.source.Enemies.some((row) => row['Release Phase'] === 'Expansion')).toBe(true)
    expect(launch.Enemies.every((row) => row['Release Phase'] === 'Launch')).toBe(true)
    expect(launch.Enemies.length).toBeLessThan(loaded.source.Enemies.length)
    expect(launch.Locations.every((row) => row['Release Phase'] === 'Launch')).toBe(true)
    expect(validateDatabase(loaded.source).filter((issue) => issue.severity === 'error')).toEqual([])
  })

  it('indexes stable IDs for lookup', () => {
    const loaded = prepareDatabase(rawDatabase)
    const town = loaded.launchIndexes.locationsById.get('LOC-0002')
    expect(town?.['Display Name']).toBe('The Town')
    expect(loaded.launchIndexes.skillsById.get('SKL-0001')?.['Display Name']).toBe('Combat')
  })

  it('rejects unknown requirement types and missing drop chances', () => {
    const loaded = prepareDatabase(rawDatabase)
    const action = loaded.source.Actions.find((row) => row['Reward Table ID'])
    expect(action).toBeDefined()
    const issues = validateDatabase({
      ...loaded.source,
      Actions: loaded.source.Actions.map((row) =>
        row === action ? { ...row, 'Drop Chance': null } : row,
      ),
      Requirements: [
        ...loaded.source.Requirements,
        {
          'Requirement ID': 'REQ-BAD',
          'Requirement Type': 'Made Up',
          'Entity Type': 'Activity',
          'Entity ID': 'ACT-0001',
          'Reference ID / Value': 'x',
        } as RequirementRow,
      ],
    })
    expect(issues.some((issue) => issue.message.includes('Missing Drop Chance'))).toBe(true)
    expect(issues.some((issue) => issue.message.includes('Unknown Requirement Type'))).toBe(true)
  })
})
