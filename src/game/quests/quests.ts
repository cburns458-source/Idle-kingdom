import { addItemToInventory } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import { inventoryCount } from '../production/recipes'
import { removeIngredients } from '../production/inventory'
import type { PlayerSave, QuestProgress } from '../save/types'

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

export function completeQuest(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
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

  const targetId = quest['Objective Target ID']
  const required = quest['Required Quantity']
  if (!targetId || typeof required !== 'number' || required <= 0) {
    return { ok: false, reason: 'Quest objectives are incomplete in data.' }
  }
  if (inventoryCount(save, targetId) < required) {
    const itemName =
      db.Items.find((item) => item['Item ID'] === targetId)?.['Display Name'] ?? 'items'
    return { ok: false, reason: `Need ${required} ${itemName}.` }
  }

  const removed = removeIngredients(save, [{ itemId: targetId, quantity: required }], 1)
  if (!removed) return { ok: false, reason: 'Missing required items.' }

  let next = removed
  const xpSkill = quest['Reward XP Skill ID']
  const xpAmount = quest['Reward XP Amount']
  let xpNote = ''
  if (xpSkill && typeof xpAmount === 'number' && xpAmount > 0) {
    const applied = applyXp(next, db, xpSkill, xpAmount)
    next = applied.save
    const skillName =
      db.Skills.find((skill) => skill['Skill ID'] === xpSkill)?.['Display Name'] ?? 'skill'
    xpNote = `${xpAmount.toLocaleString()} ${skillName} XP`
  }

  const rewardItemId = quest['Reward Item ID']
  const rewardQty = quest['Reward Item Quantity']
  let itemNote = ''
  if (rewardItemId && typeof rewardQty === 'number' && rewardQty > 0) {
    next = addItemToInventory(next, rewardItemId, rewardQty)
    const itemName =
      db.Items.find((item) => item['Item ID'] === rewardItemId)?.['Display Name'] ?? 'item'
    itemNote = `${rewardQty}× ${itemName}`
  }

  const nextQuests = next.quests.filter((row) => row.questId !== questId)
  nextQuests.push({ questId, status: 'completed', progress: required })
  next = { ...next, quests: nextQuests }

  const rewardParts = [xpNote, itemNote].filter(Boolean)
  return {
    ok: true,
    save: next,
    message:
      rewardParts.length > 0
        ? `Quest complete — ${rewardParts.join(' and ')}.`
        : 'Quest complete.',
  }
}
