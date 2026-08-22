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
  type RemoteRow,
} from './remote'
import { rankLeaderboardEntries, buildLeaderboardSnapshot } from './snapshots'
import {
  DEFAULT_PLAYER_APPEARANCE,
  GUILD_MAX_MEMBERS,
  playerAppearanceFromRemote,
  type GuildEmblem,
  type LeaderboardEntry,
  type MultiplayerBoardKey,
} from './types'

export { boardLabel, buildLeaderboardSnapshot, publicProfileStatsFromLeaderboardRows } from './snapshots'

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
  await client.from(REMOTE_TABLES.profiles).upsert({
    user_id: session.userId,
    username: session.username,
    appearance_json: save.appearance,
  })
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
  if (boardKey === 'guild_total_level') {
    return fetchGuildTotalLevelBoard(client, limit)
  }
  const { data, error } = await client
    .from(REMOTE_TABLES.leaderboardEntries)
    .select(REMOTE_LEADERBOARD_COLUMNS)
    .eq('board_key', boardKey)
    .order('value', { ascending: false })
    .limit(limit)
  if (error || !data) return []
  return leaderboardEntriesFrom(data as unknown as RemoteRow[], boardKey)
}

async function fetchGuildTotalLevelBoard(
  client: NonNullable<ReturnType<typeof getSupabaseClient>>,
  limit: number,
): Promise<LeaderboardEntry[]> {
  const [guilds, members] = await Promise.all([
    client.from(REMOTE_TABLES.guilds).select('id, name, tag, emblem, leader_id'),
    client.from(REMOTE_TABLES.guildMembers).select('guild_id, user_id, appearance_json, total_level'),
  ])
  if (guilds.error || !guilds.data) return []
  const byGuild = new Map<string, Array<Record<string, unknown>>>()
  for (const row of (members.data ?? []) as RemoteRow[]) {
    const guildId = String(row.guild_id ?? '')
    if (!guildId) continue
    const list = byGuild.get(guildId) ?? []
    list.push(row)
    byGuild.set(guildId, list)
  }
  const scored: LeaderboardEntry[] = (guilds.data as RemoteRow[]).map((guild) => {
    const roster = byGuild.get(String(guild.id ?? '')) ?? []
    const value = roster.reduce((sum, row) => sum + Number(row.total_level ?? 0), 0)
    const leader =
      roster.find((row) => String(row.user_id ?? '') === String(guild.leader_id ?? '')) ??
      roster[0]
    return {
      userId: String(guild.id ?? ''),
      username: `[${String(guild.tag ?? '')}] ${String(guild.name ?? '')}`,
      appearance: leader
        ? playerAppearanceFromRemote(leader.appearance_json)
        : DEFAULT_PLAYER_APPEARANCE,
      guildName: `${roster.length}/${GUILD_MAX_MEMBERS} members`,
      boardKey: 'guild_total_level',
      value,
      rank: 0,
      entryKind: 'guild',
      emblem: (guild.emblem as GuildEmblem | null) ?? null,
    }
  })
  return rankLeaderboardEntries(scored).slice(0, limit)
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
    'log_completion',
    'pvp_kd',
    ...skills,
  ]
}
