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
import { CHAT_COOLDOWN_SECONDS, PRESENCE_TTL_SECONDS } from './config'
import { buildLeaderboardSnapshot } from './snapshots'
import type { GameDatabase } from '../data/types'
import {
  chatChannelKey,
  MULTIPLAYER_LOCAL_DB_KEY,
  type ActivityPresence,
  type ChatChannel,
  type ChatMessage,
  type CloudSaveRecord,
  type GuildApplication,
  type GuildChallenge,
  type GuildMember,
  type GuildProject,
  type GuildRecord,
  type GuildRole,
  type LeaderboardEntry,
  type MultiplayerBoardKey,
  type MultiplayerProfile,
  type MultiplayerSession,
  type PublicPlayerProfile,
} from './types'

interface LocalDb {
  users: Array<{ userId: string; email: string; username: string; password: string }>
  profiles: MultiplayerProfile[]
  saves: CloudSaveRecord[]
  leaderboards: Array<{
    userId: string
    boardKey: MultiplayerBoardKey
    value: number
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
}

function nowIso(): string {
  return new Date().toISOString()
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
  }
}

function loadDb(storage: Storage = localStorage): LocalDb {
  try {
    const raw = storage.getItem(MULTIPLAYER_LOCAL_DB_KEY)
    if (!raw) return emptyDb()
    const parsed = JSON.parse(raw) as LocalDb
    return { ...emptyDb(), ...parsed }
  } catch {
    return emptyDb()
  }
}

function saveDb(db: LocalDb, storage: Storage = localStorage): void {
  storage.setItem(MULTIPLAYER_LOCAL_DB_KEY, JSON.stringify(db))
}

