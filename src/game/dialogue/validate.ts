/**
 * Content checks for dialogue graphs, dialogue quest steps and Reward Mode.
 *
 * Kept apart from `validateDatabase` because that one runs inside
 * `prepareDatabase` and a failure there stops the game loading; these run in
 * the test suite against the real database so a typo fails CI, not players.
 * The Dart twin is `validateDialogueContent` in ik_rules.
 */

import type { DialogueChoiceRow, GameDatabase, ValidationIssue } from '../data/types'
import { parseStructuredObjectives } from '../quests/objectives'
import { asQuestRows, questRewardMode, type QuestRow } from '../quests/quests'
import { dialogueStepType, getQuestStep } from '../quests/steps'
import {
  DIALOGUE_ACTION_ARITY,
  DIALOGUE_CONDITION_ARITY,
  isKnownDialogueAction,
  isKnownDialogueCondition,
  parseDialogueTokens,
  type DialogueToken,
} from './engine'

const DIALOGUE_STEP_TYPES = ['Talk', 'Show', 'HandIn']

/** Columns that pay on completion; a `dialogue` quest must leave them blank. */
const QUEST_REWARD_COLUMNS = [
  'Reward XP Skill ID',
  'Reward XP Amount',
  'Reward Item ID',
  'Reward Item Quantity',
  'Possible Rewards',
] as const

const STEP_ACTION_TYPES: Record<string, string> = {
  talk_flag: 'Talk',
  show_items: 'Show',
  hand_in: 'HandIn',
}

function isBlank(value: unknown): boolean {
  return value == null || (typeof value === 'string' && value.trim() === '')
}

function hasId(rows: Record<string, unknown>[], field: string, id: string): boolean {
  return rows.some((row) => row[field] === id)
}

function issue(table: string, id: string, message: string, severity: 'error' | 'warning' = 'error'): ValidationIssue {
  return { severity, table, id, message }
}

/** Reference checks shared by conditions and actions. */
function referenceProblem(db: GameDatabase, token: DialogueToken): string | null {
  const [a = '', b = ''] = token.args
  const quests = db.Quests
  switch (token.name) {
    case 'quest_active':
    case 'quest_done':
    case 'start_quest':
    case 'complete_quest':
      return hasId(quests, 'Quest ID', a) ? null : `Unknown quest ${a} in ${token.raw}`
    case 'quest_step':
    case 'step_ready':
    case 'talk_flag':
    case 'show_items':
    case 'hand_in': {
      if (!hasId(quests, 'Quest ID', a)) return `Unknown quest ${a} in ${token.raw}`
      const step = getQuestStep(db, a, b)
      if (!step) return `Step ${b} is not part of ${a} in ${token.raw}`
      const wanted = STEP_ACTION_TYPES[token.name]
      if (wanted && dialogueStepType(step) !== wanted) {
        return `${token.name} needs a ${wanted} step but ${b} is not one`
      }
      return null
    }
    case 'dialogue_done':
      return hasId(db.Dialogues as unknown as Record<string, unknown>[], 'Dialogue ID', a)
        ? null
        : `Unknown dialogue ${a} in ${token.raw}`
    case 'has_item':
    case 'grant_item':
    case 'take_item':
      if (!hasId(db.Items as unknown as Record<string, unknown>[], 'Item ID', a)) {
        return `Unknown item ${a} in ${token.raw}`
      }
      if (token.args.length > 1 && !/^[1-9]\d*$/.test(b)) return `Quantity must be a whole number ≥ 1 in ${token.raw}`
      return null
    case 'total_level':
      return /^[1-9]\d*$/.test(a) ? null : `Level must be a whole number ≥ 1 in ${token.raw}`
    case 'skill':
      if (!hasId(db.Skills as unknown as Record<string, unknown>[], 'Skill ID', a)) {
        return `Unknown skill ${a} in ${token.raw}`
      }
      return /^[1-9]\d*$/.test(b) ? null : `Level must be a whole number ≥ 1 in ${token.raw}`
    case 'has_book':
    case 'grant_book':
      return hasId(db.Books as unknown as Record<string, unknown>[], 'Book ID', a)
        ? null
        : `Unknown book ${a} in ${token.raw}`
    default:
      return null
  }
}

