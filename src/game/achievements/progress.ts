import { getSkillProgress } from '../activity/xp'
import { CRITTER_DEFS, collectionCount } from '../critters/critters'
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

/**
 * Achievements in this category are re-checked every sync and can be lost.
 *
 * A skill milestone is a thing the player did once, so it is theirs forever. A
 * collection is a statement about the collection as it stands now, which stops
 * being true the moment the world grows a new critter.
 */
export const REVOCABLE_ACHIEVEMENT_CATEGORY = 'Collections'

export const CRITTER_COLLECTOR_ACHIEVEMENT_ID = 'ACH-0015'

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

function revokeAchievement(
  list: AchievementProgress[],
  achievementId: string,
): AchievementProgress[] {
  if (!list.some((row) => row.achievementId === achievementId)) return list
  return list.filter((row) => row.achievementId !== achievementId)
}

/** Whether the collection holds at least one of every critter that exists. */
export function hasEveryCritter(save: PlayerSave): boolean {
  if (CRITTER_DEFS.length === 0) return false
  return CRITTER_DEFS.every((critter) => collectionCount(save, critter.id) > 0)
}

/** Whether a save currently qualifies for a category that can be lost again. */
function holdsRevocableAchievement(save: PlayerSave, achievementId: string): boolean {
  return achievementId === CRITTER_COLLECTOR_ACHIEVEMENT_ID && hasEveryCritter(save)
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
    const achievementId = achievement['Achievement ID']
    if (achievement.Category === REVOCABLE_ACHIEVEMENT_CATEGORY) {
      achievements = holdsRevocableAchievement(save, achievementId)
        ? upsertAchievement(achievements, achievementId, unlockedAt)
        : revokeAchievement(achievements, achievementId)
      continue
    }
    const skillId = achievement['Target Skill ID']
    const required = achievement['Required Level']
    if (!skillId || typeof required !== 'number') continue
    const level = getSkillProgress(save, skillId).level
    if (level >= required) {
      achievements = upsertAchievement(achievements, achievementId, unlockedAt)
    }
  }

  return {
    ...save,
    statistics: { values },
    achievements,
  }
}
