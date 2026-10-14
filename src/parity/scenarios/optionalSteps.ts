/**
 * Optional quest steps parity.
 *
 * Test-only content: QST-9301 is appended to the real database (no live quest
 * changes). Its second and last steps carry a bare `Optional` Notes field, so
 * the walkthroughs show an unfinished optional step being passed over by the
 * current-step search and by latching, and the quest completing on its
 * required steps alone. Mirrored op for op by
 * `packages/ik_rules/test/quests_parity_test.dart`.
 */

import { addItemToInventory } from '../../game/activity/rewards'
import type { GameDatabase, QuestStepRow } from '../../game/data/types'
import { applyQuestProcessProgress, applyQuestVisitProgress } from '../../game/quests/progress'
import { completeQuest, getQuest, getQuestProgress } from '../../game/quests/quests'
import {
  applyQuestStepUnlocks,
  getCurrentStepId,
  getCurrentStepIndex,
  isOptionalStep,
  questAllStepsComplete,
} from '../../game/quests/steps'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { patchedDatabase } from './dialogue'
import { asJson, baseSave } from './saveFixtures'

type Row = Record<string, JsonValue>

export const OPTIONAL_QUEST = 'QST-9301'
export const OPTIONAL_STEP_VISIT = 'QSTP-9301'
export const OPTIONAL_STEP_HOLD = 'QSTP-9302'
export const OPTIONAL_STEP_COOK = 'QSTP-9303'
export const OPTIONAL_STEP_DEFEAT = 'QSTP-9304'

export const OPTIONAL_KITCHEN = 'LOC-0023'
export const OPTIONAL_BAKED_POTATO = 'ITEM-0058'
export const OPTIONAL_BAKE_RECIPE = 'RCP-0001'

function step(id: string, order: number, label: string, notes: string): Row {
  return {
    'Step ID': id,
    'Quest ID': OPTIONAL_QUEST,
    'Step Order': order,
    'Journal Label': label,
    Notes: notes,
    'Step Type': null,
    'Step Items': null,
    'Step NPC': null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
  }
}

/**
 * Visit the kitchen (required), hold ten baked potatoes (optional), bake one
 * (required), defeat a goblin (optional, trailing).
 */
export const OPTIONAL_STEPS_PATCH: Record<string, Row[]> = {
  Quests: [
    {
      'Quest ID': OPTIONAL_QUEST,
      'Internal Key': 'optional_steps_fixture',
      'Display Name': 'Optional Steps',
      'NPC ID': 'NPC-0014',
      Summary: null,
      Pitch: null,
      Status: 'Confirmed',
      'Release Phase': 'Launch',
      Notes: null,
      'Objective Type': null,
      'Objective Target ID': null,
      'Required Quantity': null,
      Repeatable: null,
      'Reward XP Skill ID': null,
      'Reward XP Amount': null,
      'Reward Item ID': null,
      'Reward Item Quantity': null,
      'Possible Rewards': null,
    },
  ],
  QuestSteps: [
    step(OPTIONAL_STEP_VISIT, 1, 'Visit the kitchen', `Visit: ${OPTIONAL_KITCHEN}`),
    step(OPTIONAL_STEP_HOLD, 2, 'Hold ten baked potatoes', `Hold: ${OPTIONAL_BAKED_POTATO} x10; Optional`),
    step(OPTIONAL_STEP_COOK, 3, 'Bake a potato', `Process: ${OPTIONAL_BAKE_RECIPE} x1`),
    step(OPTIONAL_STEP_DEFEAT, 4, 'Defeat a goblin', 'Defeat: ENM-0001 x1; Optional'),
  ],
}

/** Notes strings the `Optional` field parser is checked against. */
export const OPTIONAL_PARSER_NOTES: Array<string | null> = [
  'Hold: ITEM-0058 x10; Optional',
  'Optional',
  'Hold: ITEM-0058 x10;Optional',
  '  Optional  ; Visit: LOC-0023',
  'Optional; Hold: ITEM-0058 x10; Optional',
  'Talk: NPC-0012; OptionalTalk: NPC-0007',
  'Optional: yes',
  'Optional Talk',
  'optional',
  'OPTIONAL',
  'Hold: ITEM-0058 x10',
  '',
  null,
]

