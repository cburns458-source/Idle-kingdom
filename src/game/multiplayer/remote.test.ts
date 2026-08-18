import { describe, expect, it } from 'vitest'
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
  type RemoteRow,
} from './remote'
import { DEFAULT_PLAYER_APPEARANCE, type CloudSaveRecord } from './types'
import type { PlayerSave } from '../save/types'

function save(overrides: Partial<PlayerSave> = {}): PlayerSave {
  return {
    saveVersion: 22,
    updatedAt: '2026-08-12T21:00:00.000Z',
    gold: 10,
    ...overrides,
  } as unknown as PlayerSave
}

describe('remote identity', () => {
  it('trims and caps what a username may be', () => {
    expect(remoteUsername('  Rowan  ')).toBe('Rowan')
    expect(remoteUsername('a'.repeat(40))).toHaveLength(24)
  })

  it('folds an email to one form so two spellings are one account', () => {
    expect(remoteEmail('  HERO@Example.com ')).toBe('hero@example.com')
  })

  it('keeps the username the sign-up asked for', () => {
    const session = sessionFromSignUp('usr-1', ' HERO@Example.com ', '  Rowan  ', 'token')
    expect(session).toEqual({
      userId: 'usr-1',
      email: 'hero@example.com',
      username: 'Rowan',
      accessToken: 'token',
    })
  })

  it('treats a missing access token as none rather than as undefined', () => {
    expect(sessionFromSignUp('usr-1', 'a@b.co', 'Rowan', null).accessToken).toBe('')
  })

  it('prefers the stored username on sign-in', () => {
    const session = sessionFromSignIn('usr-1', 'hero@example.com', 'typed@x.co', 'Rowan', 'token')
    expect(session.username).toBe('Rowan')
    expect(session.email).toBe('hero@example.com')
  })

  it('falls back to the local part of the email, then to a generic name', () => {
    expect(sessionFromSignIn('usr-1', 'hero@example.com', 'x@y.co', null, null).username).toBe(
      'hero',
    )
    expect(sessionFromSignIn('usr-1', null, ' TYPED@X.co ', null, null)).toEqual({
      userId: 'usr-1',
      email: 'typed@x.co',
      username: 'Adventurer',
      accessToken: '',
    })
  })

  it('opts a new account into public skills', () => {
    const session = sessionFromSignUp('usr-1', 'a@b.co', 'Rowan', null)
    expect(profileRowForSignUp(session)).toEqual({
      user_id: 'usr-1',
      username: 'Rowan',
      privacy_public_skills: true,
    })
  })
})

describe('remote cloud saves', () => {
  it('writes the version and the stamp the save carries', () => {
    expect(saveRowFor('usr-1', save())).toMatchObject({
      user_id: 'usr-1',
      save_version: 22,
      updated_at: '2026-08-12T21:00:00.000Z',
    })
  })

  it('reads a row back as the cloud copy it stands for', () => {
    const row: RemoteRow = {
      save_version: '23',
      updated_at: '2026-08-12T22:00:00.000Z',
      payload: save(),
    }
    expect(cloudSaveRecordFrom('usr-1', row)).toMatchObject({
      userId: 'usr-1',
      saveVersion: 23,
      updatedAt: '2026-08-12T22:00:00.000Z',
    })
  })

  it('reports no row as no cloud save', () => {
    expect(cloudSaveRecordFrom('usr-1', null)).toBeNull()
  })

  it('lets the stored copy win only when it is newer by clock and version', () => {
    const local = save()
    const remote = (overrides: Partial<CloudSaveRecord>): CloudSaveRecord => ({
      userId: 'usr-1',
      saveVersion: 22,
      updatedAt: '2026-08-12T22:00:00.000Z',
      payload: local,
      ...overrides,
    })
    expect(isRemoteSaveNewer(remote({}), local)).toBe(true)
    expect(isRemoteSaveNewer(remote({ updatedAt: '2026-08-12T20:00:00.000Z' }), local)).toBe(false)
    // Newer by the clock but written by an older build: the migration wins.
    expect(isRemoteSaveNewer(remote({ saveVersion: 21 }), local)).toBe(false)
  })
})