function checkConditions(
  db: GameDatabase,
  table: string,
  id: string,
  condition: string | null | undefined,
  issues: ValidationIssue[],
): DialogueToken[] {
  const tokens = parseDialogueTokens(condition)
  for (const token of tokens) {
    if (!isKnownDialogueCondition(token)) {
      const known = token.name in DIALOGUE_CONDITION_ARITY
      issues.push(issue(table, id, known ? `Malformed condition: ${token.raw}` : `Unknown condition: ${token.raw}`))
      continue
    }
    const problem = referenceProblem(db, token)
    if (problem) issues.push(issue(table, id, problem))
  }
  return tokens
}

const GIFT_FLAG = /^gift:([A-Z]+-\d+)(?::.+)?$/

/**
 * A grant on a non-Repeatable choice must be once-only: it completes a quest in
 * the same commit, or is gated by `!dialogue_done:`, or sets a `gift:` flag its
 * own (or its dialogue's) Condition rejects with `!flag:`.
 */
function checkOnceOnly(
  db: GameDatabase,
  choice: DialogueChoiceRow,
  dialogueCondition: DialogueToken[],
  dialogueRepeatable: boolean,
  conditions: DialogueToken[],
  actions: DialogueToken[],
  issues: ValidationIssue[],
): void {
  const id = choice['Choice ID']
  if (choice.Repeatable === true) return
  if (!actions.some((token) => token.name === 'grant_item' || token.name === 'grant_book')) return
  if (actions.some((token) => token.name === 'complete_quest')) return
  const gates = [...conditions, ...dialogueCondition].filter(isKnownDialogueCondition)
  if (gates.some((token) => token.negated && token.name === 'dialogue_done')) return
  const blocked = new Set(gates.filter((token) => token.negated && token.name === 'flag').map((token) => token.args[0]))
  const guards = actions.filter(
    (token) => token.name === 'set_flag' && isKnownDialogueAction(token) && blocked.has(token.args[0]),
  )
  if (guards.length === 0) {
    issues.push(
      issue(
        'DialogueChoices',
        id,
        'A once-only grant must set a gift flag that its Condition rejects (set_flag:gift:… with !flag:gift:…), ' +
          'be gated by !dialogue_done:, complete a quest, or mark the choice Repeatable',
        // One-time dialogues only record completion at the end, so a grant mid-way can repeat.
        dialogueRepeatable ? 'error' : 'warning',
      ),
    )
    return
  }
  for (const guard of guards) {
    const owner = GIFT_FLAG.exec(guard.args[0] ?? '')?.[1]
    const known =
      owner != null &&
      (hasId(db.Quests, 'Quest ID', owner) ||
        hasId(db.Dialogues as unknown as Record<string, unknown>[], 'Dialogue ID', owner))
    if (!known) {
      issues.push(
        issue('DialogueChoices', id, `Gift flag ${guard.args[0]} must be gift:<quest or dialogue ID>[:key]`),
      )
    }
  }
}

function questRewardsPaid(quest: QuestRow): string[] {
  const paid: string[] = []
  for (const column of QUEST_REWARD_COLUMNS) {
    if (!isBlank(quest[column])) paid.push(column)
  }
  const parsed = parseStructuredObjectives(quest)
  if (parsed.rewardXp.length > 0) paid.push('RewardXP')
  if (parsed.rewardGold > 0) paid.push('RewardGold')
  if (parsed.rewardItems.length > 0) paid.push('RewardItem')
  if (parsed.rewardRecipeIds.length > 0) paid.push('RewardRecipe')
  if (parsed.rewardProjectNpcIds.length > 0) paid.push('RewardProjectNpc')
  if (parsed.rewardCosmeticIds.length > 0) paid.push('RewardCosmetic')
  if (parsed.rewardBookIds.length > 0) paid.push('RewardBook')
  if (parsed.branchSkillXp > 0) paid.push('BranchSkillXP')
  return paid
}

