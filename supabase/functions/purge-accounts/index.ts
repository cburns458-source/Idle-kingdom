import { createClient } from 'npm:@supabase/supabase-js@2'
import { patchDiscordWebhookMessage } from '../_shared/discord.ts'
import { handlePurgeAccounts, type DuePurge, type FeedbackDiscordRef, type PurgeDeps } from './handler.ts'

function connect(url: string, key: string, options?: Parameters<typeof createClient>[2]) {
  return createClient(url, key, options)
}

type Client = ReturnType<typeof connect>

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

function authorised(req: Request, serviceKey: string, cronSecret: string): boolean {
  const header = req.headers.get('Authorization') ?? ''
  const token = header.startsWith('Bearer ') ? header.slice(7) : ''
  const purge = req.headers.get('x-purge-secret') ?? ''
  if (cronSecret && (token === cronSecret || purge === cronSecret)) return true
  return Boolean(serviceKey) && token === serviceKey
}

function liveStore(admin: Client) {
  return {
    async listDue(limit: number): Promise<DuePurge[]> {
      const { data, error } = await admin.rpc('account_list_due_purges', { p_limit: limit })
      if (error || !Array.isArray(data)) return []
      return data.map((row) => {
        const item = row as Record<string, unknown>
        return {
          request_id: String(item.request_id ?? ''),
          user_id: String(item.user_id ?? ''),
          status: String(item.status ?? ''),
          data_purged: item.data_purged === true,
        }
      })
    },
    async purgeData(userId: string) {
      const { data, error } = await admin.rpc('account_purge_data', { p_user: userId })
      if (error) return { ok: false, feedback: [] as FeedbackDiscordRef[] }
      const row = (data ?? {}) as Record<string, unknown>
      const raw = Array.isArray(row.feedback) ? row.feedback : []
      return {
        ok: row.ok !== false,
        feedback: raw.map((item) => {
          const ref = item as Record<string, unknown>
          return {
            id: String(ref.id ?? ''),
            discord_message_id: typeof ref.discord_message_id === 'string' ? ref.discord_message_id : null,
            discord_thread_id: typeof ref.discord_thread_id === 'string' ? ref.discord_thread_id : null,
          }
        }),
      }
    },
    async deleteAuthUser(userId: string) {
      const { error } = await admin.auth.admin.deleteUser(userId)
      if (!error) return { ok: true }
      if (/not (found|exist)|user not found/i.test(error.message)) {
        return { ok: true, alreadyGone: true }
      }
      return { ok: false, error: error.message }
    },
    async markPurged(requestId: string) {
      await admin.rpc('account_mark_purged', { p_request: requestId })
    },
    async dropExpiredReports() {
      const { data } = await admin.rpc('account_drop_expired_reports')
      return typeof data === 'number' ? data : 0
    },
    async purgeHalfMadeGuilds() {
      const { data } = await admin.rpc('account_purge_half_made_guilds')
      return typeof data === 'number' ? data : 0
    },
  }
}

function liveDeps(_req: Request): PurgeDeps | Response {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Function is missing Supabase secrets.' }, 500)
  }
  const admin = connect(supabaseUrl, serviceKey)
  const cronSecret = Deno.env.get('PURGE_CRON_SECRET') ?? ''
  return {
    authorized: (incoming) => authorised(incoming, serviceKey, cronSecret),
    store: liveStore(admin),
    webhookUrl: Deno.env.get('FEEDBACK_DISCORD_WEBHOOK_URL') ?? '',
    patchDiscord: (url, messageId, payload, threadId) =>
      patchDiscordWebhookMessage(url, messageId, payload, threadId),
  }
}

Deno.serve(async (req) => {
  const deps = liveDeps(req)
  if (deps instanceof Response) return deps
  try {
    return await handlePurgeAccounts(req, deps)
  } catch {
    return json({ error: 'That purge could not be completed.' }, 500)
  }
})
