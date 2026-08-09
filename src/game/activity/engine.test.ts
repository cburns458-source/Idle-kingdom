import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  beginActivitySave,
  completeGatheringAction,
  generateNextAction,
  validateActivityStart,
} from './engine'
import { gatheringDurationMs } from './gathering'
import { eligiblePoolEntries, pickWeightedAction } from './pools'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('primary activity engine', () => {
  it('starts meadow gathering without tools and awards XP/items', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0009' }

    const validation = validateActivityStart(launch, save, 'ACT-0012')
    expect(validation.ok).toBe(true)

    save = beginActivitySave(save, 'ACT-0012')
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0)
    expect(generated?.action['Action ID']).toBe('ACN-0105')

    const completed = completeGatheringAction(launch, generated!.save, generated!.action, () => 0)
    expect(completed.result.xpGained).toBe(5000)
    expect(completed.save.inventory.some((stack) => stack.itemId === 'ITEM-0030')).toBe(true)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0004')?.xp).toBe(5000)
  })

  it('rejects copper mining without a mining tool', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    const validation = validateActivityStart(launch, save, 'ACT-0005')
    expect(validation.ok).toBe(false)
    if (!validation.ok) {
      expect(validation.reason.toLowerCase()).toContain('mining')
    }
  })

  it('doubles gathering duration below proficiency', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const potato = launch.Actions.find((action) => action['Action ID'] === 'ACN-0035')!
    expect(potato['Proficiency Level']).toBe(10)
    expect(gatheringDurationMs(launch, save, potato)).toBe(240_000)
  })

  it('excludes Needs Data and Combat actions from Step 3 pools', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const woodland = eligiblePoolEntries(launch, 'POOL-0010')
    expect(woodland).toHaveLength(0)

    const pasture = eligiblePoolEntries(launch, 'POOL-0001')
    expect(pasture).toHaveLength(0)

    const copper = eligiblePoolEntries(launch, 'POOL-0005')
    expect(copper.every((pair) => pair.action.Category === 'Gathering')).toBe(true)
    expect(pickWeightedAction(copper, () => 0)?.['Action ID']).toBeTruthy()
  })

  it('weighted selection respects ordering', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const meadow = eligiblePoolEntries(launch, 'POOL-0012')
    // Only Wild Roots remains after Needs Data exclusion.
    expect(meadow).toHaveLength(1)
    expect(pickWeightedAction(meadow, () => 0.99)?.['Action ID']).toBe('ACN-0105')
  })
})
