import {
  citadelChatLocationId,
  citadelHubSummary,
  citadelLocalChannelKey,
  citadelLocationId,
} from '../../game/multiplayer/citadel'
import { softValidateSave } from '../../game/multiplayer/cloudSave'
import { CHAT_COOLDOWN_SECONDS, PRESENCE_TTL_SECONDS } from '../../game/multiplayer/config'
import { filterProfanity, LocalMultiplayerBackend } from '../../game/multiplayer/localBackend'
import { boardLabel, launchBoardKeys } from '../../game/multiplayer/leaderboards'
import { presenceInputFromSave } from '../../game/multiplayer/presence'
import {
  chatMessageFrom,
  cloudSaveRecordFrom,
  isRemoteSaveNewer,
  leaderboardEntriesFrom,
  leaderboardRowsFor,
  profileRowForSignUp,
  remoteEmail,
  remoteUsername,
  saveRowFor,
  sessionFromSignIn,
  sessionFromSignUp,
  REMOTE_CHAT_COLUMNS,
  REMOTE_CHAT_LIMIT,
  REMOTE_LEADERBOARD_COLUMNS,
  REMOTE_LEADERBOARD_CONFLICT,
  REMOTE_MAGIC_LINK_UNAVAILABLE,
  REMOTE_NOT_CONFIGURED,
  REMOTE_SAVE_COLUMNS,
  REMOTE_SEND_CHAT_FUNCTION,
  REMOTE_SIGN_IN_FAILED,
  REMOTE_SIGN_UP_FAILED,
  REMOTE_TABLES,
  REMOTE_USERNAME_MAX_LENGTH,
  type RemoteRow,
} from '../../game/multiplayer/remote'
import { buildLeaderboardSnapshot } from '../../game/multiplayer/snapshots'
import {
  chatChannelKey,
  dmPairKey,
  DEFAULT_GUILD_RANK_LABELS,
  GUILD_CREATE_GOLD_COST,
  GUILD_EMBLEM_COLORS,
  GUILD_EMBLEM_EMOJI_TO_SYMBOL,
  GUILD_EMBLEM_SYMBOLS,
  GUILD_MAX_MEMBERS,
  DEFAULT_PLAYER_APPEARANCE,
  MULTIPLAYER_LOCAL_DB_KEY,
  PROMOTABLE_GUILD_RANKS,
  type ChatChannel,
  type MultiplayerBoardKey,
  type MultiplayerSession,
} from '../../game/multiplayer/types'
import { OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID } from '../../game/save/types'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, richSave } from './saveFixtures'

const NOW_MS = Date.parse('2026-08-12T21:00:00.000Z')

/**
 * A `Storage` that exists only for the run.
 *
 * The backend reaches for `localStorage`, which a fixture cannot share between
 * scenarios without leaking state from one into the next.
 */
class MemoryStorage implements Storage {
  private entries = new Map<string, string>()

  get length(): number {
    return this.entries.size
  }

  clear(): void {
    this.entries.clear()
  }

  getItem(key: string): string | null {
    return this.entries.get(key) ?? null
  }

  key(index: number): string | null {
    return [...this.entries.keys()][index] ?? null
  }

  removeItem(key: string): void {
    this.entries.delete(key)
  }

  setItem(key: string, value: string): void {
    this.entries.set(key, value)
  }
}

/**
 * A backend with the clock and the id generator pinned.
 *
 * Ids count up from one so a fixture names the same row as the Dart replay, and
 * the clock only moves when a scenario asks it to.
 */
class Harness {
  readonly storage = new MemoryStorage()
  readonly backend: LocalMultiplayerBackend
  private clock = NOW_MS
  private counter = 0

  constructor(startMs = NOW_MS, seed?: string) {
    this.clock = startMs
    if (seed) this.storage.setItem(MULTIPLAYER_LOCAL_DB_KEY, seed)
    this.backend = new LocalMultiplayerBackend(this.storage, {
      nowMs: () => this.clock,
      newId: (prefix) => `${prefix}_${String((this.counter += 1)).padStart(4, '0')}`,
    })
  }

  advance(ms: number): void {
    this.clock += ms
  }

  /** The stored document, as the next load would read it. */
  doc(): JsonValue {
    const raw = this.storage.getItem(MULTIPLAYER_LOCAL_DB_KEY)
    return raw ? (JSON.parse(raw) as JsonValue) : null
  }

  signUp(email: string, username: string): MultiplayerSession {
    const result = this.backend.signUp(email, username, 'secret')
    if (!result.ok) throw new Error(`Fixture sign-up failed: ${result.reason}`)
    return result.session
  }
}

function pinnedSave(): PlayerSave {
  return baseSave(contentDatabase())
}

