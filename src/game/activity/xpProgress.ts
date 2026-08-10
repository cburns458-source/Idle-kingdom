import type { GameDatabase } from '../data/types'

export interface SkillXpProgress {
  level: number
  totalXp: number
  /** XP earned within the current level. */
  intoLevel: number
  /** XP required to reach the next level from the start of this level. */
  toNextLevel: number
  nextLevel: number | null
  /** True when total XP is at or past the highest curve row. */
  atCap: boolean
}

export function skillXpProgress(db: GameDatabase, totalXp: number): SkillXpProgress {
  const xp = Math.max(0, Math.floor(totalXp))
  const curve = db.XPCurve
  if (curve.length === 0) {
    return {
      level: 1,
      totalXp: xp,
      intoLevel: xp,
      toNextLevel: 0,
      nextLevel: null,
      atCap: true,
    }
  }

  let level = 1
  let totalAtLevel = 0
  let xpToNext = curve[0]?.['XP to Next Level'] ?? 0
  for (const row of curve) {
    if (xp >= row['Total XP at Level']) {
      level = row.Level
      totalAtLevel = row['Total XP at Level']
      xpToNext = row['XP to Next Level']
    } else {
      break
    }
  }

  const last = curve[curve.length - 1]!
  const atCap = level >= last.Level && (xpToNext <= 0 || xp >= totalAtLevel + xpToNext)
  const intoLevel = Math.max(0, xp - totalAtLevel)
  const nextLevel = atCap ? null : level + 1

  return {
    level,
    totalXp: xp,
    intoLevel: atCap ? intoLevel : Math.min(intoLevel, Math.max(0, xpToNext)),
    toNextLevel: Math.max(0, xpToNext),
    nextLevel,
    atCap,
  }
}
