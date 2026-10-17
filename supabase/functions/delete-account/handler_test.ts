import { assertEquals } from 'jsr:@std/assert@1'
import { handleDeleteAccount, type DeleteAccountDeps, type DeleteAccountStore } from './handler.ts'

const USER = {
  id: '11111111-1111-4111-8111-111111111111',
  last_sign_in_at: '2026-10-17T12:00:00.000Z',
}
const NOW = Date.parse('2026-10-17T12:05:00.000Z')

class MemoryStore implements DeleteAccountStore {
  developer = false
  username = 'Hero'
  saveName = 'Hero'
  pending: { purge_after: string; status: string } | null = null
  requested: Array<{ userId: string; name: string }> = []
  restored: string[] = []
  revoked: string[] = []
  requestFails: string | null = null

  async isDeveloper() {
    return this.developer
  }
  async profileUsername() {
    return this.username
  }
  async saveCharacterName() {
    return this.saveName
  }
  async requestDeletion(userId: string, characterName: string) {
    if (this.requestFails) return { ok: false, reason: this.requestFails }
    this.requested.push({ userId, name: characterName })
    this.pending = { purge_after: '2026-10-31T12:05:00.000Z', status: 'pending' }
    return { ok: true, purge_after: this.pending.purge_after }
  }
  async restore(userId: string) {
    this.restored.push(userId)
    this.pending = null
    return { ok: true }
  }
  async pendingDeletion() {
    return this.pending
  }
  async revokeSessions(userId: string) {
    this.revoked.push(userId)
  }
}

function request(body: unknown): Request {
  return new Request('http://localhost/delete-account', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer test' },
    body: JSON.stringify(body),
  })
}

function deps(store: MemoryStore, user = USER): DeleteAccountDeps {
  return {
    getUser: async () => user,
    store,
    nowMs: () => NOW,
  }
}

async function read(response: Response): Promise<Record<string, unknown>> {
  return (await response.json()) as Record<string, unknown>
}

Deno.test('staff accounts cannot self-delete', async () => {
  const store = new MemoryStore()
  store.developer = true
  const response = await handleDeleteAccount(request({ action: 'request', characterName: 'Hero' }), deps(store))
  assertEquals(response.status, 403)
  assertEquals((await read(response)).error, 'Staff accounts cannot be deleted this way.')
  assertEquals(store.requested.length, 0)
})

Deno.test('delete requires a fresh re-auth then the character name', async () => {
  const store = new MemoryStore()
  const stale = await handleDeleteAccount(
    request({ action: 'request', characterName: 'Hero' }),
    deps(store, { ...USER, last_sign_in_at: '2026-10-17T11:00:00.000Z' }),
  )
  assertEquals(stale.status, 401)
  assertEquals((await read(stale)).code, 'reauth_required')

  const wrong = await handleDeleteAccount(request({ action: 'request', characterName: 'Other' }), deps(store))
  assertEquals(wrong.status, 400)
  assertEquals((await read(wrong)).error, 'Type your character name to confirm.')

  const ok = await handleDeleteAccount(request({ action: 'request', characterName: 'hero' }), deps(store))
  assertEquals(ok.status, 200)
  const body = await read(ok)
  assertEquals(body.ok, true)
  assertEquals(body.purge_after, '2026-10-31T12:05:00.000Z')
  assertEquals(store.revoked, [USER.id])
})

Deno.test('restore during grace puts the account back; after grace it refuses', async () => {
  const store = new MemoryStore()
  store.pending = { purge_after: '2026-10-31T00:00:00.000Z', status: 'pending' }
  const restored = await handleDeleteAccount(request({ action: 'restore' }), deps(store))
  assertEquals(restored.status, 200)
  assertEquals((await read(restored)).restored, true)
  assertEquals(store.restored, [USER.id])

  store.pending = { purge_after: '2026-10-17T12:00:00.000Z', status: 'pending' }
  const late = await handleDeleteAccount(request({ action: 'restore' }), deps(store))
  assertEquals(late.status, 400)
  assertEquals((await read(late)).error, 'This account is being deleted.')
})

Deno.test('a second delete request is idempotent', async () => {
  const store = new MemoryStore()
  store.requestFails = null
  const first = await handleDeleteAccount(request({ action: 'request', characterName: 'Hero' }), deps(store))
  assertEquals(first.status, 200)
  store.requestFails = null
  const original = store.requestDeletion.bind(store)
  store.requestDeletion = async (userId, characterName) => {
    await original(userId, characterName)
    return { ok: true, purge_after: '2026-10-31T12:05:00.000Z', already: true }
  }
  const second = await handleDeleteAccount(request({ action: 'request', characterName: 'Hero' }), deps(store))
  assertEquals(second.status, 200)
  assertEquals((await read(second)).already, true)
})
