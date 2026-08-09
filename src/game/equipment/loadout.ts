import type { EquipmentRow, GameDatabase } from '../data/types'
import type { EquippedStack, PlayerSave } from '../save/types'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'

export const FOOD_SLOT_ID = 'SLOT-0011'
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
 * Food: moves the entire inventory stack into the food slot (any quantity).
 * Other gear: moves one item into the slot.
 */
export function equipItemFromInventory(
  db: GameDatabase,
  save: PlayerSave,
  itemId: string,
): EquipResult {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  const slotId = equipment?.['Slot ID']
  if (!equipment || !slotId) {
    return { ok: false, reason: 'That item cannot be equipped.' }
  }

  const invStack = save.inventory.find((entry) => entry.itemId === itemId)
  if (!invStack || invStack.quantity <= 0) {
    return { ok: false, reason: 'Item is not in inventory.' }
  }

  const requirementFailure = equipmentRequirementFailure(db, save, equipment)
  if (requirementFailure) {
    return { ok: false, reason: requirementFailure }
  }

  let next = save
  const current = slotStack(next, slotId)

  const enchantmentId = invStack.enchantmentId ?? null

  if (isFoodSlot(slotId)) {
    const moveQty = invStack.quantity
    if (current && current.itemId !== itemId) {
      next = unequipSlot(next, slotId)
    }
    const existingQty = current?.itemId === itemId ? current.quantity : 0
    next = removeItemQuantity(next, itemId, moveQty)
    return {
      ok: true,
      save: setSlot(next, slotId, {
        itemId,
        quantity: existingQty + moveQty,
        ...(enchantmentId ? { enchantmentId } : {}),
      }),
    }
  }

  if (current) {
    next = unequipSlot(next, slotId)
  }
  next = removeItemQuantity(next, itemId, 1)
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
