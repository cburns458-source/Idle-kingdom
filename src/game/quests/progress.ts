import type { PlayerSave } from '../save/types'
import { asQuestRows, getQuestProgress } from './quests'
import { parseStructuredObjectives } from './objectives'
import { questActiveStepObjectives, questObjectiveSources, questUsesSteps } from './steps'
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
    if (!questObjectiveSources(db, quest).some((row) => row.defeatTargets.some((t) => t.targetId === enemyId))) {
      continue
    }
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
    if (
      !questObjectiveSources(db, quest).some((row) =>
        row.processTargets.some((target) => target.targetId === recipeOrProjectId),
      )
    ) {
      continue
    }
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
    if (!questObjectiveSources(db, quest).some((row) => row.learnRecipeIds.includes(recipeId))) {
      continue
    }
    next = bumpCounter(next, quest['Quest ID'], `learn:${recipeId}`, 1)
  }
  return next
}

export function questFlag(save: PlayerSave, questId: string, key: string): number {
  return Number(getQuestProgress(save, questId).counters?.[key] ?? 0)
}

export function hasQuestFlag(save: PlayerSave, questId: string, key: string): boolean {
  return questFlag(save, questId, key) >= 1
}

export function questIsActive(save: PlayerSave, questId: string): boolean {
  return getQuestProgress(save, questId).status === 'active'
}

export function questIsActiveOrComplete(save: PlayerSave, questId: string): boolean {
  const status = getQuestProgress(save, questId).status
  return status === 'active' || status === 'completed'
}

export function setQuestFlag(save: PlayerSave, questId: string, key: string): PlayerSave {
  if (hasQuestFlag(save, questId, key)) return save
  return bumpCounter(save, questId, key, 1)
}

/**
 * Records a flag even when the quest is still inactive.
 *
 * Donate-before-start needs this: bumpCounter only writes active quests.
 */
export function recordQuestFlag(save: PlayerSave, questId: string, key: string): PlayerSave {
  if (hasQuestFlag(save, questId, key)) return save
  const progress = getQuestProgress(save, questId)
  const counters = { ...(progress.counters ?? {}), [key]: 1 }
  const nextQuests = save.quests.filter((row) => row.questId !== questId)
  nextQuests.push({
    ...progress,
    counters,
    progress: Object.values(counters).reduce((sum, value) => sum + Number(value), 0),
  })
  return { ...save, quests: nextQuests }
}

/** Marks a Talk objective when the player hears that NPC's quest line. */
export function applyQuestTalkProgress(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    if (questUsesSteps(db, quest['Quest ID'])) {
      const active = questActiveStepObjectives(db, next, quest)
      if (!active?.talkNpcIds.includes(npcId)) continue
    } else if (!questObjectiveSources(db, quest).some((row) => row.talkNpcIds.includes(npcId))) {
      continue
    }
    next = setQuestFlag(next, quest['Quest ID'], `talk:${npcId}`)
  }
  return next
}

/** Marks Visit objectives on arrival. */
export function applyQuestVisitProgress(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    if (!questObjectiveSources(db, quest).some((row) => row.visitLocationIds.includes(locationId))) {
      continue
    }
    next = setQuestFlag(next, quest['Quest ID'], `visit:${locationId}`)
  }
  return next
}

/** Marks Inspect objectives (bazaar, bounties, processing). */
export function applyQuestInspectProgress(
  db: GameDatabase,
  save: PlayerSave,
  inspectId: string,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    if (!questObjectiveSources(db, quest).some((row) => row.inspectIds.includes(inspectId))) {
      continue
    }
    next = setQuestFlag(next, quest['Quest ID'], `inspect:${inspectId}`)
  }
  return next
}

/** Auto-accepts quests whose AutoStart location matches this arrival. */
export function applyQuestAutoStart(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): PlayerSave {
  let next = save
  for (const quest of asQuestRows(db)) {
    const structured = parseStructuredObjectives(quest)
    if (structured.autoStartLocationId !== locationId) continue
    const questId = quest['Quest ID']
    const progress = getQuestProgress(next, questId)
    // Only a quest never taken up auto-starts, repeatable or not.
    if (progress.status !== 'inactive') continue
    next = {
      ...next,
      quests: [
        ...next.quests.filter((row) => row.questId !== questId),
        { questId, status: 'active', progress: 0 },
      ],
    }
  }
  return next
}

export function applyQuestLocationProgress(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): PlayerSave {
  return applyQuestVisitProgress(db, applyQuestAutoStart(db, save, locationId), locationId)
}
