import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { isAmbientIngredientAt, type RecipeIngredient } from './recipes'

export function removeIngredients(
  db: GameDatabase,
  save: PlayerSave,
  ingredients: RecipeIngredient[],
  crafts: number = 1,
): PlayerSave | null {
  if (crafts <= 0) return save
  let inventory = save.inventory.map((stack) => ({ ...stack }))
  for (const ingredient of ingredients) {
    if (isAmbientIngredientAt(db, save, ingredient.itemId)) continue
    const need = ingredient.quantity * crafts
    const stack = inventory.find((entry) => entry.itemId === ingredient.itemId)
    if (!stack || stack.quantity < need) return null
    stack.quantity -= need
  }
  inventory = inventory.filter((stack) => stack.quantity > 0)
  return { ...save, inventory }
}
