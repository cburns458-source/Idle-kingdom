import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import { chatChannelKey, type ChatChannel, type ChatMessage } from './types'

export async function sendChatMessage(
  channel: ChatChannel,
  body: string,
): Promise<{ ok: true; message: ChatMessage } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to chat.' }

  if (multiplayerMode() === 'local') {
    return getLocalBackend().sendChat(session, channel, body)
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { data, error } = await client.functions.invoke('send-chat', {
    body: { channelKey: chatChannelKey(channel), body },
  })
  if (error) return { ok: false, reason: error.message }
  return { ok: true, message: data as ChatMessage }
}

export async function listChatMessages(channel: ChatChannel): Promise<ChatMessage[]> {
  const session = getSession()
  if (!session) return []
  if (multiplayerMode() === 'local') {
    return getLocalBackend().listChat(channel, session.userId)
  }
  const client = getSupabaseClient()
  if (!client) return []
  const { data, error } = await client
    .from('chat_messages')
    .select('id, channel_key, user_id, username, body, created_at')
    .eq('channel_key', chatChannelKey(channel))
    .order('created_at', { ascending: true })
    .limit(50)
  if (error || !data) return []
  return data.map((row) => ({
    id: String(row.id),
    channelKey: String(row.channel_key),
    userId: String(row.user_id),
    username: String(row.username),
    body: String(row.body),
    createdAt: String(row.created_at),
  }))
}

export function mutePlayer(targetUserId: string): void {
  const session = getSession()
  if (!session) return
  getLocalBackend().muteUser(session.userId, targetUserId)
}

export function blockPlayer(targetUserId: string): void {
  const session = getSession()
  if (!session) return
  getLocalBackend().blockUser(session.userId, targetUserId)
}

export function reportPlayer(targetUserId: string, reason: string): void {
  const session = getSession()
  if (!session) return
  getLocalBackend().reportUser(session.userId, targetUserId, reason)
}
