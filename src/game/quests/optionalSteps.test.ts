import { describe, expect, it } from 'vitest'
import type { QuestStepRow } from '../data/types'
import {
  OPTIONAL_BAKE_RECIPE,
  OPTIONAL_BAKED_POTATO,
  OPTIONAL_KITCHEN,
  OPTIONAL_QUEST,
  OPTIONAL_STEP_COOK,
  OPTIONAL_STEP_DEFEAT,
  OPTIONAL_STEP_HOLD,
  OPTIONAL_STEP_VISIT,
  optionalStepsDatabase,
  setItemCount,
  withOptionalQuestActive,
} from '../../parity/scenarios/optionalSteps'
import { baseSave } from '../../parity/scenarios/saveFixtures'
import type { PlayerSave } from '../save/types'
import { questObjectiveProgress } from './objectives'
import { applyQuestProcessProgress, applyQuestVisitProgress } from './progress'
import { completeQuest, getQuest, getQuestProgress } from './quests'
import {
  applyQuestStepUnlocks,
  getCurrentStepId,
  getCurrentStepIndex,
  getQuestSteps,
  isOptionalStep,
  isStepLatched,
  questActiveStepObjectives,
  questAllStepsComplete,
} from './steps'

// A step whose Notes carry a bare `Optional` field is passed over while
// unfinished: it is never current, it does not stop later steps latching, and
// the quest completes once the required steps are done.

const db = optionalStepsDatabase()
const quest = getQuest(db, OPTIONAL_QUEST)!

function row(notes: string | null): QuestStepRow {
  return { Notes: notes } as unknown as QuestStepRow
}

function fresh(): PlayerSave {
  return withOptionalQuestActive(baseSave(db))
}

const index = (save: PlayerSave) => getCurrentStepIndex(db, save, quest)
const current = (save: PlayerSave) => getCurrentStepId(db, save, quest)
const latched = (save: PlayerSave, stepId: string) => isStepLatched(save, OPTIONAL_QUEST, stepId)

describe('isOptionalStep', () => {
  it('matches a whole trimmed Optional field', () => {
    expect(isOptionalStep(row('Hold: ITEM-0058 x10; Optional'))).toBe(true)
    expect(isOptionalStep(row('Optional'))).toBe(true)
    expect(isOptionalStep(row('Hold: ITEM-0058 x10;Optional'))).toBe(true)
    expect(isOptionalStep(row('  Optional  ; Visit: LOC-0023'))).toBe(true)
  })

  it('is not fooled by prefixes, values or case', () => {
    expect(isOptionalStep(row('Talk: NPC-0012; OptionalTalk: NPC-0007'))).toBe(false)
    expect(isOptionalStep(row('Optional: yes'))).toBe(false)
    expect(isOptionalStep(row('Optional Talk'))).toBe(false)
    expect(isOptionalStep(row('optional'))).toBe(false)
    expect(isOptionalStep(row('Hold: ITEM-0058 x10'))).toBe(false)
    expect(isOptionalStep(row(''))).toBe(false)
    expect(isOptionalStep(row(null))).toBe(false)
    expect(isOptionalStep(null)).toBe(false)
    expect(isOptionalStep(undefined)).toBe(false)
  })

  it('reads the fixture quest as required, optional, required, optional', () => {
    expect(getQuestSteps(db, OPTIONAL_QUEST).map((step) => isOptionalStep(step))).toEqual([
      false,
      true,
      false,
      true,
    ])
  })

  it('marks no shipped step optional', () => {
    const shipped = db.QuestSteps.filter((step) => step['Quest ID'] !== OPTIONAL_QUEST)
    expect(shipped.length).toBeGreaterThan(0)
    expect(shipped.some((step) => isOptionalStep(step))).toBe(false)
  })
})

describe('optional quest steps', () => {
  it('starts on the first required step', () => {
    const save = fresh()
    expect(index(save)).toBe(0)
    expect(current(save)).toBe(OPTIONAL_STEP_VISIT)
    expect(questAllStepsComplete(db, save, quest)).toBe(false)
  })

  it('does not latch a finished optional step ahead of an unfinished required one', () => {
    const save = applyQuestStepUnlocks(db, setItemCount(fresh(), OPTIONAL_BAKED_POTATO, 10))
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(false)
    expect(getQuestProgress(save, OPTIONAL_QUEST).counters).toEqual({})
    expect(current(save)).toBe(OPTIONAL_STEP_VISIT)
  })

  it('passes over the unfinished optional step once the step before it is done', () => {
    const save = applyQuestVisitProgress(db, fresh(), OPTIONAL_KITCHEN)
    expect(latched(save, OPTIONAL_STEP_VISIT)).toBe(true)
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(false)
    expect(index(save)).toBe(2)
    expect(current(save)).toBe(OPTIONAL_STEP_COOK)
    expect(questActiveStepObjectives(db, save, quest)?.processTargets).toEqual([
      { targetId: OPTIONAL_BAKE_RECIPE, quantity: 1 },
    ])
  })

  it('latches a finished optional step and keeps the latch after the bag changes', () => {
    let save = applyQuestVisitProgress(db, fresh(), OPTIONAL_KITCHEN)
    save = applyQuestStepUnlocks(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 10))
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(true)
    expect(current(save)).toBe(OPTIONAL_STEP_COOK)

    save = applyQuestStepUnlocks(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 0))
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(true)
    expect(current(save)).toBe(OPTIONAL_STEP_COOK)
  })

  it('completes on the required steps with both optional steps untouched', () => {
    let save = fresh()
    expect(completeQuest(db, save, OPTIONAL_QUEST, { ignoreLocation: true }).ok).toBe(false)

    save = applyQuestVisitProgress(db, save, OPTIONAL_KITCHEN)
    save = applyQuestProcessProgress(db, save, OPTIONAL_BAKE_RECIPE)
    expect(latched(save, OPTIONAL_STEP_COOK)).toBe(true)
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(false)
    expect(latched(save, OPTIONAL_STEP_DEFEAT)).toBe(false)
    expect(index(save)).toBe(getQuestSteps(db, OPTIONAL_QUEST).length)
    expect(current(save)).toBeNull()
    expect(questAllStepsComplete(db, save, quest)).toBe(true)
    expect(questObjectiveProgress(db, save, quest).ready).toBe(true)

    const turnedIn = completeQuest(db, save, OPTIONAL_QUEST, { ignoreLocation: true })
    expect(turnedIn.ok).toBe(true)
    if (!turnedIn.ok) return
    expect(getQuestProgress(turnedIn.save, OPTIONAL_QUEST).status).toBe('completed')
  })

  it('still needs every required step', () => {
    const save = applyQuestStepUnlocks(
      db,
      applyQuestVisitProgress(db, setItemCount(fresh(), OPTIONAL_BAKED_POTATO, 10), OPTIONAL_KITCHEN),
    )
    expect(latched(save, OPTIONAL_STEP_VISIT)).toBe(true)
    expect(latched(save, OPTIONAL_STEP_HOLD)).toBe(true)
    expect(current(save)).toBe(OPTIONAL_STEP_COOK)
    expect(questAllStepsComplete(db, save, quest)).toBe(false)
    expect(completeQuest(db, save, OPTIONAL_QUEST, { ignoreLocation: true }).ok).toBe(false)
  })
})
