import { addItemToInventoryExact } from '../activity/rewards'
import { stackIsUnbankableGold } from '../inventory/bank'
import type { InventoryStack, PlayerSave } from '../save/types'
import { withGuildHallDonor } from './achievements'
import {
  goldContributedFromDebtRemaining,
  guildHallDonationCap,
  guildHallGoldChipInCap,
  GUILD_HALL_GOLD_CAP,
  nextGuildHallTier,
  settleGuildHallTiers,
} from './hall'

export const GUILD_HALL_FINISHED_REFUSAL = 'The hall is finished.'
export const GUILD_HALL_UNNEEDED_REFUSAL = 'The hall does not need that.'
export const GUILD_HALL_GOLD_CAP_REFUSAL = 'The gold total is already at its cap.'
export const GUILD_HALL_GOLD_OVERPAY_REFUSAL = 'That would go past the gold cap.'
export const GUILD_HALL_NOT_ENOUGH_GOLD = 'Not enough gold.'

export type GuildHallState = {
  goldContributed: number
  goldContributedBy: Record<string, number>
  /** Members who donated hall materials (gold donors also live on goldContributedBy). */
  donatedBy: Record<string, boolean>
  storehouse: InventoryStack[]
  completedTiers: string[]
  /** Kept in sync with the running total so older rows still load. */
  debtRemaining: number
  debtPaidOff: boolean
  debtPaidBy: Record<string, number>
}

export type GuildHallActionResult =
  | {
      ok: true
      save: PlayerSave
      hall: GuildHallState
      paidOffJustNow?: boolean
      tiersFinishedNow?: string[]
      goldChipped?: number
      donatedItem?: { itemId: string; quantity: number }
    }
  | { ok: false; reason: string }

export function normalizeGuildHallState(hall: Partial<GuildHallState> & { storehouse?: InventoryStack[] }): GuildHallState {
  const goldContributed =
    typeof hall.goldContributed === 'number'
      ? Math.max(0, Math.min(GUILD_HALL_GOLD_CAP, hall.goldContributed))
      : goldContributedFromDebtRemaining(hall.debtRemaining ?? GUILD_HALL_GOLD_CAP)
  const goldContributedBy = hall.goldContributedBy ?? hall.debtPaidBy ?? {}
  const donatedBy = { ...(hall.donatedBy ?? {}) }
  return {
    goldContributed,
    goldContributedBy,
    donatedBy,
    storehouse: hall.storehouse ?? [],
    completedTiers: hall.completedTiers ?? [],
    debtRemaining: Math.max(0, GUILD_HALL_GOLD_CAP - goldContributed),
    debtPaidOff: goldContributed >= GUILD_HALL_GOLD_CAP,
    debtPaidBy: goldContributedBy,
  }
}

export function emptyGuildHallState(): GuildHallState {
  return normalizeGuildHallState({
    goldContributed: 0,
    goldContributedBy: {},
    storehouse: [],
    completedTiers: [],
  })
}

function withSettledHall(hall: GuildHallState, storehouse: InventoryStack[], completedTiers: string[]): GuildHallState {
  return normalizeGuildHallState({
    ...hall,
    storehouse,
    completedTiers,
  })
}

/** Chip gold into the one running total. Refuses a short purse, a full cap, or an overpay. */
export function chipInGuildHallGold(
  hall: GuildHallState,
  userId: string,
  save: PlayerSave,
  amount: number,
): GuildHallActionResult {
  const want = Math.max(0, Math.floor(amount))
  if (want <= 0) return { ok: false, reason: 'Choose an amount.' }
  if (save.gold < want) return { ok: false, reason: GUILD_HALL_NOT_ENOUGH_GOLD }
  const remaining = guildHallGoldChipInCap(hall.goldContributed)
  if (remaining <= 0) {
    return { ok: false, reason: GUILD_HALL_GOLD_CAP_REFUSAL }
  }
  if (want > remaining) {
    return { ok: false, reason: GUILD_HALL_GOLD_OVERPAY_REFUSAL }
  }
  const pay = want
  const goldContributed = hall.goldContributed + pay
  const goldContributedBy = { ...hall.goldContributedBy }
  goldContributedBy[userId] = (goldContributedBy[userId] ?? 0) + pay
  const nextHall = normalizeGuildHallState({
    ...hall,
    goldContributed,
    goldContributedBy,
    donatedBy: withGuildHallDonor(hall.donatedBy, userId),
  })
  const settled = settleGuildHallTiers(nextHall.storehouse, nextHall.completedTiers, nextHall.goldContributed)
  return {
    ok: true,
    save: { ...save, gold: save.gold - pay },
    hall: withSettledHall(nextHall, settled.storehouse, settled.completedTiers),
    paidOffJustNow: nextHall.goldContributed >= GUILD_HALL_GOLD_CAP && hall.goldContributed < GUILD_HALL_GOLD_CAP,
    tiersFinishedNow: settled.finishedNow.map((tier) => tier.id),
    goldChipped: pay,
  }
}

