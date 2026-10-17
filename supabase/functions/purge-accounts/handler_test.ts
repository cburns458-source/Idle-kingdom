import { assertEquals } from 'jsr:@std/assert@1'
import { handlePurgeAccounts, type DuePurge, type FeedbackDiscordRef, type PurgeStore } from './handler.ts'
import { shouldPurgeHalfMadeGuild, type HalfMadeGuildProbe } from './half_made_guilds.ts'

class MemoryPurge implements PurgeStore {
  due: DuePurge[] = []
  purgedUsers: string[] = []
  deletedUsers: string[] = []
  marked: string[] = []
  droppedReports = 0
  halfMadeGuilds = 0
  purgeHalfMadeCalls = 0
  authGone = new Set<string>()
  failDelete = new Set<string>()
  patches: Array<{ messageId: string; threadId?: string | null }> = []

  async listDue() {
    return this.due
  }
  async purgeData(userId: string) {
    this.purgedUsers.push(userId)
    const feedback: FeedbackDiscordRef[] = [
      { id: 'fb1', discord_message_id: 'msg-1', discord_thread_id: 'thread-1' },
    ]
    return { ok: true, feedback }
  }
  async deleteAuthUser(userId: string) {
    if (this.failDelete.has(userId)) return { ok: false, error: 'busy' }
    if (this.authGone.has(userId)) return { ok: true, alreadyGone: true }
    this.deletedUsers.push(userId)
    return { ok: true }
  }
  async markPurged(requestId: string) {
    this.marked.push(requestId)
  }
  async dropExpiredReports() {
    return this.droppedReports
  }
  async purgeHalfMadeGuilds() {
    this.purgeHalfMadeCalls += 1
    return this.halfMadeGuilds
  }
}

function request(): Request {
  return new Request('http://localhost/purge-accounts', {
    method: 'POST',
    headers: { Authorization: 'Bearer cron-secret' },
  })
}

Deno.test('purge is idempotent and still deletes auth when data was already cleared', async () => {
  const store = new MemoryPurge()
  store.due = [
    { request_id: 'r1', user_id: 'u1', status: 'pending', data_purged: false },
    { request_id: 'r2', user_id: 'u2', status: 'data_purged', data_purged: true },
  ]
  store.authGone.add('u2')
  const patches: string[] = []
  const response = await handlePurgeAccounts(request(), {
    authorized: () => true,
    store,
    webhookUrl: 'https://discord.com/api/webhooks/1/token',
    patchDiscord: async (_url, messageId) => {
      patches.push(messageId)
      return { ok: true }
    },
  })
  assertEquals(response.status, 200)
  const body = (await response.json()) as Record<string, unknown>
  assertEquals(body.purged, 2)
  assertEquals(store.purgedUsers, ['u1'])
  assertEquals(store.deletedUsers, ['u1'])
  assertEquals(store.marked, ['r1', 'r2'])
  assertEquals(patches, ['msg-1'])
})

Deno.test('a Discord patch failure does not block the purge', async () => {
  const store = new MemoryPurge()
  store.due = [{ request_id: 'r1', user_id: 'u1', status: 'pending', data_purged: false }]
  const response = await handlePurgeAccounts(request(), {
    authorized: () => true,
    store,
    webhookUrl: 'https://discord.com/api/webhooks/1/token',
    patchDiscord: async () => ({ ok: false }),
  })
  assertEquals(response.status, 200)
  const body = (await response.json()) as Record<string, unknown>
  assertEquals(body.purged, 1)
  assertEquals(store.deletedUsers, ['u1'])
  assertEquals(store.marked, ['r1'])
})

Deno.test('a failed auth delete leaves the row for the next run', async () => {
  const store = new MemoryPurge()
  store.due = [{ request_id: 'r1', user_id: 'u1', status: 'pending', data_purged: false }]
  store.failDelete.add('u1')
  const response = await handlePurgeAccounts(request(), {
    authorized: () => true,
    store,
    webhookUrl: '',
  })
  assertEquals(response.status, 200)
  const body = (await response.json()) as Record<string, unknown>
  assertEquals(body.purged, 0)
  assertEquals(body.skipped, 1)
  assertEquals(store.marked, [])
  assertEquals(store.purgedUsers, ['u1'])
})

Deno.test('unauthorised callers are refused', async () => {
  const store = new MemoryPurge()
  const response = await handlePurgeAccounts(request(), {
    authorized: () => false,
    store,
    webhookUrl: '',
  })
  assertEquals(response.status, 401)
})

const NOW = new Date('2026-10-17T12:00:00.000Z')

function probe(partial: Partial<HalfMadeGuildProbe> = {}): HalfMadeGuildProbe {
  return {
    id: 'g1',
    createdAt: new Date('2026-10-17T10:00:00.000Z'),
    memberCount: 0,
    hadLeaderRow: false,
    hasHall: false,
    hasAchievements: false,
    ...partial,
  }
}

Deno.test('a half-made guild gets purged', () => {
  assertEquals(shouldPurgeHalfMadeGuild(probe(), NOW), true)
})

Deno.test('a real guild with no members is kept', () => {
  assertEquals(shouldPurgeHalfMadeGuild(probe({ hasHall: true }), NOW), false)
  assertEquals(shouldPurgeHalfMadeGuild(probe({ hasAchievements: true }), NOW), false)
})

Deno.test('a real guild with no hall but with members or a leader history is kept', () => {
  assertEquals(shouldPurgeHalfMadeGuild(probe({ memberCount: 1 }), NOW), false)
  assertEquals(shouldPurgeHalfMadeGuild(probe({ hadLeaderRow: true }), NOW), false)
})

Deno.test('a guild under an hour old is kept', () => {
  assertEquals(
    shouldPurgeHalfMadeGuild(probe({ createdAt: new Date('2026-10-17T11:15:00.000Z') }), NOW),
    false,
  )
})

Deno.test('the hourly purge job deletes half-made guilds', async () => {
  const store = new MemoryPurge()
  store.halfMadeGuilds = 2
  const response = await handlePurgeAccounts(request(), {
    authorized: () => true,
    store,
    webhookUrl: '',
  })
  assertEquals(response.status, 200)
  const body = (await response.json()) as Record<string, unknown>
  assertEquals(store.purgeHalfMadeCalls, 1)
  assertEquals(body.half_made_guilds, 2)
})
