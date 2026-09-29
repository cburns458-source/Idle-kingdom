import { applyQuiverHuntingXp } from '../equipment/specialist'
import { equippedActionTimeReductionPercentForAction } from '../equipment/loadout'
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
 * Level 1 = 40%, +0.5% per skill level (89.5% at level 100).
 * Plus +1% for each level above the action's proficiency level.
 */
export function gatheringSuccessChancePercent(
  level: number,
  proficiencyLevel: number = 1,
): number {
  return successChancePercent(level, proficiencyLevel, 40)
}

/**
 * Standard production uses a copy of the gathering curve with a +10% base
 * (level 1 = 50%, 99.5% at level 100, same above-proficiency bonus).
 */
export function productionSuccessChancePercent(
  level: number,
  proficiencyLevel: number = 1,
): number {
  return successChancePercent(level, proficiencyLevel, 50)
}

function successChancePercent(
  level: number,
  proficiencyLevel: number,
  baseAtLevel1: number,
): number {
  const lvl = Math.max(1, Math.floor(Number(level) || 1))
  const proficiency = Math.max(1, Math.floor(Number(proficiencyLevel) || 1))
  const base = baseAtLevel1 + 0.5 * (lvl - 1)
  const aboveProficiency = Math.max(0, lvl - proficiency)
  return Math.min(100, base + aboveProficiency)
}

/** False means the action yields no loot and no XP. */
export function rollGatheringSuccess(
  level: number,
  random: RandomFn = Math.random,
  proficiencyLevel: number = 1,
): boolean {
  return random() * 100 < gatheringSuccessChancePercent(level, proficiencyLevel)
}

/** False means the craft botches: materials spent, no output/XP. */
export function rollProductionSuccess(
  level: number,
  random: RandomFn = Math.random,
  proficiencyLevel: number = 1,
): boolean {
  return random() * 100 < productionSuccessChancePercent(level, proficiencyLevel)
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
  const atr = equippedActionTimeReductionPercentForAction(db, save, action)
  const reductionFactor = Math.max(0.01, 1 - atr / 100)
  const enchantFactor = equippedEnchantmentGatheringMultiplier(
    db,
    save,
    action['Relevant Skill ID'],
  )
  const spellFactor = activeSpellGatheringDurationMultiplier(db, save)
  return Math.max(
    0,
    baseSeconds * multiplier * reductionFactor * enchantFactor * spellFactor * 1000,
  )
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
