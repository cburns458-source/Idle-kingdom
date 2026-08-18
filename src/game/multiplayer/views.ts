import { PRESENCE_TTL_SECONDS } from './config'
import type { GameDatabase } from '../data/types'
import type { PlayerAppearance } from '../save/types'
import { filterProfanity } from './moderation'
import { boardLabel, launchBoardKeys } from './leaderboards'
import {
  CITADEL_CHAT_LOCATION_ID,
  DEFAULT_GUILD_RANK_LABELS,
  GUILD_CREATE_GOLD_COST,
  GUILD_MAX_MEMBERS,
  PROMOTABLE_GUILD_RANKS,
  guildRoleLabel,
  type ActivityPresence,
  type ChatChannel,
  type ChatMessage,
  type GuildApplication,
  type GuildEmblem,
  type GuildJoinPolicy,
  type GuildListing,
  type GuildMember,
  type GuildRankKey,
  type GuildRecord,
  type GuildRole,
  type LeaderboardEntry,
  type MultiplayerBoardKey,
  type PublicPlayerProfile,
} from './types'

/** How many skills a public profile shows before it stops. */
export const PUBLIC_PROFILE_SKILL_LIMIT = 8

/** The ranks a guild leader can rename, Leader included. */
export const EDITABLE_RANK_KEYS = Object.keys(DEFAULT_GUILD_RANK_LABELS) as GuildRankKey[]

export type GuildRosterSort = 'oldest' | 'newest'

function policyLabel(policy: GuildJoinPolicy): string {
  return policy === 'open' ? 'Accept applications' : 'Closed'
}

/** One row of the guild browser. */
export interface GuildBrowseRow {
  guildId: string
  /** `[IRN] Iron League`. */
  title: string
  /** `Accept applications · 4/25 · For the kingdom`. */
  subtitle: string
  emblem: GuildEmblem
  tag: string
  /** `Join`, `Apply`, or `Full`. */
  actionLabel: string
  /** Always `Guest` — guests do not count toward the member cap. */
  guestLabel: string
  /** True when the guild has no room left for members. */
  full: boolean
}

/**
 * The guilds worth showing for [query].
 *
 * A player who types `[irn]` means the tag they saw in chat, so the bracketed
 * form matches too.
 */
export function filterGuildListings(rows: GuildListing[], query: string): GuildListing[] {
  const needle = query.trim().toLowerCase()
  if (!needle) return rows
  return rows.filter(
    (row) =>
      row.name.toLowerCase().includes(needle) ||
      row.tag.toLowerCase().includes(needle) ||
      `[${row.tag.toLowerCase()}]`.includes(needle),
  )
}

export function guildBrowseRows(rows: GuildListing[], query = ''): GuildBrowseRow[] {
  return filterGuildListings(rows, query).map((row) => {
    const full = row.memberCount >= GUILD_MAX_MEMBERS
    return {
      guildId: row.id,
      title: `[${row.tag}] ${row.name}`,
      subtitle: [
        policyLabel(row.joinPolicy),
        `${row.memberCount}/${GUILD_MAX_MEMBERS}`,
        row.description || 'No description.',
      ].join(' · '),
      emblem: row.emblem,
      tag: row.tag,
      actionLabel: full ? 'Full' : row.joinPolicy === 'open' ? 'Join' : 'Apply',
      guestLabel: 'Guest',
      full,
    }
  })
}

/**
 * The message an application carries when the player writes nothing.
 *
 * A character with no name still has to introduce themselves, so a blank name
 * reads as Adventurer rather than as leading whitespace.
 */
export function defaultApplicationMessage(characterName: string | null): string {
  const name = characterName?.trim()
  return `${name || 'Adventurer'} requests to join`
}

/** What the guild home shows above its roster. */
export interface GuildHomeHeader {
  title: string
  subtitle: string
  emblem: GuildEmblem
  tag: string
  /** True when the viewer may open settings and manage ranks. */
  canManage: boolean
}

