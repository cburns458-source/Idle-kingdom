import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('tuna renamed to bass', () => {
  it('renames catch/cook items and actions', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const raw = launch.Items.find((row) => row['Item ID'] === 'ITEM-0050')!
    const cooked = launch.Items.find((row) => row['Item ID'] === 'ITEM-0062')!
    expect(raw['Display Name']).toBe('Raw Bass')
    expect(raw['Internal Key']).toBe('raw_bass')
    expect(cooked['Display Name']).toBe('Cooked Bass')
    expect(cooked['Internal Key']).toBe('cooked_bass')

    const catchAction = launch.Actions.find((row) => row['Action ID'] === 'ACN-0102')!
    expect(catchAction['Display Name']).toBe('Catch bass')
    expect(catchAction['Internal Key']).toBe('catch_bass')
    expect(JSON.stringify(launch)).not.toMatch(/tuna/i)
  })
})
