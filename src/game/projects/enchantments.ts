import type { EnchantmentRow } from '../data/projectTypes'
import type { GameDatabase } from '../data/types'
import type { EquippedStack, PlayerSave } from '../save/types'
import { getEnchantment } from './projects'

/** Equipped slots that can receive an enchantment based on its Valid Target text. */
export function eligibleEnchantmentSlots(
  db: GameDatabase,
  save: PlayerSave,
  enchantment: EnchantmentRow,
): Array<{ slotId: string; stack: EquippedStack }> {
  const target = (enchantment['Valid Target'] ?? '').toLowerCase()
  const out: Array<{ slotId: string; stack: EquippedStack }> = []

  for (const [slotId, stack] of Object.entries(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    if (!equipment) continue

    const isWeapon =
      typeof equipment['Min Damage'] === 'number' || typeof equipment['Max Damage'] === 'number'
    const isGatheringTool =
      typeof equipment['Action Time Reduction %'] === 'number' ||
      Boolean(equipment['Capabilities / Effects'])

    if (target.includes('weapon') && isWeapon) {
      out.push({ slotId, stack })
      continue
    }
    if (target.includes('gathering') && isGatheringTool) {
      out.push({ slotId, stack })
    }
  }

  return out
}

export function applyEnchantmentToSlot(
  save: PlayerSave,
  slotId: string,
  enchantmentId: string,
): PlayerSave | null {
  const stack = save.equipment.slots[slotId]
  if (!stack) return null
  return {
    ...save,
    equipment: {
      ...save.equipment,
      slots: {
        ...save.equipment.slots,
        [slotId]: { ...stack, enchantmentId },
      },
    },
  }
}

/** Flat damage bonus from equipped enchantments with explicit numeric data. */
export function equippedEnchantmentDamageBonus(db: GameDatabase, save: PlayerSave): number {
  let bonus = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.enchantmentId) continue
    // ENCH-0003: "+20 minimum and maximum Damage"
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