export function guildHomeHeader(
  guild: GuildRecord,
  memberCount: number,
  viewerId: string | null,
): GuildHomeHeader {
  return {
    title: `[${guild.tag}] ${guild.name}`,
    subtitle: `${policyLabel(guild.joinPolicy)} · ${memberCount}/${GUILD_MAX_MEMBERS} members`,
    emblem: guild.emblem,
    tag: guild.tag,
    canManage: viewerId !== null && guild.leaderId === viewerId,
  }
}

/** One rank a leader can move a member to, under this guild's own names. */
export interface GuildRankOption {
  role: GuildRole
  label: string
}

export function guildRankOptions(guild: GuildRecord): GuildRankOption[] {
  return PROMOTABLE_GUILD_RANKS.map((role) => ({
    role,
    label: guild.rankLabels[role] ?? DEFAULT_GUILD_RANK_LABELS[role],
  }))
}

/** One row of the guild roster. */
export interface GuildRosterRow {
  userId: string
  /** Position in the roster as shown, counting from one. */
  position: number
  username: string
  /** This guild's name for the member's rank. */
  rankLabel: string
  role: GuildRole
  totalLevel: number
  appearance: PlayerAppearance
  /** True when the viewer can change this member's rank. */
  manageable: boolean
  /** Presence `updatedAt`, or null when this member has never been seen. */
  lastOnlineAt: string | null
  isOnline: boolean
  /** `Online`, a relative time, or `Unknown`. */
  lastOnlineLabel: string
}

/** Presence age → the roster's last-online line. */
export function rosterLastOnline(
  updatedAt: string | null | undefined,
  nowMs: number,
): { lastOnlineAt: string | null; isOnline: boolean; lastOnlineLabel: string } {
  if (!updatedAt) {
    return { lastOnlineAt: null, isOnline: false, lastOnlineLabel: 'Unknown' }
  }
  const then = Date.parse(updatedAt)
  if (!Number.isFinite(then)) {
    return { lastOnlineAt: null, isOnline: false, lastOnlineLabel: 'Unknown' }
  }
  const age = nowMs - then
  if (age >= 0 && age < PRESENCE_TTL_SECONDS * 1000) {
    return { lastOnlineAt: updatedAt, isOnline: true, lastOnlineLabel: 'Online' }
  }
  const minutes = Math.floor(age / 60_000)
  if (minutes < 1) {
    return { lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: 'Just now' }
  }
  if (minutes < 60) {
    return { lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: `${minutes}m ago` }
  }
  const hours = Math.floor(minutes / 60)
  if (hours < 24) {
    return { lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: `${hours}h ago` }
  }
  const days = Math.floor(hours / 24)
  return { lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: `${days}d ago` }
}

/**
 * The roster in join order.
 *
 * Ties keep the order the backend returned, which is itself join order, so two
 * members who joined in the same second do not swap places between refreshes.
 */
export function guildRosterRows(
  guild: GuildRecord,
  members: GuildMember[],
  sort: GuildRosterSort,
  viewerId: string | null,
  presence: ActivityPresence[] = [],
  nowMs = 0,
): GuildRosterRow[] {
  const canManage = viewerId !== null && guild.leaderId === viewerId
  const seen = new Map(presence.map((row) => [row.userId, row.updatedAt]))
  const sorted = members
    .map((member, index) => ({ member, index }))
    .sort((a, b) => {
      const delta = Date.parse(a.member.joinedAt) - Date.parse(b.member.joinedAt)
      if (delta !== 0) return sort === 'oldest' ? delta : -delta
      return a.index - b.index
    })
  return sorted.map(({ member }, index) => {
    const online = rosterLastOnline(seen.get(member.userId), nowMs)
    return {
      userId: member.userId,
      position: index + 1,
      username: member.username,
      rankLabel: guildRoleLabel(guild, member.role),
      role: member.role,
      totalLevel: member.totalLevel,
      appearance: member.appearance,
      manageable: canManage && member.role !== 'leader',
      lastOnlineAt: online.lastOnlineAt,
      isOnline: online.isOnline,
      lastOnlineLabel: online.lastOnlineLabel,
    }
  })
}

