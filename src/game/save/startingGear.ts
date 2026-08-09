import type { EquippedStack, PlayerSave } from './types'
import { STARTING_HUNTING_TOOL_ID, WEAPON_TOOL_SLOT_ID } from './types'

function hasItem(save: PlayerSave, itemId: string): boolean {
  if (save.inventory.some((stack) => stack.itemId === itemId && stack.quantity > 0)) {
    return true
  }
  return Object.values(save.equipment.slots).some(
    (stack) => stack?.itemId === itemId && stack.quantity > 0,
  )
}

/** Ensure the demo hunting Net is owned and equipped when the tool slot is free. */
export function ensureStartingHuntingTool(save: PlayerSave): PlayerSave {
  const slots: Record<string, EquippedStack | null> = { ...save.equipment.slots }
  let inventory = save.inventory.map((stack) => ({ ...stack }))
  const weapon = slots[WEAPON_TOOL_SLOT_ID]

  if (!hasItem({ ...save, inventory, equipment: { slots } }, STARTING_HUNTING_TOOL_ID)) {
    if (!weapon) {
      slots[WEAPON_TOOL_SLOT_ID] = { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }
    } else {
      const existing = inventory.find((stack) => stack.itemId === STARTING_HUNTING_TOOL_ID)
      if (existing) existing.quantity += 1
      else inventory = [...inventory, { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }]
    }
    return {
      ...save,
      inventory,
      equipment: { slots },
    }
  }

  // Already owned: equip it if the weapon/tool slot is empty.
  if (!weapon) {
    const invStack = inventory.find((stack) => stack.itemId === STARTING_HUNTING_TOOL_ID)
    if (invStack && invStack.quantity > 0) {
      inventory = inventory
        .map((stack) =>
          stack.itemId === STARTING_HUNTING_TOOL_ID
            ? { ...stack, quantity: stack.quantity - 1 }
            : stack,
        )
        .filter((stack) => stack.quantity > 0)
      slots[WEAPON_TOOL_SLOT_ID] = { itemId: STARTING_HUNTING_TOOL_ID, quantity: 1 }
      return {
        ...save,
        inventory,
        equipment: { slots },
      }
    }
  }

  return save
}
