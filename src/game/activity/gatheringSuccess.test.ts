import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { completeGatheringAction } from './engine'
import {
  gatheringSuccessChancePercent,
  rollGatheringSuccess,
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
  it('scales from 40% at level 1 along the same +0.5% curve', () => {
    // Pass proficiency >= level so this isolates the base curve.
    expect(gatheringSuccessChancePercent(1, 1)).toBe(40)
    expect(gatheringSuccessChancePercent(2, 2)).toBe(40.5)
    expect(gatheringSuccessChancePercent(100, 100)).toBe(89.5)
    expect(gatheringSuccessChancePercent(200, 200)).toBe(100)
  })

  it('adds 1% per level above proficiency', () => {
    // Level 15 base = 40 + 0.5*14 = 47; proficiency 10 → +5 = 52
    expect(gatheringSuccessChancePercent(15, 10)).toBe(52)
    expect(gatheringSuccessChancePercent(10, 10)).toBe(44.5)
    expect(gatheringSuccessChancePercent(5, 10)).toBe(42)
  })

  it('grants nothing on a failed success roll', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0018')!
    const save = createNewSave(launch)
    const beforeXp = save.skills.find((row) => row.skillId === 'SKL-0002')?.xp ?? 0
    // Level 1 needs random() < 0.40; 0.41 fails.
    const completed = completeGatheringAction(launch, save, action, () => 0.41)
    expect(completed.result.xpGained).toBe(0)
    expect(completed.result.loot).toEqual([])
    expect(completed.save.skills.find((row) => row.skillId === 'SKL-0002')?.xp ?? 0).toBe(beforeXp)
  })

  it('rollGatheringSuccess matches the percent threshold', () => {
    expect(rollGatheringSuccess(1, () => 0.399)).toBe(true)
    expect(rollGatheringSuccess(1, () => 0.4)).toBe(false)
    // Level 15 / proficiency 10 → 52%
    expect(rollGatheringSuccess(15, () => 0.519, 10)).toBe(true)
    expect(rollGatheringSuccess(15, () => 0.52, 10)).toBe(false)
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