/** Two accounts whose gold ties, so the board's tie-break has to decide. */
function heroBoardSave(): PlayerSave {
  return {
    ...richSave(contentDatabase()),
    characterName: 'Hero of Parity',
    statistics: {
      values: { gold_earned: 900, monsters_killed: 12, bounties_completed: 3 },
    },
  }
}

function rivalBoardSave(): PlayerSave {
  return {
    ...pinnedSave(),
    characterName: 'Rival',
    statistics: { values: { gold_earned: 900, monsters_killed: 40 } },
  }
}

/** Enough kills for the guild challenge aggregate to be non-zero. */
function killCountSave(): PlayerSave {
  return { ...pinnedSave(), statistics: { values: { monsters_killed: 30 } } }
}

/** A save with one achievement unlocked, for the public profile count. */
function profileSave(): PlayerSave {
  return {
    ...richSave(contentDatabase()),
    achievements: [
      {
        achievementId: 'ACH-0001',
        unlocked: true,
        unlockedAt: '2026-08-12T20:00:00.000Z',
      },
      { achievementId: 'ACH-0002', unlocked: false, unlockedAt: null },
    ],
  }
}

const CHANNELS: ChatChannel[] = [
  { kind: 'global' },
  { kind: 'local', locationId: 'LOC-0002' },
  { kind: 'local', locationId: 'citadel' },
  { kind: 'guild', guildId: 'gld_0001' },
  { kind: 'dm', pairKey: 'usr_0001:usr_0002' },
]

const EMBLEM = { color: GUILD_EMBLEM_COLORS[1]!, symbol: 'tree' }

/**
 * Rows as a remote backend hands them back: a stored save newer than the local
 * one, one older, one written by an older build, and nothing at all.
 */
const REMOTE_SAVE_ROWS: RemoteRow[] = [
  { save_version: 22, updated_at: '2026-08-12T22:00:00.000Z', payload: { gold: 1 } },
  { save_version: 22, updated_at: '2026-08-12T20:00:00.000Z', payload: { gold: 2 } },
  { save_version: 21, updated_at: '2026-08-12T22:00:00.000Z', payload: { gold: 3 } },
  { save_version: '23', updated_at: '2026-08-13T00:00:00.000Z', payload: { gold: 4 } },
]

/** A joined leaderboard read: a full profile, a missing one, and holes. */
const REMOTE_BOARD_ROWS: RemoteRow[] = [
  {
    user_id: 'usr_0001',
    value: 1204,
    profiles: {
      username: 'Hero',
      appearance_json: DEFAULT_PLAYER_APPEARANCE,
      guilds: { name: 'Iron League' },
    },
  },
  { user_id: 'usr_0002', value: '12', profiles: null },
  { user_id: 'usr_0003', value: 0, profiles: { username: 'Quiet', guilds: null } },
]

const REMOTE_CHAT_ROWS: RemoteRow[] = [
  {
    id: 7,
    channel_key: 'global',
    user_id: 'usr_0001',
    username: 'Hero',
    body: 'Hello',
    created_at: '2026-08-12T21:00:00.000Z',
  },
  {},
]

/**
 * A document an older build wrote: emoji emblems, no tag, no join policy, and
 * members without the appearance or level the roster now shows.
 */
const LEGACY_DOC = JSON.stringify({
  guilds: [
    {
      id: 'gld_legacy',
      name: 'Old Guard',
      description: 'Wrote its emblem as an emoji.',
      emblem: '🛡️',
      leaderId: 'usr_legacy',
      createdAt: '2026-01-01T00:00:00.000Z',
    },
    {
      id: 'gld_symbols',
      name: '???',
      tag: 'x',
      emblem: { color: '#123456', symbol: 'not-a-symbol' },
      leaderId: 'usr_legacy',
      joinPolicy: 'closed',
      rankLabels: {
        officer: '  ',
        veteran: 'Elder',
        member: 'A very long rank name indeed',
      },
      createdAt: '2026-01-01T00:00:00.000Z',
    },
  ],
  members: [
    {
      guildId: 'gld_legacy',
      userId: 'usr_legacy',
      username: 'Legacy',
      role: 'grandmaster',
      joinedAt: '2026-01-01T00:00:00.000Z',
    },
  ],
})

