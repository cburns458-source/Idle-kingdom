import { addItemToInventory, addItemToInventoryExact } from '../activity/rewards'
import { summarizeXpReward } from '../activity/rewardSummary'
import type { ActionRewardBundle } from '../activity/types'
import { applyXp } from '../activity/xp'
import { canFitItemQuantity } from '../inventory/capacity'
import type { GameDatabase } from '../data/types'
import {
  applyPotionDurationMs,
  clearActivePotionEffect,
  tryConsumePotionForScope,
} from '../potions/effects'
import type { PlayerSave } from '../save/types'
import { removeIngredients } from './inventory'
import {
  facilityIdForActivity,
  getRecipe,
  isCompleteRecipe,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
  recipeIngredients,
  recipeMatchesFacility,
} from './recipes'

export function clearProductionSave(save: PlayerSave): PlayerSave {
  return clearActivePotionEffect({
    ...save,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
  })
}

/** Stop production and refund materials for crafts still remaining in the queue. */
export function cancelProductionActivity(db: GameDatabase, save: PlayerSave): PlayerSave {
  let next = save
  const remaining = save.productionQuantityRemaining ?? 0
  if (save.productionRecipeId && remaining > 0) {
    const recipe = getRecipe(db, save.productionRecipeId)
    if (recipe) {
      for (const ingredient of recipeIngredients(recipe)) {
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

  const outputTotal = recipe['Output Quantity'] * crafts
  if (!canFitItemQuantity(withMaterials, recipe['Output Item ID'], outputTotal)) {
    return {
      ok: false,
      reason: 'Not enough inventory space for that queue (180 slots, stacks to max).',
    }
  }

  const startedAt = new Date(nowMs).toISOString()
  const baseDurationMs = recipe['Base Duration Seconds'] * 1000
  const potion = tryConsumePotionForScope(db, withMaterials, 'one_standard_production_action')
  const durationMs = applyPotionDurationMs(baseDurationMs, potion.effect)
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
  nowMs: number = Date.now(),
): {
  save: PlayerSave
  finishedQueue: boolean
  xpGained: number
  outputName: string
  outputQty: number
  /** Same reward summary shape used by gathering/combat panels. */
  reward: ActionRewardBundle
} | null {
  if (!save.productionRecipeId || !save.productionQuantityRemaining) return null
  const recipe = getRecipe(db, save.productionRecipeId)
  if (!recipe) return null

  const outputQty = recipe['Output Quantity']
  const granted = addItemToInventoryExact(save, recipe['Output Item ID'], outputQty)
  if (!granted.ok) return null
  let next = granted.save
  const xpApplied = applyXp(next, db, recipe['Skill ID'], recipe['XP Reward'])
  next = xpApplied.save

  const remaining = save.productionQuantityRemaining - 1
  const outputItem = db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])
  const outputName = outputItem?.['Display Name'] ?? recipe['Display Name']
  const xpReward = summarizeXpReward(
    db,
    next,
    recipe['Skill ID'],
    recipe['XP Reward'],
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

  if (remaining <= 0) {
    return {
      save: clearProductionSave({
        ...next,
        currentActivityId: null,
        activityStartedAt: null,
      }),
      finishedQueue: true,
      xpGained: recipe['XP Reward'],
      outputName,
      outputQty,
      reward,
    }
  }

  const startedAt = new Date(nowMs).toISOString()
  const cleared = clearActivePotionEffect({
    ...next,
    productionQuantityRemaining: remaining,
  })
  const potion = tryConsumePotionForScope(db, cleared, 'one_standard_production_action')
  const baseDurationMs = recipe['Base Duration Seconds'] * 1000
  const durationMs = applyPotionDurationMs(baseDurationMs, potion.effect)
  return {
    save: {
      ...potion.save,
      productionQuantityRemaining: remaining,
      currentActionId: recipe['Action ID'],
      actionStartedAt: startedAt,
      actionDurationMs: durationMs,
    },
    finishedQueue: false,
    xpGained: recipe['XP Reward'],
    outputName,
    outputQty,
    reward,
  }
}

/** Advance a production queue by elapsed offline/online time. */
export function resolveProductionProgress(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { save: PlayerSave; craftsCompleted: number; messages: string[]; activityMs: number } {
  let current = save
  let craftsCompleted = 0
  let activityMs = 0
  /** Aggregate identical outputs so AFK summaries show one line per item. */
  const craftTotals = new Map<string, { qty: number; xp: number }>()
  const craftOrder: string[] = []

  while (
    current.productionRecipeId &&
    current.productionQuantityRemaining &&
    current.actionStartedAt &&
    current.actionDurationMs
  ) {
    const durationMs = current.actionDurationMs
    const due = Date.parse(current.actionStartedAt) + durationMs
    if (due > nowMs) break
    const completed = completeProductionCraft(db, current, due)
    if (!completed) break
    current = completed.save
    craftsCompleted += 1
    activityMs += durationMs
    const existing = craftTotals.get(completed.outputName)
    if (!existing) {
      craftOrder.push(completed.outputName)
      craftTotals.set(completed.outputName, {
        qty: completed.outputQty,
        xp: completed.xpGained,
      })
    } else {
      existing.qty += completed.outputQty
      existing.xp += completed.xpGained
    }
    if (completed.finishedQueue) break
  }

  const messages = craftOrder.map((name) => {
    const total = craftTotals.get(name)!
    return `Crafted ${total.qty} ${name} (+${total.xp} XP)`
  })

  return { save: current, craftsCompleted, messages, activityMs }
}
