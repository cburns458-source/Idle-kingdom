import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1'
import {
  buildForumWebhookPayload,
  escapeDiscordText,
  parseTagIds,
  postDiscordWebhook,
  redactSecret,
  threadNameFor,
} from '../_shared/discord.ts'
import { parseFeedbackBody, sha256Hex, shortPlayerId } from '../_shared/feedback.ts'
import {
  handleSubmitFeedback,
  type FeedbackDeps,
  type FeedbackRow,
  type FeedbackStore,
} from './handler.ts'

const WEBHOOK = 'https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN'
const USER = { id: '11111111-1111-4111-8111-111111111111', user_metadata: { username: 'Hero' } }
const RIVAL = { userId: '22222222-2222-4222-8222-222222222222', username: 'Rival' }

function validBody(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    kind: 'bug',
    title: 'Combat stun lock',
    body: 'The goblin stun never ends after the second hit.',
    context: { build: 'abc1234', platform: 'web', gameArea: 'LOC-0001' },
    ...over,
  }
}

function request(body: unknown, method = 'POST'): Request {
  return new Request('http://localhost/submit-feedback', {
    method,
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer test-token' },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  })
}

class MemoryStore implements FeedbackStore {
  rows: FeedbackRow[] = []
  cooldowns = new Map<string, number>()
  reports: Array<{ reporterId: string; targetUserId: string; reason: string }> = []
  players = new Map<string, { userId: string; username: string }>([
    [RIVAL.username.toLowerCase(), RIVAL],
    [RIVAL.userId, RIVAL],
  ])
  usernames = new Map<string, string>([[USER.id, 'Hero']])

  async getCooldownMs(userId: string) {
    return this.cooldowns.get(userId) ?? null
  }
  async setCooldown(userId: string, atMs: number) {
    this.cooldowns.set(userId, atMs)
  }
  async listUserSince(userId: string, sinceMs: number) {
    return this.rows.filter((row) => row.user_id === userId && Date.parse(row.created_at) > sinceMs)
  }
  async findDuplicate(userId: string, bodyHash: string, sinceMs: number) {
    return this.rows.find(
      (row) => row.user_id === userId && row.body_hash === bodyHash && Date.parse(row.created_at) > sinceMs,
    )?.id ?? null
  }
  async countPostedSince(sinceMs: number) {
    return this.rows.filter((row) => row.discord_status === 'posted' && Date.parse(row.created_at) > sinceMs).length
  }
  async insert(row: Omit<FeedbackRow, 'id' | 'created_at'> & { created_at?: string }) {
    const stored: FeedbackRow = {
      ...row,
      id: `fb_${this.rows.length + 1}`,
      created_at: row.created_at ?? new Date().toISOString(),
    }
    this.rows.push(stored)
    return stored
  }
  async updateDiscord(id: string, patch: Partial<FeedbackRow>) {
    const at = this.rows.findIndex((row) => row.id === id)
    if (at >= 0) this.rows[at] = { ...this.rows[at], ...patch }
  }
  async listRetryable() {
    return this.rows.filter(
      (row) => (row.discord_status === 'pending' || row.discord_status === 'failed') && row.discord_attempts < 5,
    )
  }
  async resolveUsername(userId: string) {
    return this.usernames.get(userId) ?? 'Adventurer'
  }
  async lookupPlayer(usernameOrId: string) {
    return this.players.get(usernameOrId.toLowerCase()) ?? this.players.get(usernameOrId) ?? null
  }
  async insertChatReport(reporterId: string, targetUserId: string, reason: string) {
    this.reports.push({ reporterId, targetUserId, reason })
    return { ok: true as const }
  }
}

function deps(over: {
  store?: MemoryStore
  user?: { id: string; user_metadata?: Record<string, unknown> } | null
  webhookUrl?: string
  tagIdsJson?: string
  nowMs?: number
  frozen?: boolean
  discord?: Array<{ status: number; retryAfterMs?: number; messageId?: string; threadId?: string; error?: string }>
}): { deps: FeedbackDeps; store: MemoryStore; posts: unknown[] } {
  const store = over.store ?? new MemoryStore()
  const queue = [...(over.discord ?? [{ status: 200, messageId: 'm1', threadId: 't1' }])]
  const posts: unknown[] = []
  const signedIn = over.user === undefined ? USER : over.user
  return {
    store,
    posts,
    deps: {
      getUser: async () => signedIn,
      store,
      env: {
        webhookUrl: over.webhookUrl ?? WEBHOOK,
        tagIdsJson: over.tagIdsJson ?? '{"bug":"11","idea":"22","report":"33"}',
      },
      nowMs: () => over.nowMs ?? Date.parse('2026-10-16T12:00:00.000Z'),
      postDiscord: async (_url, payload) => {
        posts.push(payload)
        const next = queue.shift() ?? { status: 200, messageId: 'm1', threadId: 't1' }
        if (next.status >= 200 && next.status < 300) {
          return { ok: true, status: next.status, messageId: next.messageId ?? 'm1', threadId: next.threadId ?? 't1' }
        }
        return {
          ok: false,
          status: next.status,
          retryAfterMs: next.retryAfterMs,
          error: next.error ?? `Discord returned ${next.status}.`,
        }
      },
      sleep: async () => {},
      accountFrozen: async () => over.frozen === true,
    },
  }
}

async function read(response: Response): Promise<{ status: number; body: Record<string, unknown> }> {
  return { status: response.status, body: (await response.json()) as Record<string, unknown> }
}

Deno.test('frozen accounts cannot send feedback', async () => {
  const wired = deps({ frozen: true })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 403)
  assertEquals(result.body.error, 'This account is scheduled for deletion.')
  assertEquals(wired.store.rows.length, 0)
})

Deno.test('anon gets 401', async () => {
  const wired = deps({ user: null })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 401)
  assertEquals(result.body.error, 'Sign in to send feedback.')
  assertEquals(wired.store.rows.length, 0)
})

