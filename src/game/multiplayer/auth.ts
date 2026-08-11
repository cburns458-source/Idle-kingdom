import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import { MULTIPLAYER_SESSION_KEY, type MultiplayerSession } from './types'

function readStoredSession(): MultiplayerSession | null {
  try {
    const raw = localStorage.getItem(MULTIPLAYER_SESSION_KEY)
    if (!raw) return null
    return JSON.parse(raw) as MultiplayerSession
  } catch {
    return null
  }
}

function writeStoredSession(session: MultiplayerSession | null): void {
  if (!session) {
    localStorage.removeItem(MULTIPLAYER_SESSION_KEY)
    return
  }
  localStorage.setItem(MULTIPLAYER_SESSION_KEY, JSON.stringify(session))
}

export function getSession(): MultiplayerSession | null {
  return readStoredSession()
}

export function isSignedIn(): boolean {
  return getSession() != null
}

export async function signUpWithPassword(
  email: string,
  username: string,
  password: string,
): Promise<{ ok: true; session: MultiplayerSession } | { ok: false; reason: string }> {
  if (multiplayerMode() === 'local') {
    const result = getLocalBackend().signUp(email, username, password)
    if (result.ok) writeStoredSession(result.session)
    return result
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { data, error } = await client.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { username: username.trim().slice(0, 24) } },
  })
  if (error || !data.user) {
    return { ok: false, reason: error?.message ?? 'Sign-up failed.' }
  }
  const session: MultiplayerSession = {
    userId: data.user.id,
    email: email.trim().toLowerCase(),
    username: username.trim().slice(0, 24),
    accessToken: data.session?.access_token ?? '',
  }
  // Best-effort profile row (RLS policies in SQL migration).
  await client.from('profiles').upsert({
    user_id: session.userId,
    username: session.username,
    privacy_public_skills: true,
  })
  writeStoredSession(session)
  return { ok: true, session }
}

export async function signInWithPassword(
  email: string,
  password: string,
): Promise<{ ok: true; session: MultiplayerSession } | { ok: false; reason: string }> {
  if (multiplayerMode() === 'local') {
    const result = getLocalBackend().signIn(email, password)
    if (result.ok) writeStoredSession(result.session)
    return result
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { data, error } = await client.auth.signInWithPassword({
    email: email.trim(),
    password,
  })
  if (error || !data.user) {
    return { ok: false, reason: error?.message ?? 'Sign-in failed.' }
  }
  const username =
    String(data.user.user_metadata?.username ?? data.user.email?.split('@')[0] ?? 'Adventurer')
  const session: MultiplayerSession = {
    userId: data.user.id,
    email: data.user.email ?? email.trim().toLowerCase(),
    username,
    accessToken: data.session?.access_token ?? '',
  }
  writeStoredSession(session)
  return { ok: true, session }
}

export async function signInWithMagicLink(
  email: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (multiplayerMode() === 'local') {
    return {
      ok: false,
      reason: 'Magic links require Supabase. Use email/password in local demo mode.',
    }
  }
  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { error } = await client.auth.signInWithOtp({ email: email.trim() })
  if (error) return { ok: false, reason: error.message }
  return { ok: true }
}

export async function signOut(): Promise<void> {
  writeStoredSession(null)
  if (multiplayerMode() === 'supabase') {
    const client = getSupabaseClient()
    await client?.auth.signOut()
  }
}
