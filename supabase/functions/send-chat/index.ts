import { createClient } from 'npm:@supabase/supabase-js@2'

const MAX_BODY = 240
const SLURS = /\b(nigger|faggot)\b/i

type SendBody = {
  channelKey?: unknown
  body?: unknown
}

/**
 * A client for this project, which has no generated `Database` type.
 *
 * Named rather than written as `ReturnType<typeof createClient>`, because that
 * resolves the generic *defaults* — where the schema is `never` — instead of the
 * client `createClient(url, key)` actually returns. Every row read through a
 * `never` schema is itself typed `never`, so `deno check` rejects reading any
 * column off it.
 */
function connect(url: string, key: string, options?: Parameters<typeof createClient>[2]) {
  return createClient(url, key, options)
}

type Client = ReturnType<typeof connect>

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

  const asUser = connect(supabaseUrl, anonKey, {
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

  const admin = connect(supabaseUrl, serviceKey)
  const username = await resolveUsername(admin, user.id, user.user_metadata)

  const { data: membership } = await admin
    .from('guild_members')
    .select('guild_id, role')
    .eq('user_id', user.id)
    .maybeSingle()

  let guildTag: string | null = null
  let rankIcon: string | null = null
  let guest = false

  if (membership?.guild_id) {
    const { data: guild } = await admin
      .from('guilds')
      .select('tag, rank_icon_theme')
      .eq('id', membership.guild_id)
      .maybeSingle()
    if (typeof guild?.tag === 'string' && guild.tag.trim()) {
      guildTag = guild.tag.trim()
    }
    if (kind === 'guild' && membership.guild_id === channelKey.slice('guild:'.length)) {
      const role = typeof membership.role === 'string' ? membership.role : 'recruit'
      rankIcon = guildRankIcon(String(guild?.rank_icon_theme ?? 'stripes'), role)
    }
  }

  if (kind === 'guild') {
    const guildId = channelKey.slice('guild:'.length)
    const isMember = membership?.guild_id === guildId
    if (!isMember) {
      const { data: guestRow } = await admin
        .from('guild_guests')
        .select('user_id')
        .eq('guild_id', guildId)
        .eq('user_id', user.id)
        .maybeSingle()
      if (!guestRow) {
        return json({ error: 'Join the guild to use guild chat.' }, 400)
      }
      guest = true
    }
  }

  const { data: inserted, error: insertError } = await admin
    .from('chat_messages')
    .insert({
      channel_key: channelKey,
      user_id: user.id,
      username,
      body: trimmed,
      guild_tag: guildTag,
      rank_icon: rankIcon,
      guest,
    })
    .select('id, channel_key, user_id, username, body, created_at, guild_tag, rank_icon, guest')
    .single()
  if (insertError || !inserted) {
    return json({ error: insertError?.message ?? 'The chat message was not accepted.' }, 400)
  }

  return json(inserted, 200)
})

function guildRankIcon(theme: string, role: string): string {
  if (theme === 'crowns') {
    if (role === 'leader') return '♔'
    if (role === 'officer') return '◆'
    if (role === 'veteran') return '●'
    if (role === 'member') return '•'
    return '·'
  }
  if (role === 'leader') return '★'
  if (role === 'officer') return '▍▍▍▍'
  if (role === 'veteran') return '▍▍▍'
  if (role === 'member') return '▍▍'
  return '▍'
}

function channelKind(key: string): string | null {
  if (key === 'global') return 'global'
  if (key.startsWith('local:') && key.length > 6) return 'local'
  if (key.startsWith('guild:') && key.length > 6) return 'guild'
  if (key.startsWith('dm:') && key.length > 3) return 'dm'
  return null
}

async function resolveUsername(
  admin: Client,
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
