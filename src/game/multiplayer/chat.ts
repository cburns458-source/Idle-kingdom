import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  chatMessageFrom,
  chatMessageFromFunction,
  REMOTE_CHAT_COLUMNS,
  REMOTE_CHAT_LIMIT,
  REMOTE_CHAT_SEND_FAILED,
  REMOTE_DIRECT_MESSAGE_LIMIT,
  REMOTE_NOT_CONFIGURED,
  REMOTE_SEND_CHAT_FUNCTION,
  REMOTE_TABLES,
} from './remote'
import { chatChannelKey, dmChannelInvolves, type ChatChannel, type ChatMessage } from './types'

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
  const message = chatMessageFromFunction(data)
  if (!message) return { ok: false, reason: REMOTE_CHAT_SEND_FAILED }
  return { ok: true, message }
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
  if (multiplayerMode() === 'local') {
    return getLocalBackend().listDirectMessages(session.userId)
  }
  const client = getSupabaseClient()
  if (!client) return []
  const { data, error } = await client
    .from(REMOTE_TABLES.chat)
    .select(REMOTE_CHAT_COLUMNS)
    .like('channel_key', 'dm:%')
    .order('created_at', { ascending: true })
    .limit(REMOTE_DIRECT_MESSAGE_LIMIT)
  if (error || !data) return []
  const silenced = new Set(getLocalBackend().silencedIds(session.userId))
  return data
    .map(chatMessageFrom)
    .filter((message) => dmChannelInvolves(message.channelKey, session.userId) && !silenced.has(message.userId))
}

export async function countUnreadDirectMessages(sinceIso: string | null): Promise<number> {
  const session = getSession()
  if (!session) return 0
  if (multiplayerMode() === 'local') {
    return getLocalBackend().countUnreadDirectMessages(session.userId, sinceIso)
  }
  const sinceMs = sinceIso ? Date.parse(sinceIso) : 0
  const messages = await listDirectMessages()
  return messages.filter((row) => row.userId !== session.userId && Date.parse(row.createdAt) > sinceMs)
    .length
}

export async function countUnreadChat(channel: ChatChannel, sinceIso: string | null): Promise<number> {
  const session = getSession()
  if (!session) return 0
  if (multiplayerMode() === 'local') {
    return getLocalBackend().countUnreadChat(session.userId, channel, sinceIso)
  }
  const sinceMs = sinceIso ? Date.parse(sinceIso) : 0
  const messages = await listChatMessages(channel)
  return messages.filter((row) => row.userId !== session.userId && Date.parse(row.createdAt) > sinceMs)
    .length
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
