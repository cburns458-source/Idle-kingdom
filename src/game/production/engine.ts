import { addItemToInventory, addItemToInventoryExact } from '../activity/rewards'
import { summarizeXpReward } from '../activity/rewardSummary'
import type { ActionRewardBundle } from '../activity/types'
import { applyXp, getSkillProgress } from '../activity/xp'
import { rollGatheringSuccess } from '../activity/gathering'
import { creditXpAwards } from '../trackers/trackers'
import type { RandomFn } from '../activity/pools'
import { chefHatOutputQuantity, alchemyPotionOutputQuantity, productionOutputReservePerCraft, ALCHEMY_SKILL_ID } from '../equipment/specialist'
import { equippedActionTimeReductionPercent } from '../equipment/loadout'
import { canFitItemQuantity, maxAddableQuantity } from '../inventory/capacity'
import type { GameDatabase } from '../data/types'
import type { RecipeRow } from '../data/recipeTypes'
import {
  applyPotionDurationMs,
  tickPotionAction,
  tryConsumePotionForScope,
} from '../potions/effects'
import type { ActivePotionEffect, PlayerSave } from '../save/types'

export function productionCraftDurationMs(
  db: GameDatabase,
  save: PlayerSave,
  recipe: RecipeRow,
  potionEffect: ActivePotionEffect | null | undefined,
): number {
  const baseDurationMs = recipe['Base Duration Seconds'] * 1000
  const atr = equippedActionTimeReductionPercent(db, save, recipe['Skill ID'])
  const reduced = baseDurationMs * Math.max(0.01, 1 - atr / 100)
  return applyPotionDurationMs(reduced, potionEffect)
}
import { removeIngredients } from './inventory'
import { requirementsForEntity, unmetHardRequirements } from '../activity/requirements'
import { knowsRecipe } from '../recipes/knowledge'
import {
  canKnowRecipe,
  facilityIdForActivity,
  getRecipe,
  isCompleteRecipe,
  isKitchenAmbientIngredient,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
  recipeIngredients,
  recipeMatchesFacility,
} from './recipes'
import { applyBountyProcessProgress } from '../bounties/progress'
import { recordProductionMilestones } from '../achievements/progress'
import { applyQuestProcessProgress } from '../quests/progress'

export function clearProductionSave(save: PlayerSave): PlayerSave {
  return {
    ...save,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
  }
}

/** Stop production and refund materials for crafts still remaining in the queue. */
export function cancelProductionActivity(db: GameDatabase, save: PlayerSave): PlayerSave {
  let next = save
  const remaining = save.productionQuantityRemaining ?? 0
  if (save.productionRecipeId && remaining > 0) {
    const recipe = getRecipe(db, save.productionRecipeId)
    if (recipe) {
      for (const ingredient of recipeIngredients(recipe)) {
        if (isKitchenAmbientIngredient(ingredient.itemId)) continue
        next = addItemToInventory(next, ingredient.itemId, ingredient.quantity * remaining)
      }
    }
  }
  return clearProductionSave({
    ...next,
    currentActivityId: null,
    activityStartedAt: null,
  })
}

