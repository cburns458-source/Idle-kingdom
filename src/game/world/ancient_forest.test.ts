import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { activityVisibleForSave } from '../activity/requirements'
import { prepareDatabase } from '../data/loadDatabase'
import { recipeIngredients } from '../production/recipes'
import { createNewSave } from '../save/saveStore'
import {
  FOREST_MAP_ID,
  FOREST_PATH_ID,
  MIRROR_LAKE_ID,
  OLD_ENT_GROVE_ID,
  SMALL_CLEARING_ID,
  STARLIGHT_GLADE_ID,
} from './constants'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('Ancient Forest Through the Thicket', () => {
  it('adds Small Clearing and Mirror Lake on the forest map', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const clearing = launch.Locations.find((row) => row['Location ID'] === SMALL_CLEARING_ID)!
    const lake = launch.Locations.find((row) => row['Location ID'] === MIRROR_LAKE_ID)!
    expect(clearing['Display Name']).toBe('Small Clearing')
    expect(clearing['Map ID']).toBe(FOREST_MAP_ID)
    expect(clearing.Notes).toMatch(/requires_unlock/i)
    expect(lake['Display Name']).toBe('Mirror Lake')
    expect(lake['Map ID']).toBe(FOREST_MAP_ID)
    expect(launch.Activities.filter((row) => row['Location ID'] === SMALL_CLEARING_ID).map((row) => row['Contextual Name'])).toEqual(
      ['Chop vines'],
    )
    expect(launch.Activities.filter((row) => row['Location ID'] === MIRROR_LAKE_ID).map((row) => row['Contextual Name'])).toEqual(
      ['Chop vines'],
    )
    expect(clearing['Background Asset Key']).toBe('locations/loc_forest_path.webp')
    expect(lake['Background Asset Key']).toBe('locations/loc_starlight_glade.webp')
  })

  it('crafts four-ingredient forest offerings on the Forest Path stone', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const recipe = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0071')!
    expect(recipe['Facility ID']).toBe('FAC-0021')
    expect(recipe['Output Item ID']).toBe('ITEM-0405')
    expect(recipeIngredients(recipe)).toEqual([
      { itemId: 'ITEM-0328', quantity: 1 },
      { itemId: 'ITEM-0377', quantity: 3 },
      { itemId: 'ITEM-0032', quantity: 5 },
      { itemId: 'ITEM-0011', quantity: 10 },
    ])
    const craft = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0080')!
    expect(craft['Location ID']).toBe(FOREST_PATH_ID)
    expect(activityVisibleForSave(launch, createNewSave(launch), 'ACT-0080')).toBe(false)
  })

  it('keeps Forest Path vines as woodcutting training after the quest', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const completed = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0010', status: 'completed' as const, progress: 0 }],
    }
    expect(activityVisibleForSave(launch, completed, 'ACT-0048')).toBe(true)
    expect(activityVisibleForSave(launch, completed, 'ACT-0077')).toBe(false)
    expect(activityVisibleForSave(launch, completed, 'ACT-0078')).toBe(false)
    expect(activityVisibleForSave(launch, completed, 'ACT-0079')).toBe(false)
    expect(activityVisibleForSave(launch, completed, 'ACT-0080')).toBe(false)
    expect(
      launch.Activities.filter((row) => row['Location ID'] === STARLIGHT_GLADE_ID).some(
        (row) => row['Activity ID'] === 'ACT-0049',
      ),
    ).toBe(true)
    expect(
      launch.Activities.filter((row) => row['Location ID'] === OLD_ENT_GROVE_ID).some(
        (row) => row['Activity ID'] === 'ACT-0040',
      ),
    ).toBe(true)
  })
})
