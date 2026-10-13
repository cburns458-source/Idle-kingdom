/**
 * Standalone dialogue graphs (Dialogues / DialogueNodes / DialogueChoices).
 *
 * Pure rules: no randomness. Conditions and actions are `;`-separated tokens
 * (docs/specs/SYS-01-dialogue.md). Actions run in order on a working copy and
 * commit together: if any fails, the original save comes back untouched.
 * QuestDialogue / NpcPanel stay untouched.
 */

import { addItemsToInventory } from '../activity/rewards'
import type { DialogueChoiceRow, DialogueRow, GameDatabase } from '../data/types'
import { addFavouriteLine, CONFIRM_FAVOURITES_PROMPT, favouritesNeeded, type ItemDelta } from '../inventory/bag'
import { inventorySlotsFree } from '../inventory/capacity'
import { noRoomReason, slotsNeededForItems, type NoRoom } from '../inventory/fit'
import { bookById, grantBook, isBookUnlocked } from '../library/books'
import {
  acceptQuest,
  completeQuest,
  getQuest,
  getQuestProgress,
  type QuestArrivalCompletion,
} from '../quests/quests'
import {
  applyQuestStepUnlocks,
  dialogueStepType,
  getCurrentStepId,
  getQuestStep,
  handInCounterKey,
  latchStep,
  parseStepItems,
  withQuestCounters,
  type DialogueStepType,
} from '../quests/steps'
import type { PlayerSave } from '../save/types'
import { discoverUnlockedFarmSpot } from '../timers/locationTimers'
import { getSkillProgress } from '../activity/xp'
import { totalLevel } from '../skills/totals'
import {
  bagCount,
  stepProgressGroup,
  takeFromBag,
  type StepProgressGroup,
} from './stepProgress'

export interface DialogueToken {
  raw: string
  negated: boolean
  name: string
  args: string[]
}

/** Accepted arity per token; the flag tokens keep everything after the first `:` as one key. */
export const DIALOGUE_CONDITION_ARITY: Readonly<Record<string, readonly [number, number]>> = {
  quest_active: [1, 1],
  quest_step: [2, 2],
  quest_done: [1, 1],
  dialogue_done: [1, 1],
  has_item: [1, 2],
  total_level: [1, 1],
  skill: [2, 2],
  flag: [1, 1],
  step_ready: [2, 2],
  has_book: [1, 1],
}

export const DIALOGUE_ACTION_ARITY: Readonly<Record<string, readonly [number, number]>> = {
  grant_item: [1, 2],
  take_item: [1, 2],
  start_quest: [1, 1],
  talk_flag: [2, 2],
  show_items: [2, 2],
  hand_in: [2, 2],
  complete_quest: [1, 1],
  grant_book: [1, 1],
  set_flag: [1, 1],
  clear_flag: [1, 1],
}

const KEY_TOKENS = new Set(['flag', 'set_flag', 'clear_flag'])
const QUEST_ACTIONS = new Set(['start_quest', 'talk_flag', 'show_items', 'hand_in', 'complete_quest'])

export function parseDialogueTokens(value: string | null | undefined): DialogueToken[] {
  if (typeof value !== 'string') return []
  const tokens: DialogueToken[] = []
  for (const part of value.split(';')) {
    const raw = part.trim()
    if (raw === '') continue
    const negated = raw.startsWith('!')
    const body = (negated ? raw.slice(1) : raw).trim()
    const colon = body.indexOf(':')
    const name = (colon < 0 ? body : body.slice(0, colon)).trim()
    const rest = colon < 0 ? '' : body.slice(colon + 1)
    const args =
      colon < 0 ? [] : KEY_TOKENS.has(name) ? [rest.trim()] : rest.split(':').map((arg) => arg.trim())
    tokens.push({ raw, negated, name, args })
  }
  return tokens
}

function arityOk(token: DialogueToken, table: Readonly<Record<string, readonly [number, number]>>): boolean {
  const arity = table[token.name]
  if (!arity) return false
  if (token.args.length < arity[0] || token.args.length > arity[1]) return false
  return token.args.every((arg) => arg.length > 0)
}

