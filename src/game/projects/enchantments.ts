import { addItemToInventory } from '../activity/rewards'
import type { EnchantmentRow } from '../data/projectTypes'
import type { EquipmentRow, GameDatabase, ItemRow } from '../data/types'
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

function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

/** Combat axes (not hatchets/pickaxes) — weapon enchantments only. */
export function isAxeItem(item: ItemRow | undefined, equipment: EquipmentRow): boolean {
  const subtype = (item?.Subtype ?? '').toLowerCase()
  const key = (item?.['Internal Key'] ?? '').toLowerCase()
  const name = (item?.['Display Name'] ?? '').toLowerCase()
  const caps = capabilityTags(equipment['Capabilities / Effects'])

  if (subtype === 'hatchet' || key.includes('hatchet') || name.includes('hatchet')) return false
  if (subtype === 'pickaxe' || key.includes('pickaxe') || name.includes('pickaxe')) return false
  if (subtype === 'axe') return true
  if (caps.includes('combat_weapon') && caps.includes('woodcutting_tool')) return true
  if (/\baxe\b/.test(name) || /(^|_)axe$/.test(key) || key.includes('_axe')) return true
  return false
}

function isWeaponEquipment(
  item: ItemRow | undefined,
  equipment: EquipmentRow,
): boolean {
  const hasDamage =
    typeof equipment['Min Damage'] === 'number' || typeof equipment['Max Damage'] === 'number'
  if (!hasDamage) return false
  // Axes are combat weapons even when they also carry woodcutting_tool.
  if (isAxeItem(item, equipment)) return true
  const caps = capabilityTags(equipment['Capabilities / Effects'])
  if (caps.includes('combat_weapon')) return true
  // Gathering tools may list damage for emergency combat but are not weapon-enchant targets.
  if (isGatheringToolEquipment(item, equipment)) return false
  return hasDamage
}

function isGatheringToolEquipment(
  item: ItemRow | undefined,
  equipment: EquipmentRow,
): boolean {
  // Axes are combat-classified for Arcana; hatchets remain gathering tools.
  if (isAxeItem(item, equipment)) return false

  if (typeof equipment['Action Time Reduction %'] === 'number') return true

  const caps = capabilityTags(equipment['Capabilities / Effects'])
  return (
    caps.includes('mining_tool') ||
    caps.includes('woodcutting_tool') ||
    caps.includes('fishing_tool') ||
    caps.includes('hunting_tool') ||
    caps.includes('harvesting_tool')
  )
}

function isArmorEquipment(equipment: EquipmentRow): boolean {
  const caps = capabilityTags(equipment['Capabilities / Effects'])
  if (caps.includes('combat_armor') || caps.includes('specialist_armor')) return true
  return typeof equipment['Damage Reduction'] === 'number'
}

function equipmentMatchesEnchantment(
  db: GameDatabase,
  itemId: string,
  equipment: EquipmentRow,
  enchantment: EnchantmentRow,
): boolean {
  const target = (enchantment['Valid Target'] ?? '').toLowerCase()
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  const caps = capabilityTags(equipment['Capabilities / Effects'])
  // Special-effect gear (e.g. Lucky Necklace) keeps its own bonus and cannot be enchanted.
  if (caps.includes('special_effect') || caps.includes('not_enchantable')) return false
  // Craftable Jewelry (necklaces/rings) is flagged enchantable data-side and accepts
  // either gathering or weapon-category (combat) enchantments, despite not being a tool/weapon.
  const isEnchantableAccessory = caps.includes('arcana_enchantable')

  if (target.includes('weapon') && (isWeaponEquipment(item, equipment) || isEnchantableAccessory))
    return true
  if (target.includes('jewelry') && isEnchantableAccessory) return true
  if (
    target.includes('gathering') &&
    (isGatheringToolEquipment(item, equipment) || isEnchantableAccessory)
  )
    return true
  if (target.includes('armor') && isArmorEquipment(equipment)) return true
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
    if (!equipment || !equipmentMatchesEnchantment(db, stack.itemId, equipment, enchantment))
      continue
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
    if (!equipment || !equipmentMatchesEnchantment(db, stack.itemId, equipment, enchantment))
      return
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

const CRIT_STRIKE_ENCHANTMENT_ID = 'ENCH-0008'
const CRIT_STRIKE_CHANCE_PER_ENCHANT = 10

/** Total critical strike chance percent from equipped crit enchantments (adds across items). */
export function equippedEnchantmentCritChancePercent(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let percent = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.enchantmentId) continue
    if (stack.enchantmentId === CRIT_STRIKE_ENCHANTMENT_ID) {
      percent += CRIT_STRIKE_CHANCE_PER_ENCHANT
      continue
    }
    const row = getEnchantment(db, stack.enchantmentId)
    const match = row?.Effect?.match(/\+(\d+(?:\.\d+)?)%\s*Critical Strike Chance/i)
    if (match) percent += Number(match[1])
  }
  return Math.min(100, percent)
}

/** Critical strike damage multiplier (1.5×). */
export function criticalStrikeDamageMultiplier(): number {
  return 1.5
}

/** Percent of damage received in a combat round reflected back at the attacker (e.g. Thorns). */
export function equippedEnchantmentThornsPercent(db: GameDatabase, save: PlayerSave): number {
  let percent = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.enchantmentId) continue
    if (stack.enchantmentId === 'ENCH-0006') {
      percent += 10
      continue
    }
    const row = getEnchantment(db, stack.enchantmentId)
    const match = row?.Effect?.match(/(\d+(?:\.\d+)?)%\s+of damage received/i)
    if (match) {
      percent += Number(match[1])
    }
  }
  return percent
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