export function validateDialogueContent(db: GameDatabase): ValidationIssue[] {
  const issues: ValidationIssue[] = []
  const npcs = db.NPCs as unknown as Record<string, unknown>[]

  for (const quest of asQuestRows(db)) {
    const id = quest['Quest ID']
    const raw = quest['Reward Mode']
    if (!isBlank(raw) && !['legacy', 'dialogue'].includes(String(raw).trim().toLowerCase())) {
      issues.push(issue('Quests', id, `Unknown Reward Mode: ${String(raw)}`))
    }
    if (questRewardMode(quest) === 'dialogue') {
      const paid = questRewardsPaid(quest)
      if (paid.length > 0) {
        issues.push(issue('Quests', id, `Reward Mode dialogue must not pay on completion (${paid.join(', ')})`))
      }
    }
  }

  for (const step of db.QuestSteps) {
    const id = step['Step ID']
    const rawType = typeof step['Step Type'] === 'string' ? step['Step Type'].trim() : ''
    const type = dialogueStepType(step)
    if (!type && DIALOGUE_STEP_TYPES.some((name) => name.toLowerCase() === rawType.toLowerCase())) {
      issues.push(issue('QuestSteps', id, `Step Type must be spelled ${DIALOGUE_STEP_TYPES.join(', ')}: ${rawType}`))
    }
    const npcId = step['Step NPC']
    if (!isBlank(npcId) && !hasId(npcs, 'NPC ID', String(npcId))) {
      issues.push(issue('QuestSteps', id, `Missing Step NPC reference: ${String(npcId)}`))
    }
    const rawItems = typeof step['Step Items'] === 'string' ? step['Step Items'] : ''
    const entries = rawItems
      .split(';')
      .map((entry) => entry.trim())
      .filter((entry) => entry !== '')
    if (type === 'Talk' && entries.length > 0) {
      issues.push(issue('QuestSteps', id, 'A Talk step takes no Step Items'))
    }
    if (type === 'Show' || type === 'HandIn') {
      if (entries.length === 0) issues.push(issue('QuestSteps', id, `A ${type} step needs Step Items`))
      const seen = new Set<string>()
      for (const entry of entries) {
        const parts = entry.split(':').map((part) => part.trim())
        if (parts.length !== 2 || !/^[1-9]\d*$/.test(parts[1]!)) {
          issues.push(issue('QuestSteps', id, `Step Items entry must be ITEM-x:n with n ≥ 1: ${entry}`))
          continue
        }
        if (!hasId(db.Items as unknown as Record<string, unknown>[], 'Item ID', parts[0]!)) {
          issues.push(issue('QuestSteps', id, `Unknown item in Step Items: ${parts[0]}`))
        }
        if (seen.has(parts[0]!)) issues.push(issue('QuestSteps', id, `Item listed twice in Step Items: ${parts[0]}`))
        seen.add(parts[0]!)
      }
    }
  }

  const dialogueConditions = new Map<string, DialogueToken[]>()
  for (const dialogue of db.Dialogues) {
    const id = dialogue['Dialogue ID']
    dialogueConditions.set(id, checkConditions(db, 'Dialogues', id, dialogue.Condition, issues))
    if (!hasId(npcs, 'NPC ID', dialogue['NPC ID'])) {
      issues.push(issue('Dialogues', id, `Missing NPC ID reference: ${dialogue['NPC ID']}`))
    }
    const start = db.DialogueNodes.find((node) => node['Node ID'] === dialogue['Start Node ID'])
    if (!start || start['Dialogue ID'] !== id) {
      issues.push(issue('Dialogues', id, `Start Node ID is not a node of this dialogue: ${dialogue['Start Node ID']}`))
    }
    if (dialogue.Priority != null && !Number.isInteger(dialogue.Priority)) {
      issues.push(issue('Dialogues', id, 'Priority must be a whole number'))
    }
  }

  for (const choice of db.DialogueChoices) {
    const id = choice['Choice ID']
    const node = db.DialogueNodes.find((row) => row['Node ID'] === choice['Node ID'])
    if (!node) {
      issues.push(issue('DialogueChoices', id, `Missing Node ID reference: ${choice['Node ID']}`))
      continue
    }
    const nextId = choice['Next Node ID']
    if (!isBlank(nextId)) {
      const next = db.DialogueNodes.find((row) => row['Node ID'] === nextId)
      if (!next || next['Dialogue ID'] !== node['Dialogue ID']) {
        issues.push(issue('DialogueChoices', id, `Next Node ID is not a node of this dialogue: ${nextId}`))
      }
    }
    const conditions = checkConditions(db, 'DialogueChoices', id, choice.Condition, issues)
    const actions = parseDialogueTokens(choice.Action)
    for (const token of actions) {
      if (!isKnownDialogueAction(token)) {
        const known = token.name in DIALOGUE_ACTION_ARITY && !token.negated
        issues.push(issue('DialogueChoices', id, known ? `Malformed action: ${token.raw}` : `Unknown action: ${token.raw}`))
        continue
      }
      const problem = referenceProblem(db, token)
      if (problem) issues.push(issue('DialogueChoices', id, problem))
    }
    const dialogue = db.Dialogues.find((row) => row['Dialogue ID'] === node['Dialogue ID'])
    checkOnceOnly(
      db,
      choice,
      dialogueConditions.get(node['Dialogue ID']) ?? [],
      dialogue?.Repeatable === true,
      conditions,
      actions,
      issues,
    )
  }

  return issues
}