/** Whole count of at least 1, defaulting when the argument is absent. */
function parseCount(raw: string | undefined, fallback = 1): number | null {
  if (raw === undefined) return fallback
  if (!/^\d+$/.test(raw)) return null
  const value = Number(raw)
  return value >= 1 ? value : null
}

export function isKnownDialogueCondition(token: DialogueToken): boolean {
  return arityOk(token, DIALOGUE_CONDITION_ARITY)
}

export function isKnownDialogueAction(token: DialogueToken): boolean {
  return !token.negated && arityOk(token, DIALOGUE_ACTION_ARITY)
}

function itemName(db: GameDatabase, itemId: string): string {
  return db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name'] ?? itemId
}

function questName(db: GameDatabase, questId: string): string {
  return getQuest(db, questId)?.['Display Name'] ?? questId
}

function skillName(db: GameDatabase, skillId: string): string {
  return db.Skills.find((row) => row['Skill ID'] === skillId)?.['Display Name'] ?? skillId
}

function countLabel(count: number, name: string): string {
  return count === 1 ? name : `${count} ${name}`
}

function hasFlag(save: PlayerSave, key: string): boolean {
  return (save.dialogueFlags ?? []).includes(key)
}

function withFlag(save: PlayerSave, key: string, on: boolean): PlayerSave {
  const current = save.dialogueFlags ?? []
  if (current.includes(key) === on) return save
  const next = on ? [...current, key] : current.filter((flag) => flag !== key)
  return { ...save, dialogueFlags: [...next].sort() }
}

function isCurrentStep(db: GameDatabase, save: PlayerSave, questId: string, stepId: string): boolean {
  const quest = getQuest(db, questId)
  if (!quest || getQuestProgress(save, questId).status !== 'active') return false
  return getCurrentStepId(db, save, quest) === stepId
}

function handInRemaining(save: PlayerSave, questId: string, stepId: string, itemId: string, need: number): number {
  const kept = Number(getQuestProgress(save, questId).counters?.[handInCounterKey(stepId, itemId)] ?? 0)
  return Math.max(0, need - kept)
}

/** First player-facing reason a Show/HandIn step cannot be done now, or null. */
function stepNotReadyReason(db: GameDatabase, save: PlayerSave, questId: string, stepId: string): string | null {
  if (!isCurrentStep(db, save, questId, stepId)) return `Needs the right step of ${questName(db, questId)}`
  const step = getQuestStep(db, questId, stepId)
  const type = dialogueStepType(step)
  const needs = parseStepItems(step?.['Step Items'])
  if (type === 'Show') {
    for (const need of needs) {
      const have = bagCount(save, need.itemId)
      if (have < need.quantity) {
        return `Needs ${countLabel(need.quantity, itemName(db, need.itemId))} (you have ${have})`
      }
    }
    return null
  }
  if (type === 'HandIn') {
    const wanted = needs.filter((need) => handInRemaining(save, questId, stepId, need.itemId, need.quantity) > 0)
    if (wanted.some((need) => bagCount(save, need.itemId) > 0)) return null
    return `Bring ${wanted.map((need) => itemName(db, need.itemId)).join(' or ')}`
  }
  return null
}

/** True/false for a well-formed token, null for an unknown or malformed one. */
function positiveHolds(db: GameDatabase, save: PlayerSave, token: DialogueToken): boolean | null {
  if (!isKnownDialogueCondition(token)) return null
  const [a = '', b] = token.args
  switch (token.name) {
    case 'quest_active':
      return getQuestProgress(save, a).status === 'active'
    case 'quest_done':
      return getQuestProgress(save, a).status === 'completed'
    case 'quest_step':
      return isCurrentStep(db, save, a, b ?? '')
    case 'dialogue_done':
      return save.completedDialogueIds.includes(a)
    case 'has_item': {
      const need = parseCount(b)
      return need == null ? null : bagCount(save, a) >= need
    }
    case 'total_level': {
      const need = parseCount(a)
      return need == null ? null : totalLevel(save) >= need
    }
    case 'skill': {
      const need = parseCount(b)
      return need == null ? null : getSkillProgress(save, a).level >= need
    }
    case 'flag':
      return hasFlag(save, a)
    case 'step_ready':
      return stepNotReadyReason(db, save, a, b ?? '') == null
    case 'has_book':
      return isBookUnlocked(save, a)
    default:
      return null
  }
}

