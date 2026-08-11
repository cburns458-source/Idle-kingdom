import type { PlayerAppearance, PlayerSave } from '../save/types'

export type MultiplayerBoardKey =
  | 'total_level'
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

export type GuildRole = 'leader' | 'officer' | 'member'

export interface GuildRecord {
  id: string
  name: string
  description: string
  emblem: string
  leaderId: string
  createdAt: string
}

export interface GuildMember {
  guildId: string
  userId: string
  username: string
  role: GuildRole
  joinedAt: string
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
