import { applyQuiverHuntingXp } from '../equipment/specialist'
import type { ActionRow, GameDatabase } from '../data/types'
import { equippedEnchantmentGatheringMultiplier } from '../projects/enchantments'
import type { PlayerSave } from '../save/types'
import { activeSpellGatheringDurationMultiplier } from '../spells/spells'
import type { RandomFn } from './pools'
import { getSkillProgress } from './xp'

export function configNumber(db: GameDatabase, key: string, fallback: number): number {
  const value = db.Config.find((row) => row.Key === key)?.Value
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

export function configString(db: GameDatabase, key: string, fallback: string): string {
  const value = db.Config.find((row) => row.Key === key)?.Value
  return typeof value === 'string' && value.length > 0 ? value : fallback
}

/**
 * Gathering: base = 80 − floor(proficiency/4) (lvl 1–3 actions → 80%, lvl 40 → 70%).
 * Then −0.75%/level below proficiency, +1%/level above. Clamped 0–100.
 * Optional flat success-chance bonus from gear is applied by callers.
 */
export function gatheringSuccessChancePercent(
  level: number,
  proficiencyLevel: number = 1,
  successChanceBonusPercent: number = 0,
): number {
  const proficiency = Math.max(1, Math.floor(Number(proficiencyLevel) || 1))
  const base = 80 - Math.floor(proficiency / 4)
  return successChancePercent(level, proficiency, base, successChanceBonusPercent)
}

/**
 * Production: base 70%. −0.75%/level below proficiency, +1%/level above.
 * Clamped 0–100. Optional flat success-chance bonus from gear is applied by callers.
 */
export function productionSuccessChancePercent(
  level: number,
  proficiencyLevel: number = 1,
  successChanceBonusPercent: number = 0,
): number {
  return successChancePercent(level, proficiencyLevel, 70, successChanceBonusPercent)
}

function successChancePercent(
  level: number,
  proficiencyLevel: number,
  baseAtProficiency: number,
  successChanceBonusPercent: number = 0,
): number {
  const lvl = Math.max(1, Math.floor(Number(level) || 1))
  const proficiency = Math.max(1, Math.floor(Number(proficiencyLevel) || 1))
  const delta = lvl - proficiency
  const chance =
    (delta < 0 ? baseAtProficiency + delta * 0.75 : baseAtProficiency + delta) +
    Math.max(0, Number(successChanceBonusPercent) || 0)
  return Math.max(0, Math.min(100, chance))
}

/** False means the action yields no loot and no XP. */
export function rollGatheringSuccess(
  level: number,
  random: RandomFn = Math.random,
  proficiencyLevel: number = 1,
  successChanceBonusPercent: number = 0,
): boolean {
  return (
    random() * 100 <
    gatheringSuccessChancePercent(level, proficiencyLevel, successChanceBonusPercent)
  )
}

/** False means the craft botches: materials spent, no output/XP. */
export function rollProductionSuccess(
  level: number,
  random: RandomFn = Math.random,
  proficiencyLevel: number = 1,
  successChanceBonusPercent: number = 0,
): boolean {
  return (
    random() * 100 <
    productionSuccessChancePercent(level, proficiencyLevel, successChanceBonusPercent)
  )
}

export function gatheringDurationMs(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
): number {
  const baseSeconds = Number(action['Base Duration Seconds'] ?? 0)
  const proficiency = Number(action['Proficiency Level'] ?? 1)
  const skill = getSkillProgress(save, action['Relevant Skill ID'])
  const multiplier =
    skill.level < proficiency
      ? configNumber(db, 'gathering_below_proficiency_duration_multiplier', 2)
      : 1
  const enchantFactor = equippedEnchantmentGatheringMultiplier(
    db,
    save,
    action['Relevant Skill ID'],
  )
  const spellFactor = activeSpellGatheringDurationMultiplier(db, save)
  return Math.max(0, baseSeconds * multiplier * enchantFactor * spellFactor * 1000)
}

export function isBelowProficiency(save: PlayerSave, action: ActionRow): boolean {
  const proficiency = Number(action['Proficiency Level'] ?? 1)
  const skill = getSkillProgress(save, action['Relevant Skill ID'])
  return skill.level < proficiency
}

/** XP granted for a gathering action (halved when below proficiency). */
export function gatheringXpReward(
  db: GameDatabase,
  save: PlayerSave,
  action: ActionRow,
  baseXp: number = Number(action['XP Reward'] ?? 0),
): number {
  const amount = Math.max(0, Number(baseXp) || 0)
  if (amount <= 0) return 0
  const afterProficiency = !isBelowProficiency(save, action)
    ? Math.floor(amount)
    : Math.floor(amount * configNumber(db, 'gathering_below_proficiency_xp_multiplier', 0.5))
  return applyQuiverHuntingXp(db, afterProficiency, save, action['Relevant Skill ID'] ?? '')
}
