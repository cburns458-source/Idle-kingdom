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
import { pendingAccountUsername, isPendingAccountUsername, remoteUsername } from './remote'
import { totalLevel } from '../skills/totals'
import { CHAT_COOLDOWN_SECONDS, PRESENCE_AWAY_TTL_SECONDS } from './config'
import { containsSlur, CHAT_DISABLED_NOTICE } from './moderation'
import { buildLeaderboardSnapshot, rankLeaderboardEntries } from './snapshots'
import type { GameDatabase } from '../data/types'
import { prepareBazaarPost } from '../bazaar/post'
import {
  createGuildRefusal,
  guildDescriptionFromInput,
  guildNameFromInput,
  guildTagFromInput,
} from '../guild/rules'
import type { BazaarPost, BazaarPostKind } from '../bazaar/types'
import type { BountyClaimRecord } from '../bounties/types'
import {
  boardCarriesExperience,
  boardHidesZeroes,
  chatChannelKey,
  DEFAULT_GUILD_RANK_LABELS,
  GUILD_CREATE_GOLD_COST,
  GUILD_EMBLEM_COLORS,
  GUILD_EMBLEM_EMOJI_TO_SYMBOL,
  GUILD_EMBLEM_SYMBOLS,
  GUILD_MAX_MEMBERS,
  GUILD_RANK_ICON_THEME_STRIPES,
  MULTIPLAYER_LOCAL_DB_KEY,
  guildRankIcon,
  normalizeRankIconTheme,
  type ActivityPresence,
  type ChatChannel,
  type ChatMessage,
  type CloudSaveRecord,
  type CreateGuildInput,
  type GuildApplication,
  type GuildChallenge,
  type GuildEmblem,
  type GuildGuest,
  type GuildJoinPolicy,
  type GuildMember,
  type GuildProject,
  type GuildRankKey,
  type GuildRecord,
  type GuildRole,
  type LeaderboardEntry,
  type MultiplayerBoardKey,
  type MultiplayerProfile,
  type MultiplayerSession,
  type PublicPlayerProfile,
} from './types'

interface LocalDb {
  users: Array<{
    userId: string
    email: string
    username: string
    password: string
    chatBanned?: boolean
  }>
  profiles: MultiplayerProfile[]
  saves: CloudSaveRecord[]
  leaderboards: Array<{
    userId: string
    boardKey: MultiplayerBoardKey
    value: number
    /** The second number a combined board shows. Zero on single-value boards. */
    secondaryValue?: number
    updatedAt: string
  }>
  messages: ChatMessage[]
  lastChatAt: Record<string, string>
  blocks: Array<{ userId: string; blockedUserId: string }>
  reports: Array<{ id: string; reporterId: string; targetUserId: string; reason: string; createdAt: string }>
  guilds: GuildRecord[]
  members: GuildMember[]
  applications: GuildApplication[]
  projects: GuildProject[]
  challenges: GuildChallenge[]
  presence: ActivityPresence[]
  mutes: Array<{ userId: string; mutedUserId: string }>
  friendRequests: Array<{ fromUserId: string; toUserId: string; createdAt: string }>
  friends: Array<{ userA: string; userB: string }>
  bountyClaims: BountyClaimRecord[]
  bazaarPosts: BazaarPost[]
  guests?: GuildGuest[]
}

function defaultAppearance(): PlayerAppearance {
  return {
    skinTone: DEFAULT_SKIN_TONE_ID,
    hairstyle: DEFAULT_HAIRSTYLE_ID,
    hairColor: DEFAULT_HAIR_COLOR_ID,
    expression: DEFAULT_EXPRESSION_ID,
    beard: DEFAULT_BEARD_ID,
    genderPresentation: DEFAULT_GENDER_PRESENTATION_ID,
  }
}

function emptyDb(): LocalDb {
  return {
    users: [],
    profiles: [],
    saves: [],
    leaderboards: [],
    messages: [],
    lastChatAt: {},
    blocks: [],
    reports: [],
    guilds: [],
    members: [],
    applications: [],
    projects: [],
    challenges: [],
    presence: [],
    mutes: [],
    friendRequests: [],
    friends: [],
    bountyClaims: [],
    bazaarPosts: [],
  }
}

function normalizeSymbol(raw: unknown): (typeof GUILD_EMBLEM_SYMBOLS)[number] {
  if (typeof raw !== 'string' || !raw.trim()) return GUILD_EMBLEM_SYMBOLS[0]
  const value = raw.trim()
  if ((GUILD_EMBLEM_SYMBOLS as readonly string[]).includes(value)) {
    return value as (typeof GUILD_EMBLEM_SYMBOLS)[number]
  }
  return GUILD_EMBLEM_EMOJI_TO_SYMBOL[value] ?? GUILD_EMBLEM_SYMBOLS[0]
}

function normalizeEmblem(raw: unknown): GuildEmblem {
  if (raw && typeof raw === 'object' && 'color' in raw && 'symbol' in raw) {
    const emblem = raw as GuildEmblem
    return {
      color: typeof emblem.color === 'string' ? emblem.color : GUILD_EMBLEM_COLORS[0],
      symbol: normalizeSymbol(emblem.symbol),
    }
  }
  if (typeof raw === 'string' && raw.trim()) {
    return { color: GUILD_EMBLEM_COLORS[0], symbol: normalizeSymbol(raw) }
  }
  return { color: GUILD_EMBLEM_COLORS[0], symbol: GUILD_EMBLEM_SYMBOLS[0] }
}

function normalizeRankLabels(raw: unknown): Record<GuildRankKey, string> {
  const base = { ...DEFAULT_GUILD_RANK_LABELS }
  if (!raw || typeof raw !== 'object') return base
  const labels = raw as Partial<Record<GuildRankKey, string>>
  for (const key of Object.keys(base) as GuildRankKey[]) {
    const value = labels[key]?.trim()
    if (value) base[key] = value.slice(0, 18)
  }
  return base
}

