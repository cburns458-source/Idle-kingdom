import type { EquipmentRow, GameDatabase } from '../data/types'
import { WEAPON_TOOL_SLOT_ID, type EquippedStack, type PlayerSave } from '../save/types'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'
import { canFitItemQuantity } from '../inventory/capacity'
import { firstEmptySpellSlot, isSpellEquipment, isSpellSlotId } from '../spells/spells'
import { TEMPLE_LOCATION_ID } from '../world/blessing'

export const FOOD_SLOT_ID = 'SLOT-0011'
export const POTION_SLOT_ID = 'SLOT-0012'
export const OFFHAND_SLOT_ID = 'SLOT-0002'
export { WEAPON_TOOL_SLOT_ID }

export function isDaggerItem(db: GameDatabase, itemId: string): boolean {
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  if (!item) return false
  if ((item.Subtype ?? '').toLowerCase() === 'dagger') return true
  const key = (item['Internal Key'] ?? '').toLowerCase()
  const name = (item['Display Name'] ?? '').toLowerCase()
  return key.includes('dagger') || /\bdagger\b/.test(name)
}

function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

export function itemHasCapability(db: GameDatabase, itemId: string, tag: string): boolean {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  return capabilityTags(equipment?.['Capabilities / Effects']).includes(tag.toLowerCase())
}

export function isTwoHandedItem(db: GameDatabase, itemId: string): boolean {
  return itemHasCapability(db, itemId, 'two_handed')
}

export type EquipResult =
  | { ok: true; save: PlayerSave; warning?: string }
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

/**
 * Why the Temple will not let this slot be filled, or null anywhere else.
 *
 * The monks train bare-handed, so nothing goes in either hand while the player
 * stands on their ground. Gear worn on arrival is left alone: only reaching for
 * something new is refused.
 */
export function templeHandsRefusal(save: PlayerSave, slotId: string): string | null {
  if (save.currentLocationId !== TEMPLE_LOCATION_ID) return null
  if (slotId !== WEAPON_TOOL_SLOT_ID && slotId !== OFFHAND_SLOT_ID) return null
  return 'The monks keep your hands empty at the Temple.'
}

/**
 * Unequip a slot, returning any equipped stack to inventory.
 * Blocked (not performed) when the bag has no room for the returned item, so
 * gear is never silently destroyed.
 */
