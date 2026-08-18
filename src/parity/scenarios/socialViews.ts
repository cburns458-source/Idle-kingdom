import { guildEmblemSymbolPath } from '../../game/multiplayer/emblems'
import {
  DEFAULT_GUILD_RANK_LABELS,
  GUILD_EMBLEM_SYMBOLS,
  type ActivityPresence,
  type ChatMessage,
  type GuildApplication,
  type GuildListing,
  type GuildMember,
  type GuildRecord,
  type LeaderboardEntry,
  type PublicPlayerProfile,
} from '../../game/multiplayer/types'
import {
  boardOptions,
  chatChannelForTab,
  chatLines,
  chatLocalLocationId,
  chatTabs,
  citadelVisitorSubtitle,
  createGuildFormView,
  defaultApplicationMessage,
  dmReadCursorKey,
  emptyBoardMessage,
  emptyChatMessage,
  guildApplicationRows,
  guildBrowseRows,
  guildHomeHeader,
  guildRankOptions,
  guildRosterRows,
  leaderboardRows,
  leaveGuildPrompt,
  multiplayerModeLine,
  peerRows,
  publicProfileView,
  rankLabelFields,
  sanitizeGuildTagInput,
  unreadBadgeLabel,
  CHAT_DM_HINT,
  CHAT_NO_GUEST_NOTICE,
  CHAT_NO_GUILD_NOTICE,
  CHAT_TABS,
  GUILD_SIGN_IN_PROMPT,
  SIGN_IN_PROMPT,
} from '../../game/multiplayer/views'
import type { PlayerAppearance } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'

const APPEARANCE: PlayerAppearance = {
  skinTone: 'APR-0001',
  hairstyle: 'APR-0004',
  hairColor: 'APR-0007',
  expression: 'APR-0011',
  beard: 'APR-0014',
  genderPresentation: 'APR-0017',
}

function guild(overrides: Partial<GuildRecord> = {}): GuildRecord {
  return {
    id: 'gld_1',
    name: 'Iron League',
    tag: 'IRN',
    description: 'For the kingdom',
    emblem: { color: '#3d5a80', symbol: 'shield' },
    leaderId: 'usr_1',
    joinPolicy: 'open',
    rankLabels: { ...DEFAULT_GUILD_RANK_LABELS },
    createdAt: '2026-08-01T00:00:00.000Z',
    ...overrides,
  }
}

function listing(overrides: Partial<GuildListing> = {}): GuildListing {
  return { ...guild(), memberCount: 3, ...overrides }
}

function member(overrides: Partial<GuildMember> = {}): GuildMember {
  return {
    guildId: 'gld_1',
    userId: 'usr_2',
    username: 'Joiner',
    role: 'member',
    joinedAt: '2026-08-02T00:00:00.000Z',
    appearance: APPEARANCE,
    totalLevel: 42,
    ...overrides,
  }
}

function presence(overrides: Partial<ActivityPresence> = {}): ActivityPresence {
  return {
    userId: 'usr_2',
    username: 'Rival',
    appearance: APPEARANCE,
    locationId: 'LOC-0028',
    currentActivityId: null,
    skillId: 'SKL-0001',
    skillLevel: 7,
    guildName: null,
    outfitCosmeticId: null,
    mountCosmeticId: null,
    updatedAt: '2026-08-12T21:00:00.000Z',
    expiresAt: '2026-08-12T21:02:00.000Z',
    ...overrides,
  }
}

function entry(overrides: Partial<LeaderboardEntry> = {}): LeaderboardEntry {
  return {
    boardKey: 'total_level',
    entryKind: 'player',
    rank: 1,
    userId: 'usr_1',
    username: 'Hero',
    value: 1204,
    appearance: APPEARANCE,
    guildName: null,
    emblem: null,
    ...overrides,
  }
}

function application(overrides: Partial<GuildApplication> = {}): GuildApplication {
  return {
    id: 'app_1',
    guildId: 'gld_1',
    userId: 'usr_2',
    username: 'Joiner',
    message: 'Please',
    createdAt: '2026-08-02T00:00:00.000Z',
    ...overrides,
  }
}

