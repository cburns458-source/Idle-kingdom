import { createClient } from 'npm:@supabase/supabase-js@2'

const MAX_BODY = 240
const COOLDOWN_MS = 2000
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

  if (kind === 'dm') {
    const peers = dmPeers(channelKey)
    if (!peers || !peers.includes(user.id)) {
      return json({ error: 'That private channel is not yours.' }, 400)
    }
  }

  const admin = connect(supabaseUrl, serviceKey)
  const username = await resolveUsername(admin, user.id, user.user_metadata)

  const cooled = await enforceCooldown(admin, user.id, channelKey)
  if (cooled) return cooled

  if (kind === 'dm') {
    const peers = dmPeers(channelKey)!
    const peerId = peers.find((id) => id !== user.id)
    if (!peerId) {
      return json({ error: 'That private channel is not yours.' }, 400)
    }
    const privacy = await directMessagePrivacy(admin, peerId)
    if (privacy == null) {
      return json({ error: 'That player could not be found.' }, 400)
    }
    const blocked = await isEitherBlocked(admin, user.id, peerId)
    if (blocked) {
      return json({ error: 'You cannot message that player.' }, 400)
    }
    if (privacy === 'off') {
      return json({ error: 'That player is not accepting messages.' }, 400)
    }
    if (privacy === 'friends') {
      const friends = await areFriends(admin, user.id, peerId)
      if (!friends) {
        return json({ error: 'That player only accepts messages from friends.' }, 400)
      }
    }
  }

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

  if (kind === 'local') {
    const locationId = channelKey.slice('local:'.length)
    const { data: presence } = await admin
      .from('activity_presence')
      .select('location_id, expires_at')
      .eq('user_id', user.id)
      .maybeSingle()
    const expiresAt =
      typeof presence?.expires_at === 'string' ? Date.parse(presence.expires_at) : Number.NaN
    if (
      presence?.location_id !== locationId ||
      !Number.isFinite(expiresAt) ||
      expiresAt <= Date.now()
    ) {
      return json({ error: 'Join that location before using its chat.' }, 400)
    }
    const privacy = await localChatPrivacy(admin, user.id)
    if (privacy === 'off') {
      return json({ error: 'Local chat is turned off in your privacy settings.' }, 400)
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

  await admin.from('chat_cooldowns').upsert({
    user_id: user.id,
    channel_key: channelKey,
    last_sent_at: new Date().toISOString(),
  })

  return json(inserted, 200)
})

async function enforceCooldown(
  admin: Client,
  userId: string,
  channelKey: string,
): Promise<Response | null> {
  const { data } = await admin
    .from('chat_cooldowns')
    .select('last_sent_at')
    .eq('user_id', userId)
    .eq('channel_key', channelKey)
    .maybeSingle()
  const last = typeof data?.last_sent_at === 'string' ? Date.parse(data.last_sent_at) : 0
  if (last && Date.now() - last < COOLDOWN_MS) {
    return json({ error: 'Slow down a moment before chatting again.' }, 429)
  }
  return null
}

async function isEitherBlocked(admin: Client, a: string, b: string): Promise<boolean> {
  const { data } = await admin
    .from('player_blocks')
    .select('user_id')
    .or(
      `and(user_id.eq.${a},blocked_user_id.eq.${b}),and(user_id.eq.${b},blocked_user_id.eq.${a})`,
    )
    .limit(1)
  return (data?.length ?? 0) > 0
}

async function areFriends(admin: Client, a: string, b: string): Promise<boolean> {
  const [userA, userB] = a < b ? [a, b] : [b, a]
  const { data } = await admin
    .from('friendships')
    .select('user_a')
    .eq('user_a', userA)
    .eq('user_b', userB)
    .maybeSingle()
  return data != null
}

async function directMessagePrivacy(admin: Client, userId: string): Promise<string | null> {
  const { data } = await admin
    .from('profiles')
    .select('privacy_direct_messages')
    .eq('user_id', userId)
    .maybeSingle()
  if (!data) return null
  const value = data?.privacy_direct_messages
  return typeof value === 'string' && value ? value : 'public'
}

async function localChatPrivacy(admin: Client, userId: string): Promise<string> {
  const { data } = await admin
    .from('profiles')
    .select('privacy_local_chat')
    .eq('user_id', userId)
    .maybeSingle()
  const value = data?.privacy_local_chat
  return typeof value === 'string' && value ? value : 'public'
}

function guildRankIcon(theme: string, role: string): string {
  if (theme === 'crowns') {
    if (role === 'leader') return '♔'
    if (role === 'officer') return '◆'
    if (role === 'veteran') return '●'
    if (role === 'member') return '•'
    return '·'
  }
  if (role === 'leader') return '★'
  if (role === 'officer') return '〇〇〇〇'
  if (role === 'veteran') return '〇〇〇'
  if (role === 'member') return '〇〇'
  return '〇'
}

function channelKind(key: string): string | null {
  if (key === 'global') return 'global'
  if (key.startsWith('local:') && key.length > 6) return 'local'
  if (key.startsWith('guild:') && key.length > 6) return 'guild'
  if (key.startsWith('dm:') && key.length > 3) return 'dm'
  return null
}

function dmPeers(channelKey: string): string[] | null {
  const body = channelKey.slice('dm:'.length)
  const parts = body.split(':').filter((part) => part.length > 0)
  if (
    parts.length !== 2 ||
    parts[0] === parts[1] ||
    !parts.every((part) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(part)
    )
  ) {
    return null
  }
  return parts
}

function publicChatUsername(raw: unknown): string {
  if (typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed || trimmed.startsWith('pending_')) return ''
  return trimmed.slice(0, 24)
}

async function resolveUsername(
  admin: Client,
  userId: string,
  metadata: Record<string, unknown> | undefined,
): Promise<string> {
  const { data } = await admin.from('profiles').select('username').eq('user_id', userId).maybeSingle()
  return (
    publicChatUsername(data?.username) ||
    publicChatUsername(metadata?.username) ||
    'Adventurer'
  )
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
