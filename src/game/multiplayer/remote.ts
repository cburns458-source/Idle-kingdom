import type { BazaarPost, BazaarPostKind } from '../bazaar/types'
import type { BountyClaimRecord } from '../bounties/types'
import type { PlayerSave } from '../save/types'
import type { LeaderboardSnapshotValues } from './snapshots'
import {
  boardCarriesExperience,
  boardHidesZeroes,
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
  bountyClaims: 'bounty_claims',
  bazaarPosts: 'bazaar_posts',
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
export const REMOTE_CHAT_COLUMNS =
  'id, channel_key, user_id, username, body, created_at, guild_tag, rank_icon, guest'
export const REMOTE_LEADERBOARD_COLUMNS =
  'user_id, board_key, value, value_secondary, ' +
  'profiles(username, appearance_json, guild_id, guilds(name))'
export const REMOTE_LEADERBOARD_VALUE_COLUMNS = 'user_id, board_key, value, value_secondary'
export const REMOTE_LEADERBOARD_PROFILE_COLUMNS = 'user_id, username, appearance_json, guild_id'
export const REMOTE_LEADERBOARD_GUILD_COLUMNS = 'id, name'
export const REMOTE_BOUNTY_CLAIM_COLUMNS = 'hour_key, bounty_id, user_id, username, claimed_at'
export const REMOTE_BAZAAR_COLUMNS = 'id, kind, user_id, username, body, created_at'

/** How many Bazaar notices a read asks for. */
export const REMOTE_BAZAAR_LIMIT = 40

export type RemoteRow = Record<string, unknown>

export function remoteUsername(raw: string): string {
  return raw.trim().slice(0, REMOTE_USERNAME_MAX_LENGTH)
}

/** A unique stand-in until character creation names the account. */
export const PENDING_ACCOUNT_USERNAME_PREFIX = 'pending_'

export function pendingAccountUsername(userId: string): string {
  const compact = userId.replace(/[^a-zA-Z0-9]/g, '')
  const body = compact.length <= 16 ? compact : compact.slice(-16)
  return `${PENDING_ACCOUNT_USERNAME_PREFIX}${body}`
}

export function isPendingAccountUsername(username: string): boolean {
  return username.startsWith(PENDING_ACCOUNT_USERNAME_PREFIX)
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
    value_secondary: board.secondaryValue ?? 0,
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
  const message: ChatMessage = {
    id: str(row.id),
    channelKey: str(row.channel_key),
    userId: str(row.user_id),
    username: str(row.username),
    body: str(row.body),
    createdAt: str(row.created_at),
  }
  const guildTag = str(row.guild_tag ?? row.guildTag)
  const rankIcon = str(row.rank_icon ?? row.rankIcon)
  if (guildTag) message.guildTag = guildTag
  if (rankIcon) message.rankIcon = rankIcon
  if (row.guest === true) message.guest = true
  return message
}

/**
 * The message the send-chat function answered with.
 *
 * A function may hand back the row it inserted or the message it made of it, so
 * both spellings of each field are accepted rather than trusting one.
 */
export function chatMessageFromFunction(data: RemoteRow | null): ChatMessage | null {
  if (!data) return null
  const id = str(data.id)
  if (!id) return null
  return chatMessageFrom({
    id,
    channel_key: data.channelKey ?? data.channel_key,
    user_id: data.userId ?? data.user_id,
    username: data.username,
    body: data.body,
    created_at: data.createdAt ?? data.created_at,
    guild_tag: data.guildTag ?? data.guild_tag,
    rank_icon: data.rankIcon ?? data.rank_icon,
    guest: data.guest,
  })
}

/** What a send is refused with when the function answered with nothing usable. */
export const REMOTE_CHAT_SEND_FAILED = 'The chat message was not accepted.'

/** The same, for a Bazaar notice the board did not hand back. */
export const REMOTE_BAZAAR_POST_FAILED = 'The notice was not accepted.'

/** Why an upload stops: the account has a newer save than the one being sent. */
export const REMOTE_SAVE_CONFLICT = 'A newer cloud save exists.'

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
    ...(boardCarriesExperience(boardKey)
      ? { secondaryValue: num(row.value_secondary) }
      : {}),
  }
}

