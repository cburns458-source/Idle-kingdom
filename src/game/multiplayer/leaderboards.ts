import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  leaderboardEntriesFrom,
  leaderboardRowsFor,
  REMOTE_LEADERBOARD_COLUMNS,
  REMOTE_LEADERBOARD_CONFLICT,
  REMOTE_NOT_CONFIGURED,
  REMOTE_TABLES,
} from './remote'
import { buildLeaderboardSnapshot } from './snapshots'
import type { LeaderboardEntry, MultiplayerBoardKey } from './types'

export { boardLabel, buildLeaderboardSnapshot } from './snapshots'

export async function submitLeaderboardFromSave(
  db: GameDatabase,
  save: PlayerSave,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to submit leaderboard scores.' }

  if (multiplayerMode() === 'local') {
    getLocalBackend().submitLeaderboardSnapshot(db, session.userId, save)
    return { ok: true }
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const snapshot = buildLeaderboardSnapshot(db, save)
  const rows = leaderboardRowsFor(session.userId, snapshot, new Date().toISOString())
  const { error } = await client.from(REMOTE_TABLES.leaderboard).upsert(rows, {
    onConflict: REMOTE_LEADERBOARD_CONFLICT,
  })
  if (error) return { ok: false, reason: error.message }
  return { ok: true }
}

export async function fetchLeaderboard(
  boardKey: MultiplayerBoardKey,
  limit = 25,
): Promise<LeaderboardEntry[]> {
  if (multiplayerMode() === 'local') {
    return getLocalBackend().listLeaderboard(boardKey, limit)
  }

  const client = getSupabaseClient()
  if (!client) return []
  const { data, error } = await client
    .from(REMOTE_TABLES.leaderboard)
    .select(REMOTE_LEADERBOARD_COLUMNS)
    .eq('board_key', boardKey)
    .order('value', { ascending: false })
    .limit(limit)
  if (error || !data) return []
  return leaderboardEntriesFrom(data, boardKey)
}

export function launchBoardKeys(db: GameDatabase): MultiplayerBoardKey[] {
  const skills = db.Skills.filter((skill) => skill['Release Phase'] === 'Launch').map(
    (skill) => `skill:${skill['Skill ID']}` as MultiplayerBoardKey,
  )
  return [
    'total_level',
    'guild_total_level',
    'total_experience',
    'gold_earned',
    'monsters_killed',
    'critters_collected',
    'bounties_completed',
    ...skills,
  ]
}
