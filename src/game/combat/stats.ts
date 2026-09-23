import type { EnemyRow } from '../data/enemyTypes'
import type { EquipmentRow, GameDatabase } from '../data/types'
import { getSkillProgress } from '../activity/xp'
import {
  equippedActionTimeReductionPercent,
  OFFHAND_SLOT_ID,
  WEAPON_TOOL_SLOT_ID,
  isDaggerItem,
  itemHasCapability,
} from '../equipment/loadout'
import { FISHING_SKILL_ID } from '../skills/skillActions'
import { ARCANA_SKILL_ID } from '../npcs/knowledge'
import { equippedEnchantmentDamageBonus } from '../projects/enchantments'
import { raceMaxHpMultiplier } from '../races/races'
import type { AttackStyle, PlayerSave } from '../save/types'
import { configNumber } from '../activity/gathering'
import { activeSpellDamageRangeMultiplier } from '../spells/spells'

/** Might — weapons and damage scaling. Formerly Combat (`SKL-0001`). */
export const MIGHT_SKILL_ID = 'SKL-0001'
/** Vitality — armor/shields and max HP scaling. */
export const VITALITY_SKILL_ID = 'SKL-0016'
/** @deprecated Use MIGHT_SKILL_ID. Kept for transitional call sites. */
export const COMBAT_SKILL_ID = MIGHT_SKILL_ID

/** Level bonuses (Might→damage, Vitality→HP) begin at this level (inclusive). */
export const COMBAT_LEVEL_BONUS_START = 10
/** Each contributing skill level grants this percent once the bonus is active. */
export const COMBAT_LEVEL_BONUS_PERCENT_PER_LEVEL = 1

export const ATTACK_STYLES = ['offensive', 'defensive', 'balanced'] as const

export function normalizeAttackStyle(value: unknown): AttackStyle {
  if (value === 'offensive' || value === 'defensive' || value === 'balanced') return value
  return 'offensive'
}

/**
 * Combined Combat Level = ceil((Might + Vitality) × 0.75).
 * Shared by players and enemies.
 */
export function combatLevelFromSkills(mightLevel: number, vitalityLevel: number): number {
  return Math.ceil((Number(mightLevel) + Number(vitalityLevel)) * 0.75)
}

/**
 * Combined Combat Level = ceil((Might + Vitality) × 0.75).
 * Replaces the old single Combat skill level everywhere gates/UI need it.
 */
export function combatLevelOf(save: Pick<PlayerSave, 'skills'>): number {
  const might = getSkillProgress(save as PlayerSave, MIGHT_SKILL_ID).level
  const vitality = getSkillProgress(save as PlayerSave, VITALITY_SKILL_ID).level
  return combatLevelFromSkills(might, vitality)
}

function enemySkillLevel(raw: number | null | undefined, fallback: number | null | undefined): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) return raw
  if (typeof fallback === 'number' && Number.isFinite(fallback)) return fallback
  return 0
}

export function enemyMightLevel(enemy: EnemyRow): number {
  return enemySkillLevel(enemy['Might Level'], enemy['Combat Level'])
}

export function enemyVitalityLevel(enemy: EnemyRow): number {
  return enemySkillLevel(enemy['Vitality Level'], enemy['Combat Level'])
}

export function enemyCombatLevel(enemy: EnemyRow): number {
  return combatLevelFromSkills(enemyMightLevel(enemy), enemyVitalityLevel(enemy))
}

/** Encounter HP from table base × Vitality bonus. Boss player-base overrides sit elsewhere. */
export function enemyScaledMaxHp(enemy: EnemyRow): number {
  return Math.max(
    1,
    scaleStat(Number(enemy['Maximum HP'] ?? 0), skillLevelBonusMultiplier(enemyVitalityLevel(enemy))),
  )
}

/** Encounter damage from table base × Might bonus. Boss player-base overrides sit elsewhere. */
export function enemyScaledDamageRange(enemy: EnemyRow): { min: number; max: number } {
  const multiplier = skillLevelBonusMultiplier(enemyMightLevel(enemy))
  const min = scaleStat(Number(enemy['Min Damage'] ?? 0), multiplier)
  return { min, max: Math.max(min, scaleStat(Number(enemy['Max Damage'] ?? 0), multiplier)) }
}

/** Multiplier from a single skill's level (Might or Vitality). */
export function skillLevelBonusMultiplier(level: number): number {
  if (level < COMBAT_LEVEL_BONUS_START) return 1
  return 1 + (level * COMBAT_LEVEL_BONUS_PERCENT_PER_LEVEL) / 100
}

export function mightDamageMultiplier(save: PlayerSave): number {
  return skillLevelBonusMultiplier(getSkillProgress(save, MIGHT_SKILL_ID).level)
}

