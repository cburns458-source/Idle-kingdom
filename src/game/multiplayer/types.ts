import {
  DEFAULT_BEARD_ID,
  DEFAULT_EXPRESSION_ID,
  DEFAULT_GENDER_PRESENTATION_ID,
  DEFAULT_HAIR_COLOR_ID,
  DEFAULT_HAIRSTYLE_ID,
  DEFAULT_SKIN_TONE_ID,
  type PlayerAppearance,
  type PlayerSave,
} from '../save/types'

/** The appearance a row falls back to when no save or profile supplied one. */
export const DEFAULT_PLAYER_APPEARANCE: PlayerAppearance = {
  skinTone: DEFAULT_SKIN_TONE_ID,
  hairstyle: DEFAULT_HAIRSTYLE_ID,
  hairColor: DEFAULT_HAIR_COLOR_ID,
  expression: DEFAULT_EXPRESSION_ID,
  beard: DEFAULT_BEARD_ID,
  genderPresentation: DEFAULT_GENDER_PRESENTATION_ID,
}

/** A remote `appearance_json`, which may be missing, `{}`, or only partly filled. */
export function playerAppearanceFromRemote(value: unknown): PlayerAppearance {
  if (!value || typeof value !== 'object') return DEFAULT_PLAYER_APPEARANCE
  const raw = value as Record<string, unknown>
  const opt = (key: string): string | undefined => {
    const field = raw[key]
    return typeof field === 'string' && field.length > 0 ? field : undefined
  }
  return {
    skinTone: opt('skinTone') ?? DEFAULT_PLAYER_APPEARANCE.skinTone,
    hairstyle: opt('hairstyle') ?? DEFAULT_PLAYER_APPEARANCE.hairstyle,
    hairColor: opt('hairColor') ?? DEFAULT_PLAYER_APPEARANCE.hairColor,
    expression: opt('expression') ?? DEFAULT_PLAYER_APPEARANCE.expression,
    beard: opt('beard') ?? DEFAULT_PLAYER_APPEARANCE.beard,
    genderPresentation:
      opt('genderPresentation') ?? DEFAULT_PLAYER_APPEARANCE.genderPresentation,
  }
}

export type MultiplayerBoardKey =
  /** Ranks by total level and carries total XP alongside it. */
  | 'total_level'
  | 'guild_total_level'
  /** Written before the boards were combined. No longer offered in the picker. */
  | 'total_experience'
  /** Total level among players who have never raised Combat past level 1. */
  | 'total_level_combat_1'
  | 'gold_earned'
  | 'monsters_killed'
  | 'critters_collected'
  | 'bounties_completed'
  | 'pvp_kd'
  | 'log_completion'
  | `skill:${string}`

/**
 * Boards that carry a second number: total level and per-skill ranks show XP
 * under the level.
 *
 * The guild board is not one of them: its value is a whole roster totalled by
 * the backend, and it was never two boards to begin with.
 */
export function boardCarriesExperience(boardKey: MultiplayerBoardKey): boolean {
  return (
    boardKey === 'total_level' ||
    boardKey === 'total_level_combat_1' ||
    boardKey.startsWith('skill:')
  )
}

/**
 * A board only some players stand on, where a zero means "does not qualify"
 * rather than a real score of nothing.
 */
export function boardHidesZeroes(boardKey: MultiplayerBoardKey): boolean {
  return boardKey === 'total_level_combat_1'
}

export const CHAT_PRIVACY_PUBLIC = 'public'
export const CHAT_PRIVACY_FRIENDS = 'friends'
export const CHAT_PRIVACY_OFF = 'off'

