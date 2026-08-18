import type { LocationRow } from '../data/types'
import type { InventoryStack, PlayerSave } from '../save/types'
import { addItemToInventoryExact } from '../activity/rewards'
import { canFitItemQuantity, inventorySlotsFree, INVENTORY_SLOT_LIMIT } from './capacity'
import { isGoldCurrencyItem } from './gold'

/** Dedicated bank nodes on the Town and Citadel maps. */
export const BANK_LOCATION_IDS = ['LOC-0034', 'LOC-0035'] as const

export function locationHasBank(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  return (BANK_LOCATION_IDS as readonly string[]).includes(location['Location ID'])
}

export function bankStacks(save: Pick<PlayerSave, 'bank'>): InventoryStack[] {
  return save.bank ?? []
}

/** Gold currency cannot be deposited; enchanted gold stacks still take a slot. */
export function stackIsUnbankableGold(stack: Pick<InventoryStack, 'itemId' | 'enchantmentId'>): boolean {
  return isGoldCurrencyItem(stack.itemId) && !stack.enchantmentId
}

export function bankSlotsFree(save: Pick<PlayerSave, 'bank'>): number {
  return inventorySlotsFree({ inventory: bankStacks(save) })
}

function withBankAsBag(save: PlayerSave): PlayerSave {
  return { ...save, inventory: bankStacks(save) }
}

function restoreBag(original: PlayerSave, banked: PlayerSave): PlayerSave {
  return { ...banked, inventory: original.inventory, bank: banked.inventory }
}

export function canFitInBank(
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
  favorite = false,
): boolean {
  if (stackIsUnbankableGold({ itemId, enchantmentId })) return false
  return canFitItemQuantity(withBankAsBag(save), itemId, quantity, enchantmentId, favorite)
}

function takeFromStacks(
  stacks: InventoryStack[],
  index: number,
  quantity: number,
): { stacks: InventoryStack[]; taken: InventoryStack } | { reason: string } {
  const stack = stacks[index]
  if (!stack) return { reason: 'That stack is not there.' }
  const want = Math.floor(quantity)
  if (want <= 0) return { reason: 'Choose a quantity.' }
  const takenQty = Math.min(want, stack.quantity)
  const next = stacks.slice()
  if (takenQty >= stack.quantity) next.splice(index, 1)
  else next[index] = { ...stack, quantity: stack.quantity - takenQty }
  return {
    stacks: next,
    taken: { ...stack, quantity: takenQty },
  }
}

export type BankMoveResult =
  | { ok: true; save: PlayerSave }
  | { ok: false; reason: string }

function moveStack(
  save: PlayerSave,
  from: InventoryStack[],
  toIsBank: boolean,
  index: number,
  quantity: number,
  fullMessage: string,
): BankMoveResult {
  const taken = takeFromStacks(from, index, quantity)
  if ('reason' in taken) return { ok: false, reason: taken.reason }
  const piece = taken.taken
  if (stackIsUnbankableGold(piece)) {
    return { ok: false, reason: 'Gold cannot be deposited.' }
  }
  const destination = toIsBank
    ? { ...save, inventory: taken.stacks, bank: bankStacks(save) }
    : { ...save, inventory: save.inventory, bank: taken.stacks }
  const target = toIsBank ? withBankAsBag(destination) : { ...destination, inventory: destination.inventory }
  if (
    !canFitItemQuantity(
      target,
      piece.itemId,
      piece.quantity,
      piece.enchantmentId ?? null,
      Boolean(piece.favorite),
    )
  ) {
    return { ok: false, reason: fullMessage }
  }
  if (toIsBank) {
    const added = addItemToInventoryExact(
      withBankAsBag(destination),
      piece.itemId,
      piece.quantity,
      piece.enchantmentId ?? null,
      Boolean(piece.favorite),
    )
    if (!added.ok) return { ok: false, reason: added.reason }
    return { ok: true, save: restoreBag({ ...save, inventory: taken.stacks }, added.save) }
  }
  const added = addItemToInventoryExact(
    { ...destination, inventory: save.inventory },
    piece.itemId,
    piece.quantity,
    piece.enchantmentId ?? null,
    Boolean(piece.favorite),
  )
  if (!added.ok) return { ok: false, reason: added.reason }
  return { ok: true, save: { ...added.save, bank: taken.stacks } }
}

/** Moves a bag stack into the bank. Gold cannot be deposited. */
export function depositToBank(save: PlayerSave, inventoryIndex: number, quantity: number): BankMoveResult {
  return moveStack(
    save,
    save.inventory,
    true,
    inventoryIndex,
    quantity,
    `Bank is full (${INVENTORY_SLOT_LIMIT} slots).`,
  )
}

/** Moves a bank stack back into the bag. */
export function withdrawFromBank(save: PlayerSave, bankIndex: number, quantity: number): BankMoveResult {
  return moveStack(
    save,
    bankStacks(save),
    false,
    bankIndex,
    quantity,
    `Inventory is full (${INVENTORY_SLOT_LIMIT} slots).`,
  )
}
