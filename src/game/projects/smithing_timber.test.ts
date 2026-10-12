import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

/** Metal bar display name → timber the smithing recipes that use wood should take. */
const TIMBER_BY_BAR: Record<string, string> = {
  'Copper Bar': 'Cedar Timber',
  'Bronze Bar': 'Oak Timber',
  'Iron Bar': 'Poplar Timber',
  'Steel Bar': 'Maple Timber',
  'Reinforced Steel Bar': 'Maple Timber',
  'Tungsten Bar': 'Ironwood Timber',
  'Titanium Bar': 'Mahogany Timber',
}

describe('smithing timber tiers', () => {
  it('uses the level-matched timber for every bar that already needs wood', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const nameOf = (id: string | null | undefined) =>
      id ? launch.Items.find((row) => row['Item ID'] === id)?.['Display Name'] : null

    let checked = 0
    for (const project of launch.Projects) {
      if (project['Skill ID'] !== 'SKL-0011') continue
      const inputs = [1, 2, 3, 4]
        .map((slot) => nameOf(project[`Input ${slot} Item ID` as keyof typeof project] as string))
        .filter((name): name is string => Boolean(name))
      const bar = inputs.find((name) => name in TIMBER_BY_BAR)
      const timber = inputs.find((name) => name.endsWith('Timber'))
      if (!bar || !timber) continue
      expect(timber, project['Display Name']).toBe(TIMBER_BY_BAR[bar])
      checked += 1
    }
    expect(checked).toBeGreaterThan(40)
  })
})

describe('hunt fox drop chance', () => {
  it('stores a visible 30% main drop chance', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const fox = launch.Actions.find((row) => row['Action ID'] === 'ACN-0205')!
    expect(fox['Drop Chance']).toBe(30)
  })
})
