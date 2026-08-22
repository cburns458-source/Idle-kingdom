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
import { gatheringDurationMs, gatheringXpReward } from './gathering'
import { eligiblePoolEntries, pickWeightedAction } from './pools'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
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
    expect(completed.result.xpGained).toBe(100)
    expect(completed.save.inventory.some((stack) => stack.itemId === 'ITEM-0030')).toBe(true)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0004')?.xp).toBe(100)
  })

  it('grants bonus Combat XP for a bow-based Hunting Action when a bow is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const huntButterfly = launch.Actions.find((action) => action['Action ID'] === 'ACN-0015')!

    // No bow equipped: no Combat XP bonus.
    const withoutBow = completeGatheringAction(launch, save, huntButterfly, () => 0)
    expect(withoutBow.result.xpGained).toBe(250)
    expect(withoutBow.result.bonusXp).toEqual([])
    expect(
      withoutBow.save.skills.find((skill) => skill.skillId === 'SKL-0001')?.xp ?? 0,
    ).toBe(0)

    // Equip a Regular Bow (bow_combat_xp capability) directly for the test —
    // equipping it through the normal flow requires Hunting 10.
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: { ...save.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0135', quantity: 1 } },
      },
    }
    const withBow = completeGatheringAction(launch, save, huntButterfly, () => 0)
    expect(withBow.result.xpGained).toBe(250)
    expect(withBow.result.bonusXp).toEqual([{ skillId: 'SKL-0001', xp: 25 }])
    expect(withBow.save.skills.find((skill) => skill.skillId === 'SKL-0001')?.xp).toBe(25)
    const combatReward = withBow.result.xpRewards.find((reward) => reward.skillId === 'SKL-0001')
    expect(combatReward?.xp).toBe(25)
  })

  it('grants no bow Combat XP bonus for non-Hunting gathering, even with a bow equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0009',
      equipment: {
        ...save.equipment,
        slots: { ...save.equipment.slots, 'SLOT-0001': { itemId: 'ITEM-0135', quantity: 1 } },
      },
    }
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0)
    expect(generated?.action['Relevant Skill ID']).not.toBe('SKL-0005')
    const completed = completeGatheringAction(launch, generated!.save, generated!.action, () => 0)
    expect(completed.result.bonusXp).toEqual([])
  })

  it('grants 100 Arcana XP when delving for essence', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Meet Mining proficiency 5 so Delve awards full XP.
    save = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0002' ? { ...skill, level: 5, xp: 3713 } : skill,
      ),
    }
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0028')
    expect(action).toBeTruthy()

    const completed = completeGatheringAction(launch, save, action!, () => 0)
    expect(completed.result.xpGained).toBe(350)
    expect(completed.result.bonusXp).toEqual([{ skillId: 'SKL-0013', xp: 100 }])
    expect(completed.result.xpRewards.map((reward) => reward.skillId)).toEqual([
      'SKL-0002',
      'SKL-0013',
    ])
    expect(completed.result.xpRewards[1]).toMatchObject({
      skillId: 'SKL-0013',
      skillName: 'Arcana',
      xp: 100,
      leveledUp: false,
    })
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0002')?.xp).toBe(3713 + 350)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0013')?.xp).toBe(100)
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

  it('doubles gathering duration and halves XP below proficiency', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const potato = launch.Actions.find((action) => action['Action ID'] === 'ACN-0035')!
    expect(potato['Proficiency Level']).toBe(10)
    expect(gatheringDurationMs(launch, save, potato)).toBe(120_000)
    expect(gatheringXpReward(launch, save, potato)).toBe(325)

    const completed = completeGatheringAction(launch, save, potato, () => 0)
    expect(completed.result.xpGained).toBe(325)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0004')?.xp).toBe(325)
  })

  it('halves Delve for Essence XP and Arcana bonus below mining proficiency', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0028')!
    expect(action['Proficiency Level']).toBe(5)

    const completed = completeGatheringAction(launch, save, action, () => 0)
    expect(completed.result.xpGained).toBe(175)
    expect(completed.result.bonusXp).toEqual([{ skillId: 'SKL-0013', xp: 50 }])
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0002')?.xp).toBe(175)
    expect(completed.save.skills.find((skill) => skill.skillId === 'SKL-0013')?.xp).toBe(50)
  })

  it('excludes Needs Data actions and includes Combat when complete', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const woodland = eligiblePoolEntries(launch, 'POOL-0010')
    expect(woodland.map((pair) => pair.action['Action ID']).sort()).toEqual([
      'ACN-0107',
      'ACN-0108',
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

  it('hunts rabbit and duck in the meadows, elk and pheasant in the kingswoods', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const meadow = eligiblePoolEntries(launch, 'POOL-0011').map((pair) => pair.action['Action ID'])
    const woods = eligiblePoolEntries(launch, 'POOL-0009').map((pair) => pair.action['Action ID'])
    expect(meadow.sort()).toEqual(['ACN-0013', 'ACN-0016'])
    expect(woods.sort()).toEqual(['ACN-0008', 'ACN-0014', 'ACN-0017'])
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
