import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  isPendingAccountUsername,
  pendingAccountUsername,
  profileRowForSignUp,
  remoteUsername,
  REMOTE_MAGIC_LINK_UNAVAILABLE,
  REMOTE_NOT_CONFIGURED,
  REMOTE_SIGN_IN_FAILED,
  REMOTE_SIGN_UP_FAILED,
  REMOTE_TABLES,
  sessionFromSignIn,
  sessionFromSignUp,
} from './remote'
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

/**
 * Records a session Supabase authenticated, and gives it a local profile.
 *
 * Guilds, presence, and public profiles are still answered from this device, and
 * all of them hang off a profile row, so a remote account needs one here too.
 */
function adoptSession(session: MultiplayerSession): void {
  writeStoredSession(session)
  getLocalBackend().registerProfile(session.userId, session.username)
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
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const { data, error } = await client.auth.signUp({
    email: email.trim(),
    password,
    options: { data: { username: remoteUsername(username) } },
  })
  if (error || !data.user) {
    return { ok: false, reason: error?.message ?? REMOTE_SIGN_UP_FAILED }
  }
  const chosen =
    username.trim().length >= 2 ? remoteUsername(username) : pendingAccountUsername(data.user.id)
  const session = sessionFromSignUp(
    data.user.id,
    email,
    chosen,
    data.session?.access_token ?? null,
  )
  // Best-effort profile row (RLS policies in SQL migration).
  await client.from(REMOTE_TABLES.profiles).upsert(profileRowForSignUp(session))
  adoptSession(session)
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
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const { data, error } = await client.auth.signInWithPassword({
    email: email.trim(),
    password,
  })
  if (error || !data.user) {
    return { ok: false, reason: error?.message ?? REMOTE_SIGN_IN_FAILED }
  }
  const { data: profile } = await client
    .from(REMOTE_TABLES.profiles)
    .select('username')
    .eq('user_id', data.user.id)
    .limit(1)
    .maybeSingle()
  const profileUsername = typeof profile?.username === 'string' ? profile.username : null
  const metadataUsername = data.user.user_metadata?.username
  const session = sessionFromSignIn(
    data.user.id,
    data.user.email ?? null,
    email,
    profileUsername || (typeof metadataUsername === 'string' ? metadataUsername : null),
    data.session?.access_token ?? null,
  )
  adoptSession(session)
  return { ok: true, session }
}

/** Names the account from the first character name. Later names do not replace it. */
export async function claimAccountUsername(
  name: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  const cleaned = remoteUsername(name)
  if (cleaned.length < 2) return { ok: false, reason: 'Enter a name to continue.' }
  if (session.username.toLowerCase() === cleaned.toLowerCase()) return { ok: true }
  if (!isPendingAccountUsername(session.username)) return { ok: true }

  if (multiplayerMode() === 'local') {
    const result = getLocalBackend().claimAccountUsername(session.userId, name)
    if (result.ok) writeStoredSession({ ...session, username: cleaned })
    return result
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const taken = await client
    .from(REMOTE_TABLES.profiles)
    .select('user_id, username')
    .eq('username', cleaned)
    .limit(1)
    .maybeSingle()
  if (taken.data && `${taken.data.user_id}` !== session.userId) {
    return { ok: false, reason: 'That name is taken.' }
  }
  const { error } = await client
    .from(REMOTE_TABLES.profiles)
    .upsert({ user_id: session.userId, username: cleaned }, { onConflict: 'user_id' })
  if (error) return { ok: false, reason: error.message }
  await client.auth.updateUser({ data: { username: cleaned } })
  getLocalBackend().upsertProfile(session.userId, { username: cleaned })
  adoptSession({ ...session, username: cleaned })
  return { ok: true }
}

export async function signInWithMagicLink(
  email: string,
): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (multiplayerMode() === 'local') {
    return { ok: false, reason: REMOTE_MAGIC_LINK_UNAVAILABLE }
  }
  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
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
