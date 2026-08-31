import type { GameDatabase, NpcRow } from '../data/types'
import { questObjectiveProgress, parseStructuredObjectives } from '../quests/objectives'
import {
  applyQuestTalkProgress,
  hasQuestFlag,
} from '../quests/progress'
import { isMiniquest } from '../quests/miniquests'
import {
  acceptQuest,
  ACCEPT_GOLD_FLAG,
  applyQuestBranchSkillXp,
  bribeQuestNpc,
  chooseQuestCombatRoute,
  completeQuest,
  donateForQuest,
  getQuest,
  getQuestProgress,
  questsTouchingNpc,
  type QuestRow,
} from '../quests/quests'
import { changeRaceAtNpc, raceChangeOffer, VESPER_ID, type RaceChangeOffer } from '../races/changeRace'
import {
  currentStepTalkKey,
  getCurrentStepIndex,
  getQuestSteps,
  questAllStepsComplete,
  questCanTalkToNpc,
} from '../quests/steps'
import type { PlayerSave } from '../save/types'
import { configString } from '../activity/gathering'
import {
  ARCHMAGE_ID,
  ARCANA_SKILL_ID,
  GENERAL_STORE_MERCHANT_ID,
  MASTER_DWARF_ID,
  QUILL_ID,
  SMITHING_SKILL_ID,
  claimMerchantTip,
  hasNpcKnowledge,
  shopIdForMerchant,
  unlockNpcKnowledge,
} from './knowledge'
import { DWARVEN_MINING_MERCHANT_ID, masterDwarfLocationId, quillLocationId } from './roaming'
import type { RandomFn } from '../activity/pools'
import { tryStartQuestChoiceCombat } from '../world/hostility'

const FALLBACK_MERCHANT_TIP = 'Last I heard, Quill was nearby.'
const FALLBACK_MERCHANT_TIP_SPENT = 'Last I heard, Quill was nearby.'
const FALLBACK_MERCHANT_LINE = 'Welcome to my shop.'
const FALLBACK_NPC_DESCRIPTION = 'An inhabitant of Restoria.'
const FALLBACK_QUEST_ACTIVE_PROMPT = 'What else do you need?'
const FALLBACK_QUILL_TEACH =
  'A bow’s only half the work — you’ll want a quiver too. I can show you how to make both. Hunt with a bow and you pick up combat experience as well. The animals fight back; might as well learn from it.'
const FALLBACK_QUILL_KNOWN = 'You know how to make bows and quivers.'

export function merchantTipLine(db: GameDatabase): string {
  return configString(db, 'copy.merchant_tip', FALLBACK_MERCHANT_TIP)
}

export function merchantTipSpentLine(db: GameDatabase): string {
  return configString(db, 'copy.merchant_tip_spent', FALLBACK_MERCHANT_TIP_SPENT)
}

/**
 * Quests the giver pitches in their own words before the quest list is shown.
 *
 * A quest without a pitch is simply accepted from the list.
 */
export function questPitchLine(db: GameDatabase, questId: string): string | null {
  const quest = db.Quests.find((row) => row['Quest ID'] === questId)
  const pitch = quest?.['Pitch']
  return typeof pitch === 'string' && pitch.length > 0 ? pitch : null
}

function requiredTalkNpcIdsFromNotes(notes: string | null): string[] {
  const field = (notes ?? '').match(/(?:^|;)\s*RequiresTalk:\s*([^;]+)/i)?.[1]
  if (!field) return []
  return field
    .split(',')
    .map((part) => part.trim().toUpperCase())
    .filter((id) => /^[A-Z]+-\d+$/.test(id))
}

function requiredStepIdFromNotes(notes: string | null): string | null {
  const field = (notes ?? '').match(/(?:^|;)\s*RequiresStep:\s*(QSTP-\d+)/i)?.[1]
  return field ? field.toUpperCase() : null
}

function whenCompletedFromNotes(notes: string | null): boolean {
  return /(?:^|;)\s*When:\s*completed/i.test(notes ?? '')
}