function normalizeRole(raw: unknown): GuildRole {
  if (raw === 'leader' || raw === 'officer' || raw === 'veteran' || raw === 'member' || raw === 'recruit') {
    return raw
  }
  return 'recruit'
}

function normalizeTag(name: string, tag: unknown): string {
  if (typeof tag === 'string') {
    const clean = tag.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4)
    if (clean.length >= 2) return clean
  }
  const fromName = name.replace(/[^a-zA-Z]/g, '').toUpperCase().slice(0, 4)
  return fromName.length >= 2 ? fromName : 'GD'
}

function normalizeGuild(raw: GuildRecord): GuildRecord {
  return {
    ...raw,
    tag: normalizeTag(raw.name ?? 'Guild', (raw as GuildRecord & { tag?: unknown }).tag),
    emblem: normalizeEmblem(raw.emblem),
    joinPolicy:
      (raw as GuildRecord & { joinPolicy?: GuildJoinPolicy }).joinPolicy === 'closed'
        ? 'closed'
        : 'open',
    rankLabels: normalizeRankLabels((raw as GuildRecord & { rankLabels?: unknown }).rankLabels),
    description: raw.description ?? '',
  }
}

function loadDb(storage: Storage = localStorage): LocalDb {
  try {
    const raw = storage.getItem(MULTIPLAYER_LOCAL_DB_KEY)
    if (!raw) return emptyDb()
    const parsed = JSON.parse(raw) as LocalDb
    const merged = { ...emptyDb(), ...parsed }
    merged.guilds = (merged.guilds ?? []).map((guild) => normalizeGuild(guild as GuildRecord))
    merged.members = (merged.members ?? []).map((member) => ({
      ...member,
      role: normalizeRole(member.role),
      appearance: member.appearance ?? defaultAppearance(),
      totalLevel: Number.isFinite(member.totalLevel) ? member.totalLevel : 1,
    }))
    merged.bountyClaims = Array.isArray(merged.bountyClaims) ? merged.bountyClaims : []
    merged.bazaarPosts = Array.isArray(merged.bazaarPosts) ? merged.bazaarPosts : []
    merged.guests = Array.isArray(merged.guests) ? merged.guests : []
    return merged
  } catch {
    return emptyDb()
  }
}

function saveDb(db: LocalDb, storage: Storage = localStorage): void {
  const payload: LocalDb = { ...db }
  if (!payload.guests?.length) delete payload.guests
  storage.setItem(MULTIPLAYER_LOCAL_DB_KEY, JSON.stringify(payload))
}

/**
 * The host facilities the backend would otherwise reach for directly. Supplied
 * so a test — and the Dart parity replay — can pin both.
 */
export interface LocalBackendPorts {
  nowMs: () => number
  newId: (prefix: string) => string
}

export class LocalMultiplayerBackend {
  private storage: Storage
  private ports: LocalBackendPorts

  constructor(storage: Storage = localStorage, ports?: Partial<LocalBackendPorts>) {
    this.storage = storage
    this.ports = {
      nowMs: ports?.nowMs ?? (() => Date.now()),
      newId:
        ports?.newId ??
        ((prefix: string) =>
          `${prefix}_${Math.random().toString(36).slice(2, 10)}_${Date.now().toString(36)}`),
    }
  }

  private db(): LocalDb {
    return loadDb(this.storage)
  }

  private write(db: LocalDb): void {
    saveDb(db, this.storage)
  }

  private now(): number {
    return this.ports.nowMs()
  }

  private nowIso(): string {
    return new Date(this.ports.nowMs()).toISOString()
  }

  private newId(prefix: string): string {
    return this.ports.newId(prefix)
  }

  signUp(
    email: string,
    username: string,
    password: string,
  ): { ok: true; session: MultiplayerSession } | { ok: false; reason: string } {
    const db = this.db()
    const cleanEmail = email.trim().toLowerCase()
    const trimmedUser = username.trim()
    if (
      !cleanEmail.includes('@') ||
      password.length < 4 ||
      (trimmedUser.length > 0 && trimmedUser.length < 2)
    ) {
      return { ok: false, reason: 'Enter a valid email, username (2+), and password (4+).' }
    }
    if (db.users.some((user) => user.email === cleanEmail)) {
      return { ok: false, reason: 'An account with that email already exists.' }
    }
    const userId = this.newId('usr')
    const cleanUser =
      trimmedUser.length >= 2 ? trimmedUser.slice(0, 24) : pendingAccountUsername(userId)
    if (db.users.some((user) => user.username.toLowerCase() === cleanUser.toLowerCase())) {
      return { ok: false, reason: 'That username is taken.' }
    }
    db.users.push({ userId, email: cleanEmail, username: cleanUser, password })
    db.profiles.push({
      userId,
      username: cleanUser,
      appearance: defaultAppearance(),
      guildId: null,
      guildName: null,
      privacyPublicSkills: true,
      updatedAt: this.nowIso(),
    })
    this.write(db)
    return {
      ok: true,
      session: {
        userId,
        email: cleanEmail,
        username: cleanUser,
        accessToken: `local:${userId}`,
      },
    }
  }

  signIn(
    email: string,
    password: string,
  ): { ok: true; session: MultiplayerSession } | { ok: false; reason: string } {
    const db = this.db()
    const cleanEmail = email.trim().toLowerCase()
    const user = db.users.find((row) => row.email === cleanEmail && row.password === password)
    if (!user) return { ok: false, reason: 'Invalid email or password.' }
    return {
      ok: true,
      session: {
        userId: user.userId,
        email: user.email,
        username: user.username,
        accessToken: `local:${user.userId}`,
      },
    }
  }

