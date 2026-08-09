import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from './loadDatabase'
import { filterLaunchContent, validateDatabase } from './validate'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
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
})
