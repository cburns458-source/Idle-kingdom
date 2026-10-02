import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { completeGatheringAction } from './engine'
import {
  gatheringSuccessChancePercent,
  productionSuccessChancePercent,
  rollGatheringSuccess,
  rollProductionSuccess,
} from './gathering'
import {
  ACTION_TIME_REDUCTION_CAP_PERCENT,
  equippedActionTimeReductionBySkill,
  equipStackToSlot,
  WEAPON_TOOL_SLOT_ID,
} from '../equipment/loadout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('gathering success chance', () => {
  it('uses base 80% at proficiency with −0.75% below and +1% above', () => {
    expect(gatheringSuccessChancePercent(1, 1)).toBe(80)
    expect(gatheringSuccessChancePercent(10, 10)).toBe(80)
    expect(gatheringSuccessChancePercent(100, 100)).toBe(80)
    // 5 levels below: 80 − 5*0.75 = 76.25
    expect(gatheringSuccessChancePercent(5, 10)).toBe(76.25)
    // 5 levels above: 80 + 5 = 85
    expect(gatheringSuccessChancePercent(15, 10)).toBe(85)
    expect(gatheringSuccessChancePercent(200, 100)).toBe(100)
    expect(gatheringSuccessChancePercent(1, 200)).toBe(0)
  })

  it('grants nothing on a failed success roll', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0018')!
    const save = createNewSave(launch)
    const beforeXp = save.skills.find((row) => row.skillId === 'SKL-0002')?.xp ?? 0
    // Level 1 / proficiency 1 → 80%; 0.81 fails.
    const completed = completeGatheringAction(launch, save, action, () => 0.81)
    expect(completed.result.xpGained).toBe(0)
    expect(completed.result.loot).toEqual([])
    expect(completed.save.skills.find((row) => row.skillId === 'SKL-0002')?.xp ?? 0).toBe(beforeXp)
  })

  it('rollGatheringSuccess matches the percent threshold', () => {
    expect(rollGatheringSuccess(1, () => 0.799)).toBe(true)
    expect(rollGatheringSuccess(1, () => 0.8)).toBe(false)
    // Level 15 / proficiency 10 → 85%
    expect(rollGatheringSuccess(15, () => 0.849, 10)).toBe(true)
    expect(rollGatheringSuccess(15, () => 0.85, 10)).toBe(false)
  })
})

describe('production success chance', () => {
  it('shares the gathering success curve', () => {
    expect(productionSuccessChancePercent(1, 1)).toBe(80)
    expect(productionSuccessChancePercent(15, 10)).toBe(85)
    expect(productionSuccessChancePercent(5, 10)).toBe(76.25)
  })

  it('rollProductionSuccess matches the percent threshold', () => {
    expect(rollProductionSuccess(1, () => 0.799)).toBe(true)
    expect(rollProductionSuccess(1, () => 0.8)).toBe(false)
  })
})

describe('action time reduction cap', () => {
  it('caps per-skill ATR at 50% and ignores the rest', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Ancient Alloy Pickaxe is 20% Mining ATR; stack a second copy in another slot in tests.
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0273', 1)
    save = equipStackToSlot(save, 'SLOT-0009', 'ITEM-0273', 1)
    save = equipStackToSlot(save, 'SLOT-0007', 'ITEM-0273', 1)
    const bySkill = equippedActionTimeReductionBySkill(launch, save)
    expect(bySkill['SKL-0002']).toBe(ACTION_TIME_REDUCTION_CAP_PERCENT)
    expect(bySkill['SKL-0002']).toBeLessThanOrEqual(50)
  })
})