export function unequipSlot(save: PlayerSave, slotId: string): EquipResult {
  const equipped = slotStack(save, slotId)
  if (!equipped || equipped.quantity <= 0) {
    return { ok: true, save: setSlot(save, slotId, null) }
  }
  const favorite = equipped.favorite === true
  if (
    !canFitItemQuantity(
      save,
      equipped.itemId,
      equipped.quantity,
      equipped.enchantmentId ?? null,
      favorite,
    )
  ) {
    return { ok: false, reason: 'Not enough inventory space to unequip that item.' }
  }
  const next = addItemToInventory(
    setSlot(save, slotId, null),
    equipped.itemId,
    equipped.quantity,
    equipped.enchantmentId ?? null,
    favorite,
  )
  return { ok: true, save: next }
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

  // Ahead of the skill requirement: standing at the Temple is the reason that
  // matters, and it applies to gear the player is otherwise qualified for.
  // A dagger rerouted to the off-hand is covered too, since both hands are shut.
  const templeRefusal = templeHandsRefusal(save, equipment['Slot ID'])
  if (templeRefusal) {
    return { ok: false, reason: templeRefusal }
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
  } else if (isDaggerItem(db, itemId)) {
    // Daggers equip to the off-hand only (replacing a shield). Dual-wielding two
    // daggers is not supported yet. A two-hander in the main hand is cleared
    // later, the same way a shield is.
    slotId = OFFHAND_SLOT_ID
    const mainhandId = slotItemId(save, WEAPON_TOOL_SLOT_ID)
    if (mainhandId && isDaggerItem(db, mainhandId)) {
      return {
        ok: false,
        reason: 'Unequip your main-hand dagger before equipping an off-hand dagger.',
      }
    }
  }

  let next = save
  const current = slotStack(next, slotId)
  const enchantmentId = invStack.enchantmentId ?? null
  const favorite = invStack.favorite === true

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
    const swappingItem = current && (current.itemId !== itemId || current.enchantmentId)
    if (swappingItem) {
      // Remove the incoming stack first so unequipping the outgoing one can
      // reuse the slot it frees up, instead of over-conservatively rejecting
      // a same-size swap.
      next = removeInventoryAtIndex(next, index, moveQty)
      const unequipped = unequipSlot(next, slotId)
      if (!unequipped.ok) return unequipped
      next = unequipped.save
      return {
        ok: true,
        save: setSlot(next, slotId, {
          itemId,
          quantity: moveQty,
          ...(favorite ? { favorite: true } : {}),
        }),
      }
    }
    const existingQty =
      current?.itemId === itemId && !current.enchantmentId ? current.quantity : 0
    const keepFavorite = favorite || current?.favorite === true
    next = removeInventoryAtIndex(next, index, moveQty)
    return {
      ok: true,
      save: setSlot(next, slotId, {
        itemId,
        quantity: existingQty + moveQty,
        ...(keepFavorite ? { favorite: true } : {}),
      }),
    }
  }

  if (current) {
    // Remove the incoming item first so unequipping the outgoing one can
    // reuse the slot it frees up, instead of over-conservatively rejecting
    // a same-size swap.
    next = removeInventoryAtIndex(next, index, 1)
    const unequipped = unequipSlot(next, slotId)
    if (!unequipped.ok) return unequipped
    next = unequipped.save
  } else {
    next = removeInventoryAtIndex(next, index, 1)
  }

  // Two-handed weapons occupy both hands. Equipping one clears the off-hand;
  // equipping an off-hand item while a two-hander is worn clears the main hand.
  // Either extra unequip can fail if the bag is full, which refuses the whole
  // equip so gear is never destroyed.
  if (isTwoHandedItem(db, itemId) && slotId === WEAPON_TOOL_SLOT_ID) {
    const cleared = unequipSlot(next, OFFHAND_SLOT_ID)
    if (!cleared.ok) return cleared
    next = cleared.save
  } else if (slotId === OFFHAND_SLOT_ID) {
    const mainhandId = slotItemId(next, WEAPON_TOOL_SLOT_ID)
    if (mainhandId && isTwoHandedItem(db, mainhandId)) {
      const cleared = unequipSlot(next, WEAPON_TOOL_SLOT_ID)
      if (!cleared.ok) return cleared
      next = cleared.save
    }
  }

  return {
    ok: true,
    save: setSlot(next, slotId, {
      itemId,
      quantity: 1,
      ...(enchantmentId ? { enchantmentId } : {}),
      ...(favorite ? { favorite: true } : {}),
    }),
  }
}

/**
 * Place a stack directly into a slot (demo aids / migrations). Removes matching inventory.
 * Unlike the player-facing equip flow, this force-set helper always proceeds
 * (falling back to the pre-unequip save if the bag has no room) since it is
 * only used for test/migration setup, not reachable from normal play.
 */
export function equipStackToSlot(
  save: PlayerSave,
  slotId: string,
  itemId: string,
  quantity: number,
): PlayerSave {
  if (quantity <= 0) {
    const result = unequipSlot(save, slotId)
    return result.ok ? result.save : save
  }
  const unequipped = unequipSlot(save, slotId)
  let next = unequipped.ok ? unequipped.save : save
  next = removeItemQuantity(next, itemId, quantity)
  return setSlot(next, slotId, { itemId, quantity })
}

function isEquipmentSkillId(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0 && value !== 'None'
}

/** Action-time reduction totals keyed by required and secondary skills. */
export function equippedActionTimeReductionBySkill(
  db: GameDatabase,
  save: PlayerSave,
): Record<string, number> {
  const totals: Record<string, number> = {}
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const row = db.Equipment.find((entry) => entry['Item ID'] === stack.itemId)
    const amount = Number(row?.['Action Time Reduction %'] ?? 0)
    if (amount <= 0) continue
    for (const skillId of [row?.['Required Skill ID'], row?.['Secondary Required Skill ID']]) {
      if (!isEquipmentSkillId(skillId)) continue
      totals[skillId] = (totals[skillId] ?? 0) + amount
    }
  }
  return totals
}

/** Reduction that applies only to actions of this skill. */
export function equippedActionTimeReductionPercent(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string | null | undefined,
): number {
  if (!skillId) return 0
  return Math.max(0, equippedActionTimeReductionBySkill(db, save)[skillId] ?? 0)
}