export function optionalStepsDatabase(): GameDatabase {
  return patchedDatabase(OPTIONAL_STEPS_PATCH)
}

/** Replaces every stack of an item with one stack of `quantity` (0 clears it). */
export function setItemCount(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

/** The fixture quest active with no counters. */
export function withOptionalQuestActive(save: PlayerSave): PlayerSave {
  return {
    ...save,
    quests: [
      ...save.quests.filter((row) => row.questId !== OPTIONAL_QUEST),
      { questId: OPTIONAL_QUEST, status: 'active', progress: 0, counters: {} },
    ],
  }
}

function stage(db: GameDatabase, label: string, save: PlayerSave): JsonValue {
  const quest = getQuest(db, OPTIONAL_QUEST)!
  return {
    label,
    stepIndex: getCurrentStepIndex(db, save, quest),
    currentStepId: getCurrentStepId(db, save, quest),
    allStepsComplete: questAllStepsComplete(db, save, quest),
    progress: getQuestProgress(save, OPTIONAL_QUEST) as unknown as JsonValue,
  }
}

function turnIn(db: GameDatabase, save: PlayerSave): JsonValue {
  const result = completeQuest(db, save, OPTIONAL_QUEST, { ignoreLocation: true })
  return result.ok
    ? { ok: true, progress: getQuestProgress(result.save, OPTIONAL_QUEST) as unknown as JsonValue }
    : { ok: false, reason: result.reason }
}

const input = (): JsonValue => ({
  source: 'content',
  patch: OPTIONAL_STEPS_PATCH as unknown as JsonValue,
  save: asJson(baseSave(optionalStepsDatabase())),
})

export const optionalStepScenarios: ParityScenario[] = [
  scenario(
    'quests/optional-steps',
    'parser',
    {
      source: 'content',
      patch: OPTIONAL_STEPS_PATCH as unknown as JsonValue,
      notes: OPTIONAL_PARSER_NOTES,
    },
    () => ({
      optional: OPTIONAL_PARSER_NOTES.map((notes) =>
        isOptionalStep({ Notes: notes } as unknown as QuestStepRow),
      ),
      steps: OPTIONAL_STEPS_PATCH.QuestSteps!.map((row) => ({
        stepId: row['Step ID'],
        optional: isOptionalStep(row as unknown as QuestStepRow),
      })),
    }),
  ),

  // Hold the potatoes before the visit (complete but not yet latchable), visit,
  // hold them again (latches), spend them (latch kept), bake one (quest done
  // with the trailing optional step untouched).
  scenario('quests/optional-steps', 'done-midway', input(), () => {
    const db = optionalStepsDatabase()
    const stages: JsonValue[] = []
    let save = withOptionalQuestActive(baseSave(db))
    stages.push(stage(db, 'accepted', save))
    save = applyQuestStepUnlocks(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 10))
    stages.push(stage(db, 'held-before-visit', save))
    save = applyQuestVisitProgress(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 0), OPTIONAL_KITCHEN)
    stages.push(stage(db, 'visited', save))
    save = applyQuestStepUnlocks(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 10))
    stages.push(stage(db, 'held', save))
    save = applyQuestStepUnlocks(db, setItemCount(save, OPTIONAL_BAKED_POTATO, 0))
    stages.push(stage(db, 'spent', save))
    save = applyQuestProcessProgress(db, save, OPTIONAL_BAKE_RECIPE)
    stages.push(stage(db, 'baked', save))
    return { stages, turnIn: turnIn(db, save) }
  }),

  // Never hold the potatoes: the optional steps are passed over and the quest
  // completes on the two required ones.
  scenario('quests/optional-steps', 'skipped', input(), () => {
    const db = optionalStepsDatabase()
    const stages: JsonValue[] = []
    let save = withOptionalQuestActive(baseSave(db))
    stages.push(stage(db, 'accepted', save))
    const turnInEarly = turnIn(db, save)
    save = applyQuestVisitProgress(db, save, OPTIONAL_KITCHEN)
    stages.push(stage(db, 'visited', save))
    save = applyQuestProcessProgress(db, save, OPTIONAL_BAKE_RECIPE)
    stages.push(stage(db, 'baked', save))
    return { stages, turnInEarly, turnIn: turnIn(db, save) }
  }),
]
