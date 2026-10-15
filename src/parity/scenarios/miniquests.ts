/**
 * Miniquest journal parity.
 *
 * Miniquest is only a label: steps come from the shared `questJournalSteps` /
 * `questStepJournal` path (including skipped optional steps), and completing
 * one must not move quest-log %. Mirrored by
 * `packages/ik_rules/test/quests_parity_test.dart`.
 */

import {
  applyQuestAutoStartOnSeed,
  applyQuestProcessProgress,
  applyQuestVisitProgress,
} from '../../game/quests/progress'
import { completeQuest, getQuest } from '../../game/quests/quests'
import { isOptionalStep, questStepJournal } from '../../game/quests/steps'
import {
  logCompletion,
  miniQuestJournal,
  questJournalSteps,
  questLog,
} from '../../game/log/log'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { patchedDatabase } from './dialogue'
import { asJson, baseSave } from './saveFixtures'
import { contentDatabase } from './contentDatabase'

const OPTIONAL_MINIQUEST = 'QST-9302'
const OPTIONAL_HOLD = 'QSTP-9312'
const KITCHEN = 'LOC-0023'
const BAKE_RECIPE = 'RCP-0001'

type Row = Record<string, JsonValue>

function step(id: string, order: number, label: string, notes: string): Row {
  return {
    'Step ID': id,
    'Quest ID': OPTIONAL_MINIQUEST,
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

export const MINIQUEST_OPTIONAL_PATCH: Record<string, Row[]> = {
  Quests: [
    {
      'Quest ID': OPTIONAL_MINIQUEST,
      'Internal Key': 'miniquest_optional_journal',
      'Display Name': 'Miniquest Optional Journal',
      'NPC ID': 'NPC-0014',
      Summary: 'A test miniquest with a skipped optional step.',
      Pitch: null,
      Status: 'Confirmed',
      'Release Phase': 'Launch',
      Notes: 'Miniquest; HideFromQuestLog',
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
    step('QSTP-9311', 1, 'Visit the kitchen', `Visit: ${KITCHEN}`),
    step(OPTIONAL_HOLD, 2, 'Hold ten baked potatoes', 'Hold: ITEM-0058 x10; Optional'),
    step('QSTP-9313', 3, 'Bake a potato', `Process: ${BAKE_RECIPE} x1`),
  ],
}

function questsSection(db: ReturnType<typeof contentDatabase>, save: PlayerSave): JsonValue {
  const section = logCompletion(db, save).sections.find((row) => row.section === 'quests')
  return {
    done: section?.done ?? 0,
    total: section?.total ?? 0,
    percent: section?.percent ?? 0,
  }
}

function journalSnapshot(db: ReturnType<typeof contentDatabase>, save: PlayerSave, questId: string): JsonValue {
  const quest = getQuest(db, questId)!
  const row = miniQuestJournal(db, save, 0).find((entry) => entry.questId === questId)
  return {
    inQuestLog: questLog(db, save).some((entry) => entry.questId === questId),
    journal: row as unknown as JsonValue,
    sharedSteps: questJournalSteps(db, save, quest) as unknown as JsonValue,
    stepJournal: questStepJournal(db, save, quest) as unknown as JsonValue,
  }
}

export const miniquestJournalScenarios: ParityScenario[] = [
  scenario(
    'quests/miniquest-journal',
    'green-thumb',
    { source: 'content', save: asJson(baseSave(contentDatabase())) },
    () => {
      const db = contentDatabase()
      let save: PlayerSave = {
        ...baseSave(db),
        currentLocationId: 'LOC-0001',
        inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
        quests: [{ questId: 'QST-0006', status: 'completed', progress: 1 }],
      }
      save = applyQuestAutoStartOnSeed(db, save)
      const active = journalSnapshot(db, save, 'QST-0011')
      const before = questsSection(db, save)
      const miniDone: PlayerSave = {
        ...save,
        quests: save.quests.map((row) =>
          row.questId === 'QST-0011' ? { ...row, status: 'completed' as const } : row,
        ),
      }
      const afterMini = questsSection(db, miniDone)
      const feastDone: PlayerSave = {
        ...miniDone,
        quests: [
          ...miniDone.quests.filter((row) => row.questId !== 'QST-0001'),
          { questId: 'QST-0001', status: 'completed', progress: 10 },
        ],
      }
      return {
        active,
        completed: journalSnapshot(db, miniDone, 'QST-0011'),
        completionBefore: before,
        completionAfterMiniquest: afterMini,
        completionAfterFeast: questsSection(db, feastDone),
      }
    },
  ),

  scenario(
    'quests/miniquest-journal',
    'optional-skip',
    {
      source: 'content',
      patch: MINIQUEST_OPTIONAL_PATCH as unknown as JsonValue,
      save: asJson(baseSave(patchedDatabase(MINIQUEST_OPTIONAL_PATCH))),
    },
    () => {
      const db = patchedDatabase(MINIQUEST_OPTIONAL_PATCH)
      let save: PlayerSave = {
        ...baseSave(db),
        quests: [{ questId: OPTIONAL_MINIQUEST, status: 'active', progress: 0, counters: {} }],
      }
      save = applyQuestVisitProgress(db, save, KITCHEN)
      save = applyQuestProcessProgress(db, save, BAKE_RECIPE)
      const holdStep = db.QuestSteps.find((row) => row['Step ID'] === OPTIONAL_HOLD)!
      const before = questsSection(db, save)
      const finished = completeQuest(db, save, OPTIONAL_MINIQUEST, { ignoreLocation: true })
      const completed: JsonValue = finished.ok
        ? {
            ok: true,
            snapshot: journalSnapshot(db, finished.save, OPTIONAL_MINIQUEST),
            completion: questsSection(db, finished.save),
          }
        : { ok: false, reason: finished.reason }
      return {
        holdOptional: isOptionalStep(holdStep),
        skipped: journalSnapshot(db, save, OPTIONAL_MINIQUEST),
        completionBefore: before,
        completed,
      }
    },
  ),
]
