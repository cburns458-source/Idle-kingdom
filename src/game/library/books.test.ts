import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/prepare'
import rawDatabase from '../../../content/data/game-database.json'
import { createNewSave } from '../save/saveStore'
import { getQuest } from '../quests/quests'
import { parseStructuredObjectives } from '../quests/objectives'
import { validateActivityStart } from '../activity/engine'
import {
  bookUnlockNotice,
  grantBook,
  isBookUnlocked,
  libraryBookRows,
  LIBRARY_HINT,
} from './books'
import {
  MAIN_HALL_COOK_ACTIVITY_ID,
  MAIN_HALL_KITCHEN_LOCKED_MESSAGE,
  mainHallKitchenLocked,
} from '../world/mainHallKitchen'
import { COMBAT_DISPLAY_SKILL_ID, skillIdsForActivity } from '../world/locationSkills'

describe('library books', () => {
  it('grantBook unlocks into the Library and is idempotent', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(save.unlockedBookIds).toEqual([])

    const first = grantBook(save, 'BOOK-0001')
    expect(first.granted).toBe(true)
    expect(first.isFirstEver).toBe(true)
    expect(first.save.unlockedBookIds).toEqual(['BOOK-0001'])
    expect(isBookUnlocked(first.save, 'BOOK-0001')).toBe(true)

    const again = grantBook(first.save, 'BOOK-0001')
    expect(again.granted).toBe(false)

    const second = grantBook(first.save, 'BOOK-0002')
    expect(second.granted).toBe(true)
    expect(second.isFirstEver).toBe(false)
    expect(libraryBookRows(launch, second.save).map((row) => row['Book ID'])).toEqual([
      'BOOK-0002',
      'BOOK-0001',
    ])
  })

  it('bookUnlockNotice names the book and hints on the first ever unlock', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const first = bookUnlockNotice(launch, 'BOOK-0001', true)
    expect(first?.name).toBe("Newcomer's Guide")
    expect(first?.hint).toBe(LIBRARY_HINT)

    const later = bookUnlockNotice(launch, 'BOOK-0002', false)
    expect(later?.name).toBe("Botanist's Guide")
    expect(later?.hint).toBeNull()
  })

  it('quest notes wire RewardBook ids for Getting Started and Green Thumb', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(parseStructuredObjectives(getQuest(launch, 'QST-0006')!).rewardBookIds).toEqual([
      'BOOK-0001',
    ])
    const green = getQuest(launch, 'QST-0011')!
    expect(parseStructuredObjectives(green).rewardBookIds).toEqual(['BOOK-0002'])
    expect(green['Display Name']).toBe('Green Thumb')
  })

  it('Main Hall kitchen stays locked until Grand Feast is started', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(mainHallKitchenLocked(launch, save, MAIN_HALL_COOK_ACTIVITY_ID)).toBe(true)
    const start = validateActivityStart(launch, save, MAIN_HALL_COOK_ACTIVITY_ID)
    expect(start.ok).toBe(false)
    if (start.ok) return
    expect(start.reason).toBe(MAIN_HALL_KITCHEN_LOCKED_MESSAGE)
  })

  it('Fight the goblins activity card reports Might', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(skillIdsForActivity(launch, save, 'ACT-0002')).toContain(COMBAT_DISPLAY_SKILL_ID)
  })
})