export function questTalkLine(
  db: GameDatabase,
  questId: string,
  npcId: string,
  save?: PlayerSave,
): string | null {
  const rows = (db.QuestDialogue ?? []).filter(
    (row) => row['Quest ID'] === questId && row['NPC ID'] === npcId,
  )
  const quest = getQuest(db, questId)
  const status = save ? getQuestProgress(save, questId).status : undefined
  const currentStepId =
    save && quest
      ? getQuestSteps(db, questId)[getCurrentStepIndex(db, save, quest)]?.['Step ID']
      : undefined
  const matching = rows.filter((row) => {
    const notes = row.Notes ?? null
    if (whenCompletedFromNotes(notes)) return status === 'completed'
    if (status === 'completed') return false
    const requiredStep = requiredStepIdFromNotes(notes)
    if (requiredStep && requiredStep !== currentStepId) return false
    const required = requiredTalkNpcIdsFromNotes(notes)
    if (required.length === 0) return true
    if (!save) return false
    return required.every((requiredNpcId) => hasQuestFlag(save, questId, `talk:${requiredNpcId}`))
  })
  const specific = matching.filter((row) => {
    const notes = row.Notes ?? null
    return (
      whenCompletedFromNotes(notes) ||
      requiredTalkNpcIdsFromNotes(notes).length > 0 ||
      requiredStepIdFromNotes(notes) != null
    )
  })
  const line = (specific[0] ?? matching[0])?.Line
  return line && line.length > 0 ? line : null
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
  /** Spoken when the player asks to learn, when the mentor has something to say. */
  line?: string
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
  donateLabel: string
  /** The giver's own words, shown before accepting. Null accepts straight away. */
  pitchLine: string | null
  lines: NpcQuestObjectiveLine[]
  progressLines: Array<{ key: string; label: string; current: number; required: number }>
  goldOwned: number
  goldRequired: number
  ready: boolean
  canAccept: boolean
  canDonate: boolean
  donated: boolean
  canTurnIn: boolean
  canTalk: boolean
  talkLabel: string
  talkLine: string | null
  canBribe: boolean
  bribeLabel: string
  canChooseCombat: boolean
  combatLabel: string
  /** Shown while the quest is active and no Talk / Bribe / Combat button is up. */
  idlePrompt: string
}

/** Merchant-only: ask where the Master Dwarf is today. */
export interface NpcWhereabouts {
  label: string
  line: string
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
  whereabouts?: NpcWhereabouts
  /** Weekly race-change service. Present only on Vesper. */
  raceChange?: RaceChangeOffer
}

function completedNote(
  db: GameDatabase,
  quest: QuestRow,
  npcId: string,
  save: PlayerSave,
): string {
  const spoken = questTalkLine(db, quest['Quest ID'], npcId, save)
  if (spoken) return spoken
  const unlocked = parseStructuredObjectives(quest).unlockLocationIds
  if (unlocked.length === 0) return 'Thank you.'
  const opened = unlocked
    .map((locationId) => {
      const mapName = mapNameForLocation(db, locationId)
      const where = mapName ? ` on the ${mapName}` : ''
      return `${locationName(db, locationId)} is open${where}`
    })
    .join(', ')
  return `Thank you — ${opened}.`
}

function questBlock(
  db: GameDatabase,
  save: PlayerSave,
  quest: QuestRow,
  npcId: string,
): NpcQuestBlock {
  const questId = quest['Quest ID']
  const objective = questObjectiveProgress(db, save, quest)
  const pitch = questPitchLine(db, questId)
  const parsed = parseStructuredObjectives(quest)
  const status = getQuestProgress(save, questId).status
  const isGiver = quest['NPC ID'] === npcId
  const turnInId = parsed.turnInNpcId ?? quest['NPC ID']
  const talkedThisStep = hasQuestFlag(save, questId, currentStepTalkKey(db, save, quest, npcId))
  const chose =
    hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat')
  const donated = hasQuestFlag(save, questId, ACCEPT_GOLD_FLAG)
  const needsDonate = parsed.acceptGoldCost > 0 && !donated
  let acceptLabel = 'Accept quest'
  if (parsed.acceptGoldCost > 0) {
    acceptLabel = `Start the quest ${quest['Display Name']}?`
  } else if (pitch) {
    acceptLabel = `Start quest: ${quest['Display Name']}`
  }
  return {
    questId,
    name: quest['Display Name'],
    summary: quest.Summary,
    status,
    completedNote: completedNote(db, quest, npcId, save),
    acceptLabel,
    donateLabel: `Donate ${parsed.acceptGoldCost.toLocaleString()} gold`,
    pitchLine: pitch,
    lines: objective.lines,
    progressLines: objective.progressLines,
    goldOwned: objective.goldOwned,
    goldRequired: objective.goldRequired,
    ready: objective.ready,
    canAccept: isGiver && status === 'inactive' && !needsDonate,
    canDonate: isGiver && status === 'inactive' && needsDonate,
    donated,
    canTurnIn: turnInId === npcId && status === 'active' && !parsed.autoCompleteOnTalk,
    canTalk: status === 'active' && questCanTalkToNpc(db, save, quest, npcId) && !talkedThisStep,
    talkLabel: 'Talk',
    talkLine: questTalkLine(db, questId, npcId, save),
    idlePrompt: configString(db, 'copy.quest_active_prompt', FALLBACK_QUEST_ACTIVE_PROMPT),
    canBribe:
      status === 'active' && parsed.choiceNpcId === npcId && parsed.bribeGold > 0 && !chose,
    bribeLabel: `Bribe ${parsed.bribeGold.toLocaleString()} gold`,
    canChooseCombat: status === 'active' && parsed.choiceNpcId === npcId && !chose,
    combatLabel: 'Pressure the Guards',
  }
}

export function quillTeachLine(db: GameDatabase): string {
  return configString(db, 'copy.quill_teach', FALLBACK_QUILL_TEACH)
}

export function quillKnownLine(db: GameDatabase): string {
  return configString(db, 'copy.quill_known', FALLBACK_QUILL_KNOWN)
}

