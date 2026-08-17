import { createClient } from 'npm:@supabase/supabase-js@2'

const MAX_BODY = 240
const COOLDOWN_SECONDS: Record<string, number> = {
  global: 30,
  local: 10,
  guild: 5,
  dm: 2,
}
const SLURS = /\b(nigger|faggot)\b/i

type SendBody = {
  channelKey?: unknown
  body?: unknown
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors() })
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Function is missing Supabase secrets.' }, 500)
  }

  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: userData, error: userError } = await asUser.auth.getUser()
  const user = userData.user
  if (userError || !user) {
    return json({ error: 'Sign in to chat.' }, 401)
  }

  let payload: SendBody
  try {
    payload = (await req.json()) as SendBody
  } catch {
    return json({ error: 'Message is empty.' }, 400)
  }

  const channelKey = typeof payload.channelKey === 'string' ? payload.channelKey.trim() : ''
  const kind = channelKind(channelKey)
  if (!kind) {
    return json({ error: 'Unknown chat channel.' }, 400)
  }

  const trimmed = String(payload.body ?? '')
    .trim()
    .slice(0, MAX_BODY)
  if (!trimmed) {
    return json({ error: 'Message is empty.' }, 400)
  }
  if (SLURS.test(trimmed)) {
    return json({ error: 'Chat has been disabled.' }, 400)
  }

  const admin = createClient(supabaseUrl, serviceKey)
  const username = await resolveUsername(admin, user.id, user.user_metadata)

  if (kind === 'guild') {
    const guildId = channelKey.slice('guild:'.length)
    const { data: member } = await admin
      .from('guild_members')
      .select('user_id')
      .eq('guild_id', guildId)
      .eq('user_id', user.id)
      .maybeSingle()
    if (!member) {
      return json({ error: 'Join the guild to use guild chat.' }, 400)
    }
  }

  const cooldown = COOLDOWN_SECONDS[kind] ?? 10
  const { data: last } = await admin
    .from('chat_cooldowns')
    .select('last_sent_at')
    .eq('user_id', user.id)
    .eq('channel_key', channelKey)
    .maybeSingle()
  if (last?.last_sent_at) {
    const elapsedMs = Date.now() - Date.parse(String(last.last_sent_at))
    const waitMs = cooldown * 1000 - elapsedMs
    if (waitMs > 0) {
      return json({ error: `Wait ${Math.ceil(waitMs / 1000)}s before chatting again.` }, 400)
    }
  }

  const { data: inserted, error: insertError } = await admin
    .from('chat_messages')
    .insert({
      channel_key: channelKey,
      user_id: user.id,
      username,
      body: trimmed,
    })
    .select('id, channel_key, user_id, username, body, created_at')
    .single()
  if (insertError || !inserted) {
    return json({ error: insertError?.message ?? 'The chat message was not accepted.' }, 400)
  }

  await admin.from('chat_cooldowns').upsert({
    user_id: user.id,
    channel_key: channelKey,
    last_sent_at: inserted.created_at,
  })

  return json(inserted, 200)
})

function channelKind(key: string): string | null {
  if (key === 'global') return 'global'
  if (key.startsWith('local:') && key.length > 6) return 'local'
  if (key.startsWith('guild:') && key.length > 6) return 'guild'
  if (key.startsWith('dm:') && key.length > 3) return 'dm'
  return null
}

async function resolveUsername(
  admin: ReturnType<typeof createClient>,
  userId: string,
  metadata: Record<string, unknown> | undefined,
): Promise<string> {
  const { data } = await admin.from('profiles').select('username').eq('user_id', userId).maybeSingle()
  const fromProfile = typeof data?.username === 'string' ? data.username.trim() : ''
  if (fromProfile) return fromProfile.slice(0, 24)
  const fromMeta = typeof metadata?.username === 'string' ? metadata.username.trim() : ''
  return (fromMeta || 'Adventurer').slice(0, 24)
}

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
