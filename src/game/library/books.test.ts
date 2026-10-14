import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { getQuest } from '../quests/quests'
import { parseStructuredObjectives } from '../quests/objectives'
import { validateActivityStart } from '../activity/engine'
import { resolveActionRewards } from '../activity/rewards'
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

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

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

  it('every book reads in the house voice: Launch, Confirmed, short, no exclamations', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.Books.map((row) => row['Book ID'])).toEqual(['BOOK-0001', 'BOOK-0002', 'BOOK-0003'])
    for (const book of launch.Books) {
      expect(book.Status).toBe('Confirmed')
      expect(book.Body).not.toContain('!')
      expect(book.Body.length).toBeLessThan(1200)
    }
  })

  it('a Book reward entry unlocks the Library once, then grants nothing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0192')!
    expect(action['Secondary Reward Table ID']).toBe('RWT-0197')
    expect(action['Secondary Drop Chance']).toBe(0.1)
    const entry = launch.RewardEntries.find((row) => row['Reward Table ID'] === 'RWT-0197')!
    expect(entry['Reward Type']).toBe('Book')
    expect(entry['Reward ID / Value']).toBe('BOOK-0003')

    // random() === 0 lands every drop roll and picks the first weighted entry.
    const alwaysHit = () => 0
    const first = resolveActionRewards(launch, createNewSave(launch), action, alwaysHit)
    expect(first.booksGranted).toEqual([{ bookId: 'BOOK-0003', isFirstEver: true }])
    expect(first.save.unlockedBookIds).toEqual(['BOOK-0003'])
    // The book never enters the bag; only the coal does.
    expect(first.loot.map((grant) => grant.itemId)).toEqual(['ITEM-0006'])

    const again = resolveActionRewards(launch, first.save, action, alwaysHit)
    expect(again.booksGranted).toEqual([])
    expect(again.save.unlockedBookIds).toEqual(['BOOK-0003'])
  })

  it('Main Hall kitchen stays locked until Grand Feast is started', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch), currentLocationId: 'LOC-0015' }
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
