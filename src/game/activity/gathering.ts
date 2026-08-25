import { applyQuiverHuntingXp } from '../equipment/specialist'
import { equippedActionTimeReductionPercent } from '../equipment/loadout'
import type { ActionRow, GameDatabase } from '../data/types'
import { equippedEnchantmentGatheringMultiplier } from '../projects/enchantments'
import type { PlayerSave } from '../save/types'
import { getSkillProgress } from './xp'

export function configNumber(db: GameDatabase, key: string, fallback: number): number {
  const value = db.Config.find((row) => row.Key === key)?.Value
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

export function configString(db: GameDatabase, key: string, fallback: string): string {
  const value = db.Config.find((row) => row.Key === key)?.Value
  return typeof value === 'string' && value.length > 0 ? value : fallback
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
  const atr = equippedActionTimeReductionPercent(db, save, action['Relevant Skill ID'])
  const reductionFactor = Math.max(0.01, 1 - atr / 100)
  const enchantFactor = equippedEnchantmentGatheringMultiplier(db, save)
  return Math.max(0, baseSeconds * multiplier * reductionFactor * enchantFactor * 1000)
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
  return applyQuiverHuntingXp(afterProficiency, save, action['Relevant Skill ID'] ?? '')
}