function failedReason(db: GameDatabase, save: PlayerSave, token: DialogueToken): string {
  const [a = '', b = ''] = token.args
  if (token.negated) {
    switch (token.name) {
      case 'quest_active':
        return `Not while ${questName(db, a)} is in progress`
      case 'quest_done':
        return `Already completed ${questName(db, a)}`
      case 'quest_step':
        return `Not at this step of ${questName(db, a)}`
      case 'dialogue_done':
        return 'Already talked about this'
      case 'has_item':
        return `Not while carrying ${itemName(db, a)}`
      case 'total_level':
        return `Only below total level ${a}`
      case 'skill':
        return `Only below ${skillName(db, a)} ${b}`
      case 'flag':
        return 'Already done'
      case 'step_ready':
        return 'Already ready'
      case 'has_book':
        return `Already have ${bookById(db, a)?.['Display Name'] ?? a}`
      default:
        return 'Not available'
    }
  }
  switch (token.name) {
    case 'quest_active':
      return `Needs ${questName(db, a)} in progress`
    case 'quest_done':
      return `Needs ${questName(db, a)} completed`
    case 'quest_step':
      return `Needs the right step of ${questName(db, a)}`
    case 'dialogue_done':
      return 'Needs an earlier conversation'
    case 'has_item':
      return `Needs ${countLabel(parseCount(b) ?? 1, itemName(db, a))}`
    case 'total_level':
      return `Needs total level ${a}`
    case 'skill':
      return `Needs ${skillName(db, a)} ${b}`
    case 'flag':
      return 'Not available yet'
    case 'step_ready':
      return stepNotReadyReason(db, save, a, b) ?? 'Not available'
    case 'has_book':
      return `Needs ${bookById(db, a)?.['Display Name'] ?? a}`
    default:
      return 'Not available'
  }
}

export interface DialogueConditionCheck {
  holds: boolean
  /** Player-facing reason when the condition fails. */
  reason: string | null
}

/** One condition token. Unknown tokens never hold, negated or not. */
export function checkDialogueCondition(
  db: GameDatabase,
  save: PlayerSave,
  token: DialogueToken,
): DialogueConditionCheck {
  const positive = positiveHolds(db, save, token)
  if (positive == null) return { holds: false, reason: 'Not available' }
  const holds = token.negated ? !positive : positive
  return holds ? { holds, reason: null } : { holds, reason: failedReason(db, save, token) }
}

/** All tokens of a Condition cell (AND); the first failure's reason. */
export function checkDialogueConditions(
  db: GameDatabase,
  save: PlayerSave,
  condition: string | null | undefined,
): DialogueConditionCheck {
  for (const token of parseDialogueTokens(condition)) {
    const check = checkDialogueCondition(db, save, token)
    if (!check.holds) return check
  }
  return { holds: true, reason: null }
}

export interface DialogueChoiceView {
  choiceId: string
  label: string
  enabled: boolean
  /** First failed condition, worded for players; null when enabled. */
  reason: string | null
  hidden: boolean
  /** Starts, advances or completes a quest (or the row sets QuestMarker). */
  questMarked: boolean
}

export interface DialogueView {
  dialogueId: string
  nodeId: string
  speakerName: string
  npcId: string
  line: string
  choices: DialogueChoiceView[]
  /** Show / HandIn steps the listed choices check or act on. */
  stepProgress: StepProgressGroup[]
  /** True when this node has no further choices (should not happen — end via null next). */
  finished: boolean
}

export type DialogueItemDelta = ItemDelta

export type DialogueNoRoom = NoRoom