Deno.test('cooldown returns 429 with retryAfterSeconds', async () => {
  const store = new MemoryStore()
  const now = Date.parse('2026-10-16T12:00:00.000Z')
  store.cooldowns.set(USER.id, now - 10_000)
  const wired = deps({ store, nowMs: now })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 429)
  assertEquals(result.body.code, 'cooldown')
  assertEquals(result.body.retryAfterSeconds, 50)
  assertFalse(JSON.stringify(result.body).includes('webhooks'))
})

Deno.test('daily cap returns 429', async () => {
  const store = new MemoryStore()
  const now = Date.parse('2026-10-16T12:00:00.000Z')
  for (let i = 0; i < 5; i++) {
    store.rows.push({
      id: `old_${i}`,
      user_id: USER.id,
      username: 'Hero',
      kind: 'bug',
      category: 'bug',
      title: 'Older report title',
      body: 'Older report body that is long enough.',
      context: {},
      body_hash: `h${i}`,
      discord_status: 'posted',
      discord_message_id: 'm',
      discord_thread_id: 't',
      discord_attempts: 1,
      discord_error: null,
      created_at: new Date(now - 60_000).toISOString(),
    })
  }
  const wired = deps({ store, nowMs: now })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 429)
  assertEquals(result.body.code, 'daily_cap')
  assert(typeof result.body.retryAfterSeconds === 'number')
})

Deno.test('duplicate body_hash returns the original id', async () => {
  const wired = deps({})
  const first = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(first.status, 200)
  wired.store.cooldowns.clear()
  const second = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(second.status, 200)
  assertEquals(second.body.id, first.body.id)
  assertEquals(wired.store.rows.length, 1)
  assertEquals(wired.posts.length, 1)
})

Deno.test('rejects short title, short body, and unknown kind', async () => {
  const wired = deps({})
  assertEquals((await read(await handleSubmitFeedback(request(validBody({ title: 'Hey' })), wired.deps))).status, 400)
  assertEquals((await read(await handleSubmitFeedback(request(validBody({ body: 'Too short' })), wired.deps))).status, 400)
  assertEquals((await read(await handleSubmitFeedback(request(validBody({ kind: 'exploit' })), wired.deps))).status, 400)
})

Deno.test('escapes markdown and neutralizes mentions', () => {
  const escaped = escapeDiscordText('Hello @everyone <@123> **bold** and https://evil.example/#invite')
  assertFalse(escaped.includes('@everyone'))
  assert(escaped.includes('@\u200beveryone'))
  assert(escaped.includes('<@\u200b123') || escaped.includes('\\<@\u200b123'))
  assert(escaped.includes('\\*\\*bold\\*\\*'))
  assert(escaped.includes(':\u200b//'))
  assert(escaped.includes('#\u200binvite'))
  const payload = buildForumWebhookPayload(
    {
      kind: 'bug',
      title: '@here leak',
      body: 'Ping <@&1> and **admin**',
      username: 'Hero',
      shortPlayerId: '11111111',
      build: 'dev',
      platform: 'web',
      submittedAt: '2026-10-16T12:00:00.000Z',
      gameArea: 'LOC-0001',
      rowId: 'fb_1',
    },
    parseTagIds('{"bug":"11","idea":"22","report":"33"}'),
  )
  assertEquals((payload.allowed_mentions as { parse: string[] }).parse, [])
  assertEquals(payload.applied_tags, ['11'])
  assertEquals(payload.thread_name, '[Bug] @here leak')
  const embed = (payload.embeds as Array<{ description: string; color: number }>)[0]
  assertEquals(embed.color, 0xc0392b)
  assertFalse(embed.description.includes('@here'))
  assert(threadNameFor('suggestion', 'x'.repeat(200)).length <= 100)

  const tags = parseTagIds('{"bug":"11","idea":"22","report":"33"}')
  const idea = buildForumWebhookPayload({ ...baseEmbed(), kind: 'suggestion', title: 'A better loop' }, tags)
  assertEquals(idea.applied_tags, ['22'])
  const report = buildForumWebhookPayload({ ...baseEmbed(), kind: 'player', title: 'Spam in global' }, tags)
  assertEquals(report.applied_tags, ['33'])
  const untagged = buildForumWebhookPayload(baseEmbed(), parseTagIds(''))
  assertEquals(untagged.applied_tags, undefined)
})