export function isMissingLeaderboardProfileRelationship(reason: string | null | undefined): boolean {
  if (!reason) return false
  const lower = reason.toLowerCase()
  return (
    lower.includes('relationship') &&
    lower.includes('leaderboard_snapshots') &&
    lower.includes('profiles')
  )
}

export function attachLeaderboardProfileJoins(
  boardRows: RemoteRow[],
  profiles: RemoteRow[],
  guilds: RemoteRow[],
): RemoteRow[] {
  const guildById = new Map(guilds.map((guild) => [str(guild.id), guild]))
  const profileByUser = new Map(profiles.map((profile) => [str(profile.user_id), profile]))
  return boardRows.map((row) => ({
    ...row,
    profiles: manualLeaderboardProfile(profileByUser.get(str(row.user_id)) ?? null, guildById),
  }))
}

function manualLeaderboardProfile(
  profile: RemoteRow | null,
  guildById: Map<string, RemoteRow>,
): RemoteRow | null {
  if (!profile) return null
  const guildId = str(profile.guild_id)
  const nested = profile.guilds as { name?: unknown } | null | undefined
  const name = guildById.get(guildId)?.name ?? nested?.name ?? profile.guild_name
  return {
    username: profile.username,
    appearance_json: profile.appearance_json,
    guild_id: profile.guild_id,
    guilds: name == null ? null : { name },
  }
}

export function leaderboardEntriesFrom(
  rows: RemoteRow[],
  boardKey: MultiplayerBoardKey,
): LeaderboardEntry[] {
  const entries = rows.map((row, index) => leaderboardEntryFrom(row, boardKey, index))
  // A zero on a qualify-or-not board means the player is not on it at all.
  if (!boardHidesZeroes(boardKey)) return entries
  return entries
    .filter((entry) => entry.value > 0)
    .map((entry, index) => ({ ...entry, rank: index + 1 }))
}

/**
 * The row that claims an hourly bounty first.
 *
 * `(hour_key, bounty_id)` is the table's primary key, which is what decides the
 * race: the insert that lands first is the one that stands, and a backend says
 * so rather than a client believing it.
 */
export function bountyClaimRowFor(
  session: MultiplayerSession,
  hourKey: string,
  bountyId: string,
): RemoteRow {
  return {
    hour_key: hourKey,
    bounty_id: bountyId,
    user_id: session.userId,
    username: session.username,
  }
}

export function bountyClaimFrom(row: RemoteRow): BountyClaimRecord {
  return {
    hourKey: str(row.hour_key),
    bountyId: str(row.bounty_id),
    userId: str(row.user_id),
    username: str(row.username),
    claimedAt: str(row.claimed_at),
  }
}

export function bazaarPostRowFor(
  session: MultiplayerSession,
  kind: BazaarPostKind,
  body: string,
): RemoteRow {
  return {
    kind,
    user_id: session.userId,
    username: session.username,
    body,
  }
}

export function bazaarPostFrom(row: RemoteRow): BazaarPost {
  return {
    id: str(row.id),
    kind: str(row.kind) as BazaarPostKind,
    userId: str(row.user_id),
    username: str(row.username),
    body: str(row.body),
    createdAt: str(row.created_at),
  }
}

/**
 * The Bazaar newest-last, the way a chat log reads.
 *
 * A backend hands the newest first, because that is the only way to ask for the
 * most recent forty, so the order is turned round once they arrive.
 */
export function bazaarPostsFrom(rows: RemoteRow[]): BazaarPost[] {
  return [...rows].reverse().map(bazaarPostFrom)
}
