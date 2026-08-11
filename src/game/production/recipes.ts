import { configNumber } from '../activity/gathering'
import type { RecipeRow } from '../data/recipeTypes'
import type { ActivityRow, GameDatabase } from '../data/types'
import { canKnowRecipe as recipeKnown } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'
import { requirementsForEntity } from '../activity/requirements'

export interface RecipeIngredient {
  itemId: string
  quantity: number
}

export function isCompleteRecipe(recipe: RecipeRow): boolean {
  if (recipe.Status === 'Needs Data') return false
  if (typeof recipe['Base Duration Seconds'] !== 'number') return false
  if (typeof recipe['XP Reward'] !== 'number') return false
  if (typeof recipe['Output Quantity'] !== 'number') return false
  if (!recipe['Output Item ID'] || !recipe['Facility ID'] || !recipe['Skill ID']) return false
  if (typeof recipe['Proficiency Level'] !== 'number') return false
  return true
}

export function recipeIngredients(recipe: RecipeRow): RecipeIngredient[] {
  const out: RecipeIngredient[] = []
  const pairs: Array<[string | null, number | null]> = [
    [recipe['Ingredient 1 Item ID'], recipe['Ingredient 1 Quantity']],
    [recipe['Ingredient 2 Item ID'], recipe['Ingredient 2 Quantity']],
    [recipe['Ingredient 3 Item ID'], recipe['Ingredient 3 Quantity']],
  ]
  for (const [itemId, quantity] of pairs) {
    if (itemId && typeof quantity === 'number' && quantity > 0) {
      out.push({ itemId, quantity })
    }
  }
  return out
}

export function inventoryCount(save: PlayerSave, itemId: string): number {
  return save.inventory.find((stack) => stack.itemId === itemId)?.quantity ?? 0
}

export function maxCraftsFromMaterials(save: PlayerSave, recipe: RecipeRow): number {
  const ingredients = recipeIngredients(recipe)
  if (ingredients.length === 0) return 0
  let max = Number.POSITIVE_INFINITY
  for (const ingredient of ingredients) {
    max = Math.min(max, Math.floor(inventoryCount(save, ingredient.itemId) / ingredient.quantity))
  }
  return Number.isFinite(max) ? Math.max(0, max) : 0
}

export function queueCapSeconds(db: GameDatabase): number {
  return configNumber(db, 'standard_production_queue_cap', 24) * 3600
}

export function maxCraftsFromQueueCap(db: GameDatabase, recipe: RecipeRow): number {
  const duration = Math.max(1, recipe['Base Duration Seconds'])
  return Math.max(0, Math.floor(queueCapSeconds(db) / duration))
}

/** Hard proficiency gate + knowledge-source unlocks. */
export function canKnowRecipe(save: PlayerSave, db: GameDatabase, recipe: RecipeRow): boolean {
  return recipeKnown(save, db, recipe)
}

/** Castle kitchen shares the Town kitchen recipe book. */
const SHARED_RECIPE_FACILITY_IDS: Record<string, string> = {
  'FAC-0010': 'FAC-0001',
}

export function recipeFacilityIdForLookup(facilityId: string): string {
  return SHARED_RECIPE_FACILITY_IDS[facilityId] ?? facilityId
}

export function recipeMatchesFacility(recipeFacilityId: string, activityFacilityId: string): boolean {
  return recipeFacilityId === recipeFacilityIdForLookup(activityFacilityId)
}

export function facilityIdForActivity(db: GameDatabase, activityId: string): string | null {
  const station = requirementsForEntity(db, 'Activity', activityId).find(
    (row) => row['Requirement Type'] === 'Station',
  )
  const value = station?.['Reference ID / Value']
  return typeof value === 'string' && value.length > 0 ? value : null
}

export function isStandardProductionActivity(db: GameDatabase, activity: ActivityRow): boolean {
  if (activity['Pool ID']) return false
  return facilityIdForActivity(db, activity['Activity ID']) != null
}

export function recipesForActivity(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): RecipeRow[] {
  const facilityId = facilityIdForActivity(db, activityId)
  if (!facilityId) return []
  return db.Recipes.filter(
    (recipe) =>
      isCompleteRecipe(recipe) &&
      recipeMatchesFacility(recipe['Facility ID'], facilityId) &&
      canKnowRecipe(save, db, recipe),
  ).sort((a, b) => a['Proficiency Level'] - b['Proficiency Level'])
}

export function getRecipe(db: GameDatabase, recipeId: string): RecipeRow | undefined {
  return db.Recipes.find((recipe) => recipe['Recipe ID'] === recipeId)
}

export function clampProductionQuantity(
  db: GameDatabase,
  save: PlayerSave,
  recipe: RecipeRow,
  requested: number,
): number {
  const wanted = Math.floor(requested)
  if (wanted <= 0) return 0
  return Math.min(
    wanted,
    maxCraftsFromMaterials(save, recipe),
    maxCraftsFromQueueCap(db, recipe),
  )
}