function baseEmbed() {
  return {
    kind: 'bug' as const,
    title: '@here leak',
    body: 'Ping <@&1> and **admin**',
    username: 'Hero',
    shortPlayerId: '11111111',
    build: 'dev',
    platform: 'web',
    submittedAt: '2026-10-16T12:00:00.000Z',
    gameArea: 'LOC-0001',
    rowId: 'fb_1',
  }
}

Deno.test('Discord failure still saves the row and never returns the webhook', async () => {
  const wired = deps({
    discord: [
      { status: 500, error: `upstream ${WEBHOOK}` },
      { status: 500, error: `upstream ${WEBHOOK}` },
    ],
  })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 200)
  assertEquals(typeof result.body.id, 'string')
  assertEquals(wired.store.rows.length, 1)
  assertEquals(wired.store.rows[0].discord_status, 'failed')
  assertFalse(JSON.stringify(result.body).includes('webhooks'))
  assertFalse(JSON.stringify(result.body).includes(WEBHOOK))
  assertFalse((wired.store.rows[0].discord_error ?? '').includes('webhooks'))
})

Deno.test('successful post stores message and thread ids and retries a failed row later', async () => {
  const store = new MemoryStore()
  store.rows.push({
    id: 'old_fail',
    user_id: USER.id,
    username: 'Hero',
    kind: 'suggestion',
    category: 'suggestion',
    title: 'Older leftover title',
    body: 'Older leftover body that is long enough.',
    context: { platform: 'web' },
    body_hash: 'leftover',
    discord_status: 'failed',
    discord_message_id: null,
    discord_thread_id: null,
    discord_attempts: 1,
    discord_error: 'Discord returned 500.',
    created_at: '2026-10-16T11:00:00.000Z',
  })
  const wired = deps({
    store,
    discord: [
      { status: 200, messageId: 'm-new', threadId: 't-new' },
      { status: 200, messageId: 'm-old', threadId: 't-old' },
    ],
  })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 200)
  assertEquals(store.rows.find((row) => row.id === result.body.id)?.discord_status, 'posted')
  assertEquals(store.rows.find((row) => row.id === 'old_fail')?.discord_status, 'posted')
  assertEquals(store.rows.find((row) => row.id === 'old_fail')?.discord_thread_id, 't-old')
})

Deno.test('missing tag ids still posts without applied_tags', async () => {
  const wired = deps({ tagIdsJson: '' })
  const result = await read(await handleSubmitFeedback(request(validBody()), wired.deps))
  assertEquals(result.status, 200)
  const payload = wired.posts[0] as Record<string, unknown>
  assertEquals(payload.applied_tags, undefined)
  assertEquals(typeof payload.thread_name, 'string')
})

Deno.test('player report also writes chat_reports', async () => {
  const wired = deps({})
  const result = await read(
    await handleSubmitFeedback(
      request(
        validBody({
          kind: 'player',
          title: 'Spam in global',
          body: 'This player is advertising gold sales in chat.',
          targetUsername: 'Rival',
          reportReason: 'Spam',
        }),
      ),
      wired.deps,
    ),
  )
  assertEquals(result.status, 200)
  assertEquals(wired.store.reports.length, 1)
  assertEquals(wired.store.reports[0].targetUserId, RIVAL.userId)
  assertEquals(wired.store.rows[0].kind, 'player')
})

Deno.test('redactSecret and parseFeedbackBody reject secrets and bad types', () => {
  assertEquals(redactSecret(`fail ${WEBHOOK}`).includes('webhooks'), false)
  assertEquals('error' in parseFeedbackBody({ kind: 'bug', title: 'abc', body: 'short' }), true)
  assertEquals(shortPlayerId(USER.id), '11111111')
})

Deno.test('postDiscordWebhook does not echo the webhook URL on failure', async () => {
  const result = await postDiscordWebhook(WEBHOOK, { content: 'x' }, async () => {
    return new Response(JSON.stringify({ message: 'nope' }), { status: 500 })
  })
  assertEquals(result.ok, false)
  assertFalse((result.error ?? '').includes('webhooks'))
})

Deno.test('sha256 is stable for the same input', async () => {
  assertEquals(await sha256Hex('bug\nCombat stun lock\nbody'), await sha256Hex('bug\nCombat stun lock\nbody'))
})
