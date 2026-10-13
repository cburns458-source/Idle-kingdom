/**
 * All-or-nothing room checks for rewards (dialogue `grant_item`, legacy quest
 * rewards, the bribe purse). A reward that does not fully fit is refused with
 * `no_room` and nothing is granted.
 */

import { addItemsToInventory } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { INVENTORY_SLOT_LIMIT, inventorySlotsFree, mergeableStackIndex } from './capacity'
import { isGoldCurrencyItem } from './gold'

export type RewardFailureCode = 'no_room'

export type NoRoomStackReason = 'stack_full'

export type NoRoomTarget = 'bank'

export interface NoRoom {
  /** New slots the grants need; stacks already in the container cost none. */
  slotsNeeded?: number
  slotsFree?: number
  /** Set when a mergeable stack is at cap and free slots would not help. */
  reason?: NoRoomStackReason
  /** Which container is full. Omitted for the bag. */
  target?: NoRoomTarget
  /**
   * NPC make-room line. Set only on dialogue `no_room` when the choice has a
   * `No Room Line`. Shop, bank, and mail refusals leave this unset.
   */
  npcLine?: string
}

export interface ItemGrant {
  itemId: string
  quantity: number
  enchantmentId?: string | null
}

/** New slots [grants] need: one per distinct unenchanted non-gold pile, or one per enchanted item. */
export function slotsNeededForGrants(
  db: GameDatabase | undefined,
  save: PlayerSave,
  grants: readonly ItemGrant[],
): number {
  const seen = new Set<string>()
  let needed = 0
  for (const grant of grants) {
    if (grant.quantity <= 0) continue
    const enchantmentId = grant.enchantmentId ?? null
    if (isGoldCurrencyItem(grant.itemId, db) && !enchantmentId) continue
    if (enchantmentId) {
      needed += Math.floor(grant.quantity)
      continue
    }
    if (seen.has(grant.itemId)) continue
    seen.add(grant.itemId)
    if (mergeableStackIndex(save.inventory, grant.itemId, enchantmentId) >= 0) continue
    needed += 1
  }
  return needed
}

/** New bag slots [itemIds] need against [save]: one per distinct non-gold item without a pile to grow. */
export function slotsNeededForItems(
  db: GameDatabase | undefined,
  save: PlayerSave,
  itemIds: readonly string[],
): number {
  return slotsNeededForGrants(
    db,
    save,
    itemIds.map((itemId) => ({ itemId, quantity: 1 })),
  )
}

/** Human-readable refusal for a `no_room` payload. */
export function noRoomReason(noRoom: NoRoom): string {
  if (noRoom.reason === 'stack_full') {
    return 'That stack cannot hold more of this item.'
  }
  const slotsNeeded = noRoom.slotsNeeded ?? 1
  const slotsFree = noRoom.slotsFree ?? 0
  const short = Math.max(1, slotsNeeded - slotsFree)
  if (noRoom.target === 'bank') {
    return `Your bank is full. Make room for ${short} slot${short === 1 ? '' : 's'} and try again.`
  }
  return `No room in your bag. Free ${short} slot${short === 1 ? '' : 's'} and try again.`
}

function noRoomFromFit(fits: boolean, slotsNeeded: number, slotsFree: number): NoRoom {
  if (!fits && slotsNeeded === 0 && slotsFree > 0) {
    return { reason: 'stack_full' }
  }
  return {
    slotsNeeded: fits ? slotsNeeded : Math.max(1, slotsNeeded),
    slotsFree,
  }
}

/** Whether every grant fits in the bag together, added in order on a copy of [save]. */
export function rewardsFit(
  db: GameDatabase | undefined,
  save: PlayerSave,
  grants: readonly ItemGrant[],
  slotLimit: number = INVENTORY_SLOT_LIMIT,
): { fits: boolean } & NoRoom {
  const wanted = grants.filter((grant) => grant.quantity > 0)
  let working = save
  let fits = true
  for (const grant of wanted) {
    const added = addItemsToInventory(
      working,
      grant.itemId,
      grant.quantity,
      grant.enchantmentId ?? null,
      false,
      db,
      slotLimit,
    )
    if (added.added < Math.floor(grant.quantity)) {
      fits = false
      break
    }
    working = added.save
  }
  const slotsNeeded = slotsNeededForGrants(db, save, wanted)
  const slotsFree = inventorySlotsFree(save, slotLimit)
  return { fits, ...noRoomFromFit(fits, slotsNeeded, slotsFree) }
}

/**
 * `null` when every grant fits together; otherwise the `no_room` counts for
 * the whole list. Paid and claimed paths use this before changing any state.
 */
/** The `no_room` fields only — never `fits` from [rewardsFit]. */
export function noRoomPayload(noRoom: NoRoom): NoRoom {
  if (noRoom.reason === 'stack_full') return { reason: 'stack_full' }
  const payload: NoRoom = {
    slotsNeeded: noRoom.slotsNeeded,
    slotsFree: noRoom.slotsFree,
  }
  if (noRoom.target) payload.target = noRoom.target
  return payload
}

export function noRoomFor(
  save: PlayerSave,
  grants: readonly ItemGrant[],
  db?: GameDatabase,
  slotLimit: number = INVENTORY_SLOT_LIMIT,
): NoRoom | null {
  const fit = rewardsFit(db, save, grants, slotLimit)
  if (fit.fits) return null
  return noRoomPayload(fit)
}

/** Shared `{ok:false, code:'no_room'}` refusal used by shop, bank, and mail. */
export function noRoomRefusal(noRoom: NoRoom): {
  ok: false
  reason: string
  code: RewardFailureCode
  noRoom: NoRoom
} {
  return { ok: false, reason: noRoomReason(noRoom), code: 'no_room', noRoom }
}
