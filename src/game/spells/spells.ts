import { configNumber } from '../activity/gathering'
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

export function spellCycleDurationMs(db: GameDatabase): number {
  return Math.max(1_000, configNumber(db, 'spell_cycle_duration', 3600) * 1000)
}

/** Which of the four spell slots is currently active in the global cycle. */
export function activeSpellSlotIndex(db: GameDatabase, nowMs: number = Date.now()): number {
  const duration = spellCycleDurationMs(db)
  return Math.floor(nowMs / duration) % SPELL_SLOT_IDS.length
}

export function activeSpellSlotId(db: GameDatabase, nowMs: number = Date.now()): SpellSlotId {
  return SPELL_SLOT_IDS[activeSpellSlotIndex(db, nowMs)]!
}

export function activeSpellSlotRemainingMs(
  db: GameDatabase,
  nowMs: number = Date.now(),
): number {
  const duration = spellCycleDurationMs(db)
  return duration - (nowMs % duration)
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

export function activeSpellStack(
  save: PlayerSave,
  db: GameDatabase,
  nowMs: number = Date.now(),
): EquippedStack | null {
  const slotId = activeSpellSlotId(db, nowMs)
  return save.equipment.slots[slotId] ?? null
}

/**
 * Multiplier applied to the player's damage range from the active cycling spell.
 * Strength Spell: +10% => 1.10
 */
export function activeSpellDamageRangeMultiplier(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): number {
  const stack = activeSpellStack(save, db, nowMs)
  if (!stack?.itemId) return 1

  const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
  for (const tag of capabilityTags(equipment?.['Capabilities / Effects'])) {
    const match = tag.match(/^damage_range_bonus_percent:(\d+(?:\.\d+)?)$/)
    if (match) return 1 + Number(match[1]) / 100
  }

  const enchantmentId = spellEffectEnchantmentId(db, stack.itemId)
  const enchantment = enchantmentId ? getEnchantment(db, enchantmentId) : undefined
  const effect = enchantment?.Effect ?? ''
  const match = effect.match(/\+(\d+(?:\.\d+)?)%\s*damage range/i)
  if (match) return 1 + Number(match[1]) / 100

  return 1
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
  lines.push('Cycles through spell slots — 1 hour each.')
  return lines
}
