import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { rankedPvpKd } from '../pvp/matchmaking'
import { totalLevel, totalSkillXp } from '../skills/totals'
import type { MultiplayerBoardKey } from './types'

export interface LeaderboardSnapshotValues {
  boards: Array<{ boardKey: MultiplayerBoardKey; value: number }>
}

/** Build leaderboard snapshot values from a local save (submitted on logout / safe sync). */
export function buildLeaderboardSnapshot(
  db: GameDatabase,
  save: PlayerSave,
): LeaderboardSnapshotValues {
  const crittersCollected = (save.critterCollections ?? []).reduce(
    (sum, row) => sum + Math.max(0, row.count),
    0,
  )
  const boards: Array<{ boardKey: MultiplayerBoardKey; value: number }> = [
    { boardKey: 'total_level', value: totalLevel(save) },
    { boardKey: 'total_experience', value: totalSkillXp(save) },
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
  if (boardKey === 'total_level') return 'Total Level'
  if (boardKey === 'guild_total_level') return 'Guild Total Level'
  if (boardKey === 'total_experience') return 'Total XP'
  if (boardKey === 'gold_earned') return 'Gold Earned'
  if (boardKey === 'monsters_killed') return 'Monsters Killed'
  if (boardKey === 'critters_collected') return 'Critters Collected'
  if (boardKey === 'bounties_completed') return 'Bounties Completed'
  if (boardKey === 'pvp_kd') return 'PvP K/D'
  if (boardKey.startsWith('skill:')) {
    const skillId = boardKey.slice('skill:'.length)
    return db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId
  }
  return boardKey
}
