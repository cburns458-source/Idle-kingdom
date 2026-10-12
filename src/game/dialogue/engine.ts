/**
 * Standalone dialogue graphs (Dialogues / DialogueNodes / DialogueChoices).
 *
 * Pure rules: no randomness. One-time completion is stored on the save.
 * QuestDialogue / NpcPanel stay untouched.
 */

import { addItemsToInventory } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

export interface DialogueChoiceView {
  choiceId: string
  label: string
}

export interface DialogueView {
  dialogueId: string
  nodeId: string
  speakerName: string
  npcId: string
  line: string
  choices: DialogueChoiceView[]
  /** True when this node has no further choices (should not happen — end via null next). */
  finished: boolean
}

export interface DialogueResult {
  ok: boolean
  reason: string
  save: PlayerSave
  view: DialogueView | null
  /** True when the conversation ended on this step. */
  completed: boolean
  message: string | null
}

function failed(save: PlayerSave, reason: string): DialogueResult {
  return { ok: false, reason, save, view: null, completed: false, message: null }
}

function dialogueRow(db: GameDatabase, dialogueId: string) {
  return db.Dialogues.find((row) => row['Dialogue ID'] === dialogueId) ?? null
}

function nodeRow(db: GameDatabase, nodeId: string) {
  return db.DialogueNodes.find((row) => row['Node ID'] === nodeId) ?? null
}

function choicesForNode(db: GameDatabase, nodeId: string) {
  return db.DialogueChoices.filter((row) => row['Node ID'] === nodeId).sort(
    (a, b) => a['Sort Order'] - b['Sort Order'],
  )
}

/** Whether a one-time dialogue is still available to start. */
export function dialogueAvailable(db: GameDatabase, save: PlayerSave, dialogueId: string): boolean {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue) return false
  if (dialogue.Repeatable) return true
  return !save.completedDialogueIds.includes(dialogueId)
}

/** Dialogues still available for an NPC at the current location. */
export function dialoguesForNpc(db: GameDatabase, save: PlayerSave, npcId: string): string[] {
  return db.Dialogues.filter((row) => row['NPC ID'] === npcId)
    .map((row) => row['Dialogue ID'])
    .filter((id) => dialogueAvailable(db, save, id))
}

function conditionHolds(save: PlayerSave, condition: string | null): boolean {
  if (condition == null || condition.trim() === '') return true
  const trimmed = condition.trim()
  // Reserved for later typed conditions. Unknown conditions hide the choice.
  if (trimmed.startsWith('has_item:')) {
    const itemId = trimmed.slice('has_item:'.length)
    return save.inventory.some((stack) => stack.itemId === itemId && stack.quantity > 0)
  }
  return false
}

function applyAction(
  db: GameDatabase,
  save: PlayerSave,
  action: string | null,
): { save: PlayerSave; message: string | null; reason: string | null } {
  if (action == null || action.trim() === '') return { save, message: null, reason: null }
  const trimmed = action.trim()
  if (trimmed.startsWith('grant_item:')) {
    const parts = trimmed.split(':')
    const itemId = parts[1] ?? ''
    const qty = Math.max(1, Math.floor(Number(parts[2] ?? '1') || 1))
    if (!itemId || !db.Items.some((row) => row['Item ID'] === itemId)) {
      return { save, message: null, reason: 'That gift is missing from the database.' }
    }
    const added = addItemsToInventory(save, itemId, qty, null, false, db)
    if (added.added <= 0) {
      return { save, message: null, reason: 'Your bag is full.' }
    }
    const name = db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name'] ?? itemId
    return {
      save: added.save,
      message: added.added === 1 ? `Received ${name}.` : `Received ${added.added} ${name}.`,
      reason: null,
    }
  }
  return { save, message: null, reason: `Unknown dialogue action: ${trimmed}` }
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
  const choices = choicesForNode(db, nodeId)
    .filter((row) => conditionHolds(save, row.Condition))
    .map((row) => ({ choiceId: row['Choice ID'], label: row.Label }))
  return {
    dialogueId,
    nodeId,
    speakerName: dialogue['Display Name'],
    npcId: dialogue['NPC ID'],
    line: node.Line,
    choices,
    finished: choices.length === 0,
  }
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
  if (!dialogue) return failed(save, 'That conversation was not found.')
  if (!dialogueAvailable(db, save, dialogueId)) {
    return failed(save, 'You have already finished that conversation.')
  }
  const view = viewFor(db, save, dialogueId, dialogue['Start Node ID'])
  if (!view) return failed(save, 'That conversation has no opening line.')
  return {
    ok: true,
    reason: '',
    save,
    view,
    completed: false,
    message: null,
  }
}

/**
 * Takes a choice on the current node.
 *
 * The client sends the node it is looking at; the server re-checks that the
 * choice belongs to that node and that the dialogue is still available.
 */
export function chooseDialogue(
  db: GameDatabase,
  save: PlayerSave,
  dialogueId: string,
  nodeId: string,
  choiceId: string,
): DialogueResult {
  const dialogue = dialogueRow(db, dialogueId)
  if (!dialogue) return failed(save, 'That conversation was not found.')
  // Mid-conversation choices stay allowed even after one-time completion was
  // recorded by a parallel tab; only starting is gated. Ending still marks once.
  const node = nodeRow(db, nodeId)
  if (!node || node['Dialogue ID'] !== dialogueId) {
    return failed(save, 'That line is not part of this conversation.')
  }
  const choice =
    choicesForNode(db, nodeId).find((row) => row['Choice ID'] === choiceId) ?? null
  if (!choice) return failed(save, 'That reply is not available.')
  if (!conditionHolds(save, choice.Condition)) {
    return failed(save, 'That reply is not available.')
  }

  const applied = applyAction(db, save, choice.Action)
  if (applied.reason) return failed(save, applied.reason)
  let nextSave = applied.save
  const nextNodeId = choice['Next Node ID']
  if (nextNodeId == null || nextNodeId === '') {
    nextSave = markCompleted(db, nextSave, dialogueId)
    return {
      ok: true,
      reason: '',
      save: nextSave,
      view: null,
      completed: true,
      message: applied.message,
    }
  }
  const view = viewFor(db, nextSave, dialogueId, nextNodeId)
  if (!view) return failed(save, 'That conversation leads nowhere.')
  return {
    ok: true,
    reason: '',
    save: nextSave,
    view,
    completed: false,
    message: applied.message,
  }
}
