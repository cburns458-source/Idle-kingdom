// @vitest-environment jsdom
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { beforeEach, describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { chatTitleForSave, chatTitleFromSavePayload } from '../save/playerTitle'
import { STARTER_TITLE_COSMETIC_ID, TITLE_COSMETIC_SLOT_ID, type PlayerSave } from '../save/types'
import { chatTitleFromSavePayload as edgeChatTitleFromSavePayload } from '../../../supabase/functions/_shared/player_title.ts'
import { LocalMultiplayerBackend } from './localBackend'
import { REMOTE_CHAT_COLUMNS } from './remote'
import { MULTIPLAYER_LOCAL_DB_KEY } from './types'
import {
  CHAT_SHOW_TIMESTAMPS_STORAGE_KEY,
  CHAT_SHOW_TITLES_STORAGE_KEY,
  CHAT_TABS,
  chatLineUsername,
  chatLines,
  chatNotifyStorageKey,
  chatTabs,
  formatChatTimestamp,
} from './views'
import type { ChatMessage } from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function chatMessage(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: 'msg_1',
    channelKey: 'global',
    userId: 'usr_1',
    username: 'Rowan',
    body: 'The watch is set.',
    createdAt: '2026-01-01T12:00:00.000Z',
    ...overrides,
  }
}

function withTitle(
  save: ReturnType<typeof createNewSave>,
  cosmeticId: string | null,
  extra: Record<string, unknown> = {},
) {
  return {
    ...save,
    ...extra,
    cosmetics: {
      ...save.cosmetics,
      unlocked: cosmeticId ? [...save.cosmetics.unlocked, cosmeticId] : save.cosmetics.unlocked,
      equipped: { ...save.cosmetics.equipped, [TITLE_COSMETIC_SLOT_ID]: cosmeticId },
    },
  }
}

describe('QA: chat titles from the sender save', () => {
  const { launch } = prepareDatabase(rawDatabase)

  beforeEach(() => {
    localStorage.removeItem(MULTIPLAYER_LOCAL_DB_KEY)
  })

  it('stamps equipped title from the hosted save, null when none, and ignores a spoofed title field', () => {
    const backend = new LocalMultiplayerBackend()
    backend.gameDatabase = launch
    const signed = backend.signUp('hero@example.com', 'Hero', 'secret')
    expect(signed.ok).toBe(true)
    if (!signed.ok) return

    const untitled = backend.sendChat(signed.session, { kind: 'global' }, 'No save yet')
    expect(untitled.ok).toBe(true)
    if (untitled.ok) expect(untitled.message.title).toBeUndefined()

    const living = { ...createNewSave(launch), characterName: 'Hero', title: 'Sir' } as PlayerSave
    expect(backend.writeCloudSave(signed.session.userId, living).ok).toBe(true)
    const undying = backend.sendChat(signed.session, { kind: 'local', locationId: 'LOC-0001' }, 'Hi')
    expect(undying.ok).toBe(true)
    if (undying.ok) {
      expect(undying.message.title).toBe('The Undying')
      expect(undying.message.title).not.toBe('Sir')
      expect(undying.message.body).toBe('Hi')
    }

    const dead = withTitle(living, STARTER_TITLE_COSMETIC_ID, {
      hasEverDied: true,
      title: 'Sir',
      updatedAt: new Date(Date.now() + 1000).toISOString(),
    })
    expect(backend.writeCloudSave(signed.session.userId, dead).ok).toBe(true)
    const lost = backend.sendChat(signed.session, { kind: 'local', locationId: 'LOC-0002' }, 'Still here')
    expect(lost.ok).toBe(true)
    if (lost.ok) {
      expect(lost.message.title).toBeUndefined()
      expect(lost.message.title).not.toBe('Sir')
    }

    const faith = withTitle(living, 'COS-0013', {
      hasEverDied: true,
      title: 'Sir',
      updatedAt: new Date(Date.now() + 2000).toISOString(),
    })
    expect(backend.writeCloudSave(signed.session.userId, faith).ok).toBe(true)
    const oruvani = backend.sendChat(signed.session, { kind: 'local', locationId: 'LOC-0003' }, 'Hold')
    expect(oruvani.ok).toBe(true)
    if (oruvani.ok) {
      expect(oruvani.message.title).toBe('Oruvani')
      expect(oruvani.message.title).not.toBe('Sir')
    }
  })

  it('resolves chat title from the save cosmetics, never a client title field', () => {
    const save = createNewSave(launch)
    expect(chatTitleForSave(save, launch)).toBe('The Undying')
    expect(chatTitleFromSavePayload({ ...save, title: 'Sir' }, launch)).toBe('The Undying')
    expect(edgeChatTitleFromSavePayload({ ...save, title: 'Sir' }, rawDatabase)).toBe('The Undying')
    expect(edgeChatTitleFromSavePayload(null, rawDatabase)).toBeNull()
    expect(
      edgeChatTitleFromSavePayload({ ...save, hasEverDied: true, title: 'Sir' }, rawDatabase),
    ).toBeNull()
  })

  it('send-chat reads only channelKey and body, and stamps title from the hosted save', () => {
    const source = readFileSync(resolve(process.cwd(), 'supabase/functions/send-chat/index.ts'), 'utf8')
    expect(source).toContain("import { chatTitleFromSavePayload } from '../_shared/player_title.ts'")
    expect(source).toMatch(/type SendBody = \{\s*channelKey\?: unknown\s*body\?: unknown\s*\}/)
    expect(source).not.toMatch(/payload\.title/)
    expect(source).toContain('const title = await resolveChatTitle(admin, user.id)')
    expect(source).toContain('return chatTitleFromSavePayload(await loadSavePayload(admin, userId), rawDatabase)')
    expect(source).toContain('.select(\'payload\').eq(\'user_id\', userId)')
    expect(source).toContain('return json({ ...inserted, title }, 200)')
    const insertBlock = source.match(/\.insert\(\{([^}]+)\}\)/)?.[1] ?? ''
    expect(insertBlock).toContain('channel_key: channelKey')
    expect(insertBlock).toContain('title')
    expect(source).toContain(
      ".select('id, channel_key, user_id, username, body, created_at, guild_tag, rank_icon, guest, title')",
    )

    expect(REMOTE_CHAT_COLUMNS).toContain('title')

    const client = readFileSync(resolve(process.cwd(), 'src/game/multiplayer/chat.ts'), 'utf8')
    expect(client).toContain('body: { channelKey: chatChannelKey(channel), body }')
    expect(client).not.toMatch(/title\s*:/)
  })
})

