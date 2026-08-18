import { createClient } from 'npm:@supabase/supabase-js@2'

const MAX_BODY = 240
const COOLDOWN_SECONDS: Record<string, number> = {
  global: 30,
  local: 10,
  guild: 5,
  dm: 2,
}
const SLURS = /\b(nigger|faggot)\b/i
const DEFAULT_RANK_LABELS: Record<string, string> = {
  leader: 'Leader',
  officer: 'Officer',
  veteran: 'Veteran',
  member: 'Member',
  recruit: 'Recruit',
}

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

  const { data: membership } = await admin
    .from('guild_members')
    .select('guild_id, role')
    .eq('user_id', user.id)
    .maybeSingle()

  let guildTag: string | null = null
  let rankLabel: string | null = null
  let rankIcon: string | null = null
  let guest = false

  if (membership?.guild_id) {
    const { data: guild } = await admin
      .from('guilds')
      .select('tag, rank_labels, rank_icon_theme')
      .eq('id', membership.guild_id)
      .maybeSingle()
    if (typeof guild?.tag === 'string' && guild.tag.trim()) {
      guildTag = guild.tag.trim()
    }
    if (kind === 'guild' && membership.guild_id === channelKey.slice('guild:'.length)) {
      const role = typeof membership.role === 'string' ? membership.role : 'recruit'
      const labels = (guild?.rank_labels ?? {}) as Record<string, unknown>
      const named = typeof labels[role] === 'string' ? String(labels[role]).trim() : ''
      rankLabel = named || DEFAULT_RANK_LABELS[role] || 'Recruit'
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
      guild_tag: guildTag,
      rank_label: rankLabel,
      rank_icon: rankIcon,
      guest,
    })
    .select(
      'id, channel_key, user_id, username, body, created_at, guild_tag, rank_label, rank_icon, guest',
    )
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
