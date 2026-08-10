import type { ActionRow } from '../data/types'

/** Extra skill XP granted on specific Actions beyond Relevant Skill ID / XP Reward. */
const BONUS_SKILL_XP: Record<string, { skillId: string; xp: number }> = {
  // Delve for Essence: Mining XP from the action row + Arcana XP here.
  'ACN-0028': { skillId: 'SKL-0013', xp: 100 },
}

export function bonusSkillXpForAction(
  action: ActionRow | Pick<ActionRow, 'Action ID'>,
): { skillId: string; xp: number } | null {
  return BONUS_SKILL_XP[action['Action ID']] ?? null
}