/** A guild that renamed some ranks and left others alone. */
function renamedGuild(): GuildRecord {
  return guild({
    rankLabels: {
      ...DEFAULT_GUILD_RANK_LABELS,
      officer: 'Captain',
      member: 'Blade',
      recruit: undefined as unknown as string,
    },
  })
}

const SAME_MOMENT = '2026-08-02T00:00:00.000Z'

const ROSTER: GuildMember[] = [
  member({
    userId: 'usr_1',
    username: 'Leader',
    role: 'leader',
    joinedAt: '2026-08-01T00:00:00.000Z',
    totalLevel: 90,
  }),
  member({ userId: 'usr_3', username: 'Late', joinedAt: '2026-08-03T00:00:00.000Z' }),
  member({ userId: 'usr_2', username: 'Early', joinedAt: SAME_MOMENT, role: 'officer' }),
  member({ userId: 'usr_4', username: 'Twin', joinedAt: SAME_MOMENT, role: 'recruit' }),
]

const ROSTER_NOW = Date.parse('2026-08-12T21:00:00.000Z')
const ROSTER_PRESENCE: ActivityPresence[] = [
  presence({ userId: 'usr_1', updatedAt: '2026-08-12T20:59:10.000Z' }),
  presence({ userId: 'usr_2', updatedAt: '2026-08-12T20:00:00.000Z' }),
  presence({ userId: 'usr_4', updatedAt: '2026-08-12T20:59:50.000Z' }),
]

const PROFILE: PublicPlayerProfile = {
  userId: 'usr_2',
  username: 'Rival',
  appearance: APPEARANCE,
  totalLevel: 214,
  guildName: 'Iron League',
  achievementsUnlocked: 12,
  publicSkills: Array.from({ length: 10 }, (_, index) => ({
    skillId: index === 0 ? 'SKL-0001' : 'SKL-0002',
    level: index + 1,
    xp: index * 100,
  })),
}

const SKILL_NAMES: Record<string, string> = { 'SKL-0001': 'Combat', 'SKL-0002': 'Woodcutting' }

function skillName(skillId: string | null): string {
  return skillId === null ? 'Unknown' : (SKILL_NAMES[skillId] ?? skillId)
}

