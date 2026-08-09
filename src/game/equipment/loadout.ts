import type { GameDatabase } from '../data/types'
import type { EquippedStack, PlayerSave } from '../save/types'
import { addItemToInventory } from '../activity/rewards'

export const FOOD_SLOT_ID = 'SLOT-0011'

export function slotStack(save: PlayerSave, slotId: string): EquippedStack | null {
  return save.equipment.slots[slotId] ?? null
}

export function slotItemId(save: PlayerSave, slotId: string): string | null {
  return slotStack(save, slotId)?.itemId ?? null
}

export function isFoodSlot(slotId: string): boolean {
  return slotId === FOOD_SLOT_ID
}

function removeItemQuantity(
  save: PlayerSave,
  itemId: string,
  quantity: number,
): PlayerSave {
  if (quantity <= 0) return save
  let remaining = quantity
  const inventory = save.inventory
    .map((stack) => {
      if (stack.itemId !== itemId || remaining <= 0) return { ...stack }
      const take = Math.min(stack.quantity, remaining)
      remaining -= take
      return { ...stack, quantity: stack.quantity - take }
    })
    .filter((stack) => stack.quantity > 0)
  return { ...save, inventory }
}

function setSlot(save: PlayerSave, slotId: string, stack: EquippedStack | null): PlayerSave {
  return {
    ...save,
    equipment: {
      ...save.equipment,
      slots: { ...save.equipment.slots, [slotId]: stack },
    },
  }
}

/** Unequip a slot, returning any equipped stack to inventory. */
export function unequipSlot(save: PlayerSave, slotId: string): PlayerSave {
  const equipped = slotStack(save, slotId)
  let next = setSlot(save, slotId, null)
  if (equipped && equipped.quantity > 0) {
    next = addItemToInventory(next, equipped.itemId, equipped.quantity)
  }
  return next
}

/**
 * Equip an inventory item into its equipment slot.
 * Food: moves the entire inventory stack into the food slot (any quantity).
 * Other gear: moves one item into the slot.
 */
export function equipItemFromInventory(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
): PlayerSave {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  const slotId = equipment?.['Slot ID']
  if (!slotId) return save

  const invStack = save.inventory.find((entry) => entry.itemId === itemId)
  if (!invStack || invStack.quantity <= 0) return save

  let next = save
  const current = slotStack(next, slotId)

  if (isFoodSlot(slotId)) {
    const moveQty = invStack.quantity
    if (current && current.itemId !== itemId) {
      next = unequipSlot(next, slotId)
    }
    const existingQty = current?.itemId === itemId ? current.quantity : 0
    next = removeItemQuantity(next, itemId, moveQty)
    return setSlot(next, slotId, { itemId, quantity: existingQty + moveQty })
  }

  if (current) {
    next = unequipSlot(next, slotId)
  }
  next = removeItemQuantity(next, itemId, 1)
  return setSlot(next, slotId, { itemId, quantity: 1 })
}

/** Place a stack directly into a slot (demo aids / migrations). Removes matching inventory. */
export function equipStackToSlot(
  save: PlayerSave,
  slotId: string,
  itemId: string,
  quantity: number,
): PlayerSave {
  if (quantity <= 0) return unequipSlot(save, slotId)
  let next = unequipSlot(save, slotId)
  next = removeItemQuantity(next, itemId, quantity)
  // If items were not fully in inventory, still equip the requested stack.
  return setSlot(next, slotId, { itemId, quantity })
}
