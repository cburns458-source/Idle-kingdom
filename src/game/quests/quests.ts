import { addItemToInventory } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import { unlockRecipeId } from '../recipes/knowledge'
import { removeIngredients } from '../production/inventory'
import type { PlayerSave, QuestProgress } from '../save/types'
import { unlockLocation } from '../world/submaps'
import { parseStructuredObjectives, questObjectiveProgress } from './objectives'
import { applyQuestLearnRecipeProgress } from './progress'

export interface QuestRow {
  'Quest ID': string
  'Internal Key': string
  'Display Name': string
  'NPC ID': string
  Summary: string | null
  Status: string
  'Release Phase': string
  Notes: string | null
  'Objective Type': string | null
  'Objective Target ID': string | null
  'Required Quantity': number | null
  Repeatable: string | null
  'Reward XP Skill ID': string | null
  'Reward XP Amount': number | null
  'Reward Item ID': string | null
  'Reward Item Quantity': number | null
  'Possible Rewards': string | null
}

export function asQuestRows(db: GameDatabase): QuestRow[] {
  return db.Quests as unknown as QuestRow[]
}

export function getQuest(db: GameDatabase, questId: string): QuestRow | undefined {
  return asQuestRows(db).find((quest) => quest['Quest ID'] === questId)
}

export function questsForNpc(db: GameDatabase, npcId: string): QuestRow[] {
  return asQuestRows(db).filter((quest) => quest['NPC ID'] === npcId)
}

export function getQuestProgress(save: PlayerSave, questId: string): QuestProgress {
  return (
    save.quests.find((quest) => quest.questId === questId) ?? {
      questId,
      status: 'inactive',
      progress: 0,
    }
  )
}

export function isQuestRepeatable(quest: QuestRow): boolean {
  const flag = (quest.Repeatable ?? 'No').toLowerCase()
  return flag === 'yes' || flag === 'true' || flag === 'repeatable'
}

export function acceptQuest(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const quest = getQuest(db, questId)
  if (!quest) return { ok: false, reason: 'Quest not found.' }
  const npc = db.NPCs.find((row) => row['NPC ID'] === quest['NPC ID'])
  if (!npc || npc['Location ID'] !== save.currentLocationId) {
    return { ok: false, reason: 'Speak with the quest giver at their location.' }
  }
  const progress = getQuestProgress(save, questId)
  if (progress.status === 'active') {
    return { ok: false, reason: 'This quest is already active.' }
  }
  if (progress.status === 'completed' && !isQuestRepeatable(quest)) {
    return { ok: false, reason: 'This quest is already completed.' }
  }

  const nextQuests = save.quests.filter((row) => row.questId !== questId)
  nextQuests.push({ questId, status: 'active', progress: 0 })
  return { ok: true, save: { ...save, quests: nextQuests } }
}

export interface QuestRewardLine {
  label: string
}

