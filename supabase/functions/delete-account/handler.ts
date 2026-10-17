import {
  ACCOUNT_BEING_DELETED,
  NAME_CONFIRM_FAILED,
  REAUTH_REQUIRED,
  STAFF_DELETE_BLOCKED,
  graceStillOpen,
  namesMatch,
  reauthIsFresh,
} from '../_shared/deletion.ts'

export type DeleteAccountUser = {
  id: string
  last_sign_in_at?: string | null
  user_metadata?: Record<string, unknown>
}

export type DeleteAccountStore = {
  isDeveloper: (userId: string) => Promise<boolean>
  profileUsername: (userId: string) => Promise<string | null>
  saveCharacterName: (userId: string) => Promise<string | null>
  requestDeletion: (userId: string, characterName: string) => Promise<{
    ok: boolean
    reason?: string
    purge_after?: string
    already?: boolean
  }>
  restore: (userId: string) => Promise<{ ok: boolean; reason?: string }>
  pendingDeletion: (userId: string) => Promise<{
    purge_after: string
    status: string
  } | null>
  revokeSessions: (userId: string) => Promise<void>
}

export type DeleteAccountDeps = {
  getUser: (req: Request) => Promise<DeleteAccountUser | null>
  store: DeleteAccountStore
  nowMs: () => number
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

export async function handleDeleteAccount(req: Request, deps: DeleteAccountDeps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })
  if (req.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  const user = await deps.getUser(req)
  if (!user) return json({ error: 'Sign in first.' }, 401)

  let payload: Record<string, unknown>
  try {
    payload = (await req.json()) as Record<string, unknown>
  } catch {
    payload = {}
  }
  const action = typeof payload.action === 'string' ? payload.action.trim() : 'request'

  if (action === 'status') {
    const pending = await deps.store.pendingDeletion(user.id)
    return json(
      {
        ok: true,
        deletion_pending: pending != null && pending.status === 'pending',
        deletion_purge_at: pending?.purge_after ?? null,
      },
      200,
    )
  }

  if (action === 'restore') {
    const pending = await deps.store.pendingDeletion(user.id)
    if (!pending || pending.status !== 'pending') {
      return json({ error: 'This account is not waiting to be deleted.' }, 400)
    }
    if (!graceStillOpen(pending.purge_after, deps.nowMs())) {
      return json({ error: ACCOUNT_BEING_DELETED }, 400)
    }
    const restored = await deps.store.restore(user.id)
    if (!restored.ok) return json({ error: restored.reason ?? 'Could not restore this account.' }, 400)
    return json({ ok: true, restored: true }, 200)
  }

  if (action !== 'request') {
    return json({ error: 'Unknown action.' }, 400)
  }

  if (await deps.store.isDeveloper(user.id)) {
    return json({ error: STAFF_DELETE_BLOCKED }, 403)
  }
  if (!reauthIsFresh(user.last_sign_in_at, deps.nowMs())) {
    return json({ error: REAUTH_REQUIRED, code: 'reauth_required' }, 401)
  }

  const typed = typeof payload.characterName === 'string' ? payload.characterName : ''
  const username = await deps.store.profileUsername(user.id)
  const saveName = await deps.store.saveCharacterName(user.id)
  if (!namesMatch(typed, username, saveName)) {
    return json({ error: NAME_CONFIRM_FAILED }, 400)
  }

  const requested = await deps.store.requestDeletion(user.id, typed.trim())
  if (!requested.ok) {
    return json({ error: requested.reason ?? 'Could not delete this account.' }, 400)
  }
  await deps.store.revokeSessions(user.id)
  return json(
    {
      ok: true,
      purge_after: requested.purge_after ?? null,
      already: requested.already === true,
    },
    200,
  )
}