export interface DialogueMissingItem {
  itemId: string
  have: number
  need: number
}

export type DialogueFailureCode =
  | 'not_found'
  | 'not_available'
  | 'invalid'
  | 'no_room'
  | 'missing_items'
  | 'nothing_to_hand_in'
  | 'confirm_favourites'
  | 'action_failed'

export { CONFIRM_FAVOURITES_PROMPT }

export interface ChooseDialogueOptions {
  /**
   * The player said yes to using favourited stacks for this one request. Never
   * stored, so a later choice asks again.
   */
  useFavourites?: boolean
}

export interface DialogueResult {
  ok: boolean
  reason: string
  /** Machine-readable failure, null on success. */
  code: DialogueFailureCode | null
  save: PlayerSave
  view: DialogueView | null
  /** True when the conversation ended on this step. */
  completed: boolean
  message: string | null
  itemDeltas: DialogueItemDelta[]
  /** Books newly added to the Library. */
  bookDeltas: string[]
  /** Show / HandIn progress touched by this choice (after it applied, or as it stood when it failed). */
  stepProgress: StepProgressGroup[]
  noRoom: DialogueNoRoom | null
  missing: DialogueMissingItem[]
  /** For `confirm_favourites`: how many of each item would come out of hearted stacks. */
  favourites: DialogueItemDelta[]
  /** Quests this choice completed, for the client's reward popup. */
  questCompletions: QuestArrivalCompletion[]
}

function failed(
  save: PlayerSave,
  code: DialogueFailureCode,
  reason: string,
  extra: Partial<Pick<DialogueResult, 'stepProgress' | 'noRoom' | 'missing' | 'favourites'>> = {},
): DialogueResult {
  return {
    ok: false,
    reason,
    code,
    save,
    view: null,
    completed: false,
    message: null,
    itemDeltas: [],
    bookDeltas: [],
    stepProgress: extra.stepProgress ?? [],
    noRoom: extra.noRoom ?? null,
    missing: extra.missing ?? [],
    favourites: extra.favourites ?? [],
    questCompletions: [],
  }
}

function dialogueRow(db: GameDatabase, dialogueId: string): DialogueRow | null {
  return db.Dialogues.find((row) => row['Dialogue ID'] === dialogueId) ?? null
}

function nodeRow(db: GameDatabase, nodeId: string) {
  return db.DialogueNodes.find((row) => row['Node ID'] === nodeId) ?? null
}

function choicesForNode(db: GameDatabase, nodeId: string): DialogueChoiceRow[] {
  return db.DialogueChoices.filter((row) => row['Node ID'] === nodeId).sort(
    (a, b) => a['Sort Order'] - b['Sort Order'],
  )
}

function priorityOf(row: DialogueRow): number {
  return typeof row.Priority === 'number' && Number.isFinite(row.Priority) ? row.Priority : 0
}

/** Whether a dialogue can be opened now: one-time state and its Condition. */
export function dialogueAvailable(db: GameDatabase, save: PlayerSave, dialogueId: string): boolean {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue) return false
  if (!dialogue.Repeatable && save.completedDialogueIds.includes(dialogueId)) return false
  return checkDialogueConditions(db, save, dialogue.Condition).holds
}

/** Available dialogues for an NPC, highest Priority first, then by Dialogue ID. */
export function dialoguesForNpc(db: GameDatabase, save: PlayerSave, npcId: string): string[] {
  return db.Dialogues.filter((row) => row['NPC ID'] === npcId)
    .filter((row) => dialogueAvailable(db, save, row['Dialogue ID']))
    .sort((a, b) => {
      const byPriority = priorityOf(b) - priorityOf(a)
      if (byPriority !== 0) return byPriority
      const left = a['Dialogue ID']
      const right = b['Dialogue ID']
      return left < right ? -1 : left > right ? 1 : 0
    })
    .map((row) => row['Dialogue ID'])
}

