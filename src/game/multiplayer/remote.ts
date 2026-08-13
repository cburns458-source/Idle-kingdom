import type { PlayerSave } from '../save/types'
import type { LeaderboardSnapshotValues } from './snapshots'
import {
  DEFAULT_PLAYER_APPEARANCE,
  type ChatMessage,
  type CloudSaveRecord,
  type LeaderboardEntry,
  type MultiplayerBoardKey,
  type MultiplayerSession,
} from './types'

/**
 * The shape of a remote backend, as far as the client is concerned.
 *
 * Everything here is pure: what to ask a table for, and how to read a row it
 * hands back. The wire itself belongs to whichever client is running, so both
 * the web app and the Flutter app can send the same requests without agreeing
 * on an HTTP library.
 */

/** The tables the migrations define, named once. */
export const REMOTE_TABLES = {
  profiles: 'profiles',
  saves: 'player_saves',
  leaderboard: 'leaderboard_snapshots',
  chat: 'chat_messages',
} as const

/** The edge function that writes chat, since a client may not insert directly. */
export const REMOTE_SEND_CHAT_FUNCTION = 'send-chat'

export const REMOTE_NOT_CONFIGURED = 'Supabase is not configured.'
export const REMOTE_SIGN_UP_FAILED = 'Sign-up failed.'
export const REMOTE_SIGN_IN_FAILED = 'Sign-in failed.'
export const REMOTE_MAGIC_LINK_UNAVAILABLE =
  'Magic links require Supabase. Use email/password in local demo mode.'

/** How many messages a channel read asks for. */
export const REMOTE_CHAT_LIMIT = 50

/** As long as a username may be, which is what the account metadata carries. */
export const REMOTE_USERNAME_MAX_LENGTH = 24

export const REMOTE_SAVE_COLUMNS = 'save_version, updated_at, payload'
export const REMOTE_CHAT_COLUMNS = 'id, channel_key, user_id, username, body, created_at'
export const REMOTE_LEADERBOARD_COLUMNS =
  'user_id, board_key, value, profiles(username, appearance_json, guild_id, guilds(name))'

export type RemoteRow = Record<string, unknown>

export function remoteUsername(raw: string): string {
  return raw.trim().slice(0, REMOTE_USERNAME_MAX_LENGTH)
}

export function remoteEmail(raw: string): string {
  return raw.trim().toLowerCase()
}

/** The session a fresh sign-up produces, from what the auth call returned. */
export function sessionFromSignUp(
  userId: string,
  email: string,
  username: string,
  accessToken: string | null,
): MultiplayerSession {
  return {
    userId,
    email: remoteEmail(email),
    username: remoteUsername(username),
    accessToken: accessToken ?? '',
  }
}

/**
 * The session a sign-in produces.
 *
 * An account made outside the game has no username in its metadata, so the
 * local part of the email stands in, and failing that a generic name.
 */
export function sessionFromSignIn(
  userId: string,
  accountEmail: string | null,
  typedEmail: string,
  metadataUsername: string | null,
  accessToken: string | null,
): MultiplayerSession {
  const email = accountEmail ?? remoteEmail(typedEmail)
  const fallback = (accountEmail ?? '').split('@')[0]
  return {
    userId,
    email,
    username: metadataUsername ?? (fallback ? fallback : 'Adventurer'),
    accessToken: accessToken ?? '',
  }
}

/** The profile row a new account starts with. */
export function profileRowForSignUp(session: MultiplayerSession): RemoteRow {
  return {
    user_id: session.userId,
    username: session.username,
    privacy_public_skills: true,
  }
}

export function saveRowFor(userId: string, save: PlayerSave): RemoteRow {
  return {
    user_id: userId,
    save_version: save.saveVersion,
    updated_at: save.updatedAt,
    payload: save,
  }
}

/** The leaderboard rows one save is worth, all stamped with the same instant. */
export function leaderboardRowsFor(
  userId: string,
  snapshot: LeaderboardSnapshotValues,
  nowIso: string,
): RemoteRow[] {
  return snapshot.boards.map((board) => ({
    user_id: userId,
    board_key: board.boardKey,
    value: board.value,
    updated_at: nowIso,
  }))
}

/** The conflict target that makes a submit an update rather than a duplicate. */
export const REMOTE_LEADERBOARD_CONFLICT = 'user_id,board_key'

function str(value: unknown): string {
  return typeof value === 'string' ? value : String(value ?? '')
}

function num(value: unknown): number {
  return Number(value ?? 0)
}

/** A `player_saves` row as the cloud copy it stands for, or null if absent. */
export function cloudSaveRecordFrom(userId: string, row: RemoteRow | null): CloudSaveRecord | null {
  if (!row) return null
  return {
    userId,
    saveVersion: num(row.save_version),
    updatedAt: str(row.updated_at),
    payload: row.payload as PlayerSave,
  }
}

/**
 * Whether the stored copy should win over what is about to be uploaded.
 *
 * Both halves have to agree: a save that is newer by the clock but older by
 * version is a migration in progress, and the newer format wins.
 */
export function isRemoteSaveNewer(remote: CloudSaveRecord, local: PlayerSave): boolean {
  return (
    Date.parse(remote.updatedAt) > Date.parse(local.updatedAt) &&
    remote.saveVersion >= local.saveVersion
  )
}

export function chatMessageFrom(row: RemoteRow): ChatMessage {
  return {
    id: str(row.id),
    channelKey: str(row.channel_key),
    userId: str(row.user_id),
    username: str(row.username),
    body: str(row.body),
    createdAt: str(row.created_at),
  }
}

/**
 * A leaderboard row joined with its profile.
 *
 * The rank is the position the ordered read put it in, since the table stores
 * values rather than places.
 */
export function leaderboardEntryFrom(
  row: RemoteRow,
  boardKey: MultiplayerBoardKey,
  index: number,
): LeaderboardEntry {
  const profile = (row.profiles ?? null) as {
    username?: string
    appearance_json?: LeaderboardEntry['appearance']
    guilds?: { name?: string } | null
  } | null
  return {
    userId: str(row.user_id),
    username: profile?.username ?? 'Adventurer',
    appearance: profile?.appearance_json ?? DEFAULT_PLAYER_APPEARANCE,
    guildName: profile?.guilds?.name ?? null,
    boardKey,
    value: num(row.value),
    rank: index + 1,
  }
}

export function leaderboardEntriesFrom(
  rows: RemoteRow[],
  boardKey: MultiplayerBoardKey,
): LeaderboardEntry[] {
  return rows.map((row, index) => leaderboardEntryFrom(row, boardKey, index))
}
