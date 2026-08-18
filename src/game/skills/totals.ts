import { COMBAT_SKILL_ID } from '../combat/stats'
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
 * Whether this character has never raised Combat past where it started.
 *
 * A save with no Combat row at all counts: the skill only appears once it has
 * been touched, and an untouched Combat is the whole point.
 */
export function isPacifistSave(save: SkillTotalsInput): boolean {
  const combat = save.skills.find((skill) => skill.skillId === COMBAT_SKILL_ID)
  return combat == null || combat.level <= 1
}
