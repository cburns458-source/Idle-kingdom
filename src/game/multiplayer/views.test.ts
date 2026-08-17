import { describe, expect, it } from 'vitest'
import {
  boardOptions,
  citadelVisitorSubtitle,
  createGuildFormView,
  defaultApplicationMessage,
  emptyBoardMessage,
  filterGuildListings,
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
} from './views'
import type {
  ActivityPresence,
  GuildListing,
  GuildMember,
  GuildRecord,
  LeaderboardEntry,
  PublicPlayerProfile,
} from './types'
import { DEFAULT_GUILD_RANK_LABELS } from './types'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import type { PlayerAppearance } from '../save/types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

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

describe('guild browser views', () => {
  it('matches a search on name, tag, or bracketed tag', () => {
    const rows = [
      listing({ id: 'gld_1', name: 'Iron League', tag: 'IRN' }),
      listing({ id: 'gld_2', name: 'Oak Guard', tag: 'OAK' }),
    ]
    expect(filterGuildListings(rows, '  ').map((row) => row.id)).toEqual(['gld_1', 'gld_2'])
    expect(filterGuildListings(rows, 'oak').map((row) => row.id)).toEqual(['gld_2'])
    expect(filterGuildListings(rows, '[irn]').map((row) => row.id)).toEqual(['gld_1'])
    expect(filterGuildListings(rows, 'league').map((row) => row.id)).toEqual(['gld_1'])
    expect(filterGuildListings(rows, 'zzz')).toEqual([])
  })

  it('describes a row the way the button behaves', () => {
    const [open, closed, full] = guildBrowseRows([
      listing({ id: 'gld_1' }),
      listing({ id: 'gld_2', joinPolicy: 'closed', description: '' }),
      listing({ id: 'gld_3', memberCount: 25 }),
    ])
    expect(open.title).toBe('[IRN] Iron League')
    expect(open.subtitle).toBe('Accept applications · 3/25 · For the kingdom')
    expect(open.actionLabel).toBe('Join')
    expect(open.guestLabel).toBe('Guest')
    expect(closed.subtitle).toBe('Closed · 3/25 · No description.')
    expect(closed.actionLabel).toBe('Apply')
    expect(full.actionLabel).toBe('Full')
    expect(full.full).toBe(true)
  })

  it('writes an application for a nameless character', () => {
    expect(defaultApplicationMessage('Rowan')).toBe('Rowan requests to join')
    expect(defaultApplicationMessage(null)).toBe('Adventurer requests to join')
  })

  it('prices the create form against the player purse', () => {
    const poor = createGuildFormView(10, 'ir')
    expect(poor.costLine).toBe('Costs 25 gold · you have 10')
    expect(poor.tagPreview).toBe('[IR]')
    expect(poor.canAfford).toBe(false)
    expect(poor.submitLabel).toBe('Not enough gold')

    const rich = createGuildFormView(1200, '')
    expect(rich.costLine).toBe('Costs 25 gold · you have 1,200')
    expect(rich.tagPreview).toBe('[??]')
    expect(rich.submitLabel).toBe('Create for 25 gold')
  })

  it('keeps only the letters a tag may hold', () => {
    expect(sanitizeGuildTagInput('ir n2!')).toBe('IRN')
    expect(sanitizeGuildTagInput('abcdefg')).toBe('ABCD')
  })
})

