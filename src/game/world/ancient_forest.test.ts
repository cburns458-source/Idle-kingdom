import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { raiseSkillToMinimumLevel } from '../activity/xp'
import { activityVisibleForSave } from '../activity/requirements'
import { prepareDatabase } from '../data/loadDatabase'
import { recipeIngredients } from '../production/recipes'
import { talkWithQuestNpc } from '../npcs/conversation'
import { applyQuestActionProgress } from '../quests/progress'
import { acceptQuest } from '../quests/quests'
import { createNewSave } from '../save/saveStore'
import {
  FOREST_MAP_ID,
  FOREST_PATH_ID,
  MIRROR_LAKE_ID,
  OLD_ENT_GROVE_ID,
  SMALL_CLEARING_ID,
  STARLIGHT_GLADE_ID,
} from './constants'
import { applyTravelArrival } from './travel'

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
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0405')?.['Icon Asset Key']).toBe(
      'forest_offering',
    )
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0406')?.['Icon Asset Key']).toBe(
      'machete',
    )
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
    expect(activityVisibleForSave(launch, completed, 'ACT-0082')).toBe(false)
    expect(activityVisibleForSave(launch, completed, 'ACT-0049')).toBe(true)
    expect(activityVisibleForSave(launch, completed, 'ACT-0050')).toBe(true)
    expect(activityVisibleForSave(launch, completed, 'ACT-0016')).toBe(true)
    expect(activityVisibleForSave(launch, completed, 'ACT-0040')).toBe(true)
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

  it('uses one Chop vines action that needs Woodcutting 40 and a woodcutting tool', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const vine = launch.Actions.find((row) => row['Action ID'] === 'ACN-0179')!
    expect(vine['Display Name']).toBe('Chop vines')
    expect(vine['Relevant Skill ID']).toBe('SKL-0006')
    expect(vine['Proficiency Level']).toBe(40)
    const chop = launch.Activities.filter((row) => row['Contextual Name'] === 'Chop vines')
    expect(chop.map((row) => row['Activity ID']).sort()).toEqual([
      'ACT-0048',
      'ACT-0077',
      'ACT-0078',
      'ACT-0079',
      'ACT-0082',
    ])
    for (const activity of chop) {
      expect(
        launch.PoolEntries.filter((row) => row['Pool ID'] === activity['Pool ID']).map(
          (row) => row['Action ID'],
        ),
      ).toEqual(['ACN-0179'])
    }
    expect(
      launch.Requirements.find(
        (row) => row['Entity ID'] === 'ACN-0179' && row['Requirement Type'] === 'Tool Capability',
      )?.['Reference ID / Value'],
    ).toBe('woodcutting_tool')
    expect(
      launch.Requirements.find(
        (row) => row['Entity ID'] === 'ACN-0179' && row['Requirement Type'] === 'Skill Level',
      )?.['Required Value'],
    ).toBe(40)
  })

  it('hides landing vines until the quest starts, then keeps them until the player leaves', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const fresh = { ...createNewSave(launch), currentLocationId: FOREST_PATH_ID }
    expect(activityVisibleForSave(launch, fresh, 'ACT-0048')).toBe(false)
    expect(activityVisibleForSave(launch, fresh, 'ACT-0049')).toBe(false)
    expect(activityVisibleForSave(launch, fresh, 'ACT-0016')).toBe(false)

    let save = raiseSkillToMinimumLevel(fresh, launch, 'SKL-0006', 40).save
    save = raiseSkillToMinimumLevel(save, launch, 'SKL-0014', 35).save
    const accepted = acceptQuest(launch, save, 'QST-0010')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(activityVisibleForSave(launch, save, 'ACT-0048')).toBe(true)
    expect(activityVisibleForSave(launch, save, 'ACT-0049')).toBe(false)

    save = applyQuestActionProgress(launch, save, 'ACN-0179', 50)
    expect(activityVisibleForSave(launch, save, 'ACT-0048')).toBe(true)
    save = applyTravelArrival(launch, save, SMALL_CLEARING_ID)
    expect(activityVisibleForSave(launch, save, 'ACT-0048')).toBe(false)
    save = applyTravelArrival(launch, save, FOREST_PATH_ID)
    expect(activityVisibleForSave(launch, save, 'ACT-0048')).toBe(false)
  })

  it('keeps a grove vine activity until the player leaves after that step', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = raiseSkillToMinimumLevel(
      { ...createNewSave(launch), currentLocationId: FOREST_PATH_ID },
      launch,
      'SKL-0006',
      40,
    ).save
    save = raiseSkillToMinimumLevel(save, launch, 'SKL-0014', 35).save
    const accepted = acceptQuest(launch, save, 'QST-0010')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    save = applyQuestActionProgress(launch, save, 'ACN-0179', 50)
    const talked = talkWithQuestNpc(launch, save, 'NPC-0017')
    expect(talked.ok).toBe(true)
    if (!talked.ok) return
    save = applyTravelArrival(launch, talked.save, SMALL_CLEARING_ID)
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(true)
    save = applyQuestActionProgress(launch, save, 'ACN-0179', 10)
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(true)
    save = applyTravelArrival(launch, save, FOREST_PATH_ID)
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(false)
    save = applyTravelArrival(launch, save, SMALL_CLEARING_ID)
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(false)
  })
})
