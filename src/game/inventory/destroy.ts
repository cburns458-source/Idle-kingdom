import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { itemIsTradable } from './tradable'

/** Remove bag stacks at the given inventory indexes. Equipped items are untouched. */
export function destroyInventoryIndexes(
  save: PlayerSave,
  indexes: Iterable<number>,
  db?: GameDatabase,
): PlayerSave {
  const remove = new Set(
    [...indexes].filter((index) => {
      if (!Number.isInteger(index) || index < 0 || index >= save.inventory.length) return false
      const stack = save.inventory[index]
      if (!stack) return false
      if (db && !itemIsTradable(db, stack.itemId)) return false
      return true
    }),
  )
  if (remove.size === 0) return save
  return {
    ...save,
    inventory: save.inventory.filter((_, index) => !remove.has(index)),
  }
}