describe('guild home views', () => {
  it('marks the leader as the one who can manage', () => {
    const header = guildHomeHeader(guild(), 4, 'usr_1')
    expect(header.title).toBe('[IRN] Iron League')
    expect(header.subtitle).toBe('Accept applications · 4/25 members')
    expect(header.canManage).toBe(true)
    expect(guildHomeHeader(guild(), 4, 'usr_2').canManage).toBe(false)
    expect(guildHomeHeader(guild(), 4, null).canManage).toBe(false)
  })

  it('sorts the roster by join date, both ways', () => {
    const members = [
      member({ userId: 'usr_1', username: 'Leader', role: 'leader', joinedAt: '2026-08-01T00:00:00.000Z' }),
      member({ userId: 'usr_3', username: 'Late', joinedAt: '2026-08-03T00:00:00.000Z' }),
      member({ userId: 'usr_2', username: 'Early', joinedAt: '2026-08-02T00:00:00.000Z' }),
    ]
    const oldest = guildRosterRows(guild(), members, 'oldest', 'usr_1')
    expect(oldest.map((row) => row.username)).toEqual(['Leader', 'Early', 'Late'])
    expect(oldest.map((row) => row.position)).toEqual([1, 2, 3])
    expect(oldest[0].manageable).toBe(false)
    expect(oldest[1].manageable).toBe(true)

    const newest = guildRosterRows(guild(), members, 'newest', 'usr_1')
    expect(newest.map((row) => row.username)).toEqual(['Late', 'Early', 'Leader'])
  })

  it('keeps backend order when two members joined at the same moment', () => {
    const same = '2026-08-02T00:00:00.000Z'
    const rows = guildRosterRows(
      guild(),
      [
        member({ userId: 'usr_2', username: 'First', joinedAt: same }),
        member({ userId: 'usr_3', username: 'Second', joinedAt: same }),
      ],
      'oldest',
      null,
    )
    expect(rows.map((row) => row.username)).toEqual(['First', 'Second'])
  })

  it('labels last-online from presence age', () => {
    const now = Date.parse('2026-08-12T21:00:00.000Z')
    const rows = guildRosterRows(
      guild(),
      [
        member({ userId: 'usr_1', username: 'On' }),
        member({ userId: 'usr_2', username: 'Hour' }),
        member({ userId: 'usr_3', username: 'Never' }),
      ],
      'oldest',
      'usr_1',
      [
        presence({ userId: 'usr_1', updatedAt: '2026-08-12T20:59:10.000Z' }),
        presence({ userId: 'usr_2', updatedAt: '2026-08-12T20:00:00.000Z' }),
      ],
      now,
    )
    expect(rows.map((row) => row.lastOnlineLabel)).toEqual(['Online', '1h ago', 'Unknown'])
    expect(rows.map((row) => row.isOnline)).toEqual([true, false, false])
  })

  it('uses the rank names the guild chose', () => {
    const renamed = guild({
      rankLabels: { ...DEFAULT_GUILD_RANK_LABELS, officer: 'Captain', member: 'Blade' },
    })
    const rows = guildRosterRows(renamed, [member({ role: 'officer' })], 'oldest', 'usr_1')
    expect(rows[0].rankLabel).toBe('Captain')
    expect(guildRankOptions(renamed).map((option) => option.label)).toEqual([
      'Captain',
      'Veteran',
      'Blade',
      'Recruit',
    ])
    expect(rankLabelFields(renamed).map((field) => field.fieldLabel)).toEqual([
      'Leader slot',
      'Officer slot',
      'Veteran slot',
      'Member slot',
      'Recruit slot',
    ])
    expect(rankLabelFields(renamed)[1].value).toBe('Captain')
  })

  it('falls back to a default when a rank name is missing', () => {
    const sparse = guild({
      rankLabels: { ...DEFAULT_GUILD_RANK_LABELS, officer: undefined as unknown as string },
    })
    expect(rankLabelFields(sparse)[1].value).toBe('Officer')
    expect(guildRankOptions(sparse)[0].label).toBe('Officer')
  })

  it('spells out what leaving costs', () => {
    expect(leaveGuildPrompt(guild())).toBe(
      'Leave [IRN] Iron League? You will need to rejoin or reapply later.',
    )
  })

  it('shows a placeholder for a wordless application', () => {
    const rows = guildApplicationRows([
      { id: 'app_1', guildId: 'gld_1', userId: 'usr_2', username: 'Joiner', message: 'Please', createdAt: '' },
      { id: 'app_2', guildId: 'gld_1', userId: 'usr_3', username: 'Quiet', message: '', createdAt: '' },
      {
        id: 'app_3',
        guildId: 'gld_1',
        userId: 'usr_4',
        username: 'Wanderer',
        message: 'Hi',
        createdAt: '',
        guest: true,
      },
      {
        id: 'app_4',
        guildId: 'gld_1',
        userId: 'usr_5',
        username: 'Silent',
        message: '',
        createdAt: '',
        guest: true,
      },
    ])
    expect(rows.map((row) => row.message)).toEqual([
      'Please',
      'No message.',
      'Guest: Hi',
      'Guest request.',
    ])
    expect(rows[2].guest).toBe(true)
    expect(rows[0].guest).toBeUndefined()
  })
})

