import type { PlayerSave } from '../save/types'

/** Remove bag stacks at the given inventory indexes. Equipped items are untouched. */
export function destroyInventoryIndexes(save: PlayerSave, indexes: Iterable<number>): PlayerSave {
  const remove = new Set(
    [...indexes].filter((index) => Number.isInteger(index) && index >= 0 && index < save.inventory.length),
  )
  if (remove.size === 0) return save
  return {
    ...save,
    inventory: save.inventory.filter((_, index) => !remove.has(index)),
  }
}
