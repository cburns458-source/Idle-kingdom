import type { GameDatabase, NpcRow } from '../data/types'
import { questObjectiveProgress, parseStructuredObjectives } from '../quests/objectives'
import {
  applyQuestTalkProgress,
  hasQuestFlag,
} from '../quests/progress'
import {
  acceptQuest,
  applyQuestBranchSkillXp,
  bribeQuestNpc,
  chooseQuestCombatRoute,
  getQuestProgress,
  questsTouchingNpc,
  type QuestRow,
} from '../quests/quests'
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
  'QST-0003':
    'Please, traveler… guards took my coin purse. I have nothing left. If you can spare 25 gold, I’ll wait here while you look.',
  'QST-0005':
    'The Archmage will take an apprentice who can gather Essence. I can grant you access to the mine beneath the tower — bring ten Essence to the Archmage.',
}

const QUEST_TALK_LINES: Record<string, Record<string, string>> = {
  'QST-0003': {
    'NPC-0007':
      'A beggar lost a purse? The guards at the barracks were laughing about some poor fool…',
    'NPC-0012':
      'A purse? Maybe I saw something. Of course, my memory gets expensive… or you could try taking it.',
  },
  'QST-0004': {
    'NPC-0013':
      'Welcome to the Citadel. See the Market, use a Processing station, and inspect the Grand Bazaar and Bounty Board, then come back to me.',
    'NPC-0006': 'New around here? Browse all you like — no obligation to buy.',
  },
  'QST-0005': {
    'NPC-0004': 'Ten Essence, and I will begin your studies in Arcana.',
  },
}

export function questPitchLine(questId: string): string | null {
  return QUEST_PITCH_LINES[questId] ?? null
}

export function questTalkLine(questId: string, npcId: string): string | null {
  return QUEST_TALK_LINES[questId]?.[npcId] ?? null
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
  progressLines: Array<{ key: string; label: string; current: number; required: number }>
  goldOwned: number
  goldRequired: number
  ready: boolean
  canAccept: boolean
  canTurnIn: boolean
  canTalk: boolean
  talkLabel: string
  talkLine: string | null
  canBribe: boolean
  bribeLabel: string
  canChooseCombat: boolean
  combatLabel: string
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

function questBlock(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): NpcQuestBlock {
  const questId = quest['Quest ID']
  const objective = questObjectiveProgress(db, save, quest)
  const pitch = questPitchLine(questId)
  const parsed = parseStructuredObjectives(quest)
  const status = getQuestProgress(save, questId).status
  const isGiver = quest['NPC ID'] === npcId
  const turnInId = parsed.turnInNpcId ?? quest['NPC ID']
  const talked = hasQuestFlag(save, questId, `talk:${npcId}`)
  const chose =
    hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')
  const needsTalkFirst = parsed.talkNpcIds.includes(npcId) && !talked
  let acceptLabel = 'Accept quest'
  if (parsed.acceptGoldCost > 0) {
    acceptLabel = `Donate ${parsed.acceptGoldCost.toLocaleString()} gold`
  } else if (pitch) {
    acceptLabel = `Start quest: ${quest['Display Name']}`
  }
  return {
    questId,
    name: quest['Display Name'],
    summary: quest.Summary,
    status,
    completedNote: completedNote(db, quest),
    acceptLabel,
    pitchLine: pitch,
    lines: objective.lines,
    progressLines: objective.progressLines,
    goldOwned: objective.goldOwned,
    goldRequired: objective.goldRequired,
    ready: objective.ready,
    canAccept: isGiver && status === 'inactive',
    canTurnIn: turnInId === npcId && status === 'active',
    canTalk: status === 'active' && parsed.talkNpcIds.includes(npcId) && !talked,
    talkLabel: 'Talk',
    talkLine: questTalkLine(questId, npcId),
    canBribe:
      status === 'active' &&
      parsed.choiceNpcId === npcId &&
      parsed.bribeGold > 0 &&
      !chose &&
      !needsTalkFirst,
    bribeLabel: `Bribe ${parsed.bribeGold.toLocaleString()} gold`,
    canChooseCombat:
      status === 'active' && parsed.choiceNpcId === npcId && !chose && !needsTalkFirst,
    combatLabel: 'Pressure the Guards',
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
  const quests = questsTouchingNpc(db, npcId)
    .filter((quest) => {
      const isGiver = quest['NPC ID'] === npcId
      const status = getQuestProgress(save, quest['Quest ID']).status
      return isGiver || status === 'active'
    })
    .map((quest) => questBlock(db, save, quest, npcId))
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

export function talkWithQuestNpc(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  return { ok: true, save: applyQuestTalkProgress(db, save, npcId), message: 'You hear them out.' }
}

export function bribeForQuest(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = bribeQuestNpc(db, save, questId)
  if (!result.ok) return result
  return { ok: true, save: result.save, message: 'The purse changes hands.' }
}

export function chooseCombatForQuest(
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = chooseQuestCombatRoute(save, questId)
  if (!result.ok) return result
  return {
    ok: true,
    save: result.save,
    message: 'The guards look nervous. Pressure them nearby.',
  }
}

export function assignQuestSkillXp(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
  amount: number,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = applyQuestBranchSkillXp(db, save, skillId, amount)
  if (!result.ok) return result
  return {
    ok: true,
    save: result.save,
    message: `Gained ${amount.toLocaleString()} ${skillName(db, skillId)} XP.`,
  }
}
