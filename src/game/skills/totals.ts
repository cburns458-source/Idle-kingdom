import { MIGHT_SKILL_ID, VITALITY_SKILL_ID } from '../combat/stats'
import type { PlayerSave } from '../save/types'

/** Only the skill list is read, so callers can pass just that. */
type SkillTotalsInput = Pick<PlayerSave, 'skills'>

export function totalSkillXp(save: SkillTotalsInput): number {
  return save.skills.reduce((sum, skill) => sum + skill.xp, 0)
}

/** Sum of all skill levels (each skill starts at 1). */
export function totalLevel(save: SkillTotalsInput): number {
  return save.skills.reduce((sum, skill) => sum + skill.level, 0)
}

/**
 * Whether this character has never raised Might or Vitality past where they started.
 */
export function isPacifistSave(save: SkillTotalsInput): boolean {
  const might = save.skills.find((skill) => skill.skillId === MIGHT_SKILL_ID)
  const vitality = save.skills.find((skill) => skill.skillId === VITALITY_SKILL_ID)
  const mightOk = might == null || might.level <= 1
  const vitalityOk = vitality == null || vitality.level <= 1
  return mightOk && vitalityOk
}
