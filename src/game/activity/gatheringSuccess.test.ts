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
  equippedSuccessChanceBonusBySkill,
  equipStackToSlot,
  WEAPON_TOOL_SLOT_ID,
} from '../equipment/loadout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('gathering success chance', () => {
  it('uses 80 − floor(proficiency/4) at equal level, with ± curve', () => {
    expect(gatheringSuccessChancePercent(1, 1)).toBe(80)
    expect(gatheringSuccessChancePercent(10, 10)).toBe(78)
    // lvl 40 action at proficiency: 80 - 10 = 70
    expect(gatheringSuccessChancePercent(40, 40)).toBe(70)
    // lvl 88 action at proficiency: 80 - 22 = 58
    expect(gatheringSuccessChancePercent(88, 88)).toBe(58)
    // 5 levels below on a prof-10 action: base 78 − 5*0.75 = 74.25
    expect(gatheringSuccessChancePercent(5, 10)).toBe(74.25)
    // 5 levels above: 78 + 5 = 83
    expect(gatheringSuccessChancePercent(15, 10)).toBe(83)
    expect(gatheringSuccessChancePercent(200, 100)).toBe(100)
  })

  it('adds flat success-chance gear bonus', () => {
    expect(gatheringSuccessChancePercent(40, 40, 20)).toBe(90)
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
  })
})

describe('production success chance', () => {
  it('uses base 70% with the ± proficiency curve', () => {
    expect(productionSuccessChancePercent(1, 1)).toBe(70)
    expect(productionSuccessChancePercent(15, 10)).toBe(75)
    expect(productionSuccessChancePercent(5, 10)).toBe(66.25)
  })

  it('rollProductionSuccess matches the percent threshold', () => {
    expect(rollProductionSuccess(1, () => 0.699)).toBe(true)
    expect(rollProductionSuccess(1, () => 0.7)).toBe(false)
  })
})

describe('success chance gear bonus', () => {
  it('stacks tool bonuses with no 50% cap', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0273', 1)
    save = equipStackToSlot(save, 'SLOT-0009', 'ITEM-0273', 1)
    save = equipStackToSlot(save, 'SLOT-0007', 'ITEM-0273', 1)
    const bySkill = equippedSuccessChanceBonusBySkill(launch, save)
    expect(bySkill['SKL-0002']).toBeGreaterThan(50)
  })
})
