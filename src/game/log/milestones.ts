import { getSkillProgress } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

export const GATHERING_ACTIONS_STAT = 'gathering_actions_completed'

const SKILL_THRESHOLDS = [25, 50, 75, 100] as const
const COUNT_THRESHOLDS = [10_000, 100_000, 1_000_000, 1_000_000_000] as const

export interface MilestoneLogRow {
  milestoneId: string
  track: 'skills' | 'kills' | 'gold' | 'gatherings'
  name: string
  note: string
  current: number
  required: number
  unlocked: boolean
}

function formatCount(value: number): string {
  return value.toLocaleString('en-US')
}

function lowestSkillLevel(db: GameDatabase, save: PlayerSave): number {
  if (db.Skills.length === 0) return 0
  return Math.min(
    ...db.Skills.map((skill) => getSkillProgress(save, skill['Skill ID']).level),
  )
}

function countRow(
  track: MilestoneLogRow['track'],
  nameFor: (threshold: number) => string,
  current: number,
  threshold: number,
): MilestoneLogRow {
  const unlocked = current >= threshold
  return {
    milestoneId: `${track}-${threshold}`,
    track,
    name: nameFor(threshold),
    note: unlocked ? 'Reached' : `${formatCount(current)} / ${formatCount(threshold)}`,
    current,
    required: threshold,
    unlocked,
  }
}

export function milestoneLog(db: GameDatabase, save: PlayerSave): MilestoneLogRow[] {
  const lowest = lowestSkillLevel(db, save)
  const kills = Number(save.statistics.values.monsters_killed ?? 0)
  const gold = Number(save.statistics.values.gold_earned ?? 0)
  const gatherings = Number(save.statistics.values[GATHERING_ACTIONS_STAT] ?? 0)

  return [
    ...SKILL_THRESHOLDS.map((threshold) => {
      const unlocked = lowest >= threshold
      return {
        milestoneId: `skills-${threshold}`,
        track: 'skills' as const,
        name: `Every skill ${threshold}`,
        note: unlocked ? 'Reached' : `Reach level ${threshold} in every skill`,
        current: lowest,
        required: threshold,
        unlocked,
      }
    }),
    ...COUNT_THRESHOLDS.map((threshold) =>
      countRow('kills', (n) => `${formatCount(n)} monsters slain`, kills, threshold),
    ),
    ...COUNT_THRESHOLDS.map((threshold) =>
      countRow('gold', (n) => `${formatCount(n)} gold earned`, gold, threshold),
    ),
    ...COUNT_THRESHOLDS.map((threshold) =>
      countRow('gatherings', (n) => `${formatCount(n)} gatherings`, gatherings, threshold),
    ),
  ]
}