  /** Names the account from the first character name. Later names do not replace it. */
  claimAccountUsername(
    userId: string,
    name: string,
  ): { ok: true } | { ok: false; reason: string } {
    const cleaned = remoteUsername(name)
    if (cleaned.length < 2) return { ok: false, reason: 'Enter a name to continue.' }
    const db = this.db()
    const account = db.users.find((row) => row.userId === userId)
    if (!account) return { ok: false, reason: 'Sign in required.' }
    if (account.username.toLowerCase() === cleaned.toLowerCase()) return { ok: true }
    if (!isPendingAccountUsername(account.username)) return { ok: true }
    if (
      db.users.some(
        (row) => row.userId !== userId && row.username.toLowerCase() === cleaned.toLowerCase(),
      )
    ) {
      return { ok: false, reason: 'That name is taken.' }
    }
    account.username = cleaned
    const profile = db.profiles.find((row) => row.userId === userId)
    if (profile) {
      profile.username = cleaned
      profile.updatedAt = this.nowIso()
    }
    this.write(db)
    return { ok: true }
  }

  getProfile(userId: string): MultiplayerProfile | null {
    return this.db().profiles.find((row) => row.userId === userId) ?? null
  }

  /**
   * Gives an account authenticated elsewhere a profile row here.
   *
   * The features this backend still owns — guilds, presence, public profiles —
   * all hang off a profile, so an account that signed in against Supabase needs
   * one before it can join anything. Returns the row already present, so signing
   * in twice does not reset a name or a guild.
   */
  registerProfile(userId: string, username: string): MultiplayerProfile {
    const existing = this.getProfile(userId)
    if (existing) return existing
    const db = this.db()
    const profile: MultiplayerProfile = {
      userId,
      username,
      appearance: defaultAppearance(),
      guildId: null,
      guildName: null,
      privacyPublicSkills: true,
      updatedAt: this.nowIso(),
    }
    db.profiles.push(profile)
    this.write(db)
    return profile
  }

  upsertProfile(
    userId: string,
    patch: Partial<Pick<MultiplayerProfile, 'appearance' | 'privacyPublicSkills' | 'username'>>,
  ): MultiplayerProfile | null {
    const db = this.db()
    const index = db.profiles.findIndex((row) => row.userId === userId)
    if (index < 0) return null
    db.profiles[index] = {
      ...db.profiles[index]!,
      ...patch,
      updatedAt: this.nowIso(),
    }
    this.write(db)
    return db.profiles[index]!
  }

  readCloudSave(userId: string): CloudSaveRecord | null {
    return this.db().saves.find((row) => row.userId === userId) ?? null
  }

  /**
   * Stores [save] as the account's cloud copy.
   *
   * A newer stored copy stops the write, so a stale device cannot quietly erase
   * progress made elsewhere. `force` is the player answering that prompt: they
   * have been shown the other save and chosen this one.
   */
  writeCloudSave(
    userId: string,
    save: PlayerSave,
    options?: { force?: boolean },
  ):
    | { ok: true; record: CloudSaveRecord }
    | { ok: false; reason: string; remote?: CloudSaveRecord } {
    const db = this.db()
    const existing = db.saves.find((row) => row.userId === userId)
    if (
      !options?.force &&
      existing &&
      Date.parse(existing.updatedAt) > Date.parse(save.updatedAt) &&
      existing.saveVersion >= save.saveVersion
    ) {
      return {
        ok: false,
        reason: 'A newer cloud save exists. Load it or overwrite carefully.',
        remote: existing,
      }
    }
    const record: CloudSaveRecord = {
      userId,
      saveVersion: save.saveVersion,
      updatedAt: save.updatedAt || this.nowIso(),
      payload: save,
    }
    db.saves = db.saves.filter((row) => row.userId !== userId)
    db.saves.push(record)
    this.write(db)
    return { ok: true, record }
  }

  submitLeaderboardSnapshot(dbGame: GameDatabase, userId: string, save: PlayerSave): void {
    const profile = this.getProfile(userId)
    if (!profile) return
    const snapshot = buildLeaderboardSnapshot(dbGame, save)
    const local = this.db()
    const updatedAt = this.nowIso()
    for (const board of snapshot.boards) {
      local.leaderboards = local.leaderboards.filter(
        (row) => !(row.userId === userId && row.boardKey === board.boardKey),
      )
      local.leaderboards.push({
        userId,
        boardKey: board.boardKey,
        value: board.value,
        secondaryValue: board.secondaryValue ?? 0,
        updatedAt,
      })
    }
    // Refresh profile cosmetics snapshot from save.
    local.profiles = local.profiles.map((row) =>
      row.userId === userId
        ? { ...row, appearance: save.appearance, username: save.characterName || row.username, updatedAt }
        : row,
    )
    this.write(local)
  }

  listLeaderboard(boardKey: MultiplayerBoardKey, limit = 25): LeaderboardEntry[] {
    const db = this.db()
    if (boardKey === 'guild_total_level') {
      const scored = db.guilds
        .map((guild) => {
          const members = this.guildMembers(guild.id)
          const value = members.reduce((sum, member) => sum + member.totalLevel, 0)
          const leader =
            members.find((member) => member.userId === guild.leaderId) ?? members[0] ?? null
          return {
            userId: guild.id,
            username: `[${guild.tag}] ${guild.name}`,
            appearance: leader?.appearance ?? defaultAppearance(),
            guildName: `${members.length}/${GUILD_MAX_MEMBERS} members`,
            boardKey,
            value,
            rank: 0,
            entryKind: 'guild' as const,
            emblem: guild.emblem,
          }
        })
      return rankLeaderboardEntries(scored).slice(0, limit)
    }
    const entries = db.leaderboards
      .filter((row) => row.boardKey === boardKey)
      .map((row) => {
        const profile = db.profiles.find((entry) => entry.userId === row.userId)
        return {
          userId: row.userId,
          username: profile?.username ?? 'Adventurer',
          appearance: profile?.appearance ?? defaultAppearance(),
          guildName: profile?.guildName ?? null,
          boardKey,
          value: row.value,
          rank: 0,
          ...(boardCarriesExperience(boardKey)
            ? { secondaryValue: row.secondaryValue ?? 0 }
            : {}),
          entryKind: 'player' as const,
          emblem: null,
        }
      })
    // A zero on a qualify-or-not board means the player is not on it at all.
    const standing = boardHidesZeroes(boardKey)
      ? entries.filter((entry) => entry.value > 0)
      : entries
    return rankLeaderboardEntries(standing).slice(0, limit)
  }

