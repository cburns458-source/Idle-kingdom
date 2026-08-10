import type { EquipmentRow, GameDatabase } from '../data/types'
import type { EquippedStack, PlayerSave } from '../save/types'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'
import { firstEmptySpellSlot, isSpellEquipment, isSpellSlotId } from '../spells/spells'

export const FOOD_SLOT_ID = 'SLOT-0011'
export const POTION_SLOT_ID = 'SLOT-0012'
export const WEAPON_TOOL_SLOT_ID = 'SLOT-0001'

export type EquipResult =
  | { ok: true; save: PlayerSave }
  | { ok: false; reason: string }

export function slotStack(save: PlayerSave, slotId: string): EquippedStack | null {
  return save.equipment.slots[slotId] ?? null
}

export function slotItemId(save: PlayerSave, slotId: string): string | null {
  return slotStack(save, slotId)?.itemId ?? null
}

export function isFoodSlot(slotId: string): boolean {
  return slotId === FOOD_SLOT_ID
}

export function isPotionSlot(slotId: string): boolean {
  return slotId === POTION_SLOT_ID
}

/** Food and potion slots hold full stacks (any quantity). */
export function isStackableConsumableSlot(slotId: string): boolean {
  return isFoodSlot(slotId) || isPotionSlot(slotId)
}

function removeItemQuantity(
  save: PlayerSave,
  itemId: string,
  quantity: number,
  enchantmentId: string | null = null,
): PlayerSave {
  if (quantity <= 0) return save
  let remaining = quantity
  const inventory = save.inventory
    .map((stack) => {
      if (stack.itemId !== itemId || remaining <= 0) return { ...stack }
      if ((stack.enchantmentId ?? null) !== enchantmentId) return { ...stack }
      const take = Math.min(stack.quantity, remaining)
      remaining -= take
      return { ...stack, quantity: stack.quantity - take }
    })
    .filter((stack) => stack.quantity > 0)
  return { ...save, inventory }
}

function removeInventoryAtIndex(
  save: PlayerSave,
  index: number,
  quantity: number,
): PlayerSave {
  if (quantity <= 0) return save
  const inventory = save.inventory.map((stack) => ({ ...stack }))
  const stack = inventory[index]
  if (!stack || stack.quantity < quantity) return save
  stack.quantity -= quantity
  return {
    ...save,
    inventory: inventory.filter((entry) => entry.quantity > 0),
  }
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

function skillRequirementFailure(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string | null | undefined,
  requiredLevel: number | null | undefined,
): string | null {
  if (!skillId || requiredLevel == null) return null
  const progress = getSkillProgress(save, skillId)
  if (progress.level >= requiredLevel) return null
  const skillName =
    db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId
  return `Requires ${skillName} level ${requiredLevel}`
}

export function equipmentRequirementFailure(
  db: GameDatabase,
  save: PlayerSave,
  equipment: EquipmentRow,
): string | null {
  return (
    skillRequirementFailure(
      db,
      save,
      equipment['Required Skill ID'],
      equipment['Required Level'],
    ) ??
    skillRequirementFailure(
      db,
      save,
      equipment['Secondary Required Skill ID'],
      equipment['Secondary Required Level'],
    )
  )
}

/** Unequip a slot, returning any equipped stack to inventory. */
export function unequipSlot(save: PlayerSave, slotId: string): PlayerSave {
  const equipped = slotStack(save, slotId)
  let next = setSlot(save, slotId, null)
  if (equipped && equipped.quantity > 0) {
    next = addItemToInventory(
      next,
      equipped.itemId,
      equipped.quantity,
      equipped.enchantmentId ?? null,
    )
  }
  return next
}

/**
 * Equip an inventory item into its equipment slot.
 * Food / potion: moves the entire inventory stack into the slot (any quantity).
 * Other gear: moves one item into the slot.
 */
export function equipItemFromInventory(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
): EquipResult {
  const index = save.inventory.findIndex(
    (entry) => entry.itemId === itemId && !entry.enchantmentId,
  )
  const fallback = save.inventory.findIndex((entry) => entry.itemId === itemId)
  return equipInventoryIndex(db, save, index >= 0 ? index : fallback)
}

/** Equip a specific inventory stack index (preserves enchantments). */
export function equipInventoryIndex(
  db: GameDatabase,
  save: PlayerSave,
  index: number,
): EquipResult {
  const invStack = save.inventory[index]
  if (!invStack || invStack.quantity <= 0) {
    return { ok: false, reason: 'Item is not in inventory.' }
  }
  const itemId = invStack.itemId
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  if (!equipment?.['Slot ID']) {
    return { ok: false, reason: 'That item cannot be equipped.' }
  }

  const requirementFailure = equipmentRequirementFailure(db, save, equipment)
  if (requirementFailure) {
    return { ok: false, reason: requirementFailure }
  }

  // Spells may fill any empty spell slot; duplicates are allowed across slots.
  let slotId = equipment['Slot ID']
  if (isSpellEquipment(equipment) || isSpellSlotId(slotId)) {
    const empty = firstEmptySpellSlot(save)
    if (!empty) {
      return { ok: false, reason: 'All spell slots are full.' }
    }
    slotId = empty
  }

  let next = save
  const current = slotStack(next, slotId)
  const enchantmentId = invStack.enchantmentId ?? null

  if (isStackableConsumableSlot(slotId)) {
    if (enchantmentId) {
      return {
        ok: false,
        reason: isPotionSlot(slotId)
          ? 'Enchanted items cannot fill the potion slot.'
          : 'Enchanted items cannot fill the food slot.',
      }
    }
    const moveQty = invStack.quantity
    if (current && (current.itemId !== itemId || current.enchantmentId)) {
      next = unequipSlot(next, slotId)
    }
    const existingQty =
      current?.itemId === itemId && !current.enchantmentId ? current.quantity : 0
    next = removeInventoryAtIndex(next, index, moveQty)
    return {
      ok: true,
      save: setSlot(next, slotId, { itemId, quantity: existingQty + moveQty }),
    }
  }

  if (current) {
    next = unequipSlot(next, slotId)
    // Index may shift after unequip returns an item to inventory.
    const refreshed = next.inventory.findIndex(
      (entry) =>
        entry.itemId === itemId &&
        (entry.enchantmentId ?? null) === enchantmentId &&
        entry.quantity > 0,
    )
    if (refreshed < 0) return { ok: false, reason: 'Item is not in inventory.' }
    next = removeInventoryAtIndex(next, refreshed, 1)
  } else {
    next = removeInventoryAtIndex(next, index, 1)
  }

  return {
    ok: true,
    save: setSlot(next, slotId, {
      itemId,
      quantity: 1,
      ...(enchantmentId ? { enchantmentId } : {}),
    }),
  }
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
  return setSlot(next, slotId, { itemId, quantity })
}

export function equippedActionTimeReductionPercent(db: GameDatabase, save: PlayerSave): number {
  let total = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const row = db.Equipment.find((entry) => entry['Item ID'] === stack.itemId)
    total += Number(row?.['Action Time Reduction %'] ?? 0)
  }
  return Math.max(0, total)
}