function newId(prefix: string): string {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}_${Date.now().toString(36)}`
}

const BASIC_PROFANITY = /\b(fuck|shit|asshole|cunt|nigger|faggot)\b/gi

export function filterProfanity(body: string): string {
  return body.replace(BASIC_PROFANITY, (match) => '*'.repeat(match.length))
}

export class LocalMultiplayerBackend {
  private storage: Storage

  constructor(storage: Storage = localStorage) {
    this.storage = storage
  }

  private db(): LocalDb {
    return loadDb(this.storage)
  }

  private write(db: LocalDb): void {
    saveDb(db, this.storage)
  }

  signUp(
    email: string,
    username: string,
    password: string,
  ): { ok: true; session: MultiplayerSession } | { ok: false; reason: string } {
    const db = this.db()
    const cleanEmail = email.trim().toLowerCase()
    const cleanUser = username.trim().slice(0, 24)
    if (!cleanEmail.includes('@') || cleanUser.length < 2 || password.length < 4) {
      return { ok: false, reason: 'Enter a valid email, username (2+), and password (4+).' }
    }
    if (db.users.some((user) => user.email === cleanEmail)) {
      return { ok: false, reason: 'An account with that email already exists.' }
    }
    if (db.users.some((user) => user.username.toLowerCase() === cleanUser.toLowerCase())) {
      return { ok: false, reason: 'That username is taken.' }
    }
    const userId = newId('usr')
    db.users.push({ userId, email: cleanEmail, username: cleanUser, password })
    db.profiles.push({
      userId,
      username: cleanUser,
      appearance: defaultAppearance(),
      guildId: null,
      guildName: null,
      privacyPublicSkills: true,
      updatedAt: nowIso(),
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

  getProfile(userId: string): MultiplayerProfile | null {
    return this.db().profiles.find((row) => row.userId === userId) ?? null
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
      updatedAt: nowIso(),
    }
    this.write(db)
    return db.profiles[index]!
  }

  readCloudSave(userId: string): CloudSaveRecord | null {
    return this.db().saves.find((row) => row.userId === userId) ?? null
  }

  writeCloudSave(
    userId: string,
    save: PlayerSave,
  ):
    | { ok: true; record: CloudSaveRecord }
    | { ok: false; reason: string; remote?: CloudSaveRecord } {
    const db = this.db()
    const existing = db.saves.find((row) => row.userId === userId)
    if (
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
      updatedAt: save.updatedAt || nowIso(),
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
    const updatedAt = nowIso()
    for (const board of snapshot.boards) {
      local.leaderboards = local.leaderboards.filter(
        (row) => !(row.userId === userId && row.boardKey === board.boardKey),
      )
      local.leaderboards.push({
        userId,
        boardKey: board.boardKey,
        value: board.value,
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
    const rows = db.leaderboards
      .filter((row) => row.boardKey === boardKey)
      .sort((a, b) => b.value - a.value || a.userId.localeCompare(b.userId))
      .slice(0, limit)
    return rows.map((row, index) => {
      const profile = db.profiles.find((entry) => entry.userId === row.userId)
      return {
        userId: row.userId,
        username: profile?.username ?? 'Adventurer',
        appearance: profile?.appearance ?? defaultAppearance(),
        guildName: profile?.guildName ?? null,
        boardKey,
        value: row.value,
        rank: index + 1,
      }
    })
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
    const stampKey = `${session.userId}:${key}`
    const last = db.lastChatAt[stampKey]
    if (last && Date.now() - Date.parse(last) < cooldown * 1000) {
      const wait = Math.ceil((cooldown * 1000 - (Date.now() - Date.parse(last))) / 1000)
      return { ok: false, reason: `Wait ${wait}s before chatting again.` }
    }
    if (channel.kind === 'guild') {
      const member = db.members.find(
        (row) => row.guildId === channel.guildId && row.userId === session.userId,
      )
      if (!member) return { ok: false, reason: 'Join the guild to use guild chat.' }
    }
    const message: ChatMessage = {
      id: newId('msg'),
      channelKey: key,
      userId: session.userId,
      username: session.username,
      body: filterProfanity(trimmed),
      createdAt: nowIso(),
    }
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
      id: newId('rpt'),
      reporterId,
      targetUserId,
      reason: reason.trim().slice(0, 200) || 'Unspecified',
      createdAt: nowIso(),
    })
    this.write(db)
  }

  createGuild(
    session: MultiplayerSession,
    name: string,
    description: string,
    emblem = '⚔️',
  ): { ok: true; guild: GuildRecord } | { ok: false; reason: string } {
    const clean = name.trim().slice(0, 28)
    if (clean.length < 3) return { ok: false, reason: 'Guild name needs at least 3 characters.' }
    const db = this.db()
    if (db.members.some((row) => row.userId === session.userId)) {
      return { ok: false, reason: 'Leave your current guild before creating another.' }
    }
    if (db.guilds.some((row) => row.name.toLowerCase() === clean.toLowerCase())) {
      return { ok: false, reason: 'That guild name is taken.' }
    }
    const guild: GuildRecord = {
      id: newId('gld'),
      name: clean,
      description: description.trim().slice(0, 160),
      emblem: emblem.slice(0, 4) || '⚔️',
      leaderId: session.userId,
      createdAt: nowIso(),
    }
    db.guilds.push(guild)
    db.members.push({
      guildId: guild.id,
      userId: session.userId,
      username: session.username,
      role: 'leader',
      joinedAt: nowIso(),
    })
    db.profiles = db.profiles.map((row) =>
      row.userId === session.userId
        ? { ...row, guildId: guild.id, guildName: guild.name, updatedAt: nowIso() }
        : row,
    )
    db.projects.push({
      id: newId('gprj'),
      guildId: guild.id,
      name: 'Guild Storehouse',
      description: 'Pool resources for cosmetic recognition.',
      goalAmount: 1000,
      contributed: 0,
      rewardLabel: 'Guild banner cosmetic (recognition)',
    })
    db.challenges.push({
      id: newId('gch'),
      guildId: guild.id,
      name: 'Weekly Monster Hunt',
      boardKey: 'monsters_killed',
      goalValue: 100,
      currentValue: 0,
    })
    this.write(db)
    return { ok: true, guild }
  }

  listGuilds(): GuildRecord[] {
    return [...this.db().guilds].sort((a, b) => a.name.localeCompare(b.name))
  }

  guildMembers(guildId: string): GuildMember[] {
    return this.db().members.filter((row) => row.guildId === guildId)
  }

  applyToGuild(
    session: MultiplayerSession,
    guildId: string,
    message: string,
  ): { ok: true } | { ok: false; reason: string } {
    const db = this.db()
    if (!db.guilds.some((row) => row.id === guildId)) {
      return { ok: false, reason: 'Guild not found.' }
    }
    if (db.members.some((row) => row.userId === session.userId)) {
      return { ok: false, reason: 'Already in a guild.' }
    }
    if (
      db.applications.some((row) => row.guildId === guildId && row.userId === session.userId)
    ) {
      return { ok: false, reason: 'Application already pending.' }
    }
    db.applications.push({
      id: newId('app'),
      guildId,
      userId: session.userId,
      username: session.username,
      message: message.trim().slice(0, 120),
      createdAt: nowIso(),
    })
    this.write(db)
    return { ok: true }
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
      if (db.members.some((row) => row.userId === application.userId)) {
        this.write(db)
        return { ok: false, reason: 'Applicant already joined another guild.' }
      }
      db.members.push({
        guildId: guild.id,
        userId: application.userId,
        username: application.username,
        role: 'member',
        joinedAt: nowIso(),
      })
      db.profiles = db.profiles.map((row) =>
        row.userId === application.userId
          ? { ...row, guildId: guild.id, guildName: guild.name, updatedAt: nowIso() }
          : row,
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
    db.members = db.members.map((row) =>
      row.guildId === guildId && row.userId === targetUserId ? { ...row, role } : row,
    )
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
    }
    db.members = db.members.filter((row) => row.userId !== userId)
    db.profiles = db.profiles.map((row) =>
      row.userId === userId
        ? { ...row, guildId: null, guildName: null, updatedAt: nowIso() }
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
    const updatedAt = nowIso()
    const expiresAt = new Date(Date.now() + PRESENCE_TTL_SECONDS * 1000).toISOString()
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
      (entry) => entry.userId !== session.userId && Date.parse(entry.expiresAt) > Date.now(),
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
    const now = Date.now()
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
    db.friendRequests.push({ fromUserId, toUserId, createdAt: nowIso() })
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
      totalLevel: skills.reduce((sum, skill) => sum + skill.level, 0),
    }
  }
}
