import {
  buildForumWebhookPayload,
  isDiscordWebhookUrl,
  parseTagIds,
  redactSecret,
  type DiscordPostResult,
  type FeedbackKind,
} from '../_shared/discord.ts'
import { ACCOUNT_FROZEN } from '../_shared/deletion.ts'
import {
  FEEDBACK_COOLDOWN_MS,
  FEEDBACK_DAILY_CAP,
  FEEDBACK_DAILY_WINDOW_MS,
  FEEDBACK_GLOBAL_PER_MINUTE,
  feedbackHashInput,
  parseFeedbackBody,
  retryAfterSeconds,
  sha256Hex,
  shortPlayerId,
  usernameFromPublic,
  type ParsedFeedback,
} from '../_shared/feedback.ts'

export type FeedbackUser = {
  id: string
  user_metadata?: Record<string, unknown>
}

export type FeedbackRow = {
  id: string
  user_id: string
  username: string
  kind: FeedbackKind
  category: string
  title: string
  body: string
  context: Record<string, unknown>
  body_hash: string
  discord_status: 'pending' | 'posted' | 'failed'
  discord_message_id: string | null
  discord_thread_id: string | null
  discord_attempts: number
  discord_error: string | null
  created_at: string
}

export type FeedbackStore = {
  getCooldownMs: (userId: string) => Promise<number | null>
  setCooldown: (userId: string, atMs: number) => Promise<void>
  listUserSince: (userId: string, sinceMs: number) => Promise<FeedbackRow[]>
  findDuplicate: (userId: string, bodyHash: string, sinceMs: number) => Promise<string | null>
  countPostedSince: (sinceMs: number) => Promise<number>
  insert: (row: Omit<FeedbackRow, 'id' | 'created_at'> & { created_at?: string }) => Promise<FeedbackRow>
  updateDiscord: (
    id: string,
    patch: Partial<
      Pick<
        FeedbackRow,
        'discord_status' | 'discord_message_id' | 'discord_thread_id' | 'discord_attempts' | 'discord_error'
      >
    >,
  ) => Promise<void>
  listRetryable: () => Promise<FeedbackRow[]>
  resolveUsername: (userId: string, metadata?: Record<string, unknown>) => Promise<string>
  lookupPlayer: (usernameOrId: string) => Promise<{ userId: string; username: string } | null>
  insertChatReport: (
    reporterId: string,
    targetUserId: string,
    reason: string,
  ) => Promise<{ ok: boolean; reason?: string }>
}

export type FeedbackEnv = {
  webhookUrl: string
  tagIdsJson: string
}

export type FeedbackDeps = {
  getUser: (req: Request) => Promise<FeedbackUser | null>
  store: FeedbackStore
  env: FeedbackEnv
  nowMs: () => number
  postDiscord: (url: string, payload: unknown) => Promise<DiscordPostResult>
  sleep: (ms: number) => Promise<void>
  accountFrozen: (userId: string) => Promise<boolean>
}

function cors(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

export function json(body: Record<string, unknown>, status: number, extra?: HeadersInit): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json', ...extra },
  })
}

function containsSecret(value: string, webhookUrl: string): boolean {
  if (!value) return false
  if (webhookUrl && value.includes(webhookUrl)) return true
  return /\/api\/webhooks\/\d+\//.test(value)
}

function safeError(message: string, webhookUrl: string): string {
  const redacted = redactSecret(message)
  return containsSecret(redacted, webhookUrl) ? 'That report could not be sent.' : redacted
}

function categoryFor(parsed: ParsedFeedback): string {
  if (parsed.kind === 'player') {
    const reason = parsed.reportReason.trim()
    return reason ? reason.slice(0, 40) : 'player'
  }
  return parsed.kind
}

function reportReasonFor(parsed: ParsedFeedback): string {
  const reason = parsed.reportReason.trim()
  if (reason === 'Spam' || reason === 'Harassment' || reason === 'Inappropriate name' || reason === 'Other') {
    return reason
  }
  if (reason.startsWith('Other:') && reason.length <= 280) return reason
  if (parsed.body) {
    const note = `Other: ${parsed.body}`
    return note.length <= 280 ? note : note.slice(0, 280)
  }
  return 'Other'
}

function embedInput(row: FeedbackRow, submittedAt: string) {
  const context = row.context ?? {}
  return {
    kind: row.kind,
    title: row.title,
    body: row.body,
    username: row.username,
    shortPlayerId: shortPlayerId(row.user_id),
    build: typeof context.build === 'string' ? context.build : '—',
    platform: typeof context.platform === 'string' ? context.platform : '—',
    submittedAt,
    gameArea: typeof context.gameArea === 'string' ? context.gameArea : '—',
    rowId: row.id,
  }
}

async function deliverOnce(
  row: FeedbackRow,
  deps: FeedbackDeps,
  submittedAt: string,
): Promise<DiscordPostResult> {
  const payload = buildForumWebhookPayload(embedInput(row, submittedAt), parseTagIds(deps.env.tagIdsJson))
  let result = await deps.postDiscord(deps.env.webhookUrl, payload)
  const retryable = !result.ok && (result.status >= 500 || result.status === 429)
  if (retryable) {
    await deps.sleep(Math.min(result.retryAfterMs ?? 400, 5000))
    result = await deps.postDiscord(deps.env.webhookUrl, payload)
  }
  const attempts = (row.discord_attempts ?? 0) + (retryable ? 2 : 1)
  if (result.ok) {
    await deps.store.updateDiscord(row.id, {
      discord_status: 'posted',
      discord_message_id: result.messageId ?? null,
      discord_thread_id: result.threadId ?? null,
      discord_attempts: attempts,
      discord_error: null,
    })
  } else {
    await deps.store.updateDiscord(row.id, {
      discord_status: 'failed',
      discord_attempts: attempts,
      discord_error: safeError(result.error ?? 'Discord request failed.', deps.env.webhookUrl).slice(0, 300),
    })
  }
  return result
}

