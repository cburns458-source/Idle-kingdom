import type { EquipmentRow, GameDatabase, ItemRow } from '../data/types'
import { getEnchantment } from '../projects/projects'
import type { EquippedStack, PlayerSave } from '../save/types'

export const SPELL_SLOT_IDS = [
  'SLOT-0013',
  'SLOT-0014',
  'SLOT-0015',
  'SLOT-0016',
] as const

export type SpellSlotId = (typeof SPELL_SLOT_IDS)[number]

export function isSpellSlotId(slotId: string): slotId is SpellSlotId {
  return (SPELL_SLOT_IDS as readonly string[]).includes(slotId)
}

function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

export function isSpellEquipment(equipment: EquipmentRow | undefined): boolean {
  if (!equipment) return false
  const tags = capabilityTags(equipment['Capabilities / Effects'])
  if (tags.includes('spell') || tags.some((tag) => tag.startsWith('spell_effect:'))) {
    return true
  }
  return isSpellSlotId(equipment['Slot ID'] ?? '')
}

export function isSpellItem(db: GameDatabase, itemId: string): boolean {
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  if (item?.Category?.toLowerCase() === 'spell') return true
  const tags = String(item?.['Functional / Source Tags'] ?? '').toLowerCase()
  if (tags.includes('spell')) return true
  return isSpellEquipment(db.Equipment.find((row) => row['Item ID'] === itemId))
}

export function firstEmptySpellSlot(save: PlayerSave): SpellSlotId | null {
  for (const slotId of SPELL_SLOT_IDS) {
    if (!save.equipment.slots[slotId]?.itemId) return slotId
  }
  return null
}

/** All equipped spell stacks (empty slots omitted). Effects from each stack apply. */
export function equippedSpellStacks(save: PlayerSave): EquippedStack[] {
  const out: EquippedStack[] = []
  for (const slotId of SPELL_SLOT_IDS) {
    const stack = save.equipment.slots[slotId]
    if (stack?.itemId) out.push(stack)
  }
  return out
}

export function spellEffectEnchantmentId(
  db: GameDatabase,
  itemId: string,
): string | null {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  for (const tag of capabilityTags(equipment?.['Capabilities / Effects'])) {
    if (tag.startsWith('spell_effect:')) return tag.slice('spell_effect:'.length).toUpperCase()
  }
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  const itemTags = String(item?.['Functional / Source Tags'] ?? '')
  for (const part of itemTags.split(';')) {
    const tag = part.trim().toLowerCase()
    if (tag.startsWith('spell_effect:')) {
      return tag.slice('spell_effect:'.length).toUpperCase()
    }
  }
  return null
}

/** Damage-range bonus percent contributed by one spell item (0 if none). */
export function spellDamageRangeBonusPercent(db: GameDatabase, itemId: string): number {
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  for (const tag of capabilityTags(equipment?.['Capabilities / Effects'])) {
    const match = tag.match(/^damage_range_bonus_percent:(\d+(?:\.\d+)?)$/)
    if (match) return Number(match[1])
  }

  const enchantmentId = spellEffectEnchantmentId(db, itemId)
  const enchantment = enchantmentId ? getEnchantment(db, enchantmentId) : undefined
  const effect = enchantment?.Effect ?? ''
  const match = effect.match(/\+(\d+(?:\.\d+)?)%\s*damage range/i)
  if (match) return Number(match[1])
  return 0
}

/**
 * Multiplier from all equipped spells. Same bonus types add (2× Strength = +20% => 1.20).
 * `nowMs` is unused (kept for call-site compatibility after the cycle removal).
 */
export function activeSpellDamageRangeMultiplier(
  db: GameDatabase,
  save: PlayerSave,
  _nowMs: number = Date.now(),
): number {
  let bonusPercent = 0
  for (const stack of equippedSpellStacks(save)) {
    bonusPercent += spellDamageRangeBonusPercent(db, stack.itemId)
  }
  return 1 + bonusPercent / 100
}

export function spellTooltipLines(
  db: GameDatabase,
  item: ItemRow | undefined,
  itemId: string,
): string[] {
  const lines: string[] = []
  const enchantmentId = spellEffectEnchantmentId(db, itemId)
  const enchantment = enchantmentId ? getEnchantment(db, enchantmentId) : undefined
  if (enchantment?.['Display Name']) lines.push(enchantment['Display Name'])
  if (enchantment?.Effect) lines.push(enchantment.Effect)
  else if (item?.Description) lines.push(item.Description)
  lines.push('Always active while equipped. Duplicate spells stack.')
  return lines
}