describe('remote leaderboards', () => {
  it('stamps every board of one submit with the same instant', () => {
    const rows = leaderboardRowsFor(
      'usr-1',
      {
        boards: [
          { boardKey: 'total_level', value: 42, secondaryValue: 1204 },
          { boardKey: 'gold_earned', value: 7 },
        ],
      },
      '2026-08-12T21:00:00.000Z',
    )
    expect(rows).toEqual([
      {
        user_id: 'usr-1',
        board_key: 'total_level',
        value: 42,
        value_secondary: 1204,
        updated_at: '2026-08-12T21:00:00.000Z',
      },
      {
        user_id: 'usr-1',
        board_key: 'gold_earned',
        value: 7,
        value_secondary: 0,
        updated_at: '2026-08-12T21:00:00.000Z',
      },
    ])
  })

  it('reads experience back on a combined board and drops it elsewhere', () => {
    const row = {
      user_id: 'usr-1',
      value: '42',
      value_secondary: '1204',
      profiles: {
        username: 'Hero',
        appearance_json: DEFAULT_PLAYER_APPEARANCE,
        guild_id: null,
        guilds: null,
      },
    }

    expect(leaderboardEntriesFrom([row], 'total_level')[0].secondaryValue).toBe(1204)
    expect(leaderboardEntriesFrom([row], 'gold_earned')[0].secondaryValue).toBeUndefined()
  })

  it('leaves a fighter off the pacifist board', () => {
    const rows = [
      {
        user_id: 'usr-1',
        value: '42',
        value_secondary: '1204',
        profiles: {
          username: 'Hero',
          appearance_json: DEFAULT_PLAYER_APPEARANCE,
          guild_id: null,
          guilds: null,
        },
      },
      {
        user_id: 'usr-2',
        value: '0',
        value_secondary: '0',
        profiles: {
          username: 'Brawler',
          appearance_json: DEFAULT_PLAYER_APPEARANCE,
          guild_id: null,
          guilds: null,
        },
      },
    ]

    const entries = leaderboardEntriesFrom(rows, 'total_level_combat_1')
    expect(entries.map((entry) => entry.username)).toEqual(['Hero'])
    expect(entries[0].rank).toBe(1)
  })

  it('ranks rows by the order the read returned them', () => {
    const entries = leaderboardEntriesFrom(
      [
        {
          user_id: 'usr-1',
          value: '1204',
          profiles: {
            username: 'Hero',
            appearance_json: DEFAULT_PLAYER_APPEARANCE,
            guilds: { name: 'Iron League' },
          },
        },
        { user_id: 'usr-2', value: 12, profiles: null },
      ],
      'total_level',
    )
    expect(entries[0]).toMatchObject({ rank: 1, username: 'Hero', guildName: 'Iron League' })
    expect(entries[1]).toMatchObject({
      rank: 2,
      username: 'Adventurer',
      guildName: null,
      value: 12,
      appearance: DEFAULT_PLAYER_APPEARANCE,
    })
  })
})

describe('remote chat', () => {
  it('reads a message row as a message', () => {
    expect(
      chatMessageFrom({
        id: 7,
        channel_key: 'global',
        user_id: 'usr-1',
        username: 'Hero',
        body: 'Hello',
        created_at: '2026-08-12T21:00:00.000Z',
      }),
    ).toEqual({
      id: '7',
      channelKey: 'global',
      userId: 'usr-1',
      username: 'Hero',
      body: 'Hello',
      createdAt: '2026-08-12T21:00:00.000Z',
    })
  })

  it('reads a row with holes in it without throwing', () => {
    expect(chatMessageFrom({})).toEqual({
      id: '',
      channelKey: '',
      userId: '',
      username: '',
      body: '',
      createdAt: '',
    })
  })

  it('reads guild tag, rank, and guest flags when the row has them', () => {
    expect(
      chatMessageFrom({
        id: 'msg_2',
        channel_key: 'guild:gld_1',
        user_id: 'usr-2',
        username: 'Mira',
        body: 'Hold',
        created_at: '2026-08-12T21:00:01.000Z',
        guild_tag: 'DEV',
        rank_label: 'Leader',
        rank_icon: '★',
        guest: true,
      }),
    ).toEqual({
      id: 'msg_2',
      channelKey: 'guild:gld_1',
      userId: 'usr-2',
      username: 'Mira',
      body: 'Hold',
      createdAt: '2026-08-12T21:00:01.000Z',
      guildTag: 'DEV',
      rankLabel: 'Leader',
      rankIcon: '★',
      guest: true,
    })
  })
})
