import type { GameDatabase, NpcRow } from '../data/types'
import { questObjectiveProgress, parseStructuredObjectives } from '../quests/objectives'
import { acceptQuest, getQuestProgress, questsForNpc, type QuestRow } from '../quests/quests'
import type { PlayerSave } from '../save/types'
import {
  ARCHMAGE_ID,
  ARCANA_SKILL_ID,
  ARTISANRY_SKILL_ID,
  GENERAL_STORE_MERCHANT_ID,
  MASTER_DWARF_ID,
  MERCHANT_TIP_XP,
  SMITHING_SKILL_ID,
  claimMerchantTip,
  hasNpcKnowledge,
  offersMerchantTip,
  shopIdForMerchant,
  unlockNpcKnowledge,
} from './knowledge'

/** Copy the clients share, so a line only ever has to be reworded once. */
export const MERCHANT_TIP_LINE = 'Here’s some tips about artisanry'
export const MERCHANT_TIP_SPENT_LINE = 'I’ve already shared what I know about artisanry.'
const DEFAULT_MERCHANT_LINE = 'Welcome to my shop.'
const DEFAULT_NPC_DESCRIPTION = 'An inhabitant of Idale.'

/**
 * Quests the giver pitches in their own words before the quest list is shown.
 *
 * A quest without a pitch is simply accepted from the list.
 */
const QUEST_PITCH_LINES: Record<string, string> = {
  'QST-0002':
    'I’m tired of working in the kitchen, I just saw a lot for sale down the street, I’m thinking of starting the alchemy shop I’ve always dreamed of…',
}

export function questPitchLine(questId: string): string | null {
  return QUEST_PITCH_LINES[questId] ?? null
}

export function skillForKnowledgeNpc(npcId: string): string | null {
  if (npcId === MASTER_DWARF_ID) return SMITHING_SKILL_ID
  if (npcId === ARCHMAGE_ID) return ARCANA_SKILL_ID
  return null
}

function skillName(db: GameDatabase, skillId: string): string {
  return db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? 'skill'
}

function locationName(db: GameDatabase, locationId: string): string {
  return (
    db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ?? locationId
  )
}

function mapNameForLocation(db: GameDatabase, locationId: string): string | null {
  const mapId = db.Locations.find((row) => row['Location ID'] === locationId)?.['Map ID']
  if (!mapId) return null
  return db.Maps.find((row) => row['Map ID'] === mapId)?.['Display Name'] ?? null
}

/** The dialogue an NPC opens with, shown over the panel. */
export type NpcGreeting =
  | { kind: 'merchant'; line: string; detail: string | null }
  | { kind: 'quest_pitch'; questId: string; line: string; acceptLabel: string }

/** A mentor's one-off project knowledge, and how to describe it. */
export interface NpcMentorBlock {
  known: boolean
  /** Shown once the knowledge is held. */
  knownNote: string
  learnLabel: string
}

export interface NpcQuestObjectiveLine {
  itemId: string
  name: string
  owned: number
  required: number
}

export interface NpcQuestBlock {
  questId: string
  name: string
  summary: string | null
  status: 'inactive' | 'active' | 'completed'
  /** Replaces the objective list once the quest is done. */
  completedNote: string
  acceptLabel: string
  /** The giver's own words, shown before accepting. Null accepts straight away. */
  pitchLine: string | null
  lines: NpcQuestObjectiveLine[]
  goldOwned: number
  goldRequired: number
  ready: boolean
}

/** Everything a client needs to draw one NPC, with no game rules left in it. */
export interface NpcConversation {
  npcId: string
  name: string
  role: string | null
  description: string
  isMerchant: boolean
  shopId: string | null
  greeting: NpcGreeting | null
  mentor: NpcMentorBlock | null
  quests: NpcQuestBlock[]
}

function completedNote(db: GameDatabase, quest: QuestRow): string {
  const unlocked = parseStructuredObjectives(quest).unlockLocationIds
  if (unlocked.length === 0) return 'Completed.'
  const opened = unlocked
    .map((locationId) => {
      const mapName = mapNameForLocation(db, locationId)
      const where = mapName ? ` on the ${mapName}` : ''
      return `${locationName(db, locationId)} is open${where}`
    })
    .join(', ')
  return `Completed — ${opened}.`
}