export function beginProductionQueue(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  recipeId: string,
  quantity: number,
  nowMs: number = Date.now(),
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const recipe = getRecipe(db, recipeId)
  if (!recipe || !isCompleteRecipe(recipe)) {
    return { ok: false, reason: 'That recipe is not available.' }
  }
  if (!canKnowRecipe(save, db, recipe)) {
    if (!knowsRecipe(save, db, recipeId)) {
      return { ok: false, reason: 'You have not learned that recipe yet.' }
    }
    const unmet = unmetHardRequirements(
      db,
      save,
      requirementsForEntity(db, 'Recipe', recipeId),
    )
    return { ok: false, reason: unmet[0] ?? 'You cannot make that yet.' }
  }
  if (!recipeMatchesFacility(recipe['Facility ID'], facilityIdForActivity(db, activityId) ?? '')) {
    return { ok: false, reason: 'That recipe cannot be made at this station.' }
  }

  const crafts = Math.floor(quantity)
  if (crafts <= 0) {
    return { ok: false, reason: 'Choose a quantity of at least 1.' }
  }
  if (crafts > maxCraftsFromQueueCap(db, recipe)) {
    return { ok: false, reason: 'That queue exceeds the 24-hour production cap.' }
  }
  if (crafts > maxCraftsFromMaterials(save, recipe)) {
    return { ok: false, reason: 'Missing required materials for that quantity.' }
  }

  const ingredients = recipeIngredients(recipe)
  // Reserve/consume materials for the full queue up front so they cannot be spent elsewhere.
  const withMaterials = removeIngredients(save, ingredients, crafts)
  if (!withMaterials) {
    return { ok: false, reason: 'Missing required materials.' }
  }

  const outputTotal =
    productionOutputReservePerCraft(recipe['Skill ID'], recipe['Output Quantity']) * crafts
  if (!canFitItemQuantity(withMaterials, recipe['Output Item ID'], outputTotal)) {
    return {
      ok: false,
      reason: 'Not enough inventory space for that queue (180 slots, stacks to max).',
    }
  }

  const startedAt = new Date(nowMs).toISOString()
  const potion = tryConsumePotionForScope(db, withMaterials, 'one_standard_production_action')
  const durationMs = productionCraftDurationMs(db, potion.save, recipe, potion.effect)
  return {
    ok: true,
    save: {
      ...potion.save,
      currentActivityId: activityId,
      activityStartedAt: potion.save.activityStartedAt ?? startedAt,
      productionRecipeId: recipeId,
      productionQuantityTotal: crafts,
      productionQuantityRemaining: crafts,
      currentActionId: recipe['Action ID'],
      actionStartedAt: startedAt,
      actionDurationMs: durationMs,
    },
  }
}

export function completeProductionCraft(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
  random: RandomFn,
): {
  save: PlayerSave
  finishedQueue: boolean
  xpGained: number
  outputName: string
  outputQty: number
  /** True when the craft was botched: the materials are gone, nothing came back. */
  failed: boolean
  /** Same reward summary shape used by gathering/combat panels. */
  reward: ActionRewardBundle
} | null {
  if (!save.productionRecipeId || !save.productionQuantityRemaining) return null
  const recipe = getRecipe(db, save.productionRecipeId)
  if (!recipe) return null

  // The materials left the bag when the queue was placed, so a botched craft
  // costs them: rolling before the output means a full bag cannot save them.
  const craftLevel = getSkillProgress(save, recipe['Skill ID']).level
  if (!rollGatheringSuccess(craftLevel, random, recipe['Proficiency Level'])) {
    const outputItem = db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])
    return finishProductionCraft(db, save, recipe, nowMs, {
      next: save,
      outputName: outputItem?.['Display Name'] ?? recipe['Display Name'],
      outputQty: 0,
      xpGained: 0,
      failed: true,
      reward: {
        id: `craft-${recipe['Recipe ID']}-${nowMs}-${save.productionQuantityRemaining - 1}`,
        xpRewards: [],
        loot: [],
        goldGained: 0,
      },
    })
  }

  const baseQty = recipe['Output Quantity']
  let outputQty =
    recipe['Skill ID'] === ALCHEMY_SKILL_ID
      ? alchemyPotionOutputQuantity(baseQty, save, recipe['Skill ID'], random)
      : chefHatOutputQuantity(baseQty, save, recipe['Skill ID'], random)
  if (outputQty > baseQty && !canFitItemQuantity(save, recipe['Output Item ID'], outputQty)) {
    if (recipe['Skill ID'] === ALCHEMY_SKILL_ID) {
      outputQty = Math.min(outputQty, maxAddableQuantity(save, recipe['Output Item ID']))
      if (outputQty <= 0) return null
    } else {
      outputQty = baseQty
    }
  }
  const granted = addItemToInventoryExact(save, recipe['Output Item ID'], outputQty)
  if (!granted.ok) return null
  let next = granted.save
  const xpGained = recipe['XP Reward']
  const xpApplied = applyXp(next, db, recipe['Skill ID'], xpGained)
  next = xpApplied.save
  next = creditXpAwards(next, [{ skillId: recipe['Skill ID'], xp: xpGained }], nowMs)

  const remaining = save.productionQuantityRemaining - 1
  next = applyQuestProcessProgress(db, next, recipe['Recipe ID'], 1)
  // Bounty hour follows the craft's own completion time, so offline catch-up
  // credits the hour the craft finished in rather than the moment of resolving.
  next = applyBountyProcessProgress(next, recipe['Recipe ID'], 1, nowMs)
  next = recordProductionMilestones(db, next, recipe['Output Item ID'], outputQty)
  const outputItem = db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])
  const outputName = outputItem?.['Display Name'] ?? recipe['Display Name']
  const xpReward = summarizeXpReward(
    db,
    next,
    recipe['Skill ID'],
    xpGained,
    xpApplied.leveledUpTo,
  )
  const reward: ActionRewardBundle = {
    id: `craft-${recipe['Recipe ID']}-${nowMs}-${remaining}`,
    xpRewards: xpReward ? [xpReward] : [],
    loot: [
      {
        itemId: recipe['Output Item ID'],
        quantity: outputQty,
        displayName: outputName,
      },
    ],
    goldGained: 0,
  }

  return finishProductionCraft(db, save, recipe, nowMs, {
    next,
    outputName,
    outputQty,
    xpGained,
    failed: false,
    reward,
  })
}