/** One pending application, as the leader reads it. */
export interface GuildApplicationRow {
  applicationId: string
  username: string
  message: string
  guest?: boolean
}

export function guildApplicationRows(applications: GuildApplication[]): GuildApplicationRow[] {
  return applications.map((application) => {
    const guest = Boolean(application.guest)
    const row: GuildApplicationRow = {
      applicationId: application.id,
      username: application.username,
      message: guest
        ? application.message
          ? `Guest: ${application.message}`
          : 'Guest request.'
        : application.message || 'No message.',
    }
    if (guest) row.guest = true
    return row
  })
}

/** Everything the create-guild form needs to render itself. */
export interface CreateGuildFormView {
  goldCost: number
  /** `Costs 25 gold · you have 1,200`. */
  costLine: string
  /** `[IRN]`, or `[??]` before anything is typed. */
  tagPreview: string
  canAfford: boolean
  /** `Create for 25 gold`, or why the button is off. */
  submitLabel: string
}

/** Keeps a tag to the letters a tag may contain, as the player types. */
export function sanitizeGuildTagInput(raw: string): string {
  return raw.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4)
}

export function createGuildFormView(gold: number, tag: string): CreateGuildFormView {
  const canAfford = gold >= GUILD_CREATE_GOLD_COST
  return {
    goldCost: GUILD_CREATE_GOLD_COST,
    costLine: `Costs ${GUILD_CREATE_GOLD_COST} gold · you have ${gold.toLocaleString()}`,
    tagPreview: `[${sanitizeGuildTagInput(tag) || '??'}]`,
    canAfford,
    submitLabel: canAfford ? `Create for ${GUILD_CREATE_GOLD_COST} gold` : 'Not enough gold',
  }
}

/** One rank name field in guild settings. */
export interface RankLabelField {
  role: GuildRankKey
  /** `Officer slot`. */
  fieldLabel: string
  value: string
}

export function rankLabelFields(guild: GuildRecord): RankLabelField[] {
  return EDITABLE_RANK_KEYS.map((role) => ({
    role,
    fieldLabel: `${DEFAULT_GUILD_RANK_LABELS[role]} slot`,
    value: guild.rankLabels[role] ?? DEFAULT_GUILD_RANK_LABELS[role],
  }))
}

/** The sentence that asks a player to confirm leaving. */
export function leaveGuildPrompt(guild: GuildRecord): string {
  return `Leave [${guild.tag}] ${guild.name}? You will need to rejoin or reapply later.`
}

/** One board the leaderboard picker offers. */
export interface BoardOption {
  key: MultiplayerBoardKey
  label: string
}

export function boardOptions(db: GameDatabase): BoardOption[] {
  return launchBoardKeys(db).map((key) => ({ key, label: boardLabel(db, key) }))
}

/** One row of a leaderboard. */
export interface LeaderboardRowView {
  rank: number
  /** A user id for a player, a guild id for a guild. */
  entryId: string
  username: string
  /** The guild a player belongs to, or how full a guild is. */
  subtitle: string
  /** `1,204`, grouped the way the rest of the UI groups numbers. */
  valueLabel: string
  /** Set for a guild row, whose badge stands in for a portrait. */
  emblem: GuildEmblem | null
  appearance: PlayerAppearance
  isGuild: boolean
}

export function leaderboardRows(entries: LeaderboardEntry[]): LeaderboardRowView[] {
  return entries.map((entry) => {
    const isGuild = entry.entryKind === 'guild'
    return {
      rank: entry.rank,
      entryId: entry.userId,
      username: entry.username,
      subtitle: isGuild ? (entry.guildName ?? 'Guild') : (entry.guildName ?? 'No guild'),
      valueLabel: entry.value.toLocaleString(),
      emblem: isGuild ? (entry.emblem ?? null) : null,
      appearance: entry.appearance,
      isGuild,
    }
  })
}