/** @deprecated Chip-in replaced the old hall debt. */
export function payGuildHallDebt(
  hall: GuildHallState,
  userId: string,
  save: PlayerSave,
  amount: number,
): GuildHallActionResult {
  return chipInGuildHallGold(normalizeGuildHallState(hall), userId, save, amount)
}

export function donateToGuildHall(
  hall: GuildHallState,
  save: PlayerSave,
  inventoryIndex: number,
  quantity: number,
  userId?: string,
): GuildHallActionResult {
  const current = normalizeGuildHallState(hall)
  if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
    return { ok: false, reason: 'That stack is not there.' }
  }
  const stack = save.inventory[inventoryIndex]
  if (stackIsUnbankableGold(stack)) {
    return { ok: false, reason: 'Gold stays on you.' }
  }
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }

  const remaining = guildHallDonationCap(current.completedTiers, current.storehouse, stack.itemId)
  if (remaining <= 0) {
    return {
      ok: false,
      reason: nextGuildHallTier(current.completedTiers) == null ? GUILD_HALL_FINISHED_REFUSAL : GUILD_HALL_UNNEEDED_REFUSAL,
    }
  }

  const takenQty = Math.min(want, Math.min(Math.floor(stack.quantity), Math.floor(remaining)))
  const added = addItemToInventoryExact(
    { ...save, inventory: current.storehouse },
    stack.itemId,
    takenQty,
    stack.enchantmentId ?? null,
    stack.favorite ?? false,
  )
  if (!added.ok) {
    return { ok: false, reason: added.reason }
  }

  const nextInventory = [...save.inventory]
  if (takenQty >= stack.quantity) nextInventory.splice(inventoryIndex, 1)
  else nextInventory[inventoryIndex] = { ...stack, quantity: stack.quantity - takenQty }

  const settled = settleGuildHallTiers(added.save.inventory, current.completedTiers, current.goldContributed)
  const donatedHall = withSettledHall(
    { ...current, donatedBy: withGuildHallDonor(current.donatedBy, userId) },
    settled.storehouse,
    settled.completedTiers,
  )
  return {
    ok: true,
    save: { ...save, inventory: nextInventory },
    hall: donatedHall,
    tiersFinishedNow: settled.finishedNow.map((tier) => tier.id),
    donatedItem: { itemId: stack.itemId, quantity: takenQty },
  }
}

export function withdrawFromGuildHall(
  hall: GuildHallState,
  save: PlayerSave,
  storehouseIndex: number,
  quantity: number,
): GuildHallActionResult {
  const current = normalizeGuildHallState(hall)
  if (storehouseIndex < 0 || storehouseIndex >= current.storehouse.length) {
    return { ok: false, reason: 'That stack is not there.' }
  }
  const stack = current.storehouse[storehouseIndex]
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }
  const takenQty = Math.min(want, Math.floor(stack.quantity))
  const added = addItemToInventoryExact(save, stack.itemId, takenQty, stack.enchantmentId ?? null, false)
  if (!added.ok) return { ok: false, reason: added.reason }

  const nextStore = [...current.storehouse]
  if (takenQty >= stack.quantity) nextStore.splice(storehouseIndex, 1)
  else nextStore[storehouseIndex] = { ...stack, quantity: stack.quantity - takenQty }

  return {
    ok: true,
    save: added.save,
    hall: withSettledHall(current, nextStore, current.completedTiers),
  }
}
