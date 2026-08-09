import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  beginActivitySave,
  clearActivitySave,
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
    expect(completed.result.xpGained).toBe(1000)
    expect(completed.save.inventory.some((stack) => stack.itemId === 'ITEM-0030')).toBe(true)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0004')?.xp).toBe(1000)
  })

  it('grants 1000 Arcana XP when delving for essence', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0028')
    expect(action).toBeTruthy()

    const completed = completeGatheringAction(launch, save, action!, () => 0)
    expect(completed.result.xpGained).toBe(7000)
    expect(completed.result.bonusXp).toEqual([{ skillId: 'SKL-0013', xp: 1000 }])
    expect(completed.result.xpRewards.map((reward) => reward.skillId)).toEqual([
      'SKL-0002',
      'SKL-0013',
    ])
    expect(completed.result.xpRewards[1]).toMatchObject({
      skillId: 'SKL-0013',
      skillName: 'Arcana',
      xp: 1000,
      level: 2,
      leveledUp: true,
    })
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0002')?.xp).toBe(7000)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0013')?.xp).toBe(1000)
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

  it('excludes Needs Data actions and includes Combat when complete', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const woodland = eligiblePoolEntries(launch, 'POOL-0010')
    expect(woodland.map((pair) => pair.action['Action ID']).sort()).toEqual([
      'ACN-0046',
      'ACN-0109',
    ])

    const pasture = eligiblePoolEntries(launch, 'POOL-0001')
    expect(pasture.every((pair) => pair.action.Category === 'Combat')).toBe(true)
    expect(pasture.length).toBeGreaterThan(0)

    const copper = eligiblePoolEntries(launch, 'POOL-0005')
    expect(copper.every((pair) => pair.action.Category === 'Gathering')).toBe(true)
    expect(pickWeightedAction(copper, () => 0)?.['Action ID']).toBeTruthy()

    const ancientForest = eligiblePoolEntries(launch, 'POOL-0016')
    expect(ancientForest.map((pair) => pair.action['Action ID']).sort()).toEqual([
      'ACN-0010',
      'ACN-0011',
      'ACN-0012',
      'ACN-0051',
    ])
  })

  it('weighted selection respects ordering', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const meadow = eligiblePoolEntries(launch, 'POOL-0012')
    expect(meadow.map((pair) => pair.action['Action ID']).sort()).toEqual([
      'ACN-0105',
      'ACN-0106',
    ])
    // Weights are equal (50/50); high roll selects the second entry (Fernleaf).
    expect(pickWeightedAction(meadow, () => 0.99)?.['Action ID']).toBe('ACN-0106')
  })

  it('refuses to stop or replace activities during death pause', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = createNewSave(launch)
    save = {
      ...beginActivitySave(save, 'ACT-0001', new Date(now).toISOString()),
      deathPauseUntil: new Date(now + 30_000).toISOString(),
    }

    expect(clearActivitySave(save, now + 1000)).toEqual(save)
    expect(beginActivitySave(save, 'ACT-0002', new Date(now + 1000).toISOString())).toEqual(save)
  })
})