function mentorBlock(db: GameDatabase, save: PlayerSave, npcId: string): NpcMentorBlock | null {
  if (npcId === QUILL_ID) {
    return {
      known: hasNpcKnowledge(save, npcId),
      knownNote: quillKnownLine(db),
      learnLabel: 'Ask about hunting',
      line: quillTeachLine(db),
    }
  }
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
  _save: PlayerSave,
  npc: NpcRow,
  quests: NpcQuestBlock[],
): NpcGreeting | null {
  if ((npc.Role ?? '').toLowerCase() === 'merchant') {
    return {
      kind: 'merchant',
      line: npc.Description ?? configString(db, 'copy.default_merchant_line', FALLBACK_MERCHANT_LINE),
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
    acceptLabel: pitched.canDonate ? pitched.donateLabel : pitched.acceptLabel,
  }
}

function whereaboutsFor(
  db: GameDatabase,
  npcId: string,
  nowMs: number,
): NpcWhereabouts | undefined {
  if (npcId === DWARVEN_MINING_MERCHANT_ID) {
    return {
      label: 'Ask where the Master Dwarf is',
      line: `The Master Dwarf is at the ${locationName(db, masterDwarfLocationId(nowMs))} today.`,
    }
  }
  if (npcId === GENERAL_STORE_MERCHANT_ID) {
    return {
      label: 'Ask about Quill',
      line: `Last I heard, Quill was at the ${locationName(db, quillLocationId(nowMs))}.`,
    }
  }
  return undefined
}

export function npcConversation(
  db: GameDatabase,
  save: PlayerSave,
  npc: NpcRow,
  nowMs: number = Date.now(),
): NpcConversation {
  const npcId = npc['NPC ID']
  const quests = questsTouchingNpc(db, save, npcId)
    .filter((quest) => {
      if (isMiniquest(quest)) return false
      const isGiver = quest['NPC ID'] === npcId
      const status = getQuestProgress(save, quest['Quest ID']).status
      return isGiver || status === 'active'
    })
    .map((quest) => questBlock(db, save, quest, npcId))
  const whereabouts = whereaboutsFor(db, npcId, nowMs)
  const raceChange = npcId === VESPER_ID ? raceChangeOffer(db, save, nowMs) : undefined
  return {
    npcId,
    name: npc['Display Name'],
    role: npc.Role ?? null,
    description:
      npc.Description ?? configString(db, 'copy.default_npc_description', FALLBACK_NPC_DESCRIPTION),
    isMerchant: (npc.Role ?? '').toLowerCase() === 'merchant',
    shopId: shopIdForMerchant(db, npc),
    greeting: greetingFor(db, save, npc, quests),
    mentor: mentorBlock(db, save, npcId),
    quests,
    ...(whereabouts ? { whereabouts } : {}),
    ...(raceChange ? { raceChange } : {}),
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
  if (npcId === QUILL_ID) {
    return {
      ok: true,
      save: result.save,
      message: 'Quill shows you how to make bows and quivers.',
    }
  }
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

/** Pays AcceptGold without starting the quest. */
export function donateForQuestFromNpc(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  const result = donateForQuest(db, save, questId)
  if (!result.ok) return result
  const quest = getQuest(db, questId)
  const cost = quest ? parseStructuredObjectives(quest).acceptGoldCost : 0
  return {
    ok: true,
    save: result.save,
    message: `Donated ${cost.toLocaleString()} gold.`,
  }
}

export function talkWithQuestNpc(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  let next = applyQuestTalkProgress(db, save, npcId)
  for (const quest of questsTouchingNpc(db, next, npcId)) {
    const parsed = parseStructuredObjectives(quest)
    if (!parsed.autoCompleteOnTalk) continue
    if (getQuestProgress(next, quest['Quest ID']).status !== 'active') continue
    if (!questAllStepsComplete(db, next, quest)) continue
    const completed = completeQuest(db, next, quest['Quest ID'])
    if (completed.ok) {
      return {
        ok: true,
        save: completed.save,
        message: `Thank you — ${quest['Display Name']}.`,
      }
    }
  }
  return { ok: true, save: next, message: 'You hear them out.' }
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
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  nowMs: number = Date.now(),
  random: RandomFn = Math.random,
):
  | { ok: true; save: PlayerSave; message: string; startedActivity: boolean }
  | { ok: false; reason: string } {
  const result = chooseQuestCombatRoute(save, questId)
  if (!result.ok) return result
  const started = tryStartQuestChoiceCombat(db, result.save, nowMs, random)
  return {
    ok: true,
    save: started.save,
    startedActivity: started.startedActivityId != null,
    message: started.startedActivityId
      ? 'The guards look nervous.'
      : 'The guards look nervous. Pressure them nearby.',
  }
}

export function changeRaceWithNpc(
  db: GameDatabase,
  save: PlayerSave,
  raceId: string,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave; message: string } | { ok: false; reason: string } {
  return changeRaceAtNpc(db, save, raceId, nowMs)
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
