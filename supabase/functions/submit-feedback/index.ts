import { createClient } from 'npm:@supabase/supabase-js@2'
import { postDiscordWebhook } from '../_shared/discord.ts'
import { FEEDBACK_CHANNEL_KEY, isUuid, usernameFromPublic } from '../_shared/feedback.ts'
import {
  handleSubmitFeedback,
  type FeedbackDeps,
  type FeedbackRow,
  type FeedbackStore,
} from './handler.ts'

function connect(url: string, key: string, options?: Parameters<typeof createClient>[2]) {
  return createClient(url, key, options)
}

type Client = ReturnType<typeof connect>

function cors(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(), 'Content-Type': 'application/json' },
  })
}

function asFeedbackRow(raw: Record<string, unknown>): FeedbackRow {
  return {
    id: String(raw.id ?? ''),
    user_id: String(raw.user_id ?? ''),
    username: String(raw.username ?? 'Adventurer'),
    kind: (raw.kind === 'suggestion' || raw.kind === 'player' ? raw.kind : 'bug') as FeedbackRow['kind'],
    category: String(raw.category ?? 'bug'),
    title: String(raw.title ?? ''),
    body: String(raw.body ?? ''),
    context: raw.context && typeof raw.context === 'object' ? (raw.context as Record<string, unknown>) : {},
    body_hash: String(raw.body_hash ?? ''),
    discord_status:
      raw.discord_status === 'posted' || raw.discord_status === 'failed' ? raw.discord_status : 'pending',
    discord_message_id: typeof raw.discord_message_id === 'string' ? raw.discord_message_id : null,
    discord_thread_id: typeof raw.discord_thread_id === 'string' ? raw.discord_thread_id : null,
    discord_attempts: typeof raw.discord_attempts === 'number' ? raw.discord_attempts : 0,
    discord_error: typeof raw.discord_error === 'string' ? raw.discord_error : null,
    created_at: String(raw.created_at ?? new Date().toISOString()),
  }
}

