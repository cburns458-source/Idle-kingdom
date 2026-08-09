import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import type { ActionXpRewardSummary } from './types'
import { getSkillProgress } from './xp'

export function summarizeXpReward(
  db: GameDatabase,
  saveAfter: Pick<PlayerSave, 'skills'>,
  skillId: string,
  xp: number,
  leveledUpTo: number | null,
): ActionXpRewardSummary | null {
  if (xp <= 0) return null
  const skill = db.Skills.find((row) => row['Skill ID'] === skillId)
  const progress = getSkillProgress(saveAfter as PlayerSave, skillId)
  return {
    skillId,
    skillName: skill?.['Display Name'] ?? 'Skill',
    skillKey: skill?.['Internal Key'] ?? skillId,
    xp,
    level: leveledUpTo ?? progress.level,
    leveledUp: leveledUpTo != null,
  }
}