export const multiplayerScenarios: ParityScenario[] = [
  scenario(
    'multiplayer/keys',
    'channels-and-constants',
    { source: 'constants' },
    () =>
      ({
        channelKeys: CHANNELS.map((channel) => chatChannelKey(channel)),
        dmPairKeys: [
          dmPairKey('usr_b', 'usr_a'),
          dmPairKey('usr_a', 'usr_b'),
          dmPairKey('usr_a', 'usr_a'),
        ],
        cooldowns: CHAT_COOLDOWN_SECONDS,
        presenceTtlSeconds: PRESENCE_TTL_SECONDS,
        guild: {
          createGoldCost: GUILD_CREATE_GOLD_COST,
          maxMembers: GUILD_MAX_MEMBERS,
          colors: GUILD_EMBLEM_COLORS,
          symbols: GUILD_EMBLEM_SYMBOLS,
          emojiToSymbol: GUILD_EMBLEM_EMOJI_TO_SYMBOL,
          defaultRankLabels: DEFAULT_GUILD_RANK_LABELS,
          promotable: PROMOTABLE_GUILD_RANKS,
        },
        citadel: {
          locationId: citadelLocationId(),
          chatLocationId: citadelChatLocationId(),
          channelKey: citadelLocalChannelKey(),
          summary: citadelHubSummary(4),
          emptySummary: citadelHubSummary(0),
        },
        profanity: [
          filterProfanity('hello there'),
          filterProfanity('what the fuck'),
          filterProfanity('SHIT and shit'),
          filterProfanity('classic scunthorpe'),
        ],
      }) as unknown as JsonValue,
  ),

  ...(['base', 'rich'] as const).map((kind) =>
    scenario(
      'multiplayer/snapshot',
      kind,
      {
        source: 'content',
        save: asJson(kind === 'base' ? pinnedSave() : richSave(contentDatabase())),
      },
      () => {
        const db = contentDatabase()
        const save = kind === 'base' ? pinnedSave() : richSave(db)
        const keys = launchBoardKeys(db)
        return {
          boards: buildLeaderboardSnapshot(db, save) as unknown as JsonValue,
          boardKeys: keys,
          labels: [...keys, 'skill:SKL-9999' as const, 'not-a-board' as MultiplayerBoardKey].map(
            (key) => ({ key, label: boardLabel(db, key) }),
          ),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('multiplayer/accounts', 'sign-up-and-in', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const refusals = [
      harness.backend.signUp('not-an-email', 'Hero', 'secret'),
      harness.backend.signUp('hero@example.com', 'H', 'secret'),
      harness.backend.signUp('hero@example.com', 'Hero', 'abc'),
    ]
    const created = harness.backend.signUp('  HERO@Example.com ', '  Hero  ', 'secret')
    const duplicates = [
      harness.backend.signUp('hero@example.com', 'Other', 'secret'),
      harness.backend.signUp('other@example.com', 'HERO', 'secret'),
    ]
    const signedIn = harness.backend.signIn(' hero@EXAMPLE.com ', 'secret')
    const wrongPassword = harness.backend.signIn('hero@example.com', 'nope')
    const unknown = harness.backend.signIn('nobody@example.com', 'secret')
    const profile = harness.backend.getProfile('usr_0001')
    harness.advance(60_000)
    const renamed = harness.backend.upsertProfile('usr_0001', {
      username: 'Renamed',
      privacyPublicSkills: false,
    })
    const missing = harness.backend.upsertProfile('usr_9999', {
      username: 'Ghost',
    })
    return {
      refusals,
      created,
      duplicates,
      signedIn,
      wrongPassword,
      unknown,
      profile,
      renamed,
      missing,
      doc: harness.doc(),
    } as unknown as JsonValue
  }),

  scenario(
    'multiplayer/cloud-save',
    'write-conflict-and-read',
    { nowMs: NOW_MS, save: asJson(pinnedSave()) },
    () => {
      const harness = new Harness()
      const session = harness.signUp('hero@example.com', 'Hero')
      const save = pinnedSave()
      const newer: PlayerSave = {
        ...save,
        updatedAt: '2026-06-01T00:00:00.000Z',
        gold: 400,
      }
      const older: PlayerSave = {
        ...save,
        updatedAt: '2026-01-01T00:00:00.000Z',
        gold: 10,
      }
      const first = harness.backend.writeCloudSave(session.userId, newer)
      const conflict = harness.backend.writeCloudSave(session.userId, older)
      const bumped = harness.backend.writeCloudSave(session.userId, {
        ...older,
        saveVersion: save.saveVersion + 1,
      })
      const unstamped = harness.backend.writeCloudSave(session.userId, {
        ...save,
        updatedAt: '',
      })
      return {
        first,
        conflict,
        bumped,
        unstamped,
        read: harness.backend.readCloudSave(session.userId),
        missing: harness.backend.readCloudSave('usr_9999'),
      } as unknown as JsonValue
    },
  ),

  scenario('multiplayer/cloud-save', 'validation', { save: asJson(pinnedSave()) }, () => {
    const save = pinnedSave()
    return {
      clean: softValidateSave(save),
      negativeGold: softValidateSave({ ...save, gold: -1 }),
      hugeGold: softValidateSave({ ...save, gold: 1_000_000_001 }),
      infiniteGold: softValidateSave({
        ...save,
        gold: Number.POSITIVE_INFINITY,
      }),
      zeroLevel: softValidateSave({
        ...save,
        skills: save.skills.map((skill, index) => (index === 0 ? { ...skill, level: 0 } : skill)),
      }),
      negativeXp: softValidateSave({
        ...save,
        skills: save.skills.map((skill, index) => (index === 1 ? { ...skill, xp: -5 } : skill)),
      }),
    } as unknown as JsonValue
  }),

  scenario(
    'multiplayer/leaderboard',
    'players-and-guilds',
    {
      source: 'content',
      nowMs: NOW_MS,
      heroSave: asJson(heroBoardSave()),
      rivalSave: asJson(rivalBoardSave()),
    },
    () => {
      const db = contentDatabase()
      const harness = new Harness()
      const hero = harness.signUp('hero@example.com', 'Hero')
      const rival = harness.signUp('rival@example.com', 'Rival')
      const heroSave = heroBoardSave()
      const rivalSave = rivalBoardSave()
      harness.backend.writeCloudSave(hero.userId, heroSave)
      harness.backend.writeCloudSave(rival.userId, rivalSave)
      harness.backend.submitLeaderboardSnapshot(db, hero.userId, heroSave)
      harness.backend.submitLeaderboardSnapshot(db, rival.userId, rivalSave)
      // A snapshot for an account with no profile must not create rows.
      harness.backend.submitLeaderboardSnapshot(db, 'usr_9999', heroSave)
      harness.backend.createGuild(
        hero,
        {
          name: 'Oak Guard',
          tag: 'OAK',
          description: 'For the kingdom',
          emblem: EMBLEM,
        },
        100,
      )
      harness.backend.applyToGuild(rival, 'gld_0003', '')
      return {
        totalLevel: harness.backend.listLeaderboard('total_level'),
        monsters: harness.backend.listLeaderboard('monsters_killed'),
        // Equal values fall back to the user id, so this pins the tie-break.
        goldTie: harness.backend.listLeaderboard('gold_earned'),
        limited: harness.backend.listLeaderboard('monsters_killed', 1),
        guilds: harness.backend.listLeaderboard('guild_total_level'),
        empty: harness.backend.listLeaderboard('skill:SKL-9999'),
      } as unknown as JsonValue
    },
  ),

  scenario('multiplayer/chat', 'channels-and-cooldowns', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const hero = harness.signUp('hero@example.com', 'Hero')
    const sent = harness.backend.sendChat(hero, { kind: 'global' }, '  Hello world  ')
    const tooSoon = harness.backend.sendChat(hero, { kind: 'global' }, 'Again')
    const empty = harness.backend.sendChat(hero, { kind: 'global' }, '   ')
    const otherRoom = harness.backend.sendChat(
      hero,
      { kind: 'local', locationId: 'citadel' },
      'Anyone here?',
    )
    const notInGuild = harness.backend.sendChat(hero, { kind: 'guild', guildId: 'gld_0001' }, 'Hi')
    harness.advance(10_000)
    const stillTooSoon = harness.backend.sendChat(hero, { kind: 'global' }, 'Third')
    harness.advance(20_000)
    const afterCooldown = harness.backend.sendChat(hero, { kind: 'global' }, 'what the fuck')
    const long = harness.backend.sendChat(
      hero,
      { kind: 'local', locationId: 'LOC-0002' },
      'x'.repeat(300),
    )
    return {
      sent,
      tooSoon,
      empty,
      otherRoom,
      notInGuild,
      stillTooSoon,
      afterCooldown,
      longBodyLength: long.ok ? long.message.body.length : null,
      global: harness.backend.listChat({ kind: 'global' }, hero.userId),
      citadel: harness.backend.listChat({ kind: 'local', locationId: 'citadel' }, hero.userId),
    } as unknown as JsonValue
  }),

  scenario('multiplayer/chat', 'moderation-and-dms', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const hero = harness.signUp('hero@example.com', 'Hero')
    const rival = harness.signUp('rival@example.com', 'Rival')
    const loud = harness.signUp('loud@example.com', 'Loud')
    const pair = {
      kind: 'dm',
      pairKey: dmPairKey(hero.userId, rival.userId),
    } as const
    harness.backend.sendChat(hero, pair, 'Trade?')
    harness.advance(3_000)
    harness.backend.sendChat(rival, pair, 'Sure')
    harness.advance(3_000)
    const readAt = '2026-08-12T21:00:03.000Z'
    harness.backend.sendChat(loud, { kind: 'global' }, 'Buying everything')
    harness.backend.sendChat(rival, { kind: 'global' }, 'Ignore that')
    harness.backend.muteUser(hero.userId, loud.userId)
    harness.backend.muteUser(hero.userId, loud.userId)
    harness.backend.blockUser(hero.userId, 'usr_9999')
    harness.backend.reportUser(hero.userId, loud.userId, '   ')
    harness.backend.reportUser(hero.userId, loud.userId, 'y'.repeat(250))
    return {
      dms: harness.backend.listDirectMessages(hero.userId),
      unreadAll: harness.backend.countUnreadDirectMessages(hero.userId, null),
      unreadSince: harness.backend.countUnreadDirectMessages(hero.userId, readAt),
      unreadForRival: harness.backend.countUnreadDirectMessages(rival.userId, null),
      globalForHero: harness.backend.listChat({ kind: 'global' }, hero.userId),
      globalForRival: harness.backend.listChat({ kind: 'global' }, rival.userId),
      mutes: harness.doc(),
    } as unknown as JsonValue
  }),

  scenario('multiplayer/guilds', 'create-and-browse', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const leader = harness.signUp('leader@example.com', 'Leader')
    const refusals = [
      harness.backend.createGuild(leader, { name: 'Ab', tag: 'AB', emblem: EMBLEM }, 100),
      harness.backend.createGuild(leader, { name: 'Iron League', tag: 'I', emblem: EMBLEM }, 100),
      harness.backend.createGuild(
        leader,
        { name: 'Iron League', tag: 'IRON5', emblem: EMBLEM },
        100,
      ),
      harness.backend.createGuild(leader, { name: 'Iron League', tag: 'IRN', emblem: EMBLEM }, 10),
    ]
    const created = harness.backend.createGuild(
      leader,
      {
        name: 'Iron League',
        tag: 'irn',
        description: 'd'.repeat(200),
        emblem: { color: '#3d5a80', symbol: '🛡️' },
      },
      GUILD_CREATE_GOLD_COST,
    )
    const again = harness.backend.createGuild(
      leader,
      { name: 'Second Guild', tag: 'SEC', emblem: EMBLEM },
      100,
    )
    const other = harness.signUp('other@example.com', 'Other')
    const takenName = harness.backend.createGuild(
      other,
      { name: 'IRON LEAGUE', tag: 'XYZ', emblem: EMBLEM },
      100,
    )
    const takenTag = harness.backend.createGuild(
      other,
      { name: 'Bronze League', tag: 'irn', emblem: EMBLEM },
      100,
    )
    const made = harness.backend.createGuild(
      other,
      { name: 'Aardvark Alliance', tag: 'AA', emblem: EMBLEM },
      100,
    )
    return {
      refusals,
      created,
      again,
      takenName,
      takenTag,
      made,
      listed: harness.backend.listGuilds(),
      guild: harness.backend.getGuild('gld_0002'),
      missing: harness.backend.getGuild('gld_9999'),
      members: harness.backend.guildMembers('gld_0002'),
      projects: harness.backend.guildProjects('gld_0002'),
      challenges: harness.backend.guildChallenges('gld_0002'),
    } as unknown as JsonValue
  }),

  scenario(
    'multiplayer/guilds',
    'applications-and-ranks',
    { source: 'content', nowMs: NOW_MS, killSave: asJson(killCountSave()) },
    () => {
      const db = contentDatabase()
      const harness = new Harness()
      const leader = harness.signUp('leader@example.com', 'Leader')
      const joiner = harness.signUp('join@example.com', 'Joiner')
      const walkIn = harness.signUp('walk@example.com', 'WalkIn')
      const created = harness.backend.createGuild(
        leader,
        { name: 'Iron League', tag: 'IRN', emblem: EMBLEM },
        GUILD_CREATE_GOLD_COST,
      )
      const guildId = created.ok ? created.guild.id : 'gld_0002'
      const notLeader = harness.backend.setGuildJoinPolicy(joiner.userId, guildId, 'closed')
      harness.backend.setGuildJoinPolicy(leader.userId, guildId, 'closed')
      const applied = harness.backend.applyToGuild(joiner, guildId, 'p'.repeat(200))
      const duplicate = harness.backend.applyToGuild(joiner, guildId, 'again')
      const unknownGuild = harness.backend.applyToGuild(joiner, 'gld_9999', '')
      const applications = harness.backend.listApplications(guildId)
      const rejected = harness.backend.decideApplication(joiner.userId, applications[0]!.id, true)
      const accepted = harness.backend.decideApplication(leader.userId, applications[0]!.id, true)
      const goneApplication = harness.backend.decideApplication(
        leader.userId,
        applications[0]!.id,
        true,
      )
      harness.backend.setGuildJoinPolicy(leader.userId, guildId, 'open')
      const walkedIn = harness.backend.applyToGuild(walkIn, guildId, '')
      const alreadyIn = harness.backend.applyToGuild(joiner, guildId, '')
      const promoted = harness.backend.setMemberRole(
        leader.userId,
        guildId,
        joiner.userId,
        'officer',
      )
      const cannotPromoteToLeader = harness.backend.setMemberRole(
        leader.userId,
        guildId,
        joiner.userId,
        'leader',
      )
      const cannotDemoteLeader = harness.backend.setMemberRole(
        leader.userId,
        guildId,
        leader.userId,
        'member',
      )
      const labels = harness.backend.setGuildRankLabels(leader.userId, guildId, {
        officer: 'Captain',
        leader: 'Guildmaster',
        recruit: '   ',
        member: 'A rank name well past the limit',
      })
      const emblem = harness.backend.setGuildEmblem(leader.userId, guildId, {
        color: '#7a2f2f',
        symbol: 'dragon',
      })
      const leaderCannotLeave = harness.backend.leaveGuild(leader.userId)
      const contributed = harness.backend.contributeToProject(
        joiner.userId,
        harness.backend.guildProjects(guildId)[0]!.id,
        2_500.7,
      )
      const contributedTooLittle = harness.backend.contributeToProject(
        joiner.userId,
        harness.backend.guildProjects(guildId)[0]!.id,
        0,
      )
      const outsiderContribution = harness.backend.contributeToProject(
        'usr_9999',
        harness.backend.guildProjects(guildId)[0]!.id,
        5,
      )
      harness.backend.submitLeaderboardSnapshot(db, joiner.userId, killCountSave())
      harness.backend.refreshGuildChallengeAggregates(guildId)
      const memberLeft = harness.backend.leaveGuild(walkIn.userId)
      const notInGuild = harness.backend.leaveGuild('usr_9999')
      return {
        notLeader,
        applied,
        duplicate,
        unknownGuild,
        applications,
        rejected,
        accepted,
        goneApplication,
        walkedIn,
        alreadyIn,
        promoted,
        cannotPromoteToLeader,
        cannotDemoteLeader,
        labels,
        emblem,
        leaderCannotLeave,
        contributed,
        contributedTooLittle,
        outsiderContribution,
        memberLeft,
        notInGuild,
        guild: harness.backend.getGuild(guildId),
        members: harness.backend.guildMembers(guildId),
        challenges: harness.backend.guildChallenges(guildId),
        leaderProfile: harness.backend.getProfile(leader.userId),
        walkInProfile: harness.backend.getProfile(walkIn.userId),
      } as unknown as JsonValue
    },
  ),

  scenario(
    'multiplayer/guilds',
    'capacity',
    { nowMs: NOW_MS, maxMembers: GUILD_MAX_MEMBERS },
    () => {
      const harness = new Harness()
      const leader = harness.signUp('cap@example.com', 'Cap')
      const created = harness.backend.createGuild(
        leader,
        { name: 'Full House', tag: 'FUL', emblem: EMBLEM },
        GUILD_CREATE_GOLD_COST,
      )
      const guildId = created.ok ? created.guild.id : 'gld_0002'
      for (let index = 0; index < GUILD_MAX_MEMBERS - 1; index += 1) {
        const member = harness.signUp(`u${index}@example.com`, `User${index}`)
        harness.backend.applyToGuild(member, guildId, '')
      }
      const overflow = harness.signUp('overflow@example.com', 'Overflow')
      const blocked = harness.backend.applyToGuild(overflow, guildId, '')
      harness.backend.setGuildJoinPolicy(leader.userId, guildId, 'closed')
      const applied = harness.backend.applyToGuild(overflow, guildId, 'let me in')
      return {
        memberCount: harness.backend.listGuilds()[0]?.memberCount ?? null,
        blocked,
        applied,
      } as unknown as JsonValue
    },
  ),

  scenario(
    'multiplayer/presence',
    'publish-and-expire',
    {
      nowMs: NOW_MS,
      appearance: pinnedSave().appearance as unknown as JsonValue,
    },
    () => {
      const harness = new Harness()
      const hero = harness.signUp('hero@example.com', 'Hero')
      const rival = harness.signUp('rival@example.com', 'Rival')
      const save = pinnedSave()
      const published = harness.backend.upsertPresence(hero, {
        appearance: save.appearance,
        locationId: 'LOC-0028',
        currentActivityId: 'ACT-0001',
        skillId: 'SKL-0001',
        skillLevel: 7,
        outfitCosmeticId: 'COS-0001',
        mountCosmeticId: null,
      })
      harness.advance(30_000)
      const second = harness.backend.upsertPresence(rival, {
        appearance: save.appearance,
        locationId: 'LOC-0028',
        currentActivityId: null,
        skillId: 'SKL-0002',
        skillLevel: 3,
        outfitCosmeticId: null,
        mountCosmeticId: null,
      })
      const plaza = harness.backend.listPresence({ locationId: 'LOC-0028' })
      const byActivity = harness.backend.listPresence({
        locationId: 'LOC-0028',
        activityId: 'ACT-0001',
      })
      const elsewhere = harness.backend.listPresence({
        locationId: 'LOC-0002',
      })
      const anyLocation = harness.backend.listPresence({})
      // Past the TTL of the first row but not the second.
      harness.advance(100_000)
      const afterExpiry = harness.backend.listPresence({
        locationId: 'LOC-0028',
      })
      harness.backend.clearPresence(rival.userId)
      return {
        published,
        second,
        plaza,
        byActivity,
        elsewhere,
        anyLocation,
        afterExpiry,
        cleared: harness.backend.listPresence({}),
      } as unknown as JsonValue
    },
  ),

  scenario(
    'multiplayer/presence',
    'from-save',
    { source: 'content', save: asJson(richSave(contentDatabase())) },
    () => {
      const save = richSave(contentDatabase())
      const dressed: PlayerSave = {
        ...save,
        currentLocationId: 'LOC-0003',
        currentActivityId: 'ACT-0002',
        cosmetics: {
          ...save.cosmetics,
          equipped: {
            ...save.cosmetics.equipped,
            [OUTFIT_COSMETIC_SLOT_ID]: 'COS-0001',
            [PET_COSMETIC_SLOT_ID]: 'COS-0004',
          },
        },
      }
      const noSkills: PlayerSave = { ...save, skills: [] }
      const noCombat: PlayerSave = {
        ...save,
        skills: save.skills.filter((skill) => skill.skillId !== 'SKL-0001'),
      }
      return {
        dressed: presenceInputFromSave(dressed),
        noSkills: presenceInputFromSave(noSkills),
        noCombat: presenceInputFromSave(noCombat),
      } as unknown as JsonValue
    },
  ),

  scenario('multiplayer/bounty-claims', 'first-completer', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const first = harness.signUp('first@example.com', 'First')
    const second = harness.signUp('second@example.com', 'Second')
    const claimed = harness.backend.claimBounty(first, '2026-08-12T21', 'BNT-0001')
    harness.advance(5_000)
    const repeated = harness.backend.claimBounty(first, '2026-08-12T21', 'BNT-0001')
    const lost = harness.backend.claimBounty(second, '2026-08-12T21', 'BNT-0001')
    const otherBounty = harness.backend.claimBounty(second, '2026-08-12T21', 'BNT-0002')
    const nextHour = harness.backend.claimBounty(second, '2026-08-12T22', 'BNT-0001')
    return {
      claimed,
      repeated,
      lost,
      otherBounty,
      nextHour,
      thisHour: harness.backend.listBountyClaims('2026-08-12T21'),
      lookup: harness.backend.getBountyClaim('2026-08-12T21', 'BNT-0002'),
      missing: harness.backend.getBountyClaim('2026-08-12T21', 'BNT-9999'),
    } as unknown as JsonValue
  }),

  scenario('multiplayer/bazaar', 'posts', { nowMs: NOW_MS }, () => {
    const harness = new Harness()
    const hero = harness.signUp('hero@example.com', 'Hero')
    const rival = harness.signUp('rival@example.com', 'Rival')
    const posted = harness.backend.postBazaar(hero, 'trade', '  Selling copper ore  ')
    const tooSoon = harness.backend.postBazaar(hero, 'message', 'Also this')
    const empty = harness.backend.postBazaar(rival, 'message', '  ')
    const unknownKind = harness.backend.postBazaar(rival, 'auction' as 'trade', 'Bid now')
    const otherPlayer = harness.backend.postBazaar(rival, 'recruit', 'Guild needs members')
    harness.advance(10_000)
    const afterCooldown = harness.backend.postBazaar(hero, 'message', 'what the shit')
    return {
      posted,
      tooSoon,
      empty,
      unknownKind,
      otherPlayer,
      afterCooldown,
      all: harness.backend.listBazaarPosts(),
      limited: harness.backend.listBazaarPosts(2),
    } as unknown as JsonValue
  }),

  scenario('multiplayer/local-db', 'legacy-document', { nowMs: NOW_MS, seed: LEGACY_DOC }, () => {
    const harness = new Harness(NOW_MS, LEGACY_DOC)
    return {
      guilds: harness.backend.listGuilds(),
      members: harness.backend.guildMembers('gld_legacy'),
      // Writing anything re-serializes every table, so this is the migrated doc.
      afterWrite: (() => {
        harness.backend.muteUser('usr_legacy', 'usr_other')
        return harness.doc()
      })(),
    } as unknown as JsonValue
  }),

  scenario(
    'multiplayer/public-profile',
    'privacy',
    { nowMs: NOW_MS, save: asJson(profileSave()) },
    () => {
      const harness = new Harness()
      const hero = harness.signUp('hero@example.com', 'Hero')
      const shy = harness.signUp('shy@example.com', 'Shy')
      const save = profileSave()
      harness.backend.writeCloudSave(hero.userId, save)
      harness.backend.writeCloudSave(shy.userId, save)
      harness.backend.upsertProfile(shy.userId, { privacyPublicSkills: false })
      const friendRequest = harness.backend.sendFriendRequest(hero.userId, shy.userId)
      const duplicateRequest = harness.backend.sendFriendRequest(hero.userId, shy.userId)
      const self = harness.backend.sendFriendRequest(hero.userId, hero.userId)
      const accepted = harness.backend.sendFriendRequest(shy.userId, hero.userId)
      const alreadyFriends = harness.backend.sendFriendRequest(hero.userId, shy.userId)
      return {
        open: harness.backend.publicProfile(hero.userId),
        private: harness.backend.publicProfile(shy.userId),
        noAccount: harness.backend.publicProfile('usr_9999'),
        noSave: harness.backend.publicProfile(hero.userId, {
          ...save,
          skills: [],
          achievements: [],
        }),
        friendRequest,
        duplicateRequest,
        self,
        accepted,
        alreadyFriends,
      } as unknown as JsonValue
    },
  ),

  scenario(
    'multiplayer/remote',
    'rows',
    {
      source: 'content',
      save: asJson(pinnedSave()),
      nowIso: '2026-08-12T21:00:00.000Z',
      saveRows: REMOTE_SAVE_ROWS as unknown as JsonValue,
      boardRows: REMOTE_BOARD_ROWS as unknown as JsonValue,
      chatRows: REMOTE_CHAT_ROWS as unknown as JsonValue,
    },
    () => {
      const save = pinnedSave()
      const snapshot = buildLeaderboardSnapshot(contentDatabase(), save)
      const records = REMOTE_SAVE_ROWS.map((row) => cloudSaveRecordFrom('usr_0001', row))
      return {
        names: {
          tables: REMOTE_TABLES,
          sendChat: REMOTE_SEND_CHAT_FUNCTION,
          saveColumns: REMOTE_SAVE_COLUMNS,
          chatColumns: REMOTE_CHAT_COLUMNS,
          leaderboardColumns: REMOTE_LEADERBOARD_COLUMNS,
          leaderboardConflict: REMOTE_LEADERBOARD_CONFLICT,
          chatLimit: REMOTE_CHAT_LIMIT,
          usernameMaxLength: REMOTE_USERNAME_MAX_LENGTH,
        },
        messages: {
          notConfigured: REMOTE_NOT_CONFIGURED,
          signUpFailed: REMOTE_SIGN_UP_FAILED,
          signInFailed: REMOTE_SIGN_IN_FAILED,
          magicLinkUnavailable: REMOTE_MAGIC_LINK_UNAVAILABLE,
        },
        usernames: ['  Rowan  ', 'a'.repeat(40), ''].map(remoteUsername),
        emails: ['  HERO@Example.com ', 'plain@example.com'].map(remoteEmail),
        signUpSession: sessionFromSignUp('usr_0001', '  HERO@Example.com ', ' Rowan ', 'token'),
        signUpWithoutToken: sessionFromSignUp('usr_0001', 'a@b.co', 'Rowan', null),
        signInSessions: [
          sessionFromSignIn('usr_0001', 'hero@example.com', 'typed@x.co', 'Rowan', 'token'),
          sessionFromSignIn('usr_0001', 'hero@example.com', 'typed@x.co', null, null),
          sessionFromSignIn('usr_0001', null, '  TYPED@X.co ', null, null),
        ],
        profileRow: profileRowForSignUp(
          sessionFromSignUp('usr_0001', 'a@b.co', 'Rowan', null),
        ),
        saveRow: saveRowFor('usr_0001', save),
        cloudRecords: records,
        newer: records.map((record) => (record ? isRemoteSaveNewer(record, save) : null)),
        leaderboardRows: leaderboardRowsFor('usr_0001', snapshot, '2026-08-12T21:00:00.000Z'),
        entries: leaderboardEntriesFrom(REMOTE_BOARD_ROWS, 'total_level'),
        chatMessages: REMOTE_CHAT_ROWS.map(chatMessageFrom),
        defaultAppearance: DEFAULT_PLAYER_APPEARANCE,
      } as unknown as JsonValue
    },
  ),
]