describe('QA: chat title display and local toggles', () => {
  it('puts the title before the sender name, and the name alone when none', () => {
    expect(chatLineUsername(chatMessage({ title: 'The Undying' }))).toBe('The Undying Rowan')
    expect(chatLineUsername(chatMessage({}))).toBe('Rowan')
    expect(chatLineUsername(chatMessage({ title: '   ' }))).toBe('Rowan')
  })

  it('hides titles only in this viewer; the message still carries title', () => {
    const titled = chatMessage({ title: 'The Undying' })
    const hidden = chatLines([titled], 'usr_2', { showTitles: false })
    const shown = chatLines([titled], 'usr_2')
    expect(titled.title).toBe('The Undying')
    expect(hidden[0]?.username).toBe('Rowan')
    expect(shown[0]?.username).toBe('The Undying Rowan')
    expect(hidden[0]?.body).toBe(titled.body)
  })

  it('show-titles and timestamps keys default on, and channel keys cover every tab', () => {
    expect(CHAT_SHOW_TITLES_STORAGE_KEY).toBe('idle-kingdoms.client.show-chat-titles')
    expect(CHAT_SHOW_TIMESTAMPS_STORAGE_KEY).toBe('idle-kingdoms.client.show-chat-timestamps')
    expect(localStorage.getItem(CHAT_SHOW_TITLES_STORAGE_KEY)).toBeNull()
    expect(localStorage.getItem(CHAT_SHOW_TIMESTAMPS_STORAGE_KEY)).toBeNull()

    expect(CHAT_TABS).toEqual(['global', 'local', 'guild', 'guest', 'dm'])
    expect(CHAT_TABS.map(chatNotifyStorageKey)).toEqual([
      'idle-kingdoms.client.chat-notify:global',
      'idle-kingdoms.client.chat-notify:local',
      'idle-kingdoms.client.chat-notify:guild',
      'idle-kingdoms.client.chat-notify:guest',
      'idle-kingdoms.client.chat-notify:dm',
    ])

    const tabs = chatTabs({
      selected: 'global',
      citadelHub: false,
      hasGuild: true,
      hasGuest: true,
      unreadDms: 0,
    })
    expect(tabs.map((tab) => tab.label)).toEqual(['Global', 'Local', 'Guild', 'Guest', 'Private'])

    const stamp = formatChatTimestamp('2026-01-01T12:00:00.000Z', new Date('2026-01-01T18:00:00.000Z'))
    expect(stamp.length).toBeGreaterThan(0)
  })
})
