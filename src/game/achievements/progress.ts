import { getSkillProgress } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import { totalLevel, totalSkillXp } from '../skills/totals'
import type { AchievementProgress, PlayerSave } from '../save/types'

export interface AchievementRow {
  'Achievement ID': string
  'Internal Key': string
  'Display Name': string
  Category: string | null
  Status: string
  'Release Phase': string
  Reward: string | null
  'Target Skill ID': string | null
  'Required Level': number | null
  Notes: string | null
}

export interface StatisticRow {
  'Statistic ID': string
  'Internal Key': string
  'Display Name': string
  Category: string | null
  Status: string
  'Release Phase': string
  Notes: string | null
}

export function asAchievementRows(db: GameDatabase): AchievementRow[] {
  return db.Achievements as unknown as AchievementRow[]
}

export function asStatisticRows(db: GameDatabase): StatisticRow[] {
  return db.Statistics as unknown as StatisticRow[]
}

function upsertAchievement(
  list: AchievementProgress[],
  achievementId: string,
  unlockedAt: string,
): AchievementProgress[] {
  const existing = list.find((row) => row.achievementId === achievementId)
  if (existing?.unlocked) return list
  const next = list.filter((row) => row.achievementId !== achievementId)
  next.push({ achievementId, unlocked: true, unlockedAt })
  return next
}

/** Refresh lifetime totals and unlock skill-level achievements. */
export function syncProgressionMeta(db: GameDatabase, save: PlayerSave, now = Date.now()): PlayerSave {
  const crittersCollected = (save.critterCollections ?? []).reduce(
    (sum, row) => sum + Math.max(0, row.count),
    0,
  )
  const values = {
    ...save.statistics.values,
    total_level: totalLevel(save),
    total_experience: totalSkillXp(save),
    gold_earned: Number(save.statistics.values.gold_earned ?? 0),
    monsters_killed: Number(save.statistics.values.monsters_killed ?? 0),
    critters_collected: crittersCollected,
    bounties_completed: Number(save.statistics.values.bounties_completed ?? 0),
  }

  let achievements = [...save.achievements]
  const unlockedAt = new Date(now).toISOString()
  for (const achievement of asAchievementRows(db)) {
    const skillId = achievement['Target Skill ID']
    const required = achievement['Required Level']
    if (!skillId || typeof required !== 'number') continue
    const level = getSkillProgress(save, skillId).level
    if (level >= required) {
      achievements = upsertAchievement(achievements, achievement['Achievement ID'], unlockedAt)
    }
  }

  return {
    ...save,
    statistics: { values },
    achievements,
  }
}
