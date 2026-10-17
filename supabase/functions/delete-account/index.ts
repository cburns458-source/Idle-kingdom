import { createClient } from 'npm:@supabase/supabase-js@2'
import { handleDeleteAccount, type DeleteAccountDeps, type DeleteAccountStore } from './handler.ts'

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

function liveStore(admin: Client): DeleteAccountStore {
  return {
    async isDeveloper(userId) {
      const { data } = await admin.from('developer_accounts').select('user_id').eq('user_id', userId).maybeSingle()
      return Boolean(data?.user_id)
    },
    async profileUsername(userId) {
      const { data } = await admin.from('profiles').select('username').eq('user_id', userId).maybeSingle()
      return typeof data?.username === 'string' ? data.username : null
    },
    async saveCharacterName(userId) {
      const { data } = await admin.from('player_saves').select('payload').eq('user_id', userId).maybeSingle()
      const payload = data?.payload
      if (payload && typeof payload === 'object' && payload !== null && 'characterName' in payload) {
        const name = (payload as { characterName?: unknown }).characterName
        return typeof name === 'string' ? name : null
      }
      return null
    },
    async requestDeletion(userId, characterName) {
      const { data, error } = await admin.rpc('account_request_deletion', {
        p_user: userId,
        p_character_name: characterName,
      })
      if (error) return { ok: false, reason: error.message }
      const row = (data ?? {}) as Record<string, unknown>
      if (row.ok === false) {
        return { ok: false, reason: typeof row.reason === 'string' ? row.reason : 'Could not delete this account.' }
      }
      return {
        ok: true,
        purge_after: typeof row.purge_after === 'string' ? row.purge_after : undefined,
        already: row.already === true,
      }
    },
    async restore(userId) {
      const { data, error } = await admin.rpc('account_restore', { p_user: userId })
      if (error) return { ok: false, reason: error.message }
      const row = (data ?? {}) as Record<string, unknown>
      if (row.ok === false) {
        return { ok: false, reason: typeof row.reason === 'string' ? row.reason : 'Could not restore this account.' }
      }
      return { ok: true }
    },
    async pendingDeletion(userId) {
      const { data } = await admin
        .from('account_deletion_requests')
        .select('purge_after, status')
        .eq('user_id', userId)
        .eq('status', 'pending')
        .maybeSingle()
      if (!data) return null
      return {
        purge_after: String(data.purge_after ?? ''),
        status: String(data.status ?? ''),
      }
    },
    async revokeSessions(userId) {
      await admin.auth.admin.signOut(userId, 'global')
    },
  }
}

function liveDeps(req: Request): DeleteAccountDeps | Response {
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
      return {
        id: data.user.id,
        last_sign_in_at: data.user.last_sign_in_at,
        user_metadata: data.user.user_metadata,
      }
    },
    store: liveStore(admin),
    nowMs: () => Date.now(),
  }
}

Deno.serve(async (req) => {
  const deps = liveDeps(req)
  if (deps instanceof Response) return deps
  try {
    return await handleDeleteAccount(req, deps)
  } catch {
    return json({ error: 'That request could not be completed.' }, 500)
  }
})