/** Show / HandIn steps a choice row checks (`step_ready`) or acts on. */
function referencedSteps(row: DialogueChoiceRow): Array<[string, string]> {
  const refs: Array<[string, string]> = []
  for (const token of parseDialogueTokens(row.Condition)) {
    if (token.name === 'step_ready' && token.args.length === 2) refs.push([token.args[0]!, token.args[1]!])
  }
  for (const token of parseDialogueTokens(row.Action)) {
    if ((token.name === 'show_items' || token.name === 'hand_in') && token.args.length === 2) {
      refs.push([token.args[0]!, token.args[1]!])
    }
  }
  return refs
}

function progressFor(db: GameDatabase, save: PlayerSave, refs: Array<[string, string]>): StepProgressGroup[] {
  const groups: StepProgressGroup[] = []
  const seen = new Set<string>()
  for (const [questId, stepId] of refs) {
    const key = `${questId}\u0000${stepId}`
    if (seen.has(key)) continue
    seen.add(key)
    const group = stepProgressGroup(db, save, questId, stepId)
    if (group) groups.push(group)
  }
  return groups
}

function choiceView(db: GameDatabase, save: PlayerSave, row: DialogueChoiceRow): DialogueChoiceView | null {
  const check = checkDialogueConditions(db, save, row.Condition)
  const hidden = row.Hidden === true
  if (!check.holds && hidden) return null
  return {
    choiceId: row['Choice ID'],
    label: row.Label,
    enabled: check.holds,
    reason: check.reason,
    hidden,
    questMarked:
      row.QuestMarker === true ||
      parseDialogueTokens(row.Action).some((token) => QUEST_ACTIONS.has(token.name)),
  }
}

function viewFor(
  db: GameDatabase,
  save: PlayerSave,
  dialogueId: string,
  nodeId: string,
): DialogueView | null {
  const dialogue = dialogueRow(db, dialogueId)
  const node = nodeRow(db, nodeId)
  if (!dialogue || !node || node['Dialogue ID'] !== dialogueId) return null
  const rows: DialogueChoiceRow[] = []
  const choices: DialogueChoiceView[] = []
  for (const row of choicesForNode(db, nodeId)) {
    const view = choiceView(db, save, row)
    if (!view) continue
    rows.push(row)
    choices.push(view)
  }
  return {
    dialogueId,
    nodeId,
    speakerName: dialogue['Display Name'],
    npcId: dialogue['NPC ID'],
    line: node.Line,
    choices,
    stepProgress: progressFor(db, save, rows.flatMap(referencedSteps)),
    finished: choices.length === 0,
  }
}

/** Read-only view of a node for a save (the `dialogue_view` command). */
export function viewDialogueNode(
  db: GameDatabase,
  save: PlayerSave,
  dialogueId: string,
  nodeId: string,
): DialogueView | null {
  return viewFor(db, save, dialogueId, nodeId)
}

function markCompleted(db: GameDatabase, save: PlayerSave, dialogueId: string): PlayerSave {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue || dialogue.Repeatable) return save
  if (save.completedDialogueIds.includes(dialogueId)) return save
  return { ...save, completedDialogueIds: [...save.completedDialogueIds, dialogueId] }
}

/** Opens a dialogue at its start node. */
export function startDialogue(db: GameDatabase, save: PlayerSave, dialogueId: string): DialogueResult {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue) return failed(save, 'not_found', 'That conversation was not found.')
  if (!dialogue.Repeatable && save.completedDialogueIds.includes(dialogueId)) {
    return failed(save, 'not_available', 'You have already finished that conversation.')
  }
  const gate = checkDialogueConditions(db, save, dialogue.Condition)
  if (!gate.holds) return failed(save, 'not_available', gate.reason ?? 'Not available')
  const view = viewFor(db, save, dialogueId, dialogue['Start Node ID'])
  if (!view) return failed(save, 'invalid', 'That conversation has no opening line.')
  return {
    ok: true,
    reason: '',
    code: null,
    save,
    view,
    completed: false,
    message: null,
    itemDeltas: [],
    bookDeltas: [],
    stepProgress: [],
    noRoom: null,
    missing: [],
    favourites: [],
    questCompletions: [],
  }
}