function questBlock(db: GameDatabase, save: PlayerSave, quest: QuestRow): NpcQuestBlock {
  const questId = quest['Quest ID']
  const objective = questObjectiveProgress(db, save, quest)
  const pitch = questPitchLine(questId)
  return {
    questId,
    name: quest['Display Name'],
    summary: quest.Summary,
    status: getQuestProgress(save, questId).status,
    completedNote: completedNote(db, quest),
    acceptLabel: pitch ? `Start quest: ${quest['Display Name']}` : 'Accept quest',
    pitchLine: pitch,
    lines: objective.lines,
    goldOwned: objective.goldOwned,
    goldRequired: objective.goldRequired,
    ready: objective.ready,
  }
}

function mentorBlock(db: GameDatabase, save: PlayerSave, npcId: string): NpcMentorBlock | null {
  const skillId = skillForKnowledgeNpc(npcId)
  if (!skillId) return null
  const name = skillName(db, skillId)
  return {
    known: hasNpcKnowledge(save, npcId),
    knownNote: `${name} projects are unlocked.`,
    learnLabel: `Learn ${name} projects`,
  }
}

function greetingFor(
  db: GameDatabase,
  save: PlayerSave,
  npc: NpcRow,
  quests: NpcQuestBlock[],
): NpcGreeting | null {
  const npcId = npc['NPC ID']
  if ((npc.Role ?? '').toLowerCase() === 'merchant') {
    if (offersMerchantTip(save, npcId)) {
      return {
        kind: 'merchant',
        line: MERCHANT_TIP_LINE,
        detail: `${MERCHANT_TIP_XP.toLocaleString()} ${skillName(db, ARTISANRY_SKILL_ID)} XP`,
      }
    }
    const spent = npcId === GENERAL_STORE_MERCHANT_ID
    return {
      kind: 'merchant',
      line: spent ? MERCHANT_TIP_SPENT_LINE : (npc.Description ?? DEFAULT_MERCHANT_LINE),
      detail: null,
    }
  }

  const pitched = quests.find(
    (quest) => quest.pitchLine !== null && quest.status === 'inactive',
  )
  if (!pitched || pitched.pitchLine === null) return null
  return {
    kind: 'quest_pitch',
    questId: pitched.questId,
    line: pitched.pitchLine,
    acceptLabel: pitched.acceptLabel,
  }
}

export function npcConversation(
  db: GameDatabase,
  save: PlayerSave,
  npc: NpcRow,
): NpcConversation {
  const npcId = npc['NPC ID']
  const quests = questsForNpc(db, npcId).map((quest) => questBlock(db, save, quest))
  return {
    npcId,
    name: npc['Display Name'],
    role: npc.Role ?? null,
    description: npc.Description ?? DEFAULT_NPC_DESCRIPTION,
    isMerchant: (npc.Role ?? '').toLowerCase() === 'merchant',
    shopId: shopIdForMerchant(db, npc),
    greeting: greetingFor(db, save, npc, quests),
    mentor: mentorBlock(db, save, npcId),
    quests,
  }
}

/**
 * Learns a mentor's projects, with the line to announce it.
 *
 * The caller does not need to know which mentor teaches what: the message
 * names the skill the same way the button that offered it did.
 */
export function learnMentorProjects(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = unlockNpcKnowledge(save, npcId)
  if (!result.ok) return result
  const skillId = skillForKnowledgeNpc(npcId)
  const name = skillId ? skillName(db, skillId) : 'these'
  const npcName = db.NPCs.find((row) => row['NPC ID'] === npcId)?.['Display Name'] ?? 'mentor'
  return {
    ok: true,
    save: result.save,
    message: `The ${npcName} unlocks all ${name} projects.`,
  }
}

/**
 * Takes the merchant's advice when their dialogue is dismissed.
 *
 * Returns null when there was nothing left to learn, which lets a caller
 * dismiss the dialogue the same way either way.
 */
export function takeMerchantTip(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): { save: PlayerSave; message: string } | null {
  const claimed = claimMerchantTip(db, save, npcId)
  if (!claimed) return null
  return {
    save: claimed.save,
    message: `Learned artisanry tips (+${claimed.xp.toLocaleString()} XP).`,
  }
}

/** Accepts a quest from an NPC's list, with the line to announce it. */
export function acceptQuestFromNpc(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = acceptQuest(db, save, questId)
  if (!result.ok) return result
  const quest = db.Quests.find((row) => row['Quest ID'] === questId)
  return {
    ok: true,
    save: result.save,
    message: `Accepted: ${quest?.['Display Name'] ?? 'quest'}.`,
  }
}