describe('leaderboard views', () => {
  it('offers every launch board with its label', () => {
    const db = prepareDatabase(rawDatabase).launch
    const options = boardOptions(db)
    expect(options[0]).toEqual({ key: 'total_level', label: 'Total Level' })
    expect(options.some((option) => option.key === 'guild_total_level')).toBe(true)
  })

  it('groups values and names the guild column', () => {
    const rows = leaderboardRows([
      entry({ value: 1204, guildName: 'Iron League' }),
      entry({ rank: 2, userId: 'usr_2', username: 'Rival', value: 12 }),
      entry({
        rank: 1,
        boardKey: 'guild_total_level',
        entryKind: 'guild',
        userId: 'gld_1',
        username: '[IRN] Iron League',
        guildName: '4/25 members',
        emblem: { color: '#3d5a80', symbol: 'shield' },
      }),
    ])
    expect(rows[0].valueLabel).toBe('1,204')
    expect(rows[0].subtitle).toBe('Iron League')
    expect(rows[0].emblem).toBeNull()
    expect(rows[1].subtitle).toBe('No guild')
    expect(rows[2].isGuild).toBe(true)
    expect(rows[2].subtitle).toBe('4/25 members')
    expect(rows[2].emblem?.symbol).toBe('shield')
  })

  it('points an empty board at the way to fill it', () => {
    expect(emptyBoardMessage('total_level')).toBe('No scores yet — sync a cloud save to submit.')
    expect(emptyBoardMessage('guild_total_level')).toBe(
      'No guilds yet — create or join one from the Guilds tab.',
    )
  })
})

describe('presence views', () => {
  const skillName = (skillId: string | null) => (skillId === 'SKL-0001' ? 'Combat' : 'Unknown')

  it('names the skill a peer is working', () => {
    const rows = peerRows(
      [presence(), presence({ userId: 'usr_3', guildName: 'Iron League' }), presence({ userId: 'usr_4', skillLevel: null })],
      skillName,
    )
    expect(rows[0].subtitle).toBe('Combat 7')
    expect(rows[1].subtitle).toBe('Combat 7 · Iron League')
    expect(rows[2].subtitle).toBe('Combat —')
  })

  it('says whether a Citadel visitor has a guild', () => {
    expect(citadelVisitorSubtitle(presence())).toBe('No guild · Lv 7')
    expect(citadelVisitorSubtitle(presence({ guildName: 'Iron League', skillLevel: null }))).toBe(
      'Iron League',
    )
  })

  it('caps the skills a public profile lists', () => {
    const profile: PublicPlayerProfile = {
      userId: 'usr_2',
      username: 'Rival',
      appearance: APPEARANCE,
      totalLevel: 214,
      guildName: 'Iron League',
      achievementsUnlocked: 12,
      publicSkills: Array.from({ length: 10 }, (_, index) => ({
        skillId: 'SKL-0001',
        level: index + 1,
        xp: 0,
      })),
    }
    const view = publicProfileView(profile, skillName)
    expect(view.summaryLine).toBe('Total level 214 · Iron League · 12 achievements')
    expect(view.skillLines).toHaveLength(8)
    expect(view.skillLines[0]).toBe('Combat 1')
    expect(view.skillsHidden).toBe(false)

    const hidden = publicProfileView({ ...profile, guildName: null, publicSkills: [] }, skillName)
    expect(hidden.summaryLine).toBe('Total level 214 · 12 achievements')
    expect(hidden.skillsHidden).toBe(true)
  })
})

describe('account views', () => {
  it('names the backend the player is talking to', () => {
    expect(multiplayerModeLine('local')).toBe(
      'Accounts use the local demo backend. Sign in to play and sync progress.',
    )
    expect(multiplayerModeLine('supabase')).toBe(
      'Accounts use the Supabase. Sign in to play and sync progress.',
    )
  })
})
