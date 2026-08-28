import type { GameDatabase, QuestStepRow } from '../data/types'
import { inventoryCount } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import {
  objectiveProgressFromStructured,
  parseNotesObjectives,
  parseStructuredObjectives,
  type QuestProgressLine,
} from './objectives'
import { getQuestProgress, type QuestRow } from './quests'
import type { StructuredQuestObjectives } from './types'

export type QuestJournalStepState = 'done' | 'current'

export interface QuestJournalStep {
  key: string
  label: string
  state: QuestJournalStepState
}

export function asQuestStepRows(db: GameDatabase): QuestStepRow[] {
  return db.QuestSteps ?? []
}

export function getQuestSteps(db: GameDatabase, questId: string): QuestStepRow[] {
  return asQuestStepRows(db)
    .filter((row) => row['Quest ID'] === questId)
    .sort((left, right) => left['Step Order'] - right['Step Order'])
}

export function questUsesSteps(db: GameDatabase, questId: string): boolean {
  return getQuestSteps(db, questId).length > 0
}

/** Quest-level Notes plus each authored step. */
export function questObjectiveSources(
  db: GameDatabase,
  quest: QuestRow,
): StructuredQuestObjectives[] {
  return [
    parseStructuredObjectives(quest),
    ...getQuestSteps(db, quest['Quest ID']).map((step) =>
      parseNotesObjectives(step.Notes ?? ''),
    ),
  ]
}

/** First Talk step for an NPC may still use the save-wide `talk:npc` flag. */
function talkProgressForStep(
  db: GameDatabase,
  questId: string,
  counters: Record<string, number>,
  talkKey: string,
  stepId: string,
): number {
  const scoped = Number(counters[`${talkKey}:${stepId}`] ?? 0)
  if (scoped >= 1) return scoped
  const npcId = talkKey.slice('talk:'.length)
  const first = getQuestSteps(db, questId).find((step) =>
    parseNotesObjectives(step.Notes ?? '').talkNpcIds.includes(npcId),
  )
  if (first?.['Step ID'] !== stepId) return 0
  return Number(counters[talkKey] ?? 0)
}

function stepProgressLines(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  notes: string,
  stepId?: string,
): QuestProgressLine[] {
  const structured = parseNotesObjectives(notes)
  const counters = getQuestProgress(save, questId).counters ?? {}
  const lines = objectiveProgressFromStructured(db, save, structured, counters).progressLines
  if (!stepId) return lines
  return lines.map((line) => {
    if (!line.key.startsWith('talk:')) return line
    return {
      ...line,
      key: `${line.key}:${stepId}`,
      current: talkProgressForStep(db, questId, counters, line.key, stepId),
    }
  })
}

export function isStepComplete(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  notes: string,
  stepId?: string,
): boolean {
  const lines = stepProgressLines(db, save, questId, notes, stepId)
  if (lines.length === 0) return true
  return lines.every((line) => line.current >= line.required)
}

export function getCurrentStepIndex(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): number {
  const questId = quest['Quest ID']
  const steps = getQuestSteps(db, questId)
  for (let index = 0; index < steps.length; index += 1) {
    const step = steps[index]!
    if (!isStepComplete(db, save, questId, step.Notes ?? '', step['Step ID'])) return index
  }
  return steps.length
}

export function currentStepTalkKey(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): string {
  if (!questUsesSteps(db, quest['Quest ID'])) return `talk:${npcId}`
  const steps = getQuestSteps(db, quest['Quest ID'])
  const step = steps[getCurrentStepIndex(db, save, quest)]
  return step ? `talk:${npcId}:${step['Step ID']}` : `talk:${npcId}`
}

const CITADEL_QUEST_ID = 'QST-0004'
const CITADEL_GUIDE_NPC_ID = 'NPC-0013'

export function citadelGuideHeard(save: PlayerSave): boolean {
  return Number(getQuestProgress(save, CITADEL_QUEST_ID).counters?.[`talk:${CITADEL_GUIDE_NPC_ID}`] ?? 0) >= 1
}