  private guildMemberCount(db: LocalDb, guildId: string): number {
    return db.members.filter((row) => row.guildId === guildId).length
  }

  private guestsOf(db: LocalDb): GuildGuest[] {
    return db.guests ?? []
  }

  private canSpeakInGuild(db: LocalDb, guildId: string, userId: string): boolean {
    return (
      db.members.some((row) => row.guildId === guildId && row.userId === userId) ||
      this.guestsOf(db).some((row) => row.guildId === guildId && row.userId === userId)
    )
  }

  private guildForMember(db: LocalDb, userId: string): GuildRecord | undefined {
    const membership = db.members.find((row) => row.userId === userId)
    if (!membership) return undefined
    return db.guilds.find((row) => row.id === membership.guildId)
  }

  sendChat(
    session: MultiplayerSession,
    channel: ChatChannel,
    body: string,
  ): { ok: true; message: ChatMessage } | { ok: false; reason: string } {
    const trimmed = body.trim().slice(0, 240)
    if (!trimmed) return { ok: false, reason: 'Message is empty.' }
    const key = chatChannelKey(channel)
    const cooldown =
      channel.kind === 'global'
        ? CHAT_COOLDOWN_SECONDS.global
        : channel.kind === 'local'
          ? CHAT_COOLDOWN_SECONDS.local
          : channel.kind === 'guild'
            ? CHAT_COOLDOWN_SECONDS.guild
            : CHAT_COOLDOWN_SECONDS.dm
    const db = this.db()
    const account = db.users.find((row) => row.userId === session.userId)
    if (account?.chatBanned) {
      return { ok: false, reason: CHAT_DISABLED_NOTICE }
    }
    if (containsSlur(trimmed)) {
      if (account) {
        account.chatBanned = true
        this.write(db)
      }
      return { ok: false, reason: CHAT_DISABLED_NOTICE }
    }
    const stampKey = `${session.userId}:${key}`
    const last = db.lastChatAt[stampKey]
    if (last && this.now() - Date.parse(last) < cooldown * 1000) {
      const wait = Math.ceil((cooldown * 1000 - (this.now() - Date.parse(last))) / 1000)
      return { ok: false, reason: `Wait ${wait}s before chatting again.` }
    }
    if (channel.kind === 'guild' && !this.canSpeakInGuild(db, channel.guildId, session.userId)) {
      return { ok: false, reason: 'Join the guild to use guild chat.' }
    }
    const memberGuild = this.guildForMember(db, session.userId)
    let rankIcon: string | undefined
    let guest = false
    if (channel.kind === 'guild') {
      const member = db.members.find(
        (row) => row.guildId === channel.guildId && row.userId === session.userId,
      )
      if (member) {
        const guild = db.guilds.find((row) => row.id === channel.guildId)
        rankIcon = guildRankIcon(guild?.rankIconTheme ?? GUILD_RANK_ICON_THEME_STRIPES, member.role)
      } else {
        guest = true
      }
    }
    const message: ChatMessage = {
      id: this.newId('msg'),
      channelKey: key,
      userId: session.userId,
      username: session.username,
      body: trimmed,
      createdAt: this.nowIso(),
    }
    if (memberGuild?.tag) message.guildTag = memberGuild.tag
    if (rankIcon) message.rankIcon = rankIcon
    if (guest) message.guest = true
    db.messages.push(message)
    db.lastChatAt[stampKey] = message.createdAt
    this.write(db)
    return { ok: true, message }
  }