function liveStore(admin: Client, asUser: Client): FeedbackStore {
  return {
    async getCooldownMs(userId) {
      const { data } = await admin
        .from('chat_cooldowns')
        .select('last_sent_at')
        .eq('user_id', userId)
        .eq('channel_key', FEEDBACK_CHANNEL_KEY)
        .maybeSingle()
      const last = typeof data?.last_sent_at === 'string' ? Date.parse(data.last_sent_at) : NaN
      return Number.isFinite(last) ? last : null
    },
    async setCooldown(userId, atMs) {
      await admin.from('chat_cooldowns').upsert({
        user_id: userId,
        channel_key: FEEDBACK_CHANNEL_KEY,
        last_sent_at: new Date(atMs).toISOString(),
      })
    },
    async listUserSince(userId, sinceMs) {
      const { data } = await admin
        .from('player_feedback')
        .select(
          'id, user_id, username, kind, category, title, body, context, body_hash, discord_status, discord_message_id, discord_thread_id, discord_attempts, discord_error, created_at',
        )
        .eq('user_id', userId)
        .gt('created_at', new Date(sinceMs).toISOString())
        .order('created_at', { ascending: true })
      return (data ?? []).map((row) => asFeedbackRow(row as Record<string, unknown>))
    },
    async findDuplicate(userId, bodyHash, sinceMs) {
      const { data } = await admin
        .from('player_feedback')
        .select('id')
        .eq('user_id', userId)
        .eq('body_hash', bodyHash)
        .gt('created_at', new Date(sinceMs).toISOString())
        .order('created_at', { ascending: true })
        .limit(1)
        .maybeSingle()
      return typeof data?.id === 'string' ? data.id : null
    },
    async countPostedSince(sinceMs) {
      const { count } = await admin
        .from('player_feedback')
        .select('id', { count: 'exact', head: true })
        .eq('discord_status', 'posted')
        .gt('created_at', new Date(sinceMs).toISOString())
      return count ?? 0
    },
    async insert(row) {
      const { data, error } = await admin
        .from('player_feedback')
        .insert({
          user_id: row.user_id,
          username: row.username,
          kind: row.kind,
          category: row.category,
          title: row.title,
          body: row.body,
          context: row.context,
          body_hash: row.body_hash,
          status: 'new',
          discord_status: row.discord_status,
          discord_attempts: row.discord_attempts,
        })
        .select(
          'id, user_id, username, kind, category, title, body, context, body_hash, discord_status, discord_message_id, discord_thread_id, discord_attempts, discord_error, created_at',
        )
        .single()
      if (error || !data) {
        throw new Error(error?.message ?? 'The report was not saved.')
      }
      return asFeedbackRow(data as Record<string, unknown>)
    },
    async updateDiscord(id, patch) {
      await admin.from('player_feedback').update(patch).eq('id', id)
    },
    async listRetryable() {
      const { data } = await admin
        .from('player_feedback')
        .select(
          'id, user_id, username, kind, category, title, body, context, body_hash, discord_status, discord_message_id, discord_thread_id, discord_attempts, discord_error, created_at',
        )
        .in('discord_status', ['pending', 'failed'])
        .lt('discord_attempts', 5)
        .order('created_at', { ascending: true })
        .limit(8)
      return (data ?? []).map((row) => asFeedbackRow(row as Record<string, unknown>))
    },
    async resolveUsername(userId, metadata) {
      const { data } = await admin.from('profiles').select('username').eq('user_id', userId).maybeSingle()
      const fromProfile = usernameFromPublic(data?.username)
      if (fromProfile) return fromProfile
      const fromMeta = usernameFromPublic(metadata?.username)
      return fromMeta || 'Adventurer'
    },
    async lookupPlayer(usernameOrId) {
      if (isUuid(usernameOrId)) {
        const { data } = await admin
          .from('profiles')
          .select('user_id, username')
          .eq('user_id', usernameOrId)
          .maybeSingle()
        if (!data?.user_id) return null
        return { userId: String(data.user_id), username: usernameFromPublic(data.username) || 'Adventurer' }
      }
      const { data } = await admin
        .from('profiles')
        .select('user_id, username')
        .ilike('username', usernameOrId)
        .limit(1)
        .maybeSingle()
      if (!data?.user_id) return null
      return { userId: String(data.user_id), username: usernameFromPublic(data.username) || 'Adventurer' }
    },
    async insertChatReport(reporterId, targetUserId, reason) {
      const { data, error } = await asUser.rpc('report_player', {
        p_target: targetUserId,
        p_reason: reason,
      })
      if (error) {
        if (/schema cache|does not exist/i.test(error.message)) {
          await admin.from('chat_reports').insert({
            reporter_id: reporterId,
            target_user_id: targetUserId,
            reason,
          })
          return { ok: true }
        }
        return { ok: false, reason: 'Could not send that report.' }
      }
      if (data && typeof data === 'object' && (data as { ok?: unknown }).ok === false) {
        const refusal = (data as { reason?: unknown }).reason
        return { ok: false, reason: typeof refusal === 'string' ? refusal : 'Choose a reason.' }
      }
      return { ok: true }
    },
  }
}

function liveDeps(req: Request): FeedbackDeps | Response {
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Function is missing Supabase secrets.' }, 500)
  }
  const authHeader = req.headers.get('Authorization') ?? ''
  const asUser = connect(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const admin = connect(supabaseUrl, serviceKey)
  return {
    async getUser() {
      const { data, error } = await asUser.auth.getUser()
      if (error || !data.user) return null
      return { id: data.user.id, user_metadata: data.user.user_metadata }
    },
    store: liveStore(admin, asUser),
    env: {
      webhookUrl: Deno.env.get('FEEDBACK_DISCORD_WEBHOOK_URL') ?? '',
      tagIdsJson: Deno.env.get('FEEDBACK_DISCORD_TAG_IDS') ?? '',
    },
    nowMs: () => Date.now(),
    postDiscord: (url, payload) => postDiscordWebhook(url, payload),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  }
}

Deno.serve(async (req) => {
  const deps = liveDeps(req)
  if (deps instanceof Response) return deps
  try {
    return await handleSubmitFeedback(req, deps)
  } catch (error) {
    return json(
      { error: error instanceof Error ? 'That report could not be sent.' : 'That report could not be sent.' },
      500,
    )
  }
})
