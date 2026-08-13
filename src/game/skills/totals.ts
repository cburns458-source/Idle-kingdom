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