interface Working {
  /** The save the choice started from; no-room counts are reported against it. */
  original: PlayerSave
  save: PlayerSave
  messages: string[]
  itemDeltas: DialogueItemDelta[]
  bookDeltas: string[]
  stepProgress: StepProgressGroup[]
  /** Quantities taken (or about to be) from hearted stacks, per item. */
  favourites: DialogueItemDelta[]
  questCompletions: QuestArrivalCompletion[]
}

/** Records how much of taking [quantity] from [save] would come out of hearted stacks. */
function noteFavourites(work: Working, save: PlayerSave, itemId: string, quantity: number): void {
  addFavouriteLine(work.favourites, itemId, favouritesNeeded(save, itemId, quantity))
}

type ActionFailure = {
  code: DialogueFailureCode
  reason: string
  noRoom?: DialogueNoRoom
  missing?: DialogueMissingItem[]
  stepProgress?: StepProgressGroup[]
}

/** New bag slots every grant in [tokens] needs against [save]. */
function slotsNeededForGrants(db: GameDatabase, save: PlayerSave, tokens: DialogueToken[]): number {
  const itemIds = tokens
    .filter((token) => token.name === 'grant_item' && isKnownDialogueAction(token))
    .map((token) => token.args[0]!)
  return slotsNeededForItems(db, save, itemIds)
}

/** Checks the quest is active, the step belongs to it with [type], and is current. */
function guardStep(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  stepId: string,
  type: DialogueStepType,
): ActionFailure | null {
  const step = getQuestStep(db, questId, stepId)
  if (!getQuest(db, questId) || !step || dialogueStepType(step) !== type) {
    return { code: 'invalid', reason: 'That quest step cannot be done here.' }
  }
  if (getQuestProgress(save, questId).status !== 'active') {
    return { code: 'action_failed', reason: 'That quest is not active.' }
  }
  if (!isCurrentStep(db, save, questId, stepId)) {
    return { code: 'action_failed', reason: 'That step is not current.' }
  }
  return null
}

function latchAndUnlock(db: GameDatabase, save: PlayerSave, questId: string, stepId: string): PlayerSave {
  return discoverUnlockedFarmSpot(db, applyQuestStepUnlocks(db, latchStep(save, questId, stepId)))
}

/** Unenchanted bag counts that changed, sorted by item ID. */
function bagDiff(before: PlayerSave, after: PlayerSave): DialogueItemDelta[] {
  const ids = new Set<string>()
  for (const stack of [...before.inventory, ...after.inventory]) {
    if (!stack.enchantmentId) ids.add(stack.itemId)
  }
  return [...ids]
    .sort()
    .map((itemId) => ({ itemId, qty: bagCount(after, itemId) - bagCount(before, itemId) }))
    .filter((delta) => delta.qty !== 0)
}