/** What an empty board says, which differs for guilds. */
export function emptyBoardMessage(boardKey: MultiplayerBoardKey): string {
  return boardKey === 'guild_total_level'
    ? 'No guilds yet — create or join one from the Guilds tab.'
    : 'No scores on this board yet.'
}

/** One player standing in a shared space, or working the same activity. */
export interface PeerRowView {
  userId: string
  username: string
  /** `Combat 7 · Iron League`, with an em dash for an unknown level. */
  subtitle: string
  appearance: PlayerAppearance
}

export function peerRows(
  peers: ActivityPresence[],
  skillName: (skillId: string | null) => string,
): PeerRowView[] {
  return peers.map((peer) => ({
    userId: peer.userId,
    username: peer.username,
    subtitle: [
      `${skillName(peer.skillId)} ${peer.skillLevel ?? '—'}`,
      peer.guildName ?? null,
    ]
      .filter((part): part is string => part !== null)
      .join(' · '),
    appearance: peer.appearance,
  }))
}

/** What the Citadel visitor list says about one visitor. */
export function citadelVisitorSubtitle(visitor: ActivityPresence): string {
  const guild = visitor.guildName ?? 'No guild'
  return visitor.skillLevel != null ? `${guild} · Lv ${visitor.skillLevel}` : guild
}

/** The public profile sheet, with nothing left to derive. */
export interface PublicProfileView {
  userId: string
  username: string
  appearance: PlayerAppearance
  /** `Total level 214 · Iron League · 12 achievements`. */
  summaryLine: string
  /** At most [PUBLIC_PROFILE_SKILL_LIMIT] lines like `Combat 12`. */
  skillLines: string[]
  /** True when the player hid their skills. */
  skillsHidden: boolean
}

export function publicProfileView(
  profile: PublicPlayerProfile,
  skillName: (skillId: string | null) => string,
): PublicProfileView {
  return {
    userId: profile.userId,
    username: profile.username,
    appearance: profile.appearance,
    summaryLine: [
      `Total level ${profile.totalLevel}`,
      profile.guildName ?? null,
      `${profile.achievementsUnlocked} achievements`,
    ]
      .filter((part): part is string => part !== null)
      .join(' · '),
    skillLines: profile.publicSkills
      .slice(0, PUBLIC_PROFILE_SKILL_LIMIT)
      .map((skill) => `${skillName(skill.skillId)} ${skill.level}`),
    skillsHidden: profile.publicSkills.length === 0,
  }
}

/** The rooms the chat drawer offers, in tab order. */
export type ChatTab = 'global' | 'local' | 'guild' | 'guest' | 'dm'

export const CHAT_TABS: ChatTab[] = ['global', 'local', 'guild', 'guest', 'dm']

/** One tab of the chat drawer. */
export interface ChatTabView {
  tab: ChatTab
  /** `Global`, `Citadel` inside the hub, `Private (3)` when messages wait. */
  label: string
  /** False for guild or guest chat without a room to show. */
  enabled: boolean
  selected: boolean
}

/**
 * Which location the Local tab is talking about.
 *
 * Every Citadel district shares one room, so the hub answers with its own id
 * rather than the district the player happens to stand in.
 */
export function chatLocalLocationId(locationId: string, citadelHub: boolean): string {
  return citadelHub ? CITADEL_CHAT_LOCATION_ID : locationId
}

/** How many unread messages a badge admits to, before it gives up counting. */
export function unreadBadgeLabel(count: number): string | null {
  if (count <= 0) return null
  return count > 9 ? '9+' : String(count)
}

