import { anonymisedFeedbackWebhookPayload, patchDiscordWebhookMessage } from '../_shared/discord.ts'

export type DuePurge = {
  request_id: string
  user_id: string
  status: string
  data_purged: boolean
}

export type FeedbackDiscordRef = {
  id: string
  discord_message_id: string | null
  discord_thread_id: string | null
}

export type PurgeStore = {
  listDue: (limit: number) => Promise<DuePurge[]>
  purgeData: (userId: string) => Promise<{ ok: boolean; feedback: FeedbackDiscordRef[] }>
  deleteAuthUser: (userId: string) => Promise<{ ok: boolean; alreadyGone?: boolean; error?: string }>
  markPurged: (requestId: string) => Promise<void>
  dropExpiredReports: () => Promise<number>
  purgeHalfMadeGuilds: () => Promise<number>
}

export type PurgeDeps = {
  authorized: (req: Request) => boolean
  store: PurgeStore
  webhookUrl: string
  patchDiscord?: (
    url: string,
    messageId: string,
    payload: unknown,
    threadId?: string | null,
  ) => Promise<{ ok: boolean }>
}

function cors(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-purge-secret',
  }
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json' },
  })
}

export async function handlePurgeAccounts(req: Request, deps: PurgeDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)
  if (!deps.authorized(req)) return json({ error: 'Not authorised.' }, 401)

  const dropped = await deps.store.dropExpiredReports()
  const halfMade = await deps.store.purgeHalfMadeGuilds()
  const due = await deps.store.listDue(20)
  let purged = 0
  let skipped = 0
  const patch = deps.patchDiscord ?? patchDiscordWebhookMessage

  for (const row of due) {
    if (!row.user_id) {
      skipped += 1
      continue
    }
    const data = row.data_purged
      ? { ok: true, feedback: [] as FeedbackDiscordRef[] }
      : await deps.store.purgeData(row.user_id)
    if (!data.ok) {
      skipped += 1
      continue
    }
    if (deps.webhookUrl) {
      for (const item of data.feedback) {
        if (!item.discord_message_id) continue
        try {
          const patched = await patch(
            deps.webhookUrl,
            item.discord_message_id,
            anonymisedFeedbackWebhookPayload(),
            item.discord_thread_id,
          )
          if (!patched.ok) {
            console.error('purge-accounts: Discord anonymise failed', {
              feedbackId: item.id,
              status: 'status' in patched ? patched.status : undefined,
            })
          }
        } catch {
          console.error('purge-accounts: Discord anonymise failed', { feedbackId: item.id })
        }
      }
    }
    const deleted = await deps.store.deleteAuthUser(row.user_id)
    if (!deleted.ok && !deleted.alreadyGone) {
      skipped += 1
      continue
    }
    await deps.store.markPurged(row.request_id)
    purged += 1
  }

  return json({ ok: true, purged, skipped, reports_dropped: dropped, half_made_guilds: halfMade }, 200)
}