function applyAction(
  db: GameDatabase,
  work: Working,
  tokens: DialogueToken[],
  index: number,
): ActionFailure | null {
  const token = tokens[index]!
  if (!isKnownDialogueAction(token)) {
    return { code: 'invalid', reason: `Unknown dialogue action: ${token.raw}` }
  }
  const save = work.save
  const [a = '', b = ''] = token.args
  switch (token.name) {
    case 'grant_item': {
      const qty = parseCount(token.args[1])
      if (qty == null || !db.Items.some((row) => row['Item ID'] === a)) {
        return { code: 'invalid', reason: 'That gift is missing from the database.' }
      }
      const added = addItemsToInventory(save, a, qty, null, false, db)
      if (added.added < qty) {
        const noRoom = {
          slotsNeeded: Math.max(1, slotsNeededForGrants(db, work.original, tokens)),
          slotsFree: inventorySlotsFree(work.original),
        }
        return { code: 'no_room', reason: noRoomReason(noRoom), noRoom }
      }
      work.save = added.save
      work.itemDeltas.push({ itemId: a, qty })
      const name = itemName(db, a)
      work.messages.push(qty === 1 ? `Received ${name}.` : `Received ${qty} ${name}.`)
      return null
    }
    case 'take_item': {
      const qty = parseCount(token.args[1])
      if (qty == null) return { code: 'invalid', reason: `Unknown dialogue action: ${token.raw}` }
      const taken = takeFromBag(save, a, qty)
      if (taken) noteFavourites(work, save, a, qty)
      if (!taken) {
        return {
          code: 'missing_items',
          reason: `Needs ${countLabel(qty, itemName(db, a))}`,
          missing: [{ itemId: a, have: bagCount(save, a), need: qty }],
        }
      }
      work.save = taken
      work.itemDeltas.push({ itemId: a, qty: -qty })
      return null
    }
    case 'start_quest': {
      const accepted = acceptQuest(db, save, a)
      if (!accepted.ok) return { code: 'action_failed', reason: accepted.reason }
      work.save = accepted.save
      work.messages.push(`Quest started: ${questName(db, a)}.`)
      return null
    }
    case 'talk_flag': {
      const guard = guardStep(db, save, a, b, 'Talk')
      if (guard) return guard
      work.save = latchAndUnlock(db, save, a, b)
      return null
    }
    case 'show_items': {
      const guard = guardStep(db, save, a, b, 'Show')
      if (guard) return guard
      const needs = parseStepItems(getQuestStep(db, a, b)?.['Step Items'])
      const missing = needs
        .map((need) => ({ itemId: need.itemId, have: bagCount(save, need.itemId), need: need.quantity }))
        .filter((line) => line.have < line.need)
      if (missing.length > 0) {
        const first = missing[0]!
        return {
          code: 'missing_items',
          reason: `Needs ${countLabel(first.need, itemName(db, first.itemId))} (you have ${first.have})`,
          missing,
          stepProgress: progressFor(db, save, [[a, b]]),
        }
      }
      work.save = latchAndUnlock(db, save, a, b)
      work.stepProgress.push(...progressFor(db, work.save, [[a, b]]))
      return null
    }
    case 'hand_in': {
      const guard = guardStep(db, save, a, b, 'HandIn')
      if (guard) return guard
      const needs = parseStepItems(getQuestStep(db, a, b)?.['Step Items'])
      let next = save
      const counters = { ...(getQuestProgress(save, a).counters ?? {}) }
      let moved = 0
      let complete = true
      const parts: string[] = []
      for (const need of needs) {
        const key = handInCounterKey(b, need.itemId)
        const kept = Number(counters[key] ?? 0)
        const move = Math.min(bagCount(next, need.itemId), Math.max(0, need.quantity - kept))
        if (move > 0) {
          noteFavourites(work, next, need.itemId, move)
          next = takeFromBag(next, need.itemId, move)!
          counters[key] = kept + move
          moved += move
          work.itemDeltas.push({ itemId: need.itemId, qty: -move })
          parts.push(countLabel(move, itemName(db, need.itemId)))
        }
        if (kept + move < need.quantity) complete = false
      }
      if (moved === 0) {
        return {
          code: 'nothing_to_hand_in',
          reason: 'You have nothing they still need.',
          stepProgress: progressFor(db, save, [[a, b]]),
        }
      }
      next = withQuestCounters(next, a, counters)
      if (complete) next = latchAndUnlock(db, next, a, b)
      work.save = next
      work.messages.push(`Handed over ${parts.join(' and ')}.`)
      work.stepProgress.push(...progressFor(db, next, [[a, b]]))
      return null
    }
    case 'complete_quest': {
      // Hearted delivery stacks join this choice's own favourites prompt.
      let completed = completeQuest(db, save, a)
      if (!completed.ok && completed.code === 'confirm_favourites') {
        for (const line of completed.favourites ?? []) addFavouriteLine(work.favourites, line.itemId, line.qty)
        completed = completeQuest(db, save, a, { useFavourites: true })
      }
      if (!completed.ok) {
        if (completed.code === 'no_room') return { code: 'no_room', reason: completed.reason, noRoom: completed.noRoom }
        return { code: 'action_failed', reason: completed.reason }
      }
      work.itemDeltas.push(...bagDiff(save, completed.save))
      work.bookDeltas.push(...completed.booksGranted.map((grant) => grant.bookId))
      work.save = completed.save
      work.messages.push(completed.message)
      work.questCompletions.push({
        questId: a,
        questName: completed.questName,
        rewards: completed.rewards.map((reward) => reward.label),
        pendingSkillXp: completed.pendingSkillXp,
        rewardBundle: completed.rewardBundle,
        message: completed.message,
        booksGranted: completed.booksGranted,
      })
      return null
    }
    case 'grant_book': {
      const book = bookById(db, a)
      if (!book) return { code: 'invalid', reason: 'That book is missing from the database.' }
      const granted = grantBook(save, a)
      if (granted.granted) {
        work.save = granted.save
        work.bookDeltas.push(a)
        work.messages.push(`Added ${book['Display Name']} to your Library.`)
      }
      return null
    }
    case 'set_flag':
      work.save = withFlag(save, a, true)
      return null
    case 'clear_flag':
      work.save = withFlag(save, a, false)
      return null
    default:
      return { code: 'invalid', reason: `Unknown dialogue action: ${token.raw}` }
  }
}