export function vitalityHpMultiplier(save: PlayerSave): number {
  return skillLevelBonusMultiplier(getSkillProgress(save, VITALITY_SKILL_ID).level)
}

/** Flat style damage bonus percent (0 for balanced). */
export function attackStyleDamageBonusPercent(style: AttackStyle): number {
  if (style === 'offensive') return 1
  return 0
}

/** Flat style damage-reduction points (0 for balanced). */
export function attackStyleDamageReduction(style: AttackStyle): number {
  if (style === 'defensive') return 1
  return 0
}

/**
 * Split kill XP across Might / Vitality by attack style.
 * Balanced splits evenly; odd remainder goes to Might.
 */
export function splitCombatVictoryXp(
  totalXp: number,
  style: AttackStyle,
): { mightXp: number; vitalityXp: number } {
  const amount = Math.max(0, Math.floor(Number(totalXp) || 0))
  if (amount <= 0) return { mightXp: 0, vitalityXp: 0 }
  if (style === 'offensive') return { mightXp: amount, vitalityXp: 0 }
  if (style === 'defensive') return { mightXp: 0, vitalityXp: amount }
  const vitalityXp = Math.floor(amount / 2)
  return { mightXp: amount - vitalityXp, vitalityXp }
}

function equippedRows(db: GameDatabase, save: PlayerSave): EquipmentRow[] {
  const rows: EquipmentRow[] = []
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const row = db.Equipment.find((entry) => entry['Item ID'] === stack.itemId)
    if (row) rows.push(row)
  }
  return rows
}

function scaleStat(value: number, multiplier: number): number {
  return Math.max(0, Math.floor(value * multiplier))
}

function damageRangeMultipliers(
  db: GameDatabase,
  save: PlayerSave,
  nowMs: number,
): number {
  const levelMult = mightDamageMultiplier(save)
  const styleMult = 1 + attackStyleDamageBonusPercent(normalizeAttackStyle(save.attackStyle)) / 100
  const spellMult = activeSpellDamageRangeMultiplier(db, save, nowMs)
  const potionBonus = save.activePotionEffect?.damageBonusPercent
  const potionMult =
    potionBonus && potionBonus > 0 && save.activePotionEffect?.scope === 'one_combat_encounter'
      ? 1 + potionBonus / 100
      : 1
  return levelMult * styleMult * spellMult * potionMult
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

/**
 * Mother Squid fishing combat: (2000 × Fishing ATR% + Fishing Level) ± 10%.
 */
export function fishingCombatDamageRange(
  db: GameDatabase,
  save: PlayerSave,
): { min: number; max: number } {
  const atr = equippedActionTimeReductionPercent(db, save, FISHING_SKILL_ID)
  const level = getSkillProgress(save, FISHING_SKILL_ID).level
  const base = 2000 * (atr / 100) + level
  const min = Math.max(1, Math.floor(base * 0.9))
  const max = Math.max(min, Math.floor(base * 1.1))
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

  const glovesMinBonus = equippedRows(db, save).reduce((sum, row) => {
    if (row['Slot ID'] !== 'SLOT-0007') return sum
    const bonus = row['Min Damage']
    return typeof bonus === 'number' && Number.isFinite(bonus) ? sum + bonus : sum
  }, 0)
  min += glovesMinBonus

  return scaleDamageRange(min, max, combined)
}

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
  const gear = equippedRows(db, save).reduce(
    (sum, row) => sum + Number(row['Damage Reduction'] ?? 0),
    0,
  )
  return gear + attackStyleDamageReduction(normalizeAttackStyle(save.attackStyle))
}

export function playerMaxHp(db: GameDatabase, save: PlayerSave): number {
  const base = configNumber(db, 'starting_max_hp', 1000)
  const bonus = equippedRows(db, save).reduce((sum, row) => sum + Number(row['HP Bonus'] ?? 0), 0)
  const levelMult = vitalityHpMultiplier(save)
  const raceMult = raceMaxHpMultiplier(db, save)
  return Math.max(1, scaleStat(base + bonus, levelMult * raceMult))
}

export function playerBaseMaxHp(db: GameDatabase, save: PlayerSave): number {
  const base = configNumber(db, 'starting_max_hp', 1000)
  const levelMult = vitalityHpMultiplier(save)
  const raceMult = raceMaxHpMultiplier(db, save)
  return Math.max(1, scaleStat(base, levelMult * raceMult))
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

/** @deprecated Use mightDamageMultiplier / vitalityHpMultiplier. */
export function combatLevelBonusMultiplier(save: PlayerSave): number {
  return mightDamageMultiplier(save)
}
