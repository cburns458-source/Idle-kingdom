import type { GameDatabase, QuestStepRow } from '../data/types'
import { inventoryCount } from '../production/recipes'
import type { PlayerSave } from '../save/types'
import { eligiblePoolEntries } from '../activity/pools'
import { getSkillProgress } from '../activity/xp'
import {
  formatQuestProgressLine,
  objectiveProgressFromStructured,
  parseNotesObjectives,
  parseStructuredObjectives,
  type QuestProgressLine,
} from './objectives'
import {
  asQuestRows,
  getQuest,
  getQuestProgress,
  questAvailableForSave,
  type QuestRow,
} from './quests'
import { hasQuestFlag } from './progress'
import type { StructuredQuestObjectives } from './types'

export type QuestJournalStepState = 'done' | 'current' | 'header'

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

/** Every authored step, marked done — used once the quest is finished. */
export function questCompletedJournal(db: GameDatabase, quest: QuestRow): QuestJournalStep[] {
  return getQuestSteps(db, quest['Quest ID']).map((step) => ({
    key: step['Step ID'],
    label: step['Journal Label'],
    state: 'done' as const,
  }))
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

function isAskAroundSkipped(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  notes: string,
): boolean {
  const structured = parseNotesObjectives(notes)
  if (structured.optionalTalkNpcIds.length === 0) return false
  if (hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')) {
    return true
  }
  const quest = getQuest(db, questId)
  if (!quest) return false
  return questAllStepDelivers(db, quest).some(
    (line) => inventoryCount(save, line.targetId) >= line.quantity,
  )
}

function journalProgressLines(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  notes: string,
): QuestProgressLine[] {
  const lines = stepProgressLines(db, save, questId, notes)
  const structured = parseNotesObjectives(notes)
  if (structured.optionalTalkNpcIds.length === 0) return lines
  const counters = getQuestProgress(save, questId).counters ?? {}
  const revealed = structured.optionalTalkNpcIds.some(
    (npcId) => Number(counters[`talk:${npcId}`] ?? 0) >= 1,
  )
  if (revealed) return lines
  return lines.filter(
    (line) =>
      !structured.talkNpcIds.some(
        (npcId) => line.key === `talk:${npcId}` || line.key.startsWith(`talk:${npcId}:`),
      ),
  )
}

export function isStepComplete(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  notes: string,
  stepId?: string,
): boolean {
  if (isAskAroundSkipped(db, save, questId, notes)) return true
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

export function questStepJournal(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): QuestJournalStep[] {
  const questId = quest['Quest ID']
  const steps = getQuestSteps(db, questId)
  if (steps.length === 0) return []

  const currentIndex = getCurrentStepIndex(db, save, quest)
  if (currentIndex >= steps.length) {
    return questCompletedJournal(db, quest)
  }

  return steps.slice(0, currentIndex + 1).flatMap((step, index) => {
    const done = index < currentIndex
    const head = {
      key: step['Step ID'],
      label: step['Journal Label'],
      state: (done ? 'done' : 'current') as QuestJournalStepState,
    }
    const progressSource = done
      ? stepProgressLines(db, save, questId, step.Notes ?? '', step['Step ID']).filter((line) =>
          line.key.startsWith('action:'),
        )
      : journalProgressLines(db, save, questId, step.Notes ?? '')
    const progress = progressSource.map((line) => ({
      key: line.key,
      label: formatQuestProgressLine(line),
      state: (line.current >= line.required ? 'done' : 'current') as QuestJournalStepState,
    }))
    return [head, ...progress]
  })
}

/** Skill and prior-quest gates for a quest that has not been accepted yet. */
export function questRequirementJournal(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
): QuestJournalStep[] {
  const parsed = parseStructuredObjectives(quest)
  const steps: QuestJournalStep[] = []
  for (const requirement of parsed.requiresSkills) {
    const name =
      db.Skills.find((row) => row['Skill ID'] === requirement.skillId)?.['Display Name'] ??
      requirement.skillId
    const level = getSkillProgress(save, requirement.skillId).level
    steps.push({
      key: `skill:${requirement.skillId}`,
      label: `Reach ${name} ${requirement.level} (${level} / ${requirement.level})`,
      state: level >= requirement.level ? 'done' : 'current',
    })
  }
  for (const requiredQuestId of parsed.requiresQuestIds) {
    const name = getQuest(db, requiredQuestId)?.['Display Name'] ?? requiredQuestId
    const done = getQuestProgress(save, requiredQuestId).status === 'completed'
    steps.push({
      key: `quest:${requiredQuestId}`,
      label: `Complete ${name}`,
      state: done ? 'done' : 'current',
    })
  }
  if (steps.length === 0) return steps
  return [{ key: 'header:required', label: 'Required', state: 'header' }, ...steps]
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

/** Locked nodes stay hidden until a current Visit step (or a standing/unlock check) reveals them. */
export function questRevealsLocation(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): boolean {
  for (const quest of asQuestRows(db)) {
    if (getQuestProgress(save, quest['Quest ID']).status !== 'active') continue
    const step = questActiveStepObjectives(db, save, quest)
    if (step?.visitLocationIds.includes(locationId)) return true
  }
  return false
}

export function questTouchesNpcForSave(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): boolean {
  if (quest['NPC ID'] === npcId) {
    const status = getQuestProgress(save, quest['Quest ID']).status
    if (status === 'inactive') return questAvailableForSave(db, save, quest)
    return true
  }

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

/** Quest action counts that belong on this activity's dock card. */
export function questActionProgressForActivity(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): QuestProgressLine[] {
  const activity = db.Activities.find((row) => row['Activity ID'] === activityId)
  const poolId = activity?.['Pool ID']
  const actionIds = new Set<string>()
  if (typeof poolId === 'string' && poolId.length > 0) {
    for (const candidate of eligiblePoolEntries(db, poolId)) {
      actionIds.add(candidate.action['Action ID'])
    }
  }
  if (save.currentActivityId === activityId && save.currentActionId) {
    actionIds.add(save.currentActionId)
  }
  if (actionIds.size === 0) return []

  const lines: QuestProgressLine[] = []
  for (const quest of asQuestRows(db)) {
    const questId = quest['Quest ID']
    if (getQuestProgress(save, questId).status !== 'active') continue
    if (questUsesSteps(db, questId)) {
      for (const step of getQuestSteps(db, questId)) {
        for (const line of stepProgressLines(db, save, questId, step.Notes ?? '', step['Step ID'])) {
          const actionId = line.key.startsWith('action:') ? line.key.slice('action:'.length) : null
          if (actionId && actionIds.has(actionId)) lines.push(line)
        }
      }
    } else {
      for (const line of stepProgressLines(db, save, questId, quest.Notes ?? '')) {
        const actionId = line.key.startsWith('action:') ? line.key.slice('action:'.length) : null
        if (actionId && actionIds.has(actionId)) lines.push(line)
      }
    }
  }
  return lines
}
