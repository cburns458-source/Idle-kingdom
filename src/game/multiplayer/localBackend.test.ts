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

    const guild = backend.createGuild(signed.session, 'Oak Guard', 'For the kingdom')
    expect(guild.ok).toBe(true)
    if (!guild.ok) return
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
})
