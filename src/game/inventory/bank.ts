import type { GameDatabase, LocationRow, ActivityRow } from '../data/types'
import type { InventoryStack, PlayerSave } from '../save/types'
import { addItemToInventoryExact } from '../activity/rewards'
import { canFitItemQuantity, inventorySlotsFree, INVENTORY_SLOT_LIMIT } from './capacity'
import { isGoldCurrencyItem } from './gold'

/** Dedicated bank nodes (Town, Citadel) plus any future `*_bank` location. */
export const BANK_LOCATION_IDS = ['LOC-0034', 'LOC-0035'] as const

/** Pool shared by every bank's "Pick a deposit box" thievery activity. */
export const DEPOSIT_BOX_POOL_ID = 'POOL-0047'

export function locationHasBank(location: LocationRow | undefined | null): boolean {
  if (!location) return false
  if ((BANK_LOCATION_IDS as readonly string[]).includes(location['Location ID'])) return true
  const key = (location['Internal Key'] ?? '').trim().toLowerCase()
  if (key.endsWith('_bank') || key === 'bank') return true
  return /\bbank\b/i.test(location['Display Name'] ?? '')
}

function activitySerial(activityId: string): number {
  const match = /^ACT-(\d+)$/.exec(activityId)
  return match ? Number(match[1]) : 0
}

/**
 * Ensures every bank location has a deposit-box thievery activity.
 * Current Town/Citadel banks already ship with ACT-0059 / ACT-0060; future bank
 * locations get a cloned activity so authors only need to add the location.
 */
export function withBankDepositBoxActivities(db: GameDatabase): GameDatabase {
  const template = db.Activities.find((row) => row['Pool ID'] === DEPOSIT_BOX_POOL_ID)
  if (!template) return db

  const covered = new Set(
    db.Activities.filter((row) => row['Pool ID'] === DEPOSIT_BOX_POOL_ID).map(
      (row) => row['Location ID'],
    ),
  )

  let nextSerial = 0
  for (const row of db.Activities) {
    nextSerial = Math.max(nextSerial, activitySerial(row['Activity ID']))
  }

  const extras: ActivityRow[] = []
  for (const location of db.Locations) {
    if (!locationHasBank(location)) continue
    if (covered.has(location['Location ID'])) continue
    nextSerial += 1
    const id = `ACT-${String(nextSerial).padStart(4, '0')}`
    extras.push({
      ...template,
      'Activity ID': id,
      'Internal Key': `pick_deposit_box_${location['Location ID'].toLowerCase()}`,
      'Location ID': location['Location ID'],
    })
  }

  if (extras.length === 0) return db
  return { ...db, Activities: [...db.Activities, ...extras] }
}

export function bankStacks(save: Pick<PlayerSave, 'bank'>): InventoryStack[] {
  return save.bank ?? []
}

/** Gold currency cannot be deposited; enchanted gold stacks still take a slot. */
export function stackIsUnbankableGold(
  stack: Pick<InventoryStack, 'itemId' | 'enchantmentId'>,
  db?: GameDatabase,
): boolean {
  return isGoldCurrencyItem(stack.itemId, db) && !stack.enchantmentId
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
