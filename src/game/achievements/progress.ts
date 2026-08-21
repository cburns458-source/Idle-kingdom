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
  Difficulty: string | null
  'Check Type': string | null
  'Target ID': string | null
  'Required Count': number | null
  Status: string
  'Release Phase': string
  Reward: string | null
  'Target Skill ID': string | null
  'Required Level': number | null
  Notes: string | null
}

export const ACHIEVEMENT_DIFFICULTIES = ['Easy', 'Medium', 'Hard'] as const

export function addLifetimeStat(save: PlayerSave, key: string, amount = 1): PlayerSave {
  const current = Number(save.statistics.values[key] ?? 0)
  return {
    ...save,
    statistics: {
      values: {
        ...save.statistics.values,
        [key]: current + amount,
      },
    },
  }
}

export function isSpellProject(project: { 'Internal Key'?: string; 'Display Name'?: string }): boolean {
  const key = String(project['Internal Key'] ?? '')
  const name = String(project['Display Name'] ?? '').toLowerCase()
  return key.includes('_spell') || (name.includes('spell') && !name.includes('enchant'))
}

export function recordProjectMilestones(
  db: GameDatabase,
  save: PlayerSave,
  projectId: string,
  crafts: number,
): PlayerSave {
  const project = db.Projects.find((row) => row['Project ID'] === projectId)
  let next = addLifetimeStat(save, `project_${projectId}`, crafts)
  const outputId = String(project?.['Output Item / Target ID'] ?? '')
  if (outputId.startsWith('ENCH-')) {
    next = addLifetimeStat(next, 'items_enchanted', crafts)
  }
  if (project && isSpellProject(project)) {
    next = addLifetimeStat(next, 'spell_projects', crafts)
  }
  return next
}

export function recordProductionMilestones(
  db: GameDatabase,
  save: PlayerSave,
  outputItemId: string,
  quantity: number,
): PlayerSave {
  let next = addLifetimeStat(save, `output_${outputItemId}`, quantity)
  const item = db.Items.find((row) => row['Item ID'] === outputItemId)
  if (item?.Category === 'Potion') {
    next = addLifetimeStat(next, 'potions_created', quantity)
  }
  return next
}

export function recordFoodConsumed(save: PlayerSave, itemId: string): PlayerSave {
  return addLifetimeStat(save, `consumed_${itemId}`, 1)
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

function lifetimeCount(values: Record<string, number>, key: string): number {
  return Number(values[key] ?? 0)
}

function holdsMilestone(
  db: GameDatabase,
  save: PlayerSave,
  achievement: AchievementRow,
  values: Record<string, number>,
): boolean {
  const check = achievement['Check Type'] ?? ''
  const target = achievement['Target ID']
  const count = Number(achievement['Required Count'] ?? 1)
  const required = achievement['Required Level']
  switch (check) {
    case 'project':
      return target != null && lifetimeCount(values, `project_${target}`) >= count
    case 'consume':
      return target != null && lifetimeCount(values, `consumed_${target}`) >= count
    case 'output_item':
      return target != null && lifetimeCount(values, `output_${target}`) >= count
    case 'enchant':
      return lifetimeCount(values, 'items_enchanted') >= count
    case 'potion':
      return lifetimeCount(values, 'potions_created') >= count
    case 'spell_projects':
      return lifetimeCount(values, 'spell_projects') >= count
    case 'gold':
      return lifetimeCount(values, 'gold_earned') >= count
    case 'skill_all':
      if (typeof required !== 'number') return false
      return db.Skills.every((skill) => getSkillProgress(save, skill['Skill ID']).level >= required)
    default: {
      const skillId = achievement['Target Skill ID']
      if (!skillId || typeof required !== 'number') return false
      return getSkillProgress(save, skillId).level >= required
    }
  }
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
    if (holdsMilestone(db, save, achievement, values)) {
      achievements = upsertAchievement(achievements, achievementId, unlockedAt)
    }
  }

  return {
    ...save,
    statistics: { values },
    achievements,
  }
}