  listChat(channel: ChatChannel, viewerId: string, limit = 50): ChatMessage[] {
    const db = this.db()
    const key = chatChannelKey(channel)
    const muted = new Set(
      db.mutes.filter((row) => row.userId === viewerId).map((row) => row.mutedUserId),
    )
    const blocked = new Set(
      db.blocks.filter((row) => row.userId === viewerId).map((row) => row.blockedUserId),
    )
    return db.messages
      .filter(
        (row) =>
          row.channelKey === key && !muted.has(row.userId) && !blocked.has(row.userId),
      )
      .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt))
      .slice(-limit)
  }

  /** Direct messages involving the viewer (inbox-style, oldest → newest). */
  listDirectMessages(viewerId: string, limit = 80): ChatMessage[] {
    const db = this.db()
    const muted = new Set(
      db.mutes.filter((row) => row.userId === viewerId).map((row) => row.mutedUserId),
    )
    const blocked = new Set(
      db.blocks.filter((row) => row.userId === viewerId).map((row) => row.blockedUserId),
    )
    return db.messages
      .filter(
        (row) =>
          row.channelKey.startsWith('dm:') &&
          row.channelKey.includes(viewerId) &&
          !muted.has(row.userId) &&
          !blocked.has(row.userId),
      )
      .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt))
      .slice(-limit)
  }

  /** Unread DMs sent by other players after `sinceIso` (exclusive). */
  countUnreadDirectMessages(viewerId: string, sinceIso: string | null): number {
    const sinceMs = sinceIso ? Date.parse(sinceIso) : 0
    return this.listDirectMessages(viewerId, 200).filter(
      (row) => row.userId !== viewerId && Date.parse(row.createdAt) > sinceMs,
    ).length
  }

  muteUser(userId: string, mutedUserId: string): void {
    const db = this.db()
    if (!db.mutes.some((row) => row.userId === userId && row.mutedUserId === mutedUserId)) {
      db.mutes.push({ userId, mutedUserId })
      this.write(db)
    }
  }

  blockUser(userId: string, blockedUserId: string): void {
    const db = this.db()
    if (!db.blocks.some((row) => row.userId === userId && row.blockedUserId === blockedUserId)) {
      db.blocks.push({ userId, blockedUserId })
      this.write(db)
    }
  }

  reportUser(reporterId: string, targetUserId: string, reason: string): void {
    const db = this.db()
    db.reports.push({
      id: this.newId('rpt'),
      reporterId,
      targetUserId,
      reason: reason.trim().slice(0, 200) || 'Unspecified',
      createdAt: this.nowIso(),
    })
    this.write(db)
  }

  private memberSnapshot(
    db: LocalDb,
    userId: string,
    username: string,
  ): Pick<GuildMember, 'appearance' | 'totalLevel' | 'username'> {
    const profile = db.profiles.find((row) => row.userId === userId)
    const cloud = db.saves.find((row) => row.userId === userId)
    const level = cloud ? totalLevel(cloud.payload) : 1
    return {
      username: cloud?.payload.characterName?.trim() || profile?.username || username,
      appearance: cloud?.payload.appearance ?? profile?.appearance ?? defaultAppearance(),
      totalLevel: Math.max(1, level),
    }
  }

  createGuild(
    session: MultiplayerSession,
    input: CreateGuildInput,
    goldAvailable: number,
  ):
    | { ok: true; guild: GuildRecord; goldCost: number }
    | { ok: false; reason: string } {
    const refusal = createGuildRefusal(input, goldAvailable)
    if (refusal) return { ok: false, reason: refusal }
    const clean = guildNameFromInput(input.name)
    const tag = guildTagFromInput(input.tag)
    const db = this.db()
    if (db.members.some((row) => row.userId === session.userId)) {
      return { ok: false, reason: 'Leave your current guild before creating another.' }
    }
    if (db.guilds.some((row) => row.name.toLowerCase() === clean.toLowerCase())) {
      return { ok: false, reason: 'That guild name is taken.' }
    }
    if (db.guilds.some((row) => row.tag.toUpperCase() === tag)) {
      return { ok: false, reason: 'That guild tag is taken.' }
    }
    const snapshot = this.memberSnapshot(db, session.userId, session.username)
    const guild: GuildRecord = {
      id: this.newId('gld'),
      name: clean,
      tag,
      description: guildDescriptionFromInput(input.description),
      emblem: normalizeEmblem(input.emblem),
      leaderId: session.userId,
      joinPolicy: 'open',
      rankLabels: { ...DEFAULT_GUILD_RANK_LABELS },
      createdAt: this.nowIso(),
    }
    db.guilds.push(guild)
    db.members.push({
      guildId: guild.id,
      userId: session.userId,
      username: snapshot.username,
      role: 'leader',
      joinedAt: this.nowIso(),
      appearance: snapshot.appearance,
      totalLevel: snapshot.totalLevel,
    })
    db.profiles = db.profiles.map((row) =>
      row.userId === session.userId
        ? { ...row, guildId: guild.id, guildName: guild.name, updatedAt: this.nowIso() }
        : row,
    )
    db.projects.push({
      id: this.newId('gprj'),
      guildId: guild.id,
      name: 'Guild Storehouse',
      description: 'Pool resources for cosmetic recognition.',
      goalAmount: 1000,
      contributed: 0,
      rewardLabel: 'Guild banner cosmetic (recognition)',
    })
    db.challenges.push({
      id: this.newId('gch'),
      guildId: guild.id,
      name: 'Weekly Monster Hunt',
      boardKey: 'monsters_killed',
      goalValue: 100,
      currentValue: 0,
    })
    this.write(db)
    return { ok: true, guild, goldCost: GUILD_CREATE_GOLD_COST }
  }

  listGuilds(): Array<GuildRecord & { memberCount: number }> {
    const db = this.db()
    return [...db.guilds]
      .map((guild) => ({
        ...guild,
        memberCount: this.guildMemberCount(db, guild.id),
      }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }

  getGuild(guildId: string): GuildRecord | null {
    return this.db().guilds.find((row) => row.id === guildId) ?? null
  }

  guildGuests(guildId: string): GuildGuest[] {
    return this.guestsOf(this.db()).filter((row) => row.guildId === guildId)
  }

  guildMembers(guildId: string): GuildMember[] {
    const db = this.db()
    return db.members
      .filter((row) => row.guildId === guildId)
      .map((row) => {
        const snapshot = this.memberSnapshot(db, row.userId, row.username)
        return {
          ...row,
          role: normalizeRole(row.role),
          username: snapshot.username,
          appearance: snapshot.appearance,
          totalLevel: snapshot.totalLevel,
        }
      })
  }

  applyToGuild(
    session: MultiplayerSession,
    guildId: string,
    message: string,
  ): { ok: true; joined: boolean } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild) return { ok: false, reason: 'Guild not found.' }
    if (db.members.some((row) => row.userId === session.userId)) {
      return { ok: false, reason: 'Already in a guild.' }
    }
    if (this.guildMemberCount(db, guildId) >= GUILD_MAX_MEMBERS) {
      return { ok: false, reason: `That guild is full (${GUILD_MAX_MEMBERS} members).` }
    }
    if (guild.joinPolicy === 'open') {
      const snapshot = this.memberSnapshot(db, session.userId, session.username)
      db.members.push({
        guildId: guild.id,
        userId: session.userId,
        username: snapshot.username,
        role: 'recruit',
        joinedAt: this.nowIso(),
        appearance: snapshot.appearance,
        totalLevel: snapshot.totalLevel,
      })
      db.profiles = db.profiles.map((row) =>
        row.userId === session.userId
          ? { ...row, guildId: guild.id, guildName: guild.name, updatedAt: this.nowIso() }
          : row,
      )
      db.applications = db.applications.filter(
        (row) => !(row.guildId === guildId && row.userId === session.userId),
      )
      db.guests = this.guestsOf(db).filter(
        (row) => !(row.guildId === guildId && row.userId === session.userId),
      )
      this.write(db)
      return { ok: true, joined: true }
    }
    if (
      db.applications.some(
        (row) => row.guildId === guildId && row.userId === session.userId && !row.guest,
      )
    ) {
      return { ok: false, reason: 'Application already pending.' }
    }
    db.applications.push({
      id: this.newId('app'),
      guildId,
      userId: session.userId,
      username: session.username,
      message: message.trim().slice(0, 120),
      createdAt: this.nowIso(),
    })
    this.write(db)
    return { ok: true, joined: false }
  }

  joinAsGuest(
    session: MultiplayerSession,
    guildId: string,
    message: string,
  ): { ok: true; joined: boolean } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild) return { ok: false, reason: 'Guild not found.' }
    if (db.members.some((row) => row.guildId === guildId && row.userId === session.userId)) {
      return { ok: false, reason: 'Already a member of that guild.' }
    }
    if (this.guestsOf(db).some((row) => row.guildId === guildId && row.userId === session.userId)) {
      return { ok: false, reason: 'Already a guest of that guild.' }
    }
    if (this.guestsOf(db).some((row) => row.userId === session.userId)) {
      return { ok: false, reason: 'Leave your current guest guild first.' }
    }
    if (guild.guestAutoAccept) {
      const snapshot = this.memberSnapshot(db, session.userId, session.username)
      db.guests = this.guestsOf(db)
      db.guests.push({
        guildId: guild.id,
        userId: session.userId,
        username: snapshot.username,
        joinedAt: this.nowIso(),
        appearance: snapshot.appearance,
      })
      db.applications = db.applications.filter(
        (row) => !(row.guildId === guildId && row.userId === session.userId && row.guest),
      )
      this.write(db)
      return { ok: true, joined: true }
    }
    if (
      db.applications.some(
        (row) => row.guildId === guildId && row.userId === session.userId && row.guest,
      )
    ) {
      return { ok: false, reason: 'Guest request already pending.' }
    }
    db.applications.push({
      id: this.newId('app'),
      guildId,
      userId: session.userId,
      username: session.username,
      message: message.trim().slice(0, 120),
      createdAt: this.nowIso(),
      guest: true,
    })
    this.write(db)
    return { ok: true, joined: false }
  }

  leaveGuest(userId: string): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    if (!this.guestsOf(db).some((row) => row.userId === userId)) {
      return { ok: false, reason: 'Not a guest of a guild.' }
    }
    db.guests = this.guestsOf(db).filter((row) => row.userId !== userId)
    this.write(db)
    return { ok: true }
  }

  currentGuestGuildId(userId: string): string | null {
    return this.guestsOf(this.db()).find((row) => row.userId === userId)?.guildId ?? null
  }

  listApplications(guildId: string): GuildApplication[] {
    return this.db().applications.filter((row) => row.guildId === guildId)
  }

  decideApplication(
    leaderId: string,
    applicationId: string,
    accept: boolean,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const application = db.applications.find((row) => row.id === applicationId)
    if (!application) return { ok: false, reason: 'Application not found.' }
    const guild = db.guilds.find((row) => row.id === application.guildId)
    if (!guild || guild.leaderId !== leaderId) {
      return { ok: false, reason: 'Only the guild leader can decide applications.' }
    }
    db.applications = db.applications.filter((row) => row.id !== applicationId)
    if (accept) {
      if (application.guest) {
        if (this.guestsOf(db).some((row) => row.userId === application.userId)) {
          this.write(db)
          return { ok: false, reason: 'Applicant is already a guest elsewhere.' }
        }
        if (
          db.members.some((row) => row.guildId === guild.id && row.userId === application.userId)
        ) {
          this.write(db)
          return { ok: false, reason: 'Applicant already joined that guild.' }
        }
        const snapshot = this.memberSnapshot(db, application.userId, application.username)
        db.guests = this.guestsOf(db)
        db.guests.push({
          guildId: guild.id,
          userId: application.userId,
          username: snapshot.username,
          joinedAt: this.nowIso(),
          appearance: snapshot.appearance,
        })
        this.write(db)
        return { ok: true }
      }
      if (db.members.some((row) => row.userId === application.userId)) {
        this.write(db)
        return { ok: false, reason: 'Applicant already joined another guild.' }
      }
      if (this.guildMemberCount(db, guild.id) >= GUILD_MAX_MEMBERS) {
        this.write(db)
        return { ok: false, reason: `Guild is full (${GUILD_MAX_MEMBERS} members).` }
      }
      const snapshot = this.memberSnapshot(db, application.userId, application.username)
      db.members.push({
        guildId: guild.id,
        userId: application.userId,
        username: snapshot.username,
        role: 'recruit',
        joinedAt: this.nowIso(),
        appearance: snapshot.appearance,
        totalLevel: snapshot.totalLevel,
      })
      db.profiles = db.profiles.map((row) =>
        row.userId === application.userId
          ? { ...row, guildId: guild.id, guildName: guild.name, updatedAt: this.nowIso() }
          : row,
      )
      db.guests = this.guestsOf(db).filter(
        (row) => !(row.guildId === guild.id && row.userId === application.userId),
      )
    }
    this.write(db)
    return { ok: true }
  }

  setMemberRole(
    actorId: string,
    guildId: string,
    targetUserId: string,
    role: GuildRole,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can change roles.' }
    }
    if (role === 'leader') return { ok: false, reason: 'Transfer leadership is not available yet.' }
    if (targetUserId === guild.leaderId) {
      return { ok: false, reason: 'Cannot change the leader rank this way.' }
    }
    const allowed: GuildRole[] = ['officer', 'veteran', 'member', 'recruit']
    if (!allowed.includes(role)) return { ok: false, reason: 'Invalid rank.' }
    db.members = db.members.map((row) =>
      row.guildId === guildId && row.userId === targetUserId ? { ...row, role } : row,
    )
    this.write(db)
    return { ok: true }
  }

  setGuildJoinPolicy(
    actorId: string,
    guildId: string,
    joinPolicy: GuildJoinPolicy,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can change join settings.' }
    }
    guild.joinPolicy = joinPolicy
    this.write(db)
    return { ok: true }
  }

  setGuildGuestAutoAccept(
    actorId: string,
    guildId: string,
    guestAutoAccept: boolean,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can change join settings.' }
    }
    if (guestAutoAccept) guild.guestAutoAccept = true
    else delete guild.guestAutoAccept
    this.write(db)
    return { ok: true }
  }

  setGuildRankIconTheme(
    actorId: string,
    guildId: string,
    theme: string,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can change rank icons.' }
    }
    const next = normalizeRankIconTheme(theme)
    if (next !== GUILD_RANK_ICON_THEME_STRIPES) guild.rankIconTheme = next
    else delete guild.rankIconTheme
    this.write(db)
    return { ok: true }
  }

  setGuildRankLabels(
    actorId: string,
    guildId: string,
    rankLabels: Partial<Record<GuildRankKey, string>>,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can rename ranks.' }
    }
    guild.rankLabels = normalizeRankLabels({ ...guild.rankLabels, ...rankLabels })
    this.write(db)
    return { ok: true }
  }

  setGuildEmblem(
    actorId: string,
    guildId: string,
    emblem: GuildEmblem,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const guild = db.guilds.find((row) => row.id === guildId)
    if (!guild || guild.leaderId !== actorId) {
      return { ok: false, reason: 'Only the leader can edit the banner.' }
    }
    guild.emblem = normalizeEmblem(emblem)
    this.write(db)
    return { ok: true }
  }

  leaveGuild(userId: string): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    const membership = db.members.find((row) => row.userId === userId)
    if (!membership) return { ok: false, reason: 'Not in a guild.' }
    const guild = db.guilds.find((row) => row.id === membership.guildId)
    if (guild?.leaderId === userId) {
      const others = db.members.filter(
        (row) => row.guildId === membership.guildId && row.userId !== userId,
      )
      if (others.length > 0) {
        return { ok: false, reason: 'Transfer leadership or remove members before leaving.' }
      }
      db.guilds = db.guilds.filter((row) => row.id !== membership.guildId)
      db.projects = db.projects.filter((row) => row.guildId !== membership.guildId)
      db.challenges = db.challenges.filter((row) => row.guildId !== membership.guildId)
      db.applications = db.applications.filter((row) => row.guildId !== membership.guildId)
      db.guests = this.guestsOf(db).filter((row) => row.guildId !== membership.guildId)
    }
    db.members = db.members.filter((row) => row.userId !== userId)
    db.profiles = db.profiles.map((row) =>
      row.userId === userId
        ? { ...row, guildId: null, guildName: null, updatedAt: this.nowIso() }
        : row,
    )
    this.write(db)
    return { ok: true }
  }

  contributeToProject(
    userId: string,
    projectId: string,
    amount: number,
  ): { ok: true; project: GuildProject } | { ok: false; reason: string } {
    const db = this.db()
    const membership = db.members.find((row) => row.userId === userId)
    if (!membership) return { ok: false, reason: 'Join a guild first.' }
    const project = db.projects.find(
      (row) => row.id === projectId && row.guildId === membership.guildId,
    )
    if (!project) return { ok: false, reason: 'Project not found.' }
    const add = Math.max(1, Math.floor(amount))
    project.contributed = Math.min(project.goalAmount, project.contributed + add)
    this.write(db)
    return { ok: true, project }
  }

  guildProjects(guildId: string): GuildProject[] {
    return this.db().projects.filter((row) => row.guildId === guildId)
  }

  guildChallenges(guildId: string): GuildChallenge[] {
    return this.db().challenges.filter((row) => row.guildId === guildId)
  }

  refreshGuildChallengeAggregates(guildId: string): void {
    const db = this.db()
    const memberIds = new Set(
      db.members.filter((row) => row.guildId === guildId).map((row) => row.userId),
    )
    db.challenges = db.challenges.map((challenge) => {
      if (challenge.guildId !== guildId) return challenge
      const currentValue = db.leaderboards
        .filter((row) => memberIds.has(row.userId) && row.boardKey === challenge.boardKey)
        .reduce((sum, row) => sum + row.value, 0)
      return { ...challenge, currentValue }
    })
    this.write(db)
  }

  upsertPresence(
    session: MultiplayerSession,
    input: Omit<
      ActivityPresence,
      'userId' | 'username' | 'updatedAt' | 'expiresAt' | 'guildName' | 'appearance'
    > & { appearance: PlayerAppearance },
  ): ActivityPresence {
    const db = this.db()
    const profile = db.profiles.find((row) => row.userId === session.userId)
    const updatedAt = this.nowIso()
    const expiresAt = new Date(this.now() + PRESENCE_AWAY_TTL_SECONDS * 1000).toISOString()
    const row: ActivityPresence = {
      userId: session.userId,
      username: session.username,
      appearance: input.appearance,
      guildName: profile?.guildName ?? null,
      locationId: input.locationId,
      currentActivityId: input.currentActivityId,
      skillId: input.skillId,
      skillLevel: input.skillLevel,
      outfitCosmeticId: input.outfitCosmeticId,
      mountCosmeticId: input.mountCosmeticId,
      updatedAt,
      expiresAt,
    }
    db.presence = db.presence.filter(
      (entry) => entry.userId !== session.userId && Date.parse(entry.expiresAt) > this.now(),
    )
    db.presence.push(row)
    this.write(db)
    return row
  }

  clearPresence(userId: string): void {
    const db = this.db()
    db.presence = db.presence.filter((row) => row.userId !== userId)
    this.write(db)
  }

  listPresence(filter: {
    locationId?: string
    activityId?: string | null
  }): ActivityPresence[] {
    const db = this.db()
    const now = this.now()
    return db.presence
      .filter((row) => Date.parse(row.expiresAt) > now)
      .filter((row) => (filter.locationId ? row.locationId === filter.locationId : true))
      .filter((row) =>
        filter.activityId != null && filter.activityId !== undefined
          ? row.currentActivityId === filter.activityId
          : true,
      )
  }

  sendFriendRequest(
    fromUserId: string,
    toUserId: string,
  ): { ok: true } | { ok: false; reason: string } {
    if (fromUserId === toUserId) return { ok: false, reason: 'Cannot friend yourself.' }
    const db = this.db()
    const pair = [fromUserId, toUserId].sort()
    if (db.friends.some((row) => row.userA === pair[0] && row.userB === pair[1])) {
      return { ok: false, reason: 'Already friends.' }
    }
    if (
      db.friendRequests.some(
        (row) => row.fromUserId === fromUserId && row.toUserId === toUserId,
      )
    ) {
      return { ok: false, reason: 'Friend request already sent.' }
    }
    const reverse = db.friendRequests.find(
      (row) => row.fromUserId === toUserId && row.toUserId === fromUserId,
    )
    if (reverse) {
      db.friendRequests = db.friendRequests.filter((row) => row !== reverse)
      db.friends.push({ userA: pair[0]!, userB: pair[1]! })
      this.write(db)
      return { ok: true }
    }
    db.friendRequests.push({ fromUserId, toUserId, createdAt: this.nowIso() })
    this.write(db)
    return { ok: true }
  }

  publicProfile(userId: string, saveHint?: PlayerSave | null): PublicPlayerProfile | null {
    const profile = this.getProfile(userId)
    if (!profile) return null
    const cloud = this.readCloudSave(userId)
    const save = saveHint ?? cloud?.payload
    const skills = (save?.skills ?? []).map((skill) => ({
      skillId: skill.skillId,
      level: skill.level,
      xp: skill.xp,
    }))
    return {
      userId,
      username: profile.username,
      appearance: profile.appearance,
      guildName: profile.guildName,
      publicSkills: profile.privacyPublicSkills ? skills : [],
      achievementsUnlocked: save?.achievements.filter((row) => row.unlocked).length ?? 0,
      totalLevel: (() => {
        const total = skills.reduce((sum, skill) => sum + skill.level, 0)
        return total < 1 ? 13 : total
      })(),
      logCompletionPercent: 0,
    }
  }

  listBountyClaims(hourKey: string): BountyClaimRecord[] {
    return this.db().bountyClaims.filter((row) => row.hourKey === hourKey)
  }

  getBountyClaim(hourKey: string, bountyId: string): BountyClaimRecord | null {
    return (
      this.db().bountyClaims.find(
        (row) => row.hourKey === hourKey && row.bountyId === bountyId,
      ) ?? null
    )
  }

  /**
   * Records the first completer for an hourly bounty slot.
   * Later callers still succeed so they can collect personal base rewards.
   */
  claimBounty(
    session: MultiplayerSession,
    hourKey: string,
    bountyId: string,
  ):
    | { ok: true; claim: BountyClaimRecord; firstCompleter: boolean }
    | { ok: false; reason: string } {
    const db = this.db()
    const existing = db.bountyClaims.find(
      (row) => row.hourKey === hourKey && row.bountyId === bountyId,
    )
    if (existing) {
      return {
        ok: true,
        claim: existing,
        firstCompleter: existing.userId === session.userId,
      }
    }
    const claim: BountyClaimRecord = {
      hourKey,
      bountyId,
      userId: session.userId,
      username: session.username,
      claimedAt: this.nowIso(),
    }
    db.bountyClaims.push(claim)
    this.write(db)
    return { ok: true, claim, firstCompleter: true }
  }

  listBazaarPosts(limit = 40): BazaarPost[] {
    return this.db()
      .bazaarPosts.slice()
      .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt))
      .slice(-limit)
  }

  postBazaar(
    session: MultiplayerSession,
    kind: BazaarPostKind,
    body: string,
  ): { ok: true; post: BazaarPost } | { ok: false; reason: string } {
    const prepared = prepareBazaarPost(kind, body)
    if (!prepared.ok) return prepared
    const db = this.db()
    const cooldownKey = `${session.userId}:bazaar`
    const last = db.lastChatAt[cooldownKey]
    if (last && this.now() - Date.parse(last) < CHAT_COOLDOWN_SECONDS.local * 1000) {
      const wait = Math.ceil(
        (CHAT_COOLDOWN_SECONDS.local * 1000 - (this.now() - Date.parse(last))) / 1000,
      )
      return { ok: false, reason: `Wait ${wait}s before posting again.` }
    }
    const post: BazaarPost = {
      id: this.newId('bzr'),
      kind,
      userId: session.userId,
      username: session.username,
      body: prepared.body,
      createdAt: this.nowIso(),
    }
    db.bazaarPosts.push(post)
    if (db.bazaarPosts.length > 200) {
      db.bazaarPosts = db.bazaarPosts.slice(-200)
    }
    db.lastChatAt[cooldownKey] = post.createdAt
    this.write(db)
    return { ok: true, post }
  }
}
