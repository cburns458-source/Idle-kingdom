import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { APPEARANCE_CATEGORIES } from '../save/types'
import {
  appearanceOptions,
  defaultAppearance,
  isValidAppearanceOption,
  setAppearanceOption,
} from './appearance'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('appearance', () => {
  it('lists options for every category, sorted by Sort Order', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const category of APPEARANCE_CATEGORIES) {
      const options = appearanceOptions(launch, category)
      expect(options.length).toBeGreaterThan(0)
      const sorts = options.map((row) => row['Sort Order'] ?? 0)
      expect(sorts).toEqual([...sorts].sort((a, b) => a - b))
    }
  })

  it('matches createNewSave defaults to the first option per category', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const defaults = defaultAppearance(launch)
    expect(save.appearance).toEqual(defaults)
  })

  it('validates and sets a chosen option, rejecting unknown ones', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const options = appearanceOptions(launch, 'hairColor')
    const chosen = options[options.length - 1]!['Appearance Option ID']

    expect(isValidAppearanceOption(launch, 'hairColor', chosen)).toBe(true)
    const updated = setAppearanceOption(launch, save, 'hairColor', chosen)
    expect(updated?.appearance.hairColor).toBe(chosen)
    // Other categories untouched.
    expect(updated?.appearance.skinTone).toBe(save.appearance.skinTone)

    expect(isValidAppearanceOption(launch, 'hairColor', 'NOT-REAL')).toBe(false)
    expect(setAppearanceOption(launch, save, 'hairColor', 'NOT-REAL')).toBeNull()
  })
})
