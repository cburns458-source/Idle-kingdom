import { equippedActionTimeReductionPercent } from '../equipment/loadout'
import type { ActionRow, GameDatabase } from '../data/types'
import { equippedEnchantmentGatheringMultiplier } from '../projects/enchantments'
import type { PlayerSave } from '../save/types'
import { getSkillProgress } from './xp'

export function configNumber(db: GameDatabase, key: string, fallback: number): number {
  const value = db.Config.find((row) => row.Key === key)?.Value
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
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
  const atr = equippedActionTimeReductionPercent(db, save)
  const reductionFactor = Math.max(0.01, 1 - atr / 100)
  const enchantFactor = equippedEnchantmentGatheringMultiplier(db, save)
  return Math.max(0, baseSeconds * multiplier * reductionFactor * enchantFactor * 1000)
}

export function isBelowProficiency(save: PlayerSave, action: ActionRow): boolean {
  const proficiency = Number(action['Proficiency Level'] ?? 1)
  const skill = getSkillProgress(save, action['Relevant Skill ID'])
  return skill.level < proficiency
}