export function chatTabs({
  selected,
  citadelHub,
  hasGuild,
  hasGuest,
  unreadDms,
}: {
  selected: ChatTab
  citadelHub: boolean
  hasGuild: boolean
  hasGuest: boolean
  unreadDms: number
}): ChatTabView[] {
  return CHAT_TABS.map((tab) => ({
    tab,
    label:
      tab === 'global'
        ? 'Global'
        : tab === 'local'
          ? citadelHub
            ? 'Citadel'
            : 'Local'
          : tab === 'guild'
            ? 'Guild'
            : tab === 'guest'
              ? 'Guest'
              : unreadDms > 0
                ? `Private (${unreadDms})`
                : 'Private',
    enabled: tab === 'guild' ? hasGuild : tab === 'guest' ? hasGuest : true,
    selected: tab === selected,
  }))
}

/**
 * The room a tab writes to, or null when it is not a room at all.
 *
 * Private messages are a reply to a person rather than a channel, and guild
 * or guest chat without a guild has nowhere to go.
 */
export function chatChannelForTab(
  tab: ChatTab,
  {
    locationId,
    citadelHub,
    guildId,
    guestGuildId,
  }: {
    locationId: string
    citadelHub: boolean
    guildId: string | null
    guestGuildId?: string | null
  },
): ChatChannel | null {
  switch (tab) {
    case 'global':
      return { kind: 'global' }
    case 'local':
      return { kind: 'local', locationId: chatLocalLocationId(locationId, citadelHub) }
    case 'guild':
      return guildId ? { kind: 'guild', guildId } : null
    case 'guest':
      return guestGuildId ? { kind: 'guild', guildId: guestGuildId } : null
    case 'dm':
      return null
  }
}

/** What an empty room says, which differs for private messages. */
export function emptyChatMessage(tab: ChatTab): string {
  return tab === 'dm' ? 'No private messages yet.' : 'No messages yet.'
}

/** Why the Private tab has no composer. */
export const CHAT_DM_HINT = 'Reply to players from Nearby Adventurers or their public profile.'

/** What a player is told when they try to use guild chat without a guild. */
export const CHAT_NO_GUILD_NOTICE = 'Join a guild to use guild chat.'

export const CHAT_NO_GUEST_NOTICE = 'Guest a guild to use guest chat.'

export const CHAT_VIEW_GUILDS_LABEL = 'View guilds'

/** Where the read cursor for one account's DMs is kept. */
export function dmReadCursorKey(userId: string): string {
  return `idle-kingdoms.chat.dm-read-at:${userId}`
}

/** One line of a chat room. */
export interface ChatLineView {
  messageId: string
  username: string
  body: string
  /** True for the viewer's own messages, which read differently. */
  mine: boolean
}

export function chatLines(
  messages: ChatMessage[],
  viewerId: string | null,
  { filterProfanityEnabled = false }: { filterProfanityEnabled?: boolean } = {},
): ChatLineView[] {
  return messages.map((message) => ({
    messageId: message.id,
    username: chatLineUsername(message),
    body: filterProfanityEnabled ? filterProfanity(message.body) : message.body,
    mine: viewerId !== null && message.userId === viewerId,
  }))
}

/** `[TAG] Hero` in global/local, rank or Guest in guild rooms. */
export function chatLineUsername(message: ChatMessage): string {
  if (message.channelKey.startsWith('guild:')) {
    if (message.guest) return `Guest ${message.username}`
    const icon = message.rankIcon
    const rank = message.rankLabel
    if (icon && rank) return `${icon} ${rank} ${message.username}`
    if (rank) return `${rank} ${message.username}`
    return message.username
  }
  const tag = message.guildTag
  if (tag) return `[${tag}] ${message.username}`
  return message.username
}

/** What the account panel says about where multiplayer data lives. */
export function multiplayerModeLine(mode: 'local' | 'supabase'): string {
  const backend = mode === 'local' ? 'local demo backend' : 'Supabase'
  return `Accounts use the ${backend}. Sign in to play and sync progress.`
}

/** The line every signed-out multiplayer panel shows instead of content. */
export const SIGN_IN_PROMPT = 'Sign in to use multiplayer features.'

/** Guilds word the same prompt around guilds, since that is the tab in hand. */
export const GUILD_SIGN_IN_PROMPT = 'Sign in to use guilds.'
