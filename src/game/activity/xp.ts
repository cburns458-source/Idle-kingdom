import type { GameDatabase } from '../data/types'
import type { PlayerSave, SkillProgress } from '../save/types'

export function getSkillProgress(save: PlayerSave, skillId: string): SkillProgress {
  const existing = save.skills.find((skill) => skill.skillId === skillId)
  if (existing) return existing
  return { skillId, level: 1, xp: 0 }
}

export function levelForTotalXp(db: GameDatabase, totalXp: number): number {
  let level = 1
  for (const row of db.XPCurve) {
    if (totalXp >= row['Total XP at Level']) {
      level = row.Level
    } else {
      break
    }
  }
  return level
}

export function applyXp(
  save: PlayerSave,
  db: GameDatabase,
  skillId: string,
  xpAmount: number,
): { save: PlayerSave; leveledUpTo: number | null } {
  if (xpAmount <= 0) return { save, leveledUpTo: null }

  const skills = save.skills.map((skill) => ({ ...skill }))
  let progress = skills.find((skill) => skill.skillId === skillId)
  if (!progress) {
    progress = { skillId, level: 1, xp: 0 }
    skills.push(progress)
  }

  const previousLevel = progress.level
  progress.xp += xpAmount
  progress.level = levelForTotalXp(db, progress.xp)
  const leveledUpTo = progress.level > previousLevel ? progress.level : null

  return {
    save: { ...save, skills },
    leveledUpTo,
  }
}
