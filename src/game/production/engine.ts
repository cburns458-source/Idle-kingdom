import { addItemToInventory } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { removeIngredients } from './inventory'
import {
  facilityIdForActivity,
  getRecipe,
  isCompleteRecipe,
  maxCraftsFromMaterials,
  maxCraftsFromQueueCap,
  recipeIngredients,
} from './recipes'

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
  if (recipe['Facility ID'] !== facilityIdForActivity(db, activityId)) {
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

  const startedAt = new Date(nowMs).toISOString()
  const durationMs = recipe['Base Duration Seconds'] * 1000
  return {
    ok: true,
    save: {
      ...withMaterials,
      currentActivityId: activityId,
      activityStartedAt: withMaterials.activityStartedAt ?? startedAt,
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
): { save: PlayerSave; finishedQueue: boolean; xpGained: number; outputName: string; outputQty: number } | null {
  if (!save.productionRecipeId || !save.productionQuantityRemaining) return null
  const recipe = getRecipe(db, save.productionRecipeId)
  if (!recipe) return null

  const outputQty = recipe['Output Quantity']
  let next = addItemToInventory(save, recipe['Output Item ID'], outputQty)
  const xpApplied = applyXp(next, db, recipe['Skill ID'], recipe['XP Reward'])
  next = xpApplied.save

  const remaining = save.productionQuantityRemaining - 1
  const outputName =
    db.Items.find((item) => item['Item ID'] === recipe['Output Item ID'])?.['Display Name'] ??
    recipe['Display Name']

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
    }
  }

  const startedAt = new Date(nowMs).toISOString()
  return {
    save: {
      ...next,
      productionQuantityRemaining: remaining,
      currentActionId: recipe['Action ID'],
      actionStartedAt: startedAt,
      actionDurationMs: recipe['Base Duration Seconds'] * 1000,
    },
    finishedQueue: false,
    xpGained: recipe['XP Reward'],
    outputName,
    outputQty,
  }
}

/** Advance a production queue by elapsed offline/online time. */
export function resolveProductionProgress(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { save: PlayerSave; craftsCompleted: number; messages: string[] } {
  let current = save
  let craftsCompleted = 0
  const messages: string[] = []

  while (
    current.productionRecipeId &&
    current.productionQuantityRemaining &&
    current.actionStartedAt &&
    current.actionDurationMs
  ) {
    const due = Date.parse(current.actionStartedAt) + current.actionDurationMs
    if (due > nowMs) break
    const completed = completeProductionCraft(db, current, due)
    if (!completed) break
    current = completed.save
    craftsCompleted += 1
    messages.push(
      `Crafted ${completed.outputQty} ${completed.outputName} (+${completed.xpGained} XP)`,
    )
    if (completed.finishedQueue) break
  }

  return { save: current, craftsCompleted, messages }
}
