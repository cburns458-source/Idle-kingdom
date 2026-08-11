import type { PlayerSave } from '../save/types'
import { asQuestRows, getQuestProgress } from './quests'
import { parseStructuredObjectives } from './objectives'
import type { GameDatabase } from '../data/types'

function bumpCounter(save: PlayerSave, questId: string, key: string, amount: number): PlayerSave {
  if (amount <= 0) return save
  const progress = getQuestProgress(save, questId)
  if (progress.status !== 'active') return save
  const counters = { ...(progress.counters ?? {}) }
  counters[key] = Number(counters[key] ?? 0) + amount
  const nextQuests = save.quests.filter((row) => row.questId !== questId)
  nextQuests.push({
    ...progress,
    counters,
    progress: Object.values(counters).reduce((sum, value) => sum + Number(value), 0),
  })
  return { ...save, quests: nextQuests }
}

/** Call after defeating an enemy (combat victory). */
export function applyQuestDefeatProgress(
  db: GameDatabase,
  save: PlayerSave,
  enemyId: string,
  amount = 1,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    const structured = parseStructuredObjectives(quest)
    if (!structured.defeatTargets.some((row) => row.targetId === enemyId)) continue
    next = bumpCounter(next, quest['Quest ID'], `defeat:${enemyId}`, amount)
  }
  return next
}

/** Call after completing a production recipe or special project. */
export function applyQuestProcessProgress(
  db: GameDatabase,
  save: PlayerSave,
  recipeOrProjectId: string,
  amount = 1,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    const structured = parseStructuredObjectives(quest)
    if (!structured.processTargets.some((row) => row.targetId === recipeOrProjectId)) continue
    next = bumpCounter(next, quest['Quest ID'], `process:${recipeOrProjectId}`, amount)
  }
  return next
}

/** Call when a recipe ID is newly unlocked. */
export function applyQuestLearnRecipeProgress(
  db: GameDatabase,
  save: PlayerSave,
  recipeId: string,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    const structured = parseStructuredObjectives(quest)
    if (!structured.learnRecipeIds.includes(recipeId)) continue
    next = bumpCounter(next, quest['Quest ID'], `learn:${recipeId}`, 1)
  }
  return next
}
