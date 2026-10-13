/**
 * All-or-nothing room checks for rewards (dialogue `grant_item`, legacy quest
 * rewards, the bribe purse). A reward that does not fully fit is refused with
 * `no_room` and nothing is granted.
 */

import { addItemsToInventory } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { inventorySlotsFree, mergeableStackIndex } from './capacity'
import { isGoldCurrencyItem } from './gold'

export type RewardFailureCode = 'no_room'

export interface NoRoom {
  /** New bag slots the grants need; stacks already in the bag cost none. */
  slotsNeeded: number
  slotsFree: number
}

export interface ItemGrant {
  itemId: string
  quantity: number
}

/** New bag slots [itemIds] need against [save]: one per distinct non-gold item without a pile to grow. */
export function slotsNeededForItems(db: GameDatabase, save: PlayerSave, itemIds: readonly string[]): number {
  const seen = new Set<string>()
  let needed = 0
  for (const itemId of itemIds) {
    if (isGoldCurrencyItem(itemId, db) || seen.has(itemId)) continue
    seen.add(itemId)
    if (mergeableStackIndex(save.inventory, itemId) >= 0) continue
    needed += 1
  }
  return needed
}

/** `No room in your bag. Free N slot(s) and try again.` */
export function noRoomReason(noRoom: NoRoom): string {
  const short = Math.max(1, noRoom.slotsNeeded - noRoom.slotsFree)
  return `No room in your bag. Free ${short} slot${short === 1 ? '' : 's'} and try again.`
}

/** Whether every grant fits in the bag together, added in order on a copy of [save]. */
export function rewardsFit(
  db: GameDatabase,
  save: PlayerSave,
  grants: readonly ItemGrant[],
): { fits: boolean } & NoRoom {
  const wanted = grants.filter((grant) => grant.quantity > 0)
  let working = save
  let fits = true
  for (const grant of wanted) {
    const added = addItemsToInventory(working, grant.itemId, grant.quantity, null, false, db)
    if (added.added < Math.floor(grant.quantity)) {
      fits = false
      break
    }
    working = added.save
  }
  const slotsNeeded = slotsNeededForItems(
    db,
    save,
    wanted.map((grant) => grant.itemId),
  )
  return {
    fits,
    slotsNeeded: fits ? slotsNeeded : Math.max(1, slotsNeeded),
    slotsFree: inventorySlotsFree(save),
  }
}
