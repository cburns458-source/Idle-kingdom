import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  chatMessageFrom,
  REMOTE_CHAT_COLUMNS,
  REMOTE_CHAT_LIMIT,
  REMOTE_NOT_CONFIGURED,
  REMOTE_SEND_CHAT_FUNCTION,
  REMOTE_TABLES,
} from './remote'
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
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const { data, error } = await client.functions.invoke(REMOTE_SEND_CHAT_FUNCTION, {
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
    .from(REMOTE_TABLES.chat)
    .select(REMOTE_CHAT_COLUMNS)
    .eq('channel_key', chatChannelKey(channel))
    .order('created_at', { ascending: true })
    .limit(REMOTE_CHAT_LIMIT)
  if (error || !data) return []
  return data.map(chatMessageFrom)
}

export async function listDirectMessages(): Promise<ChatMessage[]> {
  const session = getSession()
  if (!session) return []
  return getLocalBackend().listDirectMessages(session.userId)
}

export function countUnreadDirectMessages(sinceIso: string | null): number {
  const session = getSession()
  if (!session) return 0
  return getLocalBackend().countUnreadDirectMessages(session.userId, sinceIso)
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
