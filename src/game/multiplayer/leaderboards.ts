import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  attachLeaderboardProfileJoins,
  isMissingLeaderboardProfileRelationship,
  leaderboardEntriesFrom,
  leaderboardRowsFor,
  REMOTE_LEADERBOARD_COLUMNS,
  REMOTE_LEADERBOARD_CONFLICT,
  REMOTE_LEADERBOARD_GUILD_COLUMNS,
  REMOTE_LEADERBOARD_PROFILE_COLUMNS,
  REMOTE_LEADERBOARD_VALUE_COLUMNS,
  REMOTE_NOT_CONFIGURED,
  REMOTE_TABLES,
  type RemoteRow,
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
  if (!error && data) {
    // The embedded profiles join is beyond what the client types can describe.
    return leaderboardEntriesFrom(data as unknown as RemoteRow[], boardKey)
  }
  if (!isMissingLeaderboardProfileRelationship(error?.message)) return []
  return fetchLeaderboardWithManualJoin(client, boardKey, limit)
}

async function fetchLeaderboardWithManualJoin(
  client: NonNullable<ReturnType<typeof getSupabaseClient>>,
  boardKey: MultiplayerBoardKey,
  limit: number,
): Promise<LeaderboardEntry[]> {
  const { data, error } = await client
    .from(REMOTE_TABLES.leaderboard)
    .select(REMOTE_LEADERBOARD_VALUE_COLUMNS)
    .eq('board_key', boardKey)
    .order('value', { ascending: false })
    .limit(limit)
  if (error || !data) return []
  const [{ data: profiles }, { data: guilds }] = await Promise.all([
    client.from(REMOTE_TABLES.profiles).select(REMOTE_LEADERBOARD_PROFILE_COLUMNS),
    client.from('guilds').select(REMOTE_LEADERBOARD_GUILD_COLUMNS),
  ])
  return leaderboardEntriesFrom(
    attachLeaderboardProfileJoins(
      data as unknown as RemoteRow[],
      (profiles ?? []) as unknown as RemoteRow[],
      (guilds ?? []) as unknown as RemoteRow[],
    ),
    boardKey,
  )
}

/**
 * The boards a launch build shows, in the order the picker lists them.
 *
 * Total XP has no board of its own: it rides along on Total Level & XP.
 */
export function launchBoardKeys(db: GameDatabase): MultiplayerBoardKey[] {
  const skills = db.Skills.filter((skill) => skill['Release Phase'] === 'Launch').map(
    (skill) => `skill:${skill['Skill ID']}` as MultiplayerBoardKey,
  )
  return [
    'total_level',
    'guild_total_level',
    'total_level_combat_1',
    'gold_earned',
    'monsters_killed',
    'critters_collected',
    'bounties_completed',
    'pvp_kd',
    ...skills,
  ]
}
