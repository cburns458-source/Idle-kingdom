import type { PlayerSave } from '../save/types'

export function totalSkillXp(save: PlayerSave): number {
  return save.skills.reduce((sum, skill) => sum + skill.xp, 0)
}

/** Sum of all skill levels (each skill starts at 1). */
export function totalLevel(save: PlayerSave): number {
  return save.skills.reduce((sum, skill) => sum + skill.level, 0)
}
