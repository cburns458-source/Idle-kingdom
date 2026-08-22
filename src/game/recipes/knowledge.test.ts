import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { canKnowRecipe, getRecipe } from '../production/recipes'
import { createNewSave } from '../save/saveStore'
import { knowsRecipe, listRecipeBookEntries, unlockRecipeId } from './knowledge'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('recipe knowledge', () => {
  it('gates automatic recipes by proficiency and unlocks explicit IDs', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const luck = getRecipe(launch, 'RCP-0053')!
    expect(canKnowRecipe(save, launch, luck)).toBe(false)

    const starter = launch.Recipes.find(
      (recipe) =>
        recipe['Proficiency Level'] === 1 &&
        (recipe['Knowledge Source'] ?? '').toLowerCase().includes('automatic'),
    )
    if (starter) {
      expect(knowsRecipe(save, launch, starter['Recipe ID'])).toBe(true)
    }

    save = unlockRecipeId(save, 'RCP-0053')
    expect(knowsRecipe(save, launch, 'RCP-0053')).toBe(true)
    expect(canKnowRecipe(save, launch, luck)).toBe(true)
  })

  it('lists recipes and projects in the recipe book', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const entries = listRecipeBookEntries(save, launch)
    expect(entries.some((entry) => entry.kind === 'recipe')).toBe(true)
    expect(entries.some((entry) => entry.known)).toBe(true)
  })

  it('lists the recipe book by proficiency, leaving locked rows in place', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const entries = listRecipeBookEntries(save, launch)
    const levels = entries.map((entry) => entry.proficiency)
    expect(levels).toEqual([...levels].sort((a, b) => a - b))
    expect(entries.some((entry) => !entry.known)).toBe(true)
    const firstLocked = entries.findIndex((entry) => !entry.known)
    const laterKnown = entries.slice(firstLocked + 1).some((entry) => entry.known)
    expect(laterKnown).toBe(true)
  })
})
