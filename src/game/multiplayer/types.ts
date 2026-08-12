import type { PlayerAppearance, PlayerSave } from '../save/types'

export type MultiplayerBoardKey =
  | 'total_level'
  | 'guild_total_level'
  | 'total_experience'
  | 'gold_earned'
  | 'monsters_killed'
  | 'critters_collected'
  | 'bounties_completed'
  | `skill:${string}`

export interface MultiplayerProfile {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildId: string | null
  guildName: string | null
  privacyPublicSkills: boolean
  updatedAt: string
}

export interface CloudSaveRecord {
  userId: string
  saveVersion: number
  updatedAt: string
  payload: PlayerSave
}

export interface LeaderboardEntry {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildName: string | null
  boardKey: MultiplayerBoardKey
  value: number
  rank: number
  /** Present for guild boards (e.g. guild_total_level). */
  entryKind?: 'player' | 'guild'
  emblem?: GuildEmblem | null
}

export type ChatChannel =
  | { kind: 'global' }
  | { kind: 'local'; locationId: string }
  | { kind: 'guild'; guildId: string }
  | { kind: 'dm'; pairKey: string }

export interface ChatMessage {
  id: string
  channelKey: string
  userId: string
  username: string
  body: string
  createdAt: string
}

/** Leader plus four promotable ranks. */
export type GuildRole = 'leader' | 'officer' | 'veteran' | 'member' | 'recruit'

export type GuildJoinPolicy = 'open' | 'closed'

/** All guild roles, including leader — used for customizable display names. */
export type GuildRankKey = GuildRole

export const DEFAULT_GUILD_RANK_LABELS: Record<GuildRankKey, string> = {
  leader: 'Leader',
  officer: 'Officer',
  veteran: 'Veteran',
  member: 'Member',
  recruit: 'Recruit',
}

export const PROMOTABLE_GUILD_RANKS: Exclude<GuildRole, 'leader'>[] = [
  'officer',
  'veteran',
  'member',
  'recruit',
]

export const GUILD_CREATE_GOLD_COST = 25
export const GUILD_MAX_MEMBERS = 25

export const GUILD_EMBLEM_COLORS = [
  '#5c4027',
  '#2f6b3a',
  '#3d5a80',
  '#7a2f2f',
  '#6b4f1d',
  '#4a3b6b',
  '#1f4b5c',
  '#5a2d4a',
] as const

export const GUILD_EMBLEM_SYMBOLS = [
  'sword',
  'shield',
  'tree',
  'dragon',
  'star',
  'flame',
  'moon',
  'eagle',
  'castle',
  'gem',
  'wolf',
  'lion',
] as const

export type GuildEmblemSymbol = (typeof GUILD_EMBLEM_SYMBOLS)[number]

export interface GuildEmblem {
  /** Banner fill color (CSS hex). */
  color: string
  /** Solid icon id shown on the banner. */
  symbol: GuildEmblemSymbol | string
}

/** Map legacy emoji emblems to solid icon ids. */
export const GUILD_EMBLEM_EMOJI_TO_SYMBOL: Record<string, GuildEmblemSymbol> = {
  '⚔️': 'sword',
  '🛡️': 'shield',
  '🌲': 'tree',
  '🐉': 'dragon',
  '⭐': 'star',
  '🔥': 'flame',
  '🌙': 'moon',
  '🦅': 'eagle',
  '🏰': 'castle',
  '💎': 'gem',
  '🐺': 'wolf',
  '🦁': 'lion',
}

export interface GuildRecord {
  id: string
  name: string
  /** 2–4 letter tag, displayed as [TAG]. */
  tag: string
  description: string
  emblem: GuildEmblem
  leaderId: string
  joinPolicy: GuildJoinPolicy
  rankLabels: Record<GuildRankKey, string>
  createdAt: string
}

export interface GuildMember {
  guildId: string
  userId: string
  username: string
  role: GuildRole
  joinedAt: string
  appearance: PlayerAppearance
  totalLevel: number
}

export interface CreateGuildInput {
  name: string
  tag: string
  description?: string
  emblem: GuildEmblem
}

export interface GuildApplication {
  id: string
  guildId: string
  userId: string
  username: string
  message: string
  createdAt: string
}

export interface GuildProject {
  id: string
  guildId: string
  name: string
  description: string
  goalAmount: number
  contributed: number
  rewardLabel: string
}

export interface GuildChallenge {
  id: string
  guildId: string
  name: string
  boardKey: MultiplayerBoardKey
  goalValue: number
  currentValue: number
}

export interface ActivityPresence {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildName: string | null
  locationId: string
  currentActivityId: string | null
  skillId: string | null
  skillLevel: number | null
  outfitCosmeticId: string | null
  mountCosmeticId: string | null
  updatedAt: string
  expiresAt: string
}

export interface MultiplayerSession {
  userId: string
  email: string
  username: string
  accessToken: string
}

export interface PublicPlayerProfile {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildName: string | null
  publicSkills: Array<{ skillId: string; level: number; xp: number }>
  achievementsUnlocked: number
  totalLevel: number
}

export const CITADEL_LOCATION_ID = 'LOC-CITADEL'
export const CITADEL_PRESENCE_CHANNEL = 'citadel:hub'
export const MULTIPLAYER_SESSION_KEY = 'idle-kingdoms.multiplayer.session'
export const MULTIPLAYER_LOCAL_DB_KEY = 'idle-kingdoms.multiplayer.local-db'

export function chatChannelKey(channel: ChatChannel): string {
  if (channel.kind === 'global') return 'global'
  if (channel.kind === 'local') return `local:${channel.locationId}`
  if (channel.kind === 'guild') return `guild:${channel.guildId}`
  return `dm:${channel.pairKey}`
}

export function dmPairKey(userA: string, userB: string): string {
  return [userA, userB].sort().join(':')
}