export function questStepJournal(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): QuestJournalStep[] {
  const questId = quest['Quest ID']
  const steps = getQuestSteps(db, questId)
  if (steps.length === 0) return []

  const currentIndex = getCurrentStepIndex(db, save, quest)
  if (questId === CITADEL_QUEST_ID && citadelGuideHeard(save) && currentIndex >= 1) {
    const heard = steps[0]!
    const remaining = steps.slice(1).flatMap((step) =>
      stepProgressLines(db, save, questId, step.Notes ?? '').map((line) => ({
        key: line.key,
        label: line.label,
        state: (line.current >= line.required ? 'done' : 'current') as QuestJournalStepState,
      })),
    )
    return [
      { key: heard['Step ID'], label: heard['Journal Label'], state: 'done' },
      ...remaining,
    ]
  }

  if (currentIndex >= steps.length) {
    return steps.map((step) => ({
      key: step['Step ID'],
      label: step['Journal Label'],
      state: 'done' as const,
    }))
  }

  return steps.slice(0, currentIndex + 1).map((step, index) => ({
    key: step['Step ID'],
    label: step['Journal Label'],
    state: index < currentIndex ? 'done' : 'current',
  }))
}

/** Objectives for the active step only, or none once every step is done. */
export function questActiveStepObjectives(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): StructuredQuestObjectives | null {
  const steps = getQuestSteps(db, quest['Quest ID'])
  if (steps.length === 0) return null

  const currentIndex = getCurrentStepIndex(db, save, quest)
  if (currentIndex >= steps.length) return null

  return parseNotesObjectives(steps[currentIndex]!.Notes ?? '')
}

export function questAllStepDelivers(
  db: GameDatabase,
  quest: QuestRow,
): StructuredQuestObjectives['delivers'] {
  const steps = getQuestSteps(db, quest['Quest ID'])
  const delivers: StructuredQuestObjectives['delivers'] = []
  for (const step of steps) {
    delivers.push(...parseNotesObjectives(step.Notes ?? '').delivers)
  }
  return delivers
}

export function questAllStepsComplete(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): boolean {
  const steps = getQuestSteps(db, quest['Quest ID'])
  if (steps.length === 0) return false
  return getCurrentStepIndex(db, save, quest) >= steps.length
}

/** Required or optional Talk on the current step (or quest Notes). */
export function questCanTalkToNpc(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): boolean {
  const objectives = questUsesSteps(db, quest['Quest ID'])
    ? questActiveStepObjectives(db, save, quest)
    : parseStructuredObjectives(quest)
  if (!objectives) return false
  const talks =
    objectives.talkNpcIds.includes(npcId) || objectives.optionalTalkNpcIds.includes(npcId)
  if (!talks) return false
  return objectives.holds.every((hold) => inventoryCount(save, hold.targetId) >= hold.quantity)
}

/** True when this NPC still has an unfinished Talk step (or Notes talk). */
export function questNpcHasIncompleteTalk(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): boolean {
  const questId = quest['Quest ID']
  const steps = getQuestSteps(db, questId)
  if (steps.length === 0) {
    return parseStructuredObjectives(quest).talkNpcIds.includes(npcId)
  }
  return steps.some(
    (step) =>
      parseNotesObjectives(step.Notes ?? '').talkNpcIds.includes(npcId) &&
      !isStepComplete(db, save, questId, step.Notes ?? '', step['Step ID']),
  )
}

export function questTouchesNpcForSave(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): boolean {
  if (quest['NPC ID'] === npcId) return true

  const meta = parseStructuredObjectives(quest)
  const progress = getQuestProgress(save, quest['Quest ID'])
  if (progress.status !== 'active') return false

  if (meta.turnInNpcId === npcId || meta.choiceNpcId === npcId) {
    if (!questUsesSteps(db, quest['Quest ID'])) return true
    if (questActiveStepObjectives(db, save, quest)?.talkNpcIds.includes(npcId)) return true
    return !questNpcHasIncompleteTalk(db, save, quest, npcId)
  }

  return questCanTalkToNpc(db, save, quest, npcId)
}
