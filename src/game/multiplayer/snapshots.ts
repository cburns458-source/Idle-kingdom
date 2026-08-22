import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { levelForTotalXp } from '../activity/xp'
import { logCompletion } from '../log/log'
import { rankedPvpKd } from '../pvp/matchmaking'
import { isPacifistSave, totalLevel, totalSkillXp } from '../skills/totals'
import type { LeaderboardEntry, MultiplayerBoardKey, PublicPlayerProfile } from './types'

export interface LeaderboardBoardValue {
  boardKey: MultiplayerBoardKey
  value: number
  /** The second number a combined board shows, and the tie-break on the first. */
  secondaryValue?: number
}

export interface LeaderboardSnapshotValues {
  boards: LeaderboardBoardValue[]
}

/** Build leaderboard snapshot values from a local save (submitted on a ranking update). */
export function buildLeaderboardSnapshot(
  db: GameDatabase,
  save: PlayerSave,
): LeaderboardSnapshotValues {
  const crittersCollected = (save.critterCollections ?? []).reduce(
    (sum, row) => sum + Math.max(0, row.count),
    0,
  )
  const level = totalLevel(save)
  const xp = totalSkillXp(save)
  const pacifist = isPacifistSave(save)

  const boards: LeaderboardBoardValue[] = [
    { boardKey: 'total_level', value: level, secondaryValue: xp },
    // Zero keeps a fighter off the board without needing a delete: the read
    // drops zero rows, and one is written again the moment they qualify.
    {
      boardKey: 'total_level_combat_1',
      value: pacifist ? level : 0,
      secondaryValue: pacifist ? xp : 0,
    },
    { boardKey: 'gold_earned', value: Number(save.statistics.values.gold_earned ?? 0) },
    { boardKey: 'monsters_killed', value: Number(save.statistics.values.monsters_killed ?? 0) },
    { boardKey: 'critters_collected', value: crittersCollected },
    {
      boardKey: 'bounties_completed',
      value: Number(save.statistics.values.bounties_completed ?? 0),
    },
    {
      boardKey: 'pvp_kd',
      value: rankedPvpKd(save.rankedPvpWins ?? 0, save.rankedPvpLosses ?? 0),
    },
    {
      boardKey: 'log_completion',
      value: logCompletion(db, save).overall.percent,
    },
  ]

  for (const skill of db.Skills.filter((row) => row['Release Phase'] === 'Launch')) {
    const progress = save.skills.find((row) => row.skillId === skill['Skill ID'])
    const level = progress?.level ?? 1
    const xp = progress?.xp ?? 0
    // Post-100 boards rank by XP; at/under 100 rank by level (XP still stored for ties).
    const value = level > 100 ? xp : level
    boards.push({ boardKey: `skill:${skill['Skill ID']}`, value })
  }

  return { boards }
}

export function boardLabel(db: GameDatabase, boardKey: MultiplayerBoardKey): string {
  if (boardKey === 'total_level') return 'Total Level & XP'
  if (boardKey === 'guild_total_level') return 'Guild Total Level'
  if (boardKey === 'total_level_combat_1') return 'Pacifist Total Level'
  if (boardKey === 'total_experience') return 'Total XP'
  if (boardKey === 'gold_earned') return 'Gold Earned'
  if (boardKey === 'monsters_killed') return 'Monsters Killed'
  if (boardKey === 'critters_collected') return 'Critters Collected'
  if (boardKey === 'bounties_completed') return 'Bounties Completed'
  if (boardKey === 'pvp_kd') return 'PvP K/D'
  if (boardKey === 'log_completion') return 'Log Completion'
  if (boardKey.startsWith('skill:')) {
    const skillId = boardKey.slice('skill:'.length)
    return db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId
  }
  return boardKey
}

/**
 * Order a board and stamp places on it.
 *
 * Highest value first, then the second number where a board carries one, then
 * name, so two players on the same total level are split by experience.
 */
export function rankLeaderboardEntries(entries: LeaderboardEntry[]): LeaderboardEntry[] {
  return [...entries]
    .sort(
      (a, b) =>
        b.value - a.value ||
        (b.secondaryValue ?? 0) - (a.secondaryValue ?? 0) ||
        a.username.localeCompare(b.username),
    )
    .map((entry, index) => ({ ...entry, rank: index + 1 }))
}

/** Public skill levels and total level reconstructed from ranking snapshots. */
export interface PublicProfileStats {
  totalLevel: number
  totalXp?: number
  skills: PublicPlayerProfile['publicSkills']
  logCompletionPercent?: number
}

/** Turns `leaderboard_snapshots` rows for one account into profile stats. */
export function publicProfileStatsFromLeaderboardRows(
  rows: Array<Record<string, unknown>>,
  db?: GameDatabase,
): PublicProfileStats {
  let totalLevelValue = 0
  let totalXp: number | undefined
  let logCompletionPercent = 0
  const skills: PublicPlayerProfile['publicSkills'] = []
  for (const row of rows) {
    const key = String(row.board_key ?? row.boardKey ?? '')
    const value = Number(row.value ?? 0)
    if (key === 'total_level') {
      totalLevelValue = value
      const secondary = row.value_secondary ?? row.secondaryValue
      if (typeof secondary === 'number') totalXp = secondary
      continue
    }
    if (key === 'log_completion') {
      logCompletionPercent = value
      continue
    }
    if (!key.startsWith('skill:')) continue
    const skillId = key.slice('skill:'.length)
    if (!skillId) continue
    if (value > 100) {
      skills.push({
        skillId,
        level: db ? levelForTotalXp(db, value) : 101,
        xp: value,
      })
    } else {
      skills.push({ skillId, level: value < 1 ? 1 : value, xp: 0 })
    }
  }
  return { totalLevel: totalLevelValue, totalXp, skills, logCompletionPercent }
}