export interface MultiplayerProfile {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildId: string | null
  guildName: string | null
  privacyPublicSkills: boolean
  privacyPublicGear: boolean
  privacyDirectMessages: string
  privacyLocalChat: string
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
  /** Player rows only. Guild board names already include the tag. */
  guildTag?: string | null
  boardKey: MultiplayerBoardKey
  value: number
  rank: number
  /**
   * The second number a combined board shows: total XP under a total level.
   * Absent on boards that rank by one thing.
   */
  secondaryValue?: number
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
  guildTag?: string
  rankIcon?: string
  guest?: boolean
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

export const GUILD_RANK_ICON_THEME_STRIPES = 'stripes'
export const GUILD_RANK_ICON_THEME_CROWNS = 'crowns'

export function normalizeRankIconTheme(raw: unknown): string {
  return raw === GUILD_RANK_ICON_THEME_CROWNS
    ? GUILD_RANK_ICON_THEME_CROWNS
    : GUILD_RANK_ICON_THEME_STRIPES
}

/** Guest speakers use this in guild chat, in place of a rank mark. */
export const GUILD_GUEST_CHAT_ICON = '☺'

/** Leader first, then officer, veteran, member, recruit. */
export function guildRankSortIndex(role: string): number {
  if (role === 'leader') return 0
  if (role === 'officer') return 1
  if (role === 'veteran') return 2
  if (role === 'member') return 3
  return 4
}

export function guildRankIcon(theme: string, role: string): string {
  if (normalizeRankIconTheme(theme) === GUILD_RANK_ICON_THEME_CROWNS) {
    if (role === 'leader') return '♔'
    if (role === 'officer') return '◆'
    if (role === 'veteran') return '●'
    if (role === 'member') return '•'
    return '·'
  }
  if (role === 'leader') return '★'
  if (role === 'officer') return '▍▍▍▍'
  if (role === 'veteran') return '▍▍▍'
  if (role === 'member') return '▍▍'
  return '▍'
}

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
  guestAutoAccept?: boolean
  rankIconTheme?: string
}

/** A guild as the browser lists it, with how full it is. */
export type GuildListing = GuildRecord & { memberCount: number }

/** This guild's own name for [role], falling back to the role's key. */
export function guildRoleLabel(guild: GuildRecord, role: GuildRole): string {
  return guild.rankLabels[role] ?? role
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

/** A player who may use this guild's chat without appearing on the roster. */
export interface GuildGuest {
  guildId: string
  userId: string
  username: string
  joinedAt: string
  appearance: PlayerAppearance
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
  guest?: boolean
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

export interface PublicEquippedSlot {
  slotId: string
  itemId: string
  quantity: number
  enchantmentId: string | null
}

export function publicEquipmentFromSave(save: PlayerSave | null | undefined): PublicEquippedSlot[] {
  if (!save) return []
  const out: PublicEquippedSlot[] = []
  for (const [slotId, stack] of Object.entries(save.equipment.slots)) {
    if (!stack?.itemId) continue
    out.push({
      slotId,
      itemId: stack.itemId,
      quantity: stack.quantity,
      enchantmentId: stack.enchantmentId ?? null,
    })
  }
  return out
}

export interface PublicPlayerProfile {
  userId: string
  username: string
  appearance: PlayerAppearance
  guildName: string | null
  publicSkills: Array<{ skillId: string; level: number; xp: number }>
  achievementsUnlocked: number
  totalLevel: number
  /** Whole percent of the Log. 0 when the save cannot be read. */
  logCompletionPercent?: number
  /** Null when the player hid their gear. */
  publicEquipment?: PublicEquippedSlot[] | null
}

/** Citadel Plaza — hub presence / Nearby listing target. */
export const CITADEL_LOCATION_ID = 'LOC-0028'
/** Stable Local-chat key while on the Citadel sub-map → `local:citadel`. */
export const CITADEL_CHAT_LOCATION_ID = 'citadel'
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

/** True when [channelKey] is a private thread that includes [userId]. */
export function dmChannelInvolves(channelKey: string, userId: string): boolean {
  if (!channelKey.startsWith('dm:')) return false
  return channelKey.slice(3).split(':').includes(userId)
}
