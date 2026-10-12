/**
 * Show / HandIn progress for the UI ("6/10 Baked Potato handed in", "You have 3/5").
 *
 * Counts read the bag only, never the bank. Enchanted stacks do not count.
 * Show counts hearted (favourited) stacks; HandIn neither counts nor takes them.
 */

import type { GameDatabase } from '../data/types'
import { getQuestProgress } from '../quests/quests'
import {
  dialogueStepType,
  getQuestStep,
  handInCounterKey,
  isStepLatched,
  parseStepItems,
} from '../quests/steps'
import type { PlayerSave } from '../save/types'

export type StepProgressMode = 'show' | 'handIn'

export interface StepProgressLine {
  itemId: string
  /** Unenchanted bag count right now; HandIn leaves hearted stacks out. */
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

/** Unenchanted bag quantity of [itemId]. */
export function bagCount(save: PlayerSave, itemId: string): number {
  let total = 0
  for (const stack of save.inventory) {
    if (stack.itemId === itemId && !stack.enchantmentId) total += stack.quantity
  }
  return total
}

/** Unenchanted, unhearted bag quantity of [itemId]: what a HandIn step may take. */
export function handInCount(save: PlayerSave, itemId: string): number {
  let total = 0
  for (const stack of save.inventory) {
    if (stack.itemId === itemId && !stack.enchantmentId && stack.favorite !== true) total += stack.quantity
  }
  return total
}

/** Removes [quantity] unenchanted, unhearted [itemId]; null when fewer are held. */
export function takeForHandIn(save: PlayerSave, itemId: string, quantity: number): PlayerSave | null {
  if (quantity <= 0) return save
  if (handInCount(save, itemId) < quantity) return null
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  let remaining = quantity
  for (const stack of inventory) {
    if (remaining <= 0) break
    if (stack.itemId !== itemId || stack.enchantmentId || stack.favorite === true) continue
    const taken = Math.min(stack.quantity, remaining)
    stack.quantity -= taken
    remaining -= taken
  }
  return { ...save, inventory: inventory.filter((stack) => stack.quantity > 0) }
}

/**
 * Removes [quantity] unenchanted [itemId] from the bag, unhearted stacks first.
 * Returns null when the bag holds fewer.
 */
export function takeFromBag(save: PlayerSave, itemId: string, quantity: number): PlayerSave | null {
  if (quantity <= 0) return save
  if (bagCount(save, itemId) < quantity) return null
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  let remaining = quantity
  for (const favoritePass of [false, true]) {
    for (const stack of inventory) {
      if (remaining <= 0) break
      if (stack.itemId !== itemId || stack.enchantmentId) continue
      if ((stack.favorite === true) !== favoritePass) continue
      const taken = Math.min(stack.quantity, remaining)
      stack.quantity -= taken
      remaining -= taken
    }
  }
  return { ...save, inventory: inventory.filter((stack) => stack.quantity > 0) }
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
      have: mode === 'show' ? bagCount(save, need.itemId) : handInCount(save, need.itemId),
      handedIn: mode === 'show' ? 0 : done ? need.quantity : Math.min(kept, need.quantity),
      need: need.quantity,
      mode,
    }
  })
  return { questId, stepId, mode, done, items }
}
