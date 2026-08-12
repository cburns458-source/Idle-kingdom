import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { LocalMultiplayerBackend, filterProfanity } from './localBackend'
import { MULTIPLAYER_LOCAL_DB_KEY } from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('local multiplayer backend', () => {
  beforeEach(() => {
    localStorage.removeItem(MULTIPLAYER_LOCAL_DB_KEY)
  })

  it('supports account, cloud save, leaderboard, chat, guild, and presence', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const backend = new LocalMultiplayerBackend()
    const signed = backend.signUp('hero@example.com', 'Hero', 'secret')
    expect(signed.ok).toBe(true)
    if (!signed.ok) return

    let save = {
      ...createNewSave(launch),
      characterName: 'Hero',
      statistics: { values: { monsters_killed: 5, gold_earned: 100 } },
    }
    const pushed = backend.writeCloudSave(signed.session.userId, save)
    expect(pushed.ok).toBe(true)
    backend.submitLeaderboardSnapshot(launch, signed.session.userId, save)
    const board = backend.listLeaderboard('monsters_killed')
    expect(board[0]?.username).toBe('Hero')
    expect(board[0]?.value).toBe(5)

    const chat = backend.sendChat(signed.session, { kind: 'global' }, 'Hello world')
    expect(chat.ok).toBe(true)
    expect(backend.listChat({ kind: 'global' }, signed.session.userId)).toHaveLength(1)

    const guild = backend.createGuild(
      signed.session,
      {
        name: 'Oak Guard',
        tag: 'OAK',
        description: 'For the kingdom',
        emblem: { color: '#2f6b3a', symbol: '🌲' },
      },
      100,
    )
    expect(guild.ok).toBe(true)
    if (!guild.ok) return
    expect(guild.goldCost).toBe(25)
    expect(guild.guild.tag).toBe('OAK')
    expect(backend.guildMembers(guild.guild.id)).toHaveLength(1)

    backend.upsertPresence(signed.session, {
      appearance: save.appearance,
      locationId: save.currentLocationId,
      currentActivityId: 'ACT-0001',
      skillId: 'SKL-0001',
      skillLevel: 1,
      outfitCosmeticId: null,
      mountCosmeticId: null,
    })
    expect(
      backend.listPresence({
        locationId: save.currentLocationId,
        activityId: 'ACT-0001',
      }),
    ).toHaveLength(1)
  })

  it('filters basic profanity', () => {
    expect(filterProfanity('what the fuck')).toMatch(/\*+/)
  })

  it('supports guild search fields, open join, closed apps, ranks, and create cost', () => {
    const backend = new LocalMultiplayerBackend()
    const leader = backend.signUp('leader@example.com', 'Leader', 'secret')
    const applicant = backend.signUp('join@example.com', 'Joiner', 'secret')
    expect(leader.ok && applicant.ok).toBe(true)
    if (!leader.ok || !applicant.ok) return

    const poor = backend.createGuild(
      leader.session,
      { name: 'Broke Band', tag: 'BRK', emblem: { color: '#5c4027', symbol: '⚔️' } },
      10,
    )
    expect(poor.ok).toBe(false)

    const created = backend.createGuild(
      leader.session,
      { name: 'Iron League', tag: 'IRN', emblem: { color: '#3d5a80', symbol: '🛡️' } },
      25,
    )
    expect(created.ok).toBe(true)
    if (!created.ok) return

    backend.setGuildJoinPolicy(leader.session.userId, created.guild.id, 'closed')
    const applied = backend.applyToGuild(applicant.session, created.guild.id, 'Please')
    expect(applied.ok).toBe(true)
    if (!applied.ok) return
    expect(applied.joined).toBe(false)
    expect(backend.listApplications(created.guild.id)).toHaveLength(1)

    const accepted = backend.decideApplication(
      leader.session.userId,
      backend.listApplications(created.guild.id)[0]!.id,
      true,
    )
    expect(accepted.ok).toBe(true)
    expect(backend.guildMembers(created.guild.id)).toHaveLength(2)

    const promoted = backend.setMemberRole(
      leader.session.userId,
      created.guild.id,
      applicant.session.userId,
      'officer',
    )
    expect(promoted.ok).toBe(true)
    expect(
      backend.guildMembers(created.guild.id).find((row) => row.userId === applicant.session.userId)
        ?.role,
    ).toBe('officer')

    const renamed = backend.setGuildRankLabels(leader.session.userId, created.guild.id, {
      officer: 'Captain',
    })
    expect(renamed.ok).toBe(true)
    expect(backend.getGuild(created.guild.id)?.rankLabels.officer).toBe('Captain')

    backend.setGuildJoinPolicy(leader.session.userId, created.guild.id, 'open')
    const third = backend.signUp('third@example.com', 'Third', 'secret')
    expect(third.ok).toBe(true)
    if (!third.ok) return
    const autoJoin = backend.applyToGuild(third.session, created.guild.id, '')
    expect(autoJoin.ok).toBe(true)
    if (!autoJoin.ok) return
    expect(autoJoin.joined).toBe(true)
  })
})
