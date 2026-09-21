import { addItemToInventory } from '../activity/rewards'
import type { GameDatabase, ItemRow } from '../data/types'
import type { PlayerSave } from '../save/types'
import { asQuestRows, getQuestProgress } from './quests'
import { parseStructuredObjectives } from './objectives'
import {
  currentStepTalkKey,
  questActiveStepObjectives,
  questCanTalkToNpc,
  questObjectiveSources,
} from './steps'

function saveHasActiveQuest(save: PlayerSave): boolean {
  return save.quests.some((row) => row.status === 'active')
}

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
  if (!saveHasActiveQuest(save)) return save
  let next = save
  for (const quest of asQuestRows(db)) {
    if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
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
  if (!saveHasActiveQuest(save)) return save
  let next = save
  for (const quest of asQuestRows(db)) {
    if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
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

export function questIsComplete(save: PlayerSave, questId: string): boolean {
  return getQuestProgress(save, questId).status === 'completed'
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

function itemTags(item: ItemRow | undefined): string {
  return (item?.['Functional / Source Tags'] ?? '').toLowerCase()
}

function saveHasBotanySeed(db: GameDatabase, save: PlayerSave): boolean {
  const stacks = [...save.inventory, ...(save.bank ?? [])]
  return stacks.some((stack) => {
    if (stack.quantity <= 0) return false
    const item = db.Items.find((row) => row['Item ID'] === stack.itemId)
    const tags = itemTags(item)
    return tags.includes('botany_seed') || tags.includes('botany_sapling')
  })
}

/** Auto-accepts quests whose AutoStartOnSeed note is set and a seed is owned. */
export function applyQuestAutoStartOnSeed(db: GameDatabase, save: PlayerSave): PlayerSave {
  if (!saveHasBotanySeed(db, save)) return save
  let next = save
  for (const quest of asQuestRows(db)) {
    const structured = parseStructuredObjectives(quest)
    if (!structured.autoStartOnSeed) continue
    const questId = quest['Quest ID']
    const progress = getQuestProgress(next, questId)
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

function grantGiveOnTalk(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  grants: Array<{ targetId: string; quantity: number }>,
): PlayerSave {
  let next = save
  for (const grant of grants) {
    const flag = `give:${grant.targetId}`
    if (hasQuestFlag(next, questId, flag)) continue
    next = addItemToInventory(next, grant.targetId, grant.quantity, null, false, db)
    next = recordQuestFlag(next, questId, flag)
  }
  return next
}

/** Marks a Talk objective when the player hears that NPC's quest line. */
export function applyQuestTalkProgress(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): PlayerSave {
  let next = applyQuestAutoStartOnSeed(db, save)
  for (const quest of asQuestRows(db)) {
    if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
    if (!questCanTalkToNpc(db, next, quest, npcId)) continue
    const questId = quest['Quest ID']
    const stepObjectives =
      questActiveStepObjectives(db, next, quest) ?? parseStructuredObjectives(quest)
    if (stepObjectives.giveOnTalk.length > 0 && !hasQuestFlag(next, questId, `talk:${npcId}`)) {
      next = grantGiveOnTalk(db, next, questId, stepObjectives.giveOnTalk)
    }
    const stepKey = currentStepTalkKey(db, next, quest, npcId)
    next = setQuestFlag(next, questId, `talk:${npcId}`)
    next = setQuestFlag(next, questId, stepKey)
  }
  return applyQuestAutoStartOnSeed(db, next)
}

/** Marks Plant objectives after seeds go into a patch. */
export function applyQuestPlantProgress(
  db: GameDatabase,
  save: PlayerSave,
  plantedItemIds: string[],
): PlayerSave {
  if (plantedItemIds.length === 0) return save
  let next = save
  for (const itemId of new Set(plantedItemIds)) {
    for (const quest of asQuestRows(db)) {
      if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
      if (
        !questObjectiveSources(db, quest).some((row) =>
          row.plantTargets.some((target) => target.targetId === itemId),
        )
      ) {
        continue
      }
      next = bumpCounter(next, quest['Quest ID'], `plant:${itemId}`, 1)
    }
  }
  return next
}

/** Marks Action objectives after a gathering/combat action completes. */
export function applyQuestActionProgress(
  db: GameDatabase,
  save: PlayerSave,
  actionId: string,
  amount = 1,
): PlayerSave {
  if (!saveHasActiveQuest(save)) return save
  let next = save
  for (const quest of asQuestRows(db)) {
    if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
    if (!questObjectiveSources(db, quest).some((row) => row.actionTargets.some((t) => t.targetId === actionId))) {
      continue
    }
    next = bumpCounter(next, quest['Quest ID'], `action:${actionId}`, amount)
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
  return applyQuestVisitProgress(
    db,
    applyQuestAutoStartOnSeed(db, applyQuestAutoStart(db, save, locationId)),
    locationId,
  )
}