export function completeQuest(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
):
  | {
      ok: true
      save: PlayerSave
      message: string
      questName: string
      rewards: QuestRewardLine[]
    }
  | { ok: false; reason: string } {
  const quest = getQuest(db, questId)
  if (!quest) return { ok: false, reason: 'Quest not found.' }
  const npc = db.NPCs.find((row) => row['NPC ID'] === quest['NPC ID'])
  if (!npc || npc['Location ID'] !== save.currentLocationId) {
    return { ok: false, reason: 'Return to the quest giver to turn this in.' }
  }

  const progress = getQuestProgress(save, questId)
  if (progress.status === 'completed') {
    return {
      ok: false,
      reason: isQuestRepeatable(quest)
        ? 'Accept this quest again before turning it in.'
        : 'This quest is already completed.',
    }
  }
  if (progress.status !== 'active') {
    return { ok: false, reason: 'Accept this quest before turning it in.' }
  }

  const parsed = parseStructuredObjectives(quest)
  const hasObjectives =
    parsed.delivers.length > 0 ||
    parsed.defeatTargets.length > 0 ||
    parsed.processTargets.length > 0 ||
    parsed.learnRecipeIds.length > 0 ||
    parsed.goldCost > 0
  if (!hasObjectives) {
    return { ok: false, reason: 'Quest objectives are incomplete in data.' }
  }

  const status = questObjectiveProgress(db, save, quest)
  if (!status.ready) {
    const missing = status.progressLines
      .filter((line) => line.current < line.required)
      .map((line) => `${line.required} ${line.label.replace(/^(Deliver|Defeat|Craft|Learn)\s+/i, '')}`)
    return {
      ok: false,
      reason: missing.length > 0 ? `Need ${missing.join(', ')}.` : 'Objectives incomplete.',
    }
  }

  let next: PlayerSave = save
  if (parsed.delivers.length > 0) {
    const removed = removeIngredients(
      next,
      parsed.delivers.map((line) => ({ itemId: line.targetId, quantity: line.quantity })),
      1,
    )
    if (!removed) return { ok: false, reason: 'Missing required items.' }
    next = removed
  }

  if (parsed.goldCost > 0) {
    if (next.gold < parsed.goldCost) {
      return { ok: false, reason: `Need ${parsed.goldCost.toLocaleString()} gold.` }
    }
    next = { ...next, gold: next.gold - parsed.goldCost }
  }

  const rewards: QuestRewardLine[] = []
  const xpSkill = quest['Reward XP Skill ID']
  const xpAmount = quest['Reward XP Amount']
  if (xpSkill && typeof xpAmount === 'number' && xpAmount > 0) {
    const applied = applyXp(next, db, xpSkill, xpAmount)
    next = applied.save
    const skillName =
      db.Skills.find((skill) => skill['Skill ID'] === xpSkill)?.['Display Name'] ?? 'skill'
    rewards.push({ label: `${xpAmount.toLocaleString()} ${skillName} XP` })
  }

  const rewardItemId = quest['Reward Item ID']
  const rewardQty = quest['Reward Item Quantity']
  if (rewardItemId && typeof rewardQty === 'number' && rewardQty > 0) {
    next = addItemToInventory(next, rewardItemId, rewardQty)
    const itemName =
      db.Items.find((item) => item['Item ID'] === rewardItemId)?.['Display Name'] ?? 'item'
    rewards.push({ label: `${rewardQty}× ${itemName}` })
  }

  let unlocked = next.unlockedLocationIds ?? []
  for (const locationId of parsed.unlockLocationIds) {
    const before = unlocked.length
    unlocked = unlockLocation({ unlockedLocationIds: unlocked }, locationId)
    if (unlocked.length > before) {
      const locName =
        db.Locations.find((location) => location['Location ID'] === locationId)?.[
          'Display Name'
        ] ?? locationId
      rewards.push({ label: `Unlocked ${locName}` })
    }
  }

  for (const recipeId of parsed.rewardRecipeIds) {
    const before = next.unlockedRecipeIds?.length ?? 0
    next = unlockRecipeId(next, recipeId)
    if ((next.unlockedRecipeIds?.length ?? 0) > before) {
      next = applyQuestLearnRecipeProgress(db, next, recipeId)
      const name =
        db.Recipes.find((recipe) => recipe['Recipe ID'] === recipeId)?.['Display Name'] ??
        recipeId
      rewards.push({ label: `Learned ${name}` })
    }
  }

  for (const npcId of parsed.rewardProjectNpcIds) {
    if (!(next.unlockedNpcIds ?? []).includes(npcId)) {
      next = {
        ...next,
        unlockedNpcIds: [...(next.unlockedNpcIds ?? []), npcId],
      }
      const name =
        db.NPCs.find((npc) => npc['NPC ID'] === npcId)?.['Display Name'] ?? npcId
      rewards.push({ label: `Project knowledge from ${name}` })
    }
  }

  const nextQuests = next.quests.filter((row) => row.questId !== questId)
  const progressTotal = status.progressLines.reduce((sum, line) => sum + line.required, 0)
  nextQuests.push({ questId, status: 'completed', progress: progressTotal, counters: {} })
  next = { ...next, quests: nextQuests, unlockedLocationIds: unlocked }

  return {
    ok: true,
    save: next,
    questName: quest['Display Name'],
    rewards,
    message:
      rewards.length > 0
        ? `Quest complete — ${rewards.map((reward) => reward.label).join(' and ')}.`
        : 'Quest complete.',
  }
}

export function questStatusLabel(
  status: 'inactive' | 'active' | 'completed',
): string {
  if (status === 'completed') return 'Completed'
  if (status === 'active') return 'Active'
  return 'Not started'
}
