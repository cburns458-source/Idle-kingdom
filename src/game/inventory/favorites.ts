import type { EquippedStack, InventoryStack, PlayerSave } from '../save/types'

export function isFavoriteStack(
  stack: InventoryStack | EquippedStack | null | undefined,
): boolean {
  return stack?.favorite === true
}

/** Favorites first; otherwise preserve relative order (stable sort). */
export function sortInventoryFavoritesFirst(save: PlayerSave): PlayerSave {
  const inventory = save.inventory
    .map((stack, index) => ({ stack, index }))
    .sort((a, b) => {
      const af = isFavoriteStack(a.stack) ? 0 : 1
      const bf = isFavoriteStack(b.stack) ? 0 : 1
      if (af !== bf) return af - bf
      return a.index - b.index
    })
    .map((entry) => entry.stack)
  return { ...save, inventory }
}

export function toggleInventoryFavorite(
  save: PlayerSave,
  index: number,
): PlayerSave | null {
  const stack = save.inventory[index]
  if (!stack) return null
  const inventory = save.inventory.map((entry, i) => {
    if (i !== index) return entry
    if (isFavoriteStack(entry)) {
      const { favorite: _removed, ...rest } = entry
      return rest
    }
    return { ...entry, favorite: true }
  })
  return sortInventoryFavoritesFirst({ ...save, inventory })
}
