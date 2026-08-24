import type { EquipmentRow, GameDatabase } from '../data/types'
import { getSkillProgress } from '../activity/xp'
import { OFFHAND_SLOT_ID, WEAPON_TOOL_SLOT_ID, isDaggerItem, itemHasCapability } from '../equipment/loadout'
import { ARCANA_SKILL_ID } from '../npcs/knowledge'
import { equippedEnchantmentDamageBonus } from '../projects/enchantments'
import { raceMaxHpMultiplier } from '../races/races'
import type { PlayerSave } from '../save/types'
import { configNumber } from '../activity/gathering'
import { activeSpellDamageRangeMultiplier } from '../spells/spells'

export const COMBAT_SKILL_ID = 'SKL-0001'
/** Combat Level bonuses begin at this level (inclusive). */
export const COMBAT_LEVEL_BONUS_START = 10
/** Each Combat Level grants this percent to max HP and damage range once the bonus is active. */
export const COMBAT_LEVEL_BONUS_PERCENT_PER_LEVEL = 1

function equippedRows(db: GameDatabase, save: PlayerSave): EquipmentRow[] {
  const rows: EquipmentRow[] = []
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const row = db.Equipment.find((entry) => entry['Item ID'] === stack.itemId)
    if (row) rows.push(row)
  }
  return rows
}

/**
 * Multiplier from Combat Level.
 * Below level 10: none.
 * Level 10+: +1% per Combat Level (level 10 → ×1.10, level 20 → ×1.20).
 */
export function combatLevelBonusMultiplier(save: PlayerSave): number {
  const level = getSkillProgress(save, COMBAT_SKILL_ID).level
  if (level < COMBAT_LEVEL_BONUS_START) return 1
  return 1 + (level * COMBAT_LEVEL_BONUS_PERCENT_PER_LEVEL) / 100
}

function scaleStat(value: number, multiplier: number): number {
  return Math.max(0, Math.floor(value * multiplier))
}

function damageRangeMultipliers(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
): number {
  const levelMult = combatLevelBonusMultiplier(save)
  const spellMult = activeSpellDamageRangeMultiplier(db, save, nowMs)
  const potionBonus = save.activePotionEffect?.damageBonusPercent
  const potionMult =
    potionBonus && potionBonus > 0 && save.activePotionEffect?.scope === 'one_combat_encounter'
      ? 1 + potionBonus / 100
      : 1
  return levelMult * spellMult * potionMult
}

function scaleDamageRange(
  min: number,
  max: number,
  multiplier: number,
): { min: number; max: number } {
  const scaledMin = scaleStat(min, multiplier)
  return {
    min: scaledMin,
    max: Math.max(scaledMin, scaleStat(max, multiplier)),
  }
}

export function staffPowerMultiplier(db: GameDatabase, save: PlayerSave): number {
  const weaponId = save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId
  if (!weaponId || !itemHasCapability(db, weaponId, 'staff_power')) return 1
  return 1 + getSkillProgress(save, ARCANA_SKILL_ID).level / 100
}

/** Spark splat range from Arcana level only: ±10%, floored, never below 1. */
export function staffSparksDamageRange(arcanaLevel: number): { min: number; max: number } {
  const min = Math.max(1, Math.floor(arcanaLevel * 0.9))
  const max = Math.max(min, Math.floor(arcanaLevel * 1.1))
  return { min, max }
}

export function playerDamageRange(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { min: number; max: number } {
  const enchantBonus = equippedEnchantmentDamageBonus(db, save)
  const combined = damageRangeMultipliers(db, save, nowMs) * staffPowerMultiplier(db, save)
  const weaponId = save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId
  let min: number
  let max: number
  if (weaponId) {
    const weapon = db.Equipment.find((entry) => entry['Item ID'] === weaponId)
    const weaponMin = weapon?.['Min Damage']
    const weaponMax = weapon?.['Max Damage']
    if (typeof weaponMin === 'number' && typeof weaponMax === 'number') {
      min = weaponMin + enchantBonus
      max = Math.max(weaponMin, weaponMax) + enchantBonus
    } else {
      min = configNumber(db, 'unarmed_min_damage', 10) + enchantBonus
      max = configNumber(db, 'unarmed_max_damage', 30) + enchantBonus
    }
  } else {
    min = configNumber(db, 'unarmed_min_damage', 10) + enchantBonus
    max = configNumber(db, 'unarmed_max_damage', 30) + enchantBonus
  }

  return scaleDamageRange(min, max, combined)
}

/**
 * Off-hand dagger damage range, or null when no dagger is equipped there.
 * Uses the same global enchant / spell / potion / race multipliers as main-hand.
 */
export function playerOffhandDamageRange(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number = Date.now(),
): { min: number; max: number } | null {
  const offhandId = save.equipment.slots[OFFHAND_SLOT_ID]?.itemId
  if (!offhandId || !isDaggerItem(db, offhandId)) return null
  const dagger = db.Equipment.find((entry) => entry['Item ID'] === offhandId)
  const daggerMin = dagger?.['Min Damage']
  const daggerMax = dagger?.['Max Damage']
  if (typeof daggerMin !== 'number' || typeof daggerMax !== 'number') return null

  const enchantBonus = equippedEnchantmentDamageBonus(db, save)
  const combined = damageRangeMultipliers(db, save, nowMs)
  return scaleDamageRange(
    daggerMin + enchantBonus,
    Math.max(daggerMin, daggerMax) + enchantBonus,
    combined,
  )
}

export function playerDamageReduction(db: GameDatabase, save: PlayerSave): number {
  return equippedRows(db, save).reduce((sum, row) => sum + Number(row['Damage Reduction'] ?? 0), 0)
}

export function playerMaxHp(db: GameDatabase, save: PlayerSave): number {
  const base = configNumber(db, 'starting_max_hp', 1000)
  const bonus = equippedRows(db, save).reduce((sum, row) => sum + Number(row['HP Bonus'] ?? 0), 0)
  const levelMult = combatLevelBonusMultiplier(save)
  const raceMult = raceMaxHpMultiplier(db, save)
  return Math.max(1, scaleStat(base + bonus, levelMult * raceMult))
}

export function rollDamage(min: number, max: number, random: () => number = Math.random): number {
  const lo = Math.min(min, max)
  const hi = Math.max(min, max)
  return lo + Math.floor(random() * (hi - lo + 1))
}

export function applyMitigation(
  rawDamage: number,
  reduction: number,
  damageFloor: number,
): number {
  return Math.max(damageFloor, rawDamage - Math.max(0, reduction))
}
