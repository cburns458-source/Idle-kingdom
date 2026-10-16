import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { addItemToInventory } from '../activity/rewards'
import { cancelProductionActivity, beginProductionQueue } from './engine'
import { removeIngredients } from './inventory'
import {
  KITCHEN_SCRAPS_ITEM_ID,
  WATER_ITEM_ID,
  alchemyStationLocationIds,
  getRecipe,
  ingredientOwned,
  isAtAlchemyStation,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
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
      expect(ingredientOwned(launch, save, WATER_ITEM_ID)).toBe(Number.POSITIVE_INFINITY)
      const tonic = getRecipe(launch, 'RCP-0078')!
      expect(maxCraftsFromMaterials(launch, save, tonic)).toBe(3)
      const after = removeIngredients(launch, save, recipeIngredients(tonic), 3)!
      expect(after.inventory.find((s) => s.itemId === 'ITEM-0031')).toBeUndefined()
    }
    const town = { ...base, currentLocationId: 'LOC-0026' }
    expect(ingredientOwned(launch, town, KITCHEN_SCRAPS_ITEM_ID)).toBe(0)
    const away = { ...base, currentLocationId: 'LOC-0001', inventory: [] }
    expect(ingredientOwned(launch, away, WATER_ITEM_ID)).toBe(0)
  })

  it('water is free at every kitchen, including Riverside Manor and Giant Camp', () => {
    const base = createNewSave(launch)
    const kitchens = ['LOC-0023', 'LOC-0015', 'LOC-0030', 'LOC-0053', 'LOC-0049']
    for (const loc of kitchens) {
      const save = { ...base, currentLocationId: loc }
      expect(ingredientOwned(launch, save, WATER_ITEM_ID), loc).toBe(Number.POSITIVE_INFINITY)
      // Kitchen scraps uses the same location list, so it is free here too.
      expect(ingredientOwned(launch, save, KITCHEN_SCRAPS_ITEM_ID), loc).toBe(Number.POSITIVE_INFINITY)
    }
    const away = { ...base, currentLocationId: 'LOC-0001' }
    expect(ingredientOwned(launch, away, WATER_ITEM_ID)).toBe(0)
    expect(ingredientOwned(launch, away, KITCHEN_SCRAPS_ITEM_ID)).toBe(0)
  })

  it('finds Alchemy stations from Facilities, not a hard-coded location list', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const fromFacilities = [
      ...new Set(
        launch.Facilities.filter((row) => row['Skill ID'] === 'SKL-0010')
          .map((row) => row['Location ID'])
          .filter((id): id is string => typeof id === 'string' && id.length > 0),
      ),
    ].sort()
    expect([...alchemyStationLocationIds(launch)].sort()).toEqual(fromFacilities)
    expect(fromFacilities).toEqual(['LOC-0026', 'LOC-0030'])
    const base = createNewSave(launch)
    expect(isAtAlchemyStation(launch, { ...base, currentLocationId: 'LOC-0026' })).toBe(true)
    expect(isAtAlchemyStation(launch, { ...base, currentLocationId: 'LOC-0023' })).toBe(false)
  })

  it('brews at the apothecary with no water, never uses water, and refunds everything except water', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const tonic = getRecipe(launch, 'RCP-0078')!
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0026' }
    save = addItemToInventory(save, 'ITEM-0031', 5)
    save = addItemToInventory(save, WATER_ITEM_ID, 2)
    expect(maxCraftsFromMaterials(launch, save, tonic)).toBe(5)
    expect(maxCraftsFromQueueCap(launch, tonic)).toBe(Math.floor((24 * 3600) / 12))

    const queued = beginProductionQueue(launch, save, 'ACT-0020', 'RCP-0078', 3)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.inventory.find((s) => s.itemId === 'ITEM-0031')?.quantity).toBe(2)
    expect(queued.save.inventory.find((s) => s.itemId === WATER_ITEM_ID)?.quantity).toBe(2)

    const cancelled = cancelProductionActivity(launch, queued.save)
    expect(cancelled.inventory.find((s) => s.itemId === 'ITEM-0031')?.quantity).toBe(5)
    expect(cancelled.inventory.find((s) => s.itemId === WATER_ITEM_ID)?.quantity).toBe(2)
  })

  it('does not treat Kitchen scraps as free at the apothecary, and max brew counts stay herb-gated', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = { ...createNewSave(launch), currentLocationId: 'LOC-0026' }
    expect(ingredientOwned(launch, base, KITCHEN_SCRAPS_ITEM_ID)).toBe(0)
    const tonic = getRecipe(launch, 'RCP-0078')!
    const withHerbs = { ...base, inventory: [{ itemId: 'ITEM-0031', quantity: 7 }] }
    expect(maxCraftsFromMaterials(launch, withHerbs, tonic)).toBe(7)
    const empty = { ...base, inventory: [] }
    expect(maxCraftsFromMaterials(launch, empty, tonic)).toBe(0)
  })
})