/**
 * Takes a choice on the current node.
 *
 * The client sends the node it is looking at; the server re-checks that the
 * choice belongs to that node and that its conditions hold on the server save.
 */
export function chooseDialogue(
  db: GameDatabase,
  save: PlayerSave,
  dialogueId: string,
  nodeId: string,
  choiceId: string,
  options: ChooseDialogueOptions = {},
): DialogueResult {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue) return failed(save, 'not_found', 'That conversation was not found.')
  // Mid-conversation choices stay allowed even after one-time completion was
  // recorded by a parallel tab; only starting is gated. Ending still marks once.
  const node = nodeRow(db, nodeId)
  if (!node || node['Dialogue ID'] !== dialogueId) {
    return failed(save, 'invalid', 'That line is not part of this conversation.')
  }
  const choice = choicesForNode(db, nodeId).find((row) => row['Choice ID'] === choiceId) ?? null
  if (!choice) return failed(save, 'not_available', 'That reply is not available.')
  const gate = checkDialogueConditions(db, save, choice.Condition)
  if (!gate.holds) return failed(save, 'not_available', gate.reason ?? 'That reply is not available.')

  const tokens = parseDialogueTokens(choice.Action)
  const work: Working = {
    original: save,
    save,
    messages: [],
    itemDeltas: [],
    bookDeltas: [],
    stepProgress: [],
    favourites: [],
    questCompletions: [],
  }
  for (let index = 0; index < tokens.length; index += 1) {
    const failure = applyAction(db, work, tokens, index)
    if (failure) return failed(save, failure.code, failure.reason, failure)
  }
  // Checked once every action has run, so the prompt lists the whole choice
  // and a choice that would fail anyway reports that failure instead.
  if (work.favourites.length > 0 && options.useFavourites !== true) {
    return failed(save, 'confirm_favourites', CONFIRM_FAVOURITES_PROMPT, { favourites: work.favourites })
  }

  let nextSave = work.save
  const message = work.messages.length > 0 ? work.messages.join(' ') : null
  const nextNodeId = choice['Next Node ID']
  const done = {
    ok: true,
    reason: '',
    code: null,
    message,
    itemDeltas: work.itemDeltas,
    bookDeltas: work.bookDeltas,
    stepProgress: work.stepProgress,
    noRoom: null,
    missing: [],
    favourites: [],
    questCompletions: work.questCompletions,
  }
  if (nextNodeId == null || nextNodeId === '') {
    nextSave = markCompleted(db, nextSave, dialogueId)
    return { ...done, save: nextSave, view: null, completed: true }
  }
  const view = viewFor(db, nextSave, dialogueId, nextNodeId)
  if (!view) return failed(save, 'invalid', 'That conversation leads nowhere.')
  return { ...done, save: nextSave, view, completed: false }
}