async function drainRetryable(deps: FeedbackDeps, remaining: number): Promise<void> {
  if (remaining <= 0 || !isDiscordWebhookUrl(deps.env.webhookUrl)) return
  const queued = await deps.store.listRetryable()
  let left = remaining
  for (const row of queued) {
    if (left <= 0) return
    const posted = await deliverOnce(row, deps, row.created_at)
    if (!posted.ok) return
    left -= 1
  }
}

export async function handleSubmitFeedback(req: Request, deps: FeedbackDeps): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors() })
  }
  if (req.method !== 'POST') {
    return json({ error: 'That report could not be sent.' }, 405)
  }

  const user = await deps.getUser(req)
  if (!user) {
    return json({ error: 'Sign in to send feedback.' }, 401)
  }
  if (await deps.accountFrozen(user.id)) {
    return json({ error: ACCOUNT_FROZEN }, 403)
  }

  let raw: unknown
  try {
    raw = await req.json()
  } catch {
    return json({ error: 'Details are too short.' }, 400)
  }

  const parsed = parseFeedbackBody(raw)
  if ('error' in parsed && !('kind' in parsed)) {
    return json({ error: parsed.error }, parsed.status)
  }
  const feedback = parsed as ParsedFeedback
  const nowMs = deps.nowMs()
  const webhookUrl = deps.env.webhookUrl

  if (feedback.kind === 'player') {
    const target = await deps.store.lookupPlayer(feedback.targetUsername)
    if (!target || target.userId === user.id) {
      return json(
        { error: target?.userId === user.id ? 'You cannot report yourself.' : 'That player was not found.' },
        400,
      )
    }
    const reported = await deps.store.insertChatReport(user.id, target.userId, reportReasonFor(feedback))
    if (!reported.ok) {
      return json({ error: reported.reason ?? 'Choose a reason.' }, 400)
    }
  }

  const last = await deps.store.getCooldownMs(user.id)
  if (last != null && nowMs - last < FEEDBACK_COOLDOWN_MS) {
    const retry = retryAfterSeconds(last + FEEDBACK_COOLDOWN_MS, nowMs)
    return json(
      { error: 'Slow down a moment before sending again.', retryAfterSeconds: retry, code: 'cooldown' },
      429,
      { 'Retry-After': String(retry) },
    )
  }

  const recent = await deps.store.listUserSince(user.id, nowMs - FEEDBACK_DAILY_WINDOW_MS)
  if (recent.length >= FEEDBACK_DAILY_CAP) {
    const oldest = recent
      .map((row) => Date.parse(row.created_at))
      .filter((ms) => Number.isFinite(ms))
      .sort((a, b) => a - b)[0]
    const retry = retryAfterSeconds((oldest ?? nowMs) + FEEDBACK_DAILY_WINDOW_MS, nowMs)
    return json(
      { error: 'You have sent enough reports today.', retryAfterSeconds: retry, code: 'daily_cap' },
      429,
      { 'Retry-After': String(retry) },
    )
  }

  const bodyHash = await sha256Hex(feedbackHashInput(feedback))
  const duplicate = await deps.store.findDuplicate(user.id, bodyHash, nowMs - FEEDBACK_DAILY_WINDOW_MS)
  if (duplicate) {
    return json({ id: duplicate }, 200)
  }

  const username = await deps.store.resolveUsername(user.id, user.user_metadata)
  const row = await deps.store.insert({
    user_id: user.id,
    username: usernameFromPublic(username) || 'Adventurer',
    kind: feedback.kind,
    category: categoryFor(feedback),
    title: feedback.title,
    body: feedback.body,
    context: feedback.context,
    body_hash: bodyHash,
    discord_status: 'pending',
    discord_message_id: null,
    discord_thread_id: null,
    discord_attempts: 0,
    discord_error: null,
  })

  await deps.store.setCooldown(user.id, nowMs)

  const postedLastMinute = await deps.store.countPostedSince(nowMs - 60_000)
  const remaining = FEEDBACK_GLOBAL_PER_MINUTE - postedLastMinute
  if (remaining <= 0) {
    return json({ id: row.id }, 200)
  }
  if (!isDiscordWebhookUrl(webhookUrl)) {
    await deps.store.updateDiscord(row.id, {
      discord_status: 'failed',
      discord_attempts: 1,
      discord_error: 'Discord webhook is not configured.',
    })
    return json({ id: row.id }, 200)
  }

  const delivered = await deliverOnce(row, deps, new Date(nowMs).toISOString())
  if (delivered.ok) {
    await drainRetryable(deps, remaining - 1)
  }

  const response = json({ id: row.id }, 200)
  const text = await response.clone().text()
  if (containsSecret(text, webhookUrl)) {
    return json({ id: row.id }, 200)
  }
  return response
}