export const socialViewScenarios: ParityScenario[] = [
  scenario('social-views/guilds', 'browse', { source: 'raw', value: null }, () => {
    const rows: GuildListing[] = [
      listing({ id: 'gld_1' }),
      listing({ id: 'gld_2', name: 'Oak Guard', tag: 'OAK', joinPolicy: 'closed', description: '' }),
      listing({ id: 'gld_3', name: 'Full House', tag: 'FUL', memberCount: 25 }),
    ]
    return {
      all: guildBrowseRows(rows),
      blank: guildBrowseRows(rows, '   ').map((row) => row.guildId),
      byName: guildBrowseRows(rows, 'oak').map((row) => row.guildId),
      byBracketedTag: guildBrowseRows(rows, '[irn]').map((row) => row.guildId),
      byPartialName: guildBrowseRows(rows, 'LEAGUE').map((row) => row.guildId),
      noMatch: guildBrowseRows(rows, 'zzz'),
      applicationMessages: [
        defaultApplicationMessage('Rowan'),
        defaultApplicationMessage(null),
        defaultApplicationMessage(''),
        defaultApplicationMessage('   '),
        defaultApplicationMessage('  Rowan  '),
      ],
    } as unknown as JsonValue
  }),

  scenario('social-views/guilds', 'create-form', { source: 'raw', value: null }, () => {
    return {
      poor: createGuildFormView(10, 'ir'),
      rich: createGuildFormView(1200, ''),
      exact: createGuildFormView(25, 'iron5'),
      million: createGuildFormView(1234567, 'a-b c!'),
      sanitized: ['ir n2!', 'abcdefg', '', '1234', 'Ok'].map(sanitizeGuildTagInput),
    } as unknown as JsonValue
  }),

  scenario('social-views/guilds', 'home', { source: 'raw', value: null }, () => {
    const renamed = renamedGuild()
    return {
      leaderHeader: guildHomeHeader(guild(), 4, 'usr_1'),
      memberHeader: guildHomeHeader(guild({ joinPolicy: 'closed' }), 4, 'usr_2'),
      anonymousHeader: guildHomeHeader(guild(), 0, null),
      oldest: guildRosterRows(guild(), ROSTER, 'oldest', 'usr_1', ROSTER_PRESENCE, ROSTER_NOW),
      newest: guildRosterRows(guild(), ROSTER, 'newest', 'usr_1', ROSTER_PRESENCE, ROSTER_NOW).map(
        (row) => row.username,
      ),
      asMember: guildRosterRows(guild(), ROSTER, 'oldest', 'usr_2', ROSTER_PRESENCE, ROSTER_NOW).map(
        (row) => row.manageable,
      ),
      renamedRoster: guildRosterRows(
        renamed,
        ROSTER,
        'oldest',
        'usr_1',
        ROSTER_PRESENCE,
        ROSTER_NOW,
      ).map((row) => row.rankLabel),
      rankOptions: guildRankOptions(renamed),
      rankFields: rankLabelFields(renamed),
      leavePrompt: leaveGuildPrompt(guild()),
      applications: guildApplicationRows([
        application(),
        application({ id: 'app_2', username: 'Quiet', message: '' }),
        application({ id: 'app_3', username: 'Wanderer', message: 'Hi', guest: true }),
        application({ id: 'app_4', username: 'Silent', message: '', guest: true }),
      ]),
      signInPrompts: [SIGN_IN_PROMPT, GUILD_SIGN_IN_PROMPT],
      symbols: GUILD_EMBLEM_SYMBOLS,
      // Both clients draw the banner from these, so a drifted path is a bug.
      symbolPaths: [...GUILD_EMBLEM_SYMBOLS, 'not-a-symbol'].map((symbol) => ({
        symbol,
        path: guildEmblemSymbolPath(symbol),
      })),
    } as unknown as JsonValue
  }),

  scenario('social-views/leaderboards', 'rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      boards: boardOptions(db),
      rows: leaderboardRows([
        entry({ value: 1204, secondaryValue: 9_500_000, guildName: 'Iron League' }),
        entry({ rank: 2, userId: 'usr_2', username: 'Rival', value: 12 }),
        entry({
          rank: 1,
          boardKey: 'guild_total_level',
          entryKind: 'guild',
          userId: 'gld_1',
          username: '[IRN] Iron League',
          guildName: '4/25 members',
          value: 1234567,
          emblem: { color: '#3d5a80', symbol: 'shield' },
        }),
        entry({
          rank: 2,
          boardKey: 'guild_total_level',
          entryKind: 'guild',
          userId: 'gld_2',
          username: '[OAK] Oak Guard',
          guildName: null,
          value: 0,
          emblem: null,
        }),
      ]),
      emptyMessages: [
        'total_level',
        'guild_total_level',
        'total_level_combat_1',
        'skill:SKL-0001',
      ].map((key) => ({
        key,
        message: emptyBoardMessage(key as 'total_level'),
      })),
    } as unknown as JsonValue
  }),

  scenario('social-views/chat', 'tabs', { source: 'raw', value: null }, () => {
    const messages: ChatMessage[] = [
      {
        id: 'msg_1',
        channelKey: 'global',
        userId: 'usr_1',
        username: 'Hero',
        body: 'Hello world',
        createdAt: '2026-08-12T21:00:00.000Z',
      },
      {
        id: 'msg_2',
        channelKey: 'global',
        userId: 'usr_2',
        username: 'Rival',
        body: 'Hi back',
        createdAt: '2026-08-12T21:00:05.000Z',
      },
    ]
    const tagged: ChatMessage = {
      id: 'msg_3',
      channelKey: 'global',
      userId: 'usr_3',
      username: 'Mira',
      body: 'The road is clear.',
      createdAt: '2026-08-12T21:00:10.000Z',
      guildTag: 'WCH',
    }
    const rude: ChatMessage = {
      id: 'msg_4',
      channelKey: 'global',
      userId: 'usr_4',
      username: 'Loud',
      body: 'what the fuck',
      createdAt: '2026-08-12T21:00:11.000Z',
    }
    const ranked: ChatMessage = {
      id: 'msg_5',
      channelKey: 'guild:gld_1',
      userId: 'usr_3',
      username: 'Mira',
      body: 'Hold the gate.',
      createdAt: '2026-08-12T21:00:12.000Z',
      rankLabel: 'Leader',
      rankIcon: '★',
    }
    const guest: ChatMessage = {
      id: 'msg_6',
      channelKey: 'guild:gld_1',
      userId: 'usr_5',
      username: 'Wanderer',
      body: 'Passing through.',
      createdAt: '2026-08-12T21:00:13.000Z',
      guest: true,
    }
    return {
      tabIds: CHAT_TABS,
      plain: chatTabs({
        selected: 'global',
        citadelHub: false,
        hasGuild: false,
        hasGuest: false,
        unreadDms: 0,
      }),
      citadelWithGuild: chatTabs({
        selected: 'local',
        citadelHub: true,
        hasGuild: true,
        hasGuest: false,
        unreadDms: 3,
      }),
      manyUnread: chatTabs({
        selected: 'dm',
        citadelHub: false,
        hasGuild: true,
        hasGuest: true,
        unreadDms: 12,
      }),
      badges: [0, 1, 9, 10, 99].map(unreadBadgeLabel),
      localLocationIds: [
        chatLocalLocationId('LOC-0002', false),
        chatLocalLocationId('LOC-0028', true),
      ],
      channels: CHAT_TABS.map((tab) => ({
        tab,
        withGuild: chatChannelForTab(tab, {
          locationId: 'LOC-0002',
          citadelHub: false,
          guildId: 'gld_1',
          guestGuildId: 'gld_2',
        }),
        inCitadelWithoutGuild: chatChannelForTab(tab, {
          locationId: 'LOC-0028',
          citadelHub: true,
          guildId: null,
        }),
      })),
      emptyMessages: CHAT_TABS.map(emptyChatMessage),
      hints: [CHAT_DM_HINT, CHAT_NO_GUILD_NOTICE, CHAT_NO_GUEST_NOTICE],
      cursorKey: dmReadCursorKey('usr_0001'),
      lines: chatLines(messages, 'usr_1'),
      linesAnonymous: chatLines(messages, null),
      prefixed: chatLines([tagged], 'usr_1'),
      filtered: chatLines([rude], null, { filterProfanityEnabled: true }),
      guildRank: chatLines([ranked], 'usr_1'),
      guestLine: chatLines([guest], null),
    } as unknown as JsonValue
  }),

  scenario('social-views/presence', 'rows', { source: 'raw', value: null }, () => {
    return {
      peers: peerRows(
        [
          presence(),
          presence({ userId: 'usr_3', guildName: 'Iron League' }),
          presence({ userId: 'usr_4', skillLevel: null }),
          presence({ userId: 'usr_5', skillId: null, skillLevel: null, guildName: 'Oak Guard' }),
          presence({ userId: 'usr_6', skillId: 'SKL-9999', skillLevel: 0 }),
        ],
        skillName,
      ),
      citadelSubtitles: [
        citadelVisitorSubtitle(presence()),
        citadelVisitorSubtitle(presence({ guildName: 'Iron League', skillLevel: null })),
        citadelVisitorSubtitle(presence({ guildName: 'Oak Guard', skillLevel: 0 })),
      ],
      profile: publicProfileView(PROFILE, skillName),
      hiddenProfile: publicProfileView(
        { ...PROFILE, guildName: null, publicSkills: [] },
        skillName,
      ),
      modeLines: [multiplayerModeLine('local'), multiplayerModeLine('supabase')],
    } as unknown as JsonValue
  }),
]
