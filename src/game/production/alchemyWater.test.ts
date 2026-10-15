import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { removeIngredients } from './inventory'
import {
  KITCHEN_SCRAPS_ITEM_ID,
  WATER_ITEM_ID,
  getRecipe,
  ingredientOwned,
  maxCraftsFromMaterials,
  recipeIngredients,
} from './recipes'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const POTION_RECIPES = [
  'RCP-0040', 'RCP-0041', 'RCP-0043', 'RCP-0053', 'RCP-0054', 'RCP-0055', 'RCP-0056', 'RCP-0059',
  'RCP-0078', 'RCP-0079', 'RCP-0080', 'RCP-0081',
]

describe('water at Alchemy stations', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('every potion recipe lists Water x1', () => {
    for (const id of POTION_RECIPES) {
      const recipe = getRecipe(launch, id)!
      expect(recipe, id).toBeDefined()
      expect(recipeIngredients(recipe), id).toContainEqual({ itemId: WATER_ITEM_ID, quantity: 1 })
    }
  })

  it('water is free and unconsumed at both apothecaries, but not elsewhere', () => {
    const base = createNewSave(launch)
    for (const loc of ['LOC-0026', 'LOC-0030']) {
      const save = { ...base, currentLocationId: loc, inventory: [{ itemId: 'ITEM-0031', quantity: 3 }] }
      expect(ingredientOwned(save, WATER_ITEM_ID)).toBe(Number.POSITIVE_INFINITY)
      const tonic = getRecipe(launch, 'RCP-0078')!
      expect(maxCraftsFromMaterials(save, tonic)).toBe(3)
      const after = removeIngredients(save, recipeIngredients(tonic), 3)!
      expect(after.inventory.find((s) => s.itemId === 'ITEM-0031')).toBeUndefined()
    }
    const town = { ...base, currentLocationId: 'LOC-0026' }
    expect(ingredientOwned(town, KITCHEN_SCRAPS_ITEM_ID)).toBe(0)
    const away = { ...base, currentLocationId: 'LOC-0001', inventory: [] }
    expect(ingredientOwned(away, WATER_ITEM_ID)).toBe(0)
  })
})
