import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

export const KINGSWOODS_LOCATION_ID = 'LOC-0008'
export const SLING_ITEM_ID = 'ITEM-0109'
export const KINGSWOODS_SLING_FOUND_MESSAGE = 'You found a Sling among the trees.'

export function saveOwnsSling(save: PlayerSave): boolean {
  if (save.inventory.some((stack) => stack.itemId === SLING_ITEM_ID)) return true
  return Object.values(save.equipment.slots ?? {}).some((stack) => stack?.itemId === SLING_ITEM_ID)
}

export interface KingswoodsSlingGrant {
  save: PlayerSave
  granted: boolean
  message: string | null
}

/** First visit to the Kingswoods grants a Sling once, if the bag has room. */
export function maybeGrantKingswoodsSling(
  db: GameDatabase,
  save: PlayerSave,
): KingswoodsSlingGrant {
  if (save.currentLocationId !== KINGSWOODS_LOCATION_ID) {
    return { save, granted: false, message: null }
  }
  if (save.claimedKingswoodsSling) {
    return { save, granted: false, message: null }
  }
  if (saveOwnsSling(save)) {
    return { save: { ...save, claimedKingswoodsSling: true }, granted: false, message: null }
  }
  const added = addItemToInventoryExact(save, SLING_ITEM_ID, 1)
  if (!added.ok) {
    return { save, granted: false, message: null }
  }
  const itemName =
    db.Items.find((item) => item['Item ID'] === SLING_ITEM_ID)?.['Display Name'] ?? 'Sling'
  return {
    save: { ...added.save, claimedKingswoodsSling: true },
    granted: true,
    message: `You found a ${itemName} among the trees.`,
  }
}
