import { addItemToInventory } from '../activity/rewards'
import type { EnchantmentRow } from '../data/projectTypes'
import type { EquipmentRow, GameDatabase } from '../data/types'
import type { EquippedStack, InventoryStack, PlayerSave } from '../save/types'
import { getEnchantment } from './projects'

export type EnchantTarget =
  | { kind: 'equipped'; slotId: string }
  | { kind: 'inventory'; index: number }

export interface EnchantTargetOption {
  id: string
  label: string
  target: EnchantTarget
  preferred: boolean
}

function equipmentMatchesEnchantment(
  equipment: EquipmentRow,
  enchantment: EnchantmentRow,
): boolean {
  const target = (enchantment['Valid Target'] ?? '').toLowerCase()
  const isWeapon =
    typeof equipment['Min Damage'] === 'number' || typeof equipment['Max Damage'] === 'number'
  const isGatheringTool =
    typeof equipment['Action Time Reduction %'] === 'number' ||
    Boolean(equipment['Capabilities / Effects'])

  if (target.includes('weapon') && isWeapon) return true
  if (target.includes('gathering') && isGatheringTool) return true
  return false
}

export function encodeEnchantTarget(target: EnchantTarget): string {
  return target.kind === 'equipped'
    ? `eq:${target.slotId}`
    : `inv:${target.index}`
}

export function decodeEnchantTarget(value: string | null | undefined): EnchantTarget | null {
  if (!value) return null
  if (value.startsWith('eq:')) {
    return { kind: 'equipped', slotId: value.slice(3) }
  }
  if (value.startsWith('inv:')) {
    const index = Number(value.slice(4))
    if (!Number.isInteger(index) || index < 0) return null
    return { kind: 'inventory', index }
  }
  // Legacy: bare slot id from older saves/UI
  if (value.startsWith('SLOT-')) {
    return { kind: 'equipped', slotId: value }
  }
  return null
}

/** Equipped slots and inventory stacks that can receive this enchantment. */
export function eligibleEnchantmentTargets(
  db: GameDatabase,
  save: PlayerSave,
  enchantment: EnchantmentRow,
): EnchantTargetOption[] {
  const out: EnchantTargetOption[] = []

  for (const [slotId, stack] of Object.entries(save.equipment.slots)) {
    if (!stack?.itemId || stack.enchantmentId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    if (!equipment || !equipmentMatchesEnchantment(equipment, enchantment)) continue
    const item = db.Items.find((row) => row['Item ID'] === stack.itemId)
    const slotName =
      db.EquipmentSlots.find((row) => row['Slot ID'] === slotId)?.['Display Name'] ?? slotId
    const target: EnchantTarget = { kind: 'equipped', slotId }
    out.push({
      id: encodeEnchantTarget(target),
      label: `Equipped · ${slotName}: ${item?.['Display Name'] ?? stack.itemId}`,
      target,
      preferred: true,
    })
  }

  save.inventory.forEach((stack, index) => {
    if (!stack.itemId || stack.enchantmentId) return
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    if (!equipment || !equipmentMatchesEnchantment(equipment, enchantment)) return
    const item = db.Items.find((row) => row['Item ID'] === stack.itemId)
    const target: EnchantTarget = { kind: 'inventory', index }
    out.push({
      id: encodeEnchantTarget(target),
      label: `Inventory · ${item?.['Display Name'] ?? stack.itemId}${
        stack.quantity > 1 ? ` ×${stack.quantity}` : ''
      }`,
      target,
      preferred: false,
    })
  })

  return out
}

/** @deprecated use eligibleEnchantmentTargets */
export function eligibleEnchantmentSlots(
  db: GameDatabase,
  save: PlayerSave,
  enchantment: EnchantmentRow,
): Array<{ slotId: string; stack: EquippedStack }> {
  return eligibleEnchantmentTargets(db, save, enchantment)
    .filter((option) => option.target.kind === 'equipped')
    .map((option) => {
      const slotId = (option.target as { kind: 'equipped'; slotId: string }).slotId
      return { slotId, stack: save.equipment.slots[slotId]! }
    })
}

export function applyEnchantmentToTarget(
  save: PlayerSave,
  target: EnchantTarget,
  enchantmentId: string,
): PlayerSave | null {
  if (target.kind === 'equipped') {
    const stack = save.equipment.slots[target.slotId]
    if (!stack || stack.enchantmentId) return null
    // Enchanted gear is unique — keep one enchanted item in the slot.
    if (stack.quantity > 1) {
      const remainder = stack.quantity - 1
      const withEnchantedSlot: PlayerSave = {
        ...save,
        equipment: {
          ...save.equipment,
          slots: {
            ...save.equipment.slots,
            [target.slotId]: { itemId: stack.itemId, quantity: 1, enchantmentId },
          },
        },
      }
      return addItemToInventory(withEnchantedSlot, stack.itemId, remainder, null)
    }
    return {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          [target.slotId]: { ...stack, quantity: 1, enchantmentId },
        },
      },
    }
  }

  const stack = save.inventory[target.index]
  if (!stack || stack.enchantmentId) return null

  const inventory = save.inventory.map((entry) => ({ ...entry }))
  const current = inventory[target.index]
  if (!current) return null

  if (current.quantity > 1) {
    current.quantity -= 1
    inventory.splice(target.index + 1, 0, {
      itemId: current.itemId,
      quantity: 1,
      enchantmentId,
    })
  } else {
    inventory[target.index] = {
      itemId: current.itemId,
      quantity: 1,
      enchantmentId,
    }
  }

  return { ...save, inventory }
}

export function applyEnchantmentToSlot(
  save: PlayerSave,
  slotId: string,
  enchantmentId: string,
): PlayerSave | null {
  return applyEnchantmentToTarget(save, { kind: 'equipped', slotId }, enchantmentId)
}

/** Flat damage bonus from equipped enchantments with explicit numeric data. */
export function equippedEnchantmentDamageBonus(db: GameDatabase, save: PlayerSave): number {
  let bonus = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.enchantmentId) continue
    if (stack.enchantmentId === 'ENCH-0003') bonus += 20
    else {
      const row = getEnchantment(db, stack.enchantmentId)
      if (row?.Effect?.includes('+20 minimum and maximum Damage')) bonus += 20
    }
  }
  return bonus
}

/** Gathering duration multiplier from equipped enchantments (e.g. -2% => 0.98). */
export function equippedEnchantmentGatheringMultiplier(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let multiplier = 1
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.enchantmentId) continue
    if (stack.enchantmentId === 'ENCH-0002') {
      multiplier *= 0.98
      continue
    }
    const row = getEnchantment(db, stack.enchantmentId)
    const match = row?.Effect?.match(/-(\d+(?:\.\d+)?)% eligible Gathering Action duration/i)
    if (match) {
      multiplier *= 1 - Number(match[1]) / 100
    }
  }
  return Math.max(0.01, multiplier)
}

export function enchantmentTooltipLines(
  db: GameDatabase,
  stack: InventoryStack | EquippedStack | null | undefined,
): string[] {
  if (!stack?.enchantmentId) return []
  const row = getEnchantment(db, stack.enchantmentId)
  if (!row) return [`Enchanted (${stack.enchantmentId})`]
  const lines = [row['Display Name']]
  if (row.Effect) lines.push(row.Effect)
  return lines
}
