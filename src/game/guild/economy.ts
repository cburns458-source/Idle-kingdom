import { addItemToInventoryExact } from '../activity/rewards'
import { stackIsUnbankableGold } from '../inventory/bank'
import type { InventoryStack, PlayerSave } from '../save/types'
import {
  guildHallDonationCap,
  nextGuildHallTier,
  settleGuildHallTiers,
} from './hall'

export const GUILD_HALL_FINISHED_REFUSAL = 'The hall is finished.'
export const GUILD_HALL_UNNEEDED_REFUSAL = 'The hall does not need that.'

export type GuildHallState = {
  debtRemaining: number
  debtPaidOff: boolean
  debtPaidBy: Record<string, number>
  storehouse: InventoryStack[]
  completedTiers: string[]
}

export type GuildHallActionResult =
  | { ok: true; save: PlayerSave; hall: GuildHallState; paidOffJustNow?: boolean; tiersFinishedNow?: string[] }
  | { ok: false; reason: string }

export function payGuildHallDebt(
  hall: GuildHallState,
  userId: string,
  save: PlayerSave,
  amount: number,
): GuildHallActionResult {
  const want = Math.max(0, Math.floor(amount))
  if (want <= 0) return { ok: false, reason: 'Choose an amount.' }
  if (save.gold < want) return { ok: false, reason: 'Not enough gold.' }
  if (hall.debtPaidOff || hall.debtRemaining <= 0) {
    return { ok: true, save, hall }
  }

  const pay = Math.min(want, Math.floor(hall.debtRemaining))
  const remaining = hall.debtRemaining - pay
  const paidOff = remaining <= 0
  const paidBy = { ...hall.debtPaidBy }
  paidBy[userId] = (paidBy[userId] ?? 0) + pay
  return {
    ok: true,
    save: { ...save, gold: save.gold - pay },
    hall: {
      ...hall,
      debtRemaining: paidOff ? 0 : remaining,
      debtPaidBy: paidBy,
      debtPaidOff: paidOff,
    },
    paidOffJustNow: paidOff,
  }
}

export function donateToGuildHall(
  hall: GuildHallState,
  save: PlayerSave,
  inventoryIndex: number,
  quantity: number,
): GuildHallActionResult {
  if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
    return { ok: false, reason: 'That stack is not there.' }
  }
  const stack = save.inventory[inventoryIndex]
  if (stackIsUnbankableGold(stack)) {
    return { ok: false, reason: 'Gold stays on you.' }
  }
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }

  const remaining = guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId)
  if (remaining <= 0) {
    return {
      ok: false,
      reason: nextGuildHallTier(hall.completedTiers) == null ? GUILD_HALL_FINISHED_REFUSAL : GUILD_HALL_UNNEEDED_REFUSAL,
    }
  }

  const takenQty = Math.min(want, Math.min(Math.floor(stack.quantity), Math.floor(remaining)))
  const added = addItemToInventoryExact(
    { ...save, inventory: hall.storehouse },
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

  const settled = settleGuildHallTiers(added.save.inventory, hall.completedTiers)
  return {
    ok: true,
    save: { ...save, inventory: nextInventory },
    hall: {
      ...hall,
      storehouse: settled.storehouse,
      completedTiers: settled.completedTiers,
    },
    tiersFinishedNow: settled.finishedNow.map((tier) => tier.id),
  }
}

export function withdrawFromGuildHall(
  hall: GuildHallState,
  save: PlayerSave,
  storehouseIndex: number,
  quantity: number,
): GuildHallActionResult {
  if (storehouseIndex < 0 || storehouseIndex >= hall.storehouse.length) {
    return { ok: false, reason: 'That stack is not there.' }
  }
  const stack = hall.storehouse[storehouseIndex]
  const want = Math.max(0, Math.floor(quantity))
  if (want <= 0) return { ok: false, reason: 'Choose a quantity.' }
  const takenQty = Math.min(want, Math.floor(stack.quantity))
  const added = addItemToInventoryExact(save, stack.itemId, takenQty, stack.enchantmentId ?? null, false)
  if (!added.ok) return { ok: false, reason: added.reason }

  const nextStore = [...hall.storehouse]
  if (takenQty >= stack.quantity) nextStore.splice(storehouseIndex, 1)
  else nextStore[storehouseIndex] = { ...stack, quantity: stack.quantity - takenQty }

  return {
    ok: true,
    save: added.save,
    hall: { ...hall, storehouse: nextStore },
  }
}
