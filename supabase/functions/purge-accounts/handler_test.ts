import { assertEquals } from 'jsr:@std/assert@1'
import { handlePurgeAccounts, type DuePurge, type FeedbackDiscordRef, type PurgeStore } from './handler.ts'

class MemoryPurge implements PurgeStore {
  due: DuePurge[] = []
  purgedUsers: string[] = []
  deletedUsers: string[] = []
  marked: string[] = []
  droppedReports = 0
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
