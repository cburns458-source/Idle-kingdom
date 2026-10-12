/**
 * Show / HandIn progress for the UI ("6/10 Baked Potato handed in", "You have 3/5").
 *
 * Counts read the bag only, never the bank. Enchanted stacks do not count.
 * Hearted (favourited) stacks count everywhere; taking from one needs the
 * player's confirmation (see `confirm_favourites` in the engine).
 */

import type { GameDatabase } from '../data/types'
import { bagCount } from '../inventory/bag'
import { getQuestProgress } from '../quests/quests'
import {
  dialogueStepType,
  getQuestStep,
  handInCounterKey,
  isStepLatched,
  parseStepItems,
} from '../quests/steps'
import type { PlayerSave } from '../save/types'

export { bagCount, takeFromBag, unfavouriteCount } from '../inventory/bag'

export type StepProgressMode = 'show' | 'handIn'

export interface StepProgressLine {
  itemId: string
  /** Unenchanted bag count right now, hearted stacks included. */
  have: number
  /** Already kept by the NPC (HandIn); always 0 for Show. */
  handedIn: number
  need: number
  mode: StepProgressMode
}

export interface StepProgressGroup {
  questId: string
  stepId: string
  mode: StepProgressMode
  /** The step is latched. */
  done: boolean
  items: StepProgressLine[]
}

/** Per-item lines for a Show or HandIn step; empty for any other step. */
export function stepProgressView(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  stepId: string,
): StepProgressLine[] {
  return stepProgressGroup(db, save, questId, stepId)?.items ?? []
}

export function stepProgressGroup(
  db: GameDatabase,
  save: PlayerSave,
  questId: string,
  stepId: string,
): StepProgressGroup | null {
  const step = getQuestStep(db, questId, stepId)
  const type = dialogueStepType(step)
  if (type !== 'Show' && type !== 'HandIn') return null
  const mode: StepProgressMode = type === 'Show' ? 'show' : 'handIn'
  const done = isStepLatched(save, questId, stepId)
  const counters = getQuestProgress(save, questId).counters ?? {}
  const items = parseStepItems(step?.['Step Items']).map((need) => {
    const kept = Number(counters[handInCounterKey(stepId, need.itemId)] ?? 0)
    return {
      itemId: need.itemId,
      have: bagCount(save, need.itemId),
      handedIn: mode === 'show' ? 0 : done ? need.quantity : Math.min(kept, need.quantity),
      need: need.quantity,
      mode,
    }
  })
  return { questId, stepId, mode, done, items }
}