/**
 * Closes one craft off: ends the queue or starts the next craft's timer.
 *
 * Shared by the craft that worked and the craft that was botched, so a failure
 * moves the queue along exactly as a success does — it just brings nothing back.
 */
function finishProductionCraft(
  db: GameDatabase,
  save: PlayerSave,
  recipe: RecipeRow,
  nowMs: number,
  craft: {
    next: PlayerSave
    outputName: string
    outputQty: number
    xpGained: number
    failed: boolean
    reward: ActionRewardBundle
  },
): {
  save: PlayerSave
  finishedQueue: boolean
  xpGained: number
  outputName: string
  outputQty: number
  failed: boolean
  reward: ActionRewardBundle
} {
  const remaining = (save.productionQuantityRemaining ?? 1) - 1
  const tail = {
    finishedQueue: remaining <= 0,
    xpGained: craft.xpGained,
    outputName: craft.outputName,
    outputQty: craft.outputQty,
    failed: craft.failed,
    reward: craft.reward,
  }
  if (remaining <= 0) {
    return {
      save: clearProductionSave(
        tickPotionAction({
          ...craft.next,
          currentActivityId: null,
          activityStartedAt: null,
        }),
      ),
      ...tail,
    }
  }

  const startedAt = new Date(nowMs).toISOString()
  const ticked = tickPotionAction({
    ...craft.next,
    productionQuantityRemaining: remaining,
  })
  const potion = tryConsumePotionForScope(db, ticked, 'one_standard_production_action')
  const durationMs = productionCraftDurationMs(db, potion.save, recipe, potion.effect)
  return {
    save: {
      ...potion.save,
      productionQuantityRemaining: remaining,
      currentActionId: recipe['Action ID'],
      actionStartedAt: startedAt,
      actionDurationMs: durationMs,
    },
    ...tail,
  }
}

/** Advance a production queue by elapsed offline/online time. */
export function resolveProductionProgress(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
  random: RandomFn,
): {
  save: PlayerSave
  craftsCompleted: number
  messages: string[]
  activityMs: number
  blockedByInventory: boolean
} {
  let current = save
  let craftsCompleted = 0
  let activityMs = 0
  /** Aggregate identical outputs so AFK summaries show one line per item. */
  const craftTotals = new Map<string, { qty: number; xp: number; ruined: number }>()
  const craftOrder: string[] = []
  let blockedByInventory = false

  while (
    current.productionRecipeId &&
    current.productionQuantityRemaining &&
    current.actionStartedAt &&
    current.actionDurationMs
  ) {
    const durationMs = current.actionDurationMs
    const due = Date.parse(current.actionStartedAt) + durationMs
    if (due > nowMs) break
    const completed = completeProductionCraft(db, current, due, random)
    if (!completed) {
      blockedByInventory = true
      break
    }
    current = completed.save
    craftsCompleted += 1
    activityMs += durationMs
    const existing = craftTotals.get(completed.outputName)
    if (!existing) {
      craftOrder.push(completed.outputName)
      craftTotals.set(completed.outputName, {
        qty: completed.outputQty,
        xp: completed.xpGained,
        ruined: completed.failed ? 1 : 0,
      })
    } else {
      existing.qty += completed.outputQty
      existing.xp += completed.xpGained
      if (completed.failed) existing.ruined += 1
    }
    if (completed.finishedQueue) break
  }

  const messages = craftOrder.flatMap((name) => {
    const total = craftTotals.get(name)!
    const lines: string[] = []
    if (total.qty > 0) lines.push(`Crafted ${total.qty} ${name} (+${total.xp} XP)`)
    if (total.ruined > 0) lines.push(`Ruined ${total.ruined} ${name}`)
    return lines
  })

  return { save: current, craftsCompleted, messages, activityMs, blockedByInventory }
}
