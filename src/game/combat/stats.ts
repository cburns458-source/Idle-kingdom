import type { EquipmentRow, GameDatabase } from '../data/types'
import { getSkillProgress } from '../activity/xp'
import { equippedEnchantmentDamageBonus } from '../projects/enchantments'
import type { PlayerSave } from '../save/types'
import { configNumber } from '../activity/gathering'

const WEAPON_SLOT = 'SLOT-0001'
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

export function playerDamageRange(
  db: GameDatabase,
  save: PlayerSave,
): { min: number; max: number } {
  const enchantBonus = equippedEnchantmentDamageBonus(db, save)
  const levelMult = combatLevelBonusMultiplier(save)
  const weaponId = save.equipment.slots[WEAPON_SLOT]?.itemId
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

  return {
    min: scaleStat(min, levelMult),
    max: Math.max(scaleStat(min, levelMult), scaleStat(max, levelMult)),
  }
}

export function playerDamageReduction(db: GameDatabase, save: PlayerSave): number {
  return equippedRows(db, save).reduce((sum, row) => sum + Number(row['Damage Reduction'] ?? 0), 0)
}

export function playerMaxHp(db: GameDatabase, save: PlayerSave): number {
  const base = configNumber(db, 'starting_max_hp', 1000)
  const bonus = equippedRows(db, save).reduce((sum, row) => sum + Number(row['HP Bonus'] ?? 0), 0)
  const levelMult = combatLevelBonusMultiplier(save)
  return Math.max(1, scaleStat(base + bonus, levelMult))
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
