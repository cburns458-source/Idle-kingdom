import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
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
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const snapshot = buildLeaderboardSnapshot(db, save)
  const rows = snapshot.boards.map((board) => ({
    user_id: session.userId,
    board_key: board.boardKey,
    value: board.value,
    updated_at: new Date().toISOString(),
  }))
  const { error } = await client.from('leaderboard_snapshots').upsert(rows, {
    onConflict: 'user_id,board_key',
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
    .from('leaderboard_snapshots')
    .select('user_id, board_key, value, profiles(username, appearance_json, guild_id, guilds(name))')
    .eq('board_key', boardKey)
    .order('value', { ascending: false })
    .limit(limit)
  if (error || !data) return []
  return data.map((row, index) => {
    const profile = row.profiles as {
      username?: string
      appearance_json?: LeaderboardEntry['appearance']
      guilds?: { name?: string } | null
    } | null
    return {
      userId: String(row.user_id),
      username: profile?.username ?? 'Adventurer',
      appearance: profile?.appearance_json ?? {
        skinTone: 'APR-0001',
        hairstyle: 'APR-0004',
        hairColor: 'APR-0007',
        expression: 'APR-0011',
        beard: 'APR-0014',
        genderPresentation: 'APR-0017',
      },
      guildName: profile?.guilds?.name ?? null,
      boardKey,
      value: Number(row.value),
      rank: index + 1,
    }
  })
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
