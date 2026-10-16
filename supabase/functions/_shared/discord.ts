/** Discord webhook helpers for ADM-04 feedback. Never log a webhook URL. */

export const DISCORD_COLOR_BUG = 0xc0392b
export const DISCORD_COLOR_SUGGESTION = 0xd4af37
export const DISCORD_COLOR_OTHER = 0x7f8c8d

const ZERO_WIDTH = /\u200B|\u200C|\u200D|\uFEFF|\u2060/g
const MARKDOWN_SPECIAL = /([\\*_`~|>[\]()])/g

export type FeedbackKind = 'bug' | 'suggestion' | 'player'

export type DiscordTagMap = Partial<Record<'bug' | 'idea' | 'report', string>>

export type FeedbackEmbedInput = {
  kind: FeedbackKind
  title: string
  body: string
  username: string
  shortPlayerId: string
  build: string
  platform: string
  submittedAt: string
  gameArea: string
  rowId: string
}

export function stripZeroWidth(text: string): string {
  return text.replace(ZERO_WIDTH, '')
}

/** Escape markdown, break mentions and links, strip sneaky zero-width chars. */
export function escapeDiscordText(raw: string): string {
  let text = stripZeroWidth(String(raw ?? ''))
  text = text.replace(/@/g, '@\u200b').replace(/#/g, '#\u200b')
  text = text.replace(/:\/\//g, ':\u200b//')
  text = text.replace(MARKDOWN_SPECIAL, '\\$1')
  return text
}

export function kindLabel(kind: FeedbackKind): string {
  if (kind === 'bug') return 'Bug'
  if (kind === 'suggestion') return 'Suggestion'
  return 'Player'
}

export function embedColor(kind: FeedbackKind): number {
  if (kind === 'bug') return DISCORD_COLOR_BUG
  if (kind === 'suggestion') return DISCORD_COLOR_SUGGESTION
  return DISCORD_COLOR_OTHER
}

export function threadNameFor(kind: FeedbackKind, title: string): string {
  const name = `[${kindLabel(kind)}] ${stripZeroWidth(title).trim()}`
  return name.slice(0, 100)
}

export function parseTagIds(raw: string | undefined): DiscordTagMap {
  if (!raw || !raw.trim()) return {}
  try {
    const parsed = JSON.parse(raw) as unknown
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {}
    const out: DiscordTagMap = {}
    for (const key of ['bug', 'idea', 'report'] as const) {
      const value = (parsed as Record<string, unknown>)[key]
      if (typeof value === 'string' && /^\d+$/.test(value.trim())) {
        out[key] = value.trim()
      }
    }
    return out
  } catch {
    return {}
  }
}

export function tagKeyForKind(kind: FeedbackKind): keyof DiscordTagMap {
  if (kind === 'suggestion') return 'idea'
  if (kind === 'player') return 'report'
  return 'bug'
}

export function appliedTagsFor(tags: DiscordTagMap, kind: FeedbackKind): string[] {
  const id = tags[tagKeyForKind(kind)]
  return id ? [id] : []
}

export function buildForumWebhookPayload(
  input: FeedbackEmbedInput,
  tags: DiscordTagMap,
): Record<string, unknown> {
  const applied = appliedTagsFor(tags, input.kind)
  const payload: Record<string, unknown> = {
    thread_name: threadNameFor(input.kind, input.title),
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: escapeDiscordText(input.title).slice(0, 256),
        description: escapeDiscordText(input.body).slice(0, 4096),
        color: embedColor(input.kind),
        fields: [
          { name: 'Message', value: escapeDiscordText(input.body).slice(0, 1024), inline: false },
          { name: 'In-game name', value: escapeDiscordText(input.username).slice(0, 256) || '—', inline: true },
          { name: 'Player id', value: escapeDiscordText(input.shortPlayerId).slice(0, 64) || '—', inline: true },
          { name: 'Build', value: escapeDiscordText(input.build).slice(0, 64) || '—', inline: true },
          { name: 'Platform', value: escapeDiscordText(input.platform).slice(0, 32) || '—', inline: true },
          { name: 'UTC time', value: escapeDiscordText(input.submittedAt).slice(0, 64) || '—', inline: true },
          { name: 'Game area', value: escapeDiscordText(input.gameArea).slice(0, 64) || '—', inline: true },
          { name: 'Feedback id', value: escapeDiscordText(input.rowId).slice(0, 64) || '—', inline: false },
        ],
      },
    ],
  }
  if (applied.length > 0) payload.applied_tags = applied
  return payload
}

export function webhookUrlWithWait(url: string): string {
  try {
    const parsed = new URL(url)
    parsed.searchParams.set('wait', 'true')
    return parsed.toString()
  } catch {
    return ''
  }
}

export function isDiscordWebhookUrl(url: string): boolean {
  try {
    const parsed = new URL(url)
    return (
      (parsed.hostname === 'discord.com' || parsed.hostname === 'discordapp.com') &&
      parsed.pathname.startsWith('/api/webhooks/')
    )
  } catch {
    return false
  }
}

/** Strip anything that looks like a webhook path from an error we might store or return. */
export function redactSecret(text: string): string {
  return text
    .replace(/https?:\/\/(?:discord|discordapp)\.com\/api\/webhooks\/[^\s]+/gi, '[redacted]')
    .replace(/\/api\/webhooks\/\d+\/[A-Za-z0-9_-]+/gi, '[redacted]')
}

export type DiscordPostResult = {
  ok: boolean
  status: number
  messageId?: string
  threadId?: string
  retryAfterMs?: number
  error?: string
}

export type DiscordPoster = (url: string, payload: unknown) => Promise<DiscordPostResult>

function retryAfterMsFrom(headers: Headers, body: unknown): number {
  if (body && typeof body === 'object' && body !== null && 'retry_after' in body) {
    const value = (body as { retry_after?: unknown }).retry_after
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value > 20 ? value * 1000 : Math.round(value * 1000)
    }
  }
  const header = headers.get('Retry-After')
  if (header) {
    const seconds = Number(header)
    if (Number.isFinite(seconds) && seconds >= 0) return Math.round(seconds * 1000)
  }
  return 1000
}

export async function postDiscordWebhook(
  url: string,
  payload: unknown,
  fetchImpl: typeof fetch = fetch,
): Promise<DiscordPostResult> {
  const target = webhookUrlWithWait(url)
  if (!target || !isDiscordWebhookUrl(url)) {
    return { ok: false, status: 0, error: 'Discord webhook is not configured.' }
  }
  try {
    const response = await fetchImpl(target, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    let body: unknown = null
    try {
      body = await response.json()
    } catch {
      body = null
    }
    if (response.ok && body && typeof body === 'object') {
      const row = body as { id?: unknown; channel_id?: unknown }
      return {
        ok: true,
        status: response.status,
        messageId: typeof row.id === 'string' ? row.id : undefined,
        threadId: typeof row.channel_id === 'string' ? row.channel_id : undefined,
      }
    }
    return {
      ok: false,
      status: response.status,
      retryAfterMs: response.status === 429 ? retryAfterMsFrom(response.headers, body) : undefined,
      error: redactSecret(`Discord returned ${response.status}.`),
    }
  } catch (error) {
    return { ok: false, status: 0, error: redactSecret(error instanceof Error ? error.message : 'Discord request failed.') }
  }
}

export async function postDiscordWithRetry(
  url: string,
  payload: unknown,
  fetchImpl: typeof fetch = fetch,
  sleep: (ms: number) => Promise<void> = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
): Promise<DiscordPostResult> {
  const first = await postDiscordWebhook(url, payload, fetchImpl)
  if (first.ok) return first
  const retryable = first.status >= 500 || first.status === 429
  if (!retryable) return first
  const wait = Math.min(first.retryAfterMs ?? 400, 5000)
  await sleep(wait)
  return postDiscordWebhook(url, payload, fetchImpl)
}
