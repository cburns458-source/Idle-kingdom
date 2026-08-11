import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'
import { parseSave, type SaveStorage, writeSave } from '../save/saveStore'
import { SAVE_STORAGE_KEY } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import { submitLeaderboardFromSave } from './leaderboards'
import type { CloudSaveRecord } from './types'

export type CloudSyncResult =
  | { ok: true; save: PlayerSave; source: 'uploaded' | 'downloaded' | 'unchanged' }
  | { ok: false; reason: string; remote?: CloudSaveRecord }

/** Soft validation before accepting a cloud snapshot (client-resolved gameplay). */
export function softValidateSave(save: PlayerSave): { ok: true } | { ok: false; reason: string } {
  if (!Number.isFinite(save.gold) || save.gold < 0 || save.gold > 1_000_000_000) {
    return { ok: false, reason: 'Cloud save gold is out of bounds.' }
  }
  for (const skill of save.skills) {
    if (skill.level < 1 || skill.level > 10_000 || skill.xp < 0) {
      return { ok: false, reason: 'Cloud save skill values are out of bounds.' }
    }
  }
  return { ok: true }
}

export async function pushCloudSave(
  db: GameDatabase,
  save: PlayerSave,
): Promise<CloudSyncResult> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to sync cloud saves.' }
  const stamped = { ...save, updatedAt: new Date().toISOString() }
  const validation = softValidateSave(stamped)
  if (!validation.ok) return validation

  if (multiplayerMode() === 'local') {
    const result = getLocalBackend().writeCloudSave(session.userId, stamped)
    if (!result.ok) return { ok: false, reason: result.reason, remote: result.remote }
    getLocalBackend().submitLeaderboardSnapshot(db, session.userId, stamped)
    getLocalBackend().upsertProfile(session.userId, {
      appearance: stamped.appearance,
      username: stamped.characterName || session.username,
    })
    return { ok: true, save: stamped, source: 'uploaded' }
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { data: existing } = await client
    .from('player_saves')
    .select('save_version, updated_at, payload')
    .eq('user_id', session.userId)
    .maybeSingle()
  if (
    existing &&
    Date.parse(String(existing.updated_at)) > Date.parse(stamped.updatedAt) &&
    Number(existing.save_version) >= stamped.saveVersion
  ) {
    return {
      ok: false,
      reason: 'A newer cloud save exists.',
      remote: {
        userId: session.userId,
        saveVersion: Number(existing.save_version),
        updatedAt: String(existing.updated_at),
        payload: existing.payload as PlayerSave,
      },
    }
  }
  const { error } = await client.from('player_saves').upsert({
    user_id: session.userId,
    save_version: stamped.saveVersion,
    updated_at: stamped.updatedAt,
    payload: stamped,
  })
  if (error) return { ok: false, reason: error.message }
  await submitLeaderboardFromSave(db, stamped)
  return { ok: true, save: stamped, source: 'uploaded' }
}

export async function pullCloudSave(): Promise<CloudSyncResult> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to load cloud saves.' }

  if (multiplayerMode() === 'local') {
    const remote = getLocalBackend().readCloudSave(session.userId)
    if (!remote) return { ok: false, reason: 'No cloud save for this account yet.' }
    const validation = softValidateSave(remote.payload)
    if (!validation.ok) return validation
    return { ok: true, save: parseSave(remote.payload), source: 'downloaded' }
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: 'Supabase is not configured.' }
  const { data, error } = await client
    .from('player_saves')
    .select('save_version, updated_at, payload')
    .eq('user_id', session.userId)
    .maybeSingle()
  if (error) return { ok: false, reason: error.message }
  if (!data) return { ok: false, reason: 'No cloud save for this account yet.' }
  const payload = parseSave(data.payload)
  const validation = softValidateSave(payload)
  if (!validation.ok) return validation
  return { ok: true, save: payload, source: 'downloaded' }
}

/**
 * Merge strategy: last-write-wins by updatedAt / saveVersion.
 * Returns the save that should remain active locally after sync.
 */
export async function syncCloudSaveOnSafePoint(
  db: GameDatabase,
  local: PlayerSave,
  options?: { forceUpload?: boolean },
): Promise<CloudSyncResult> {
  const session = getSession()
  if (!session) return { ok: true, save: local, source: 'unchanged' }

  const remoteResult =
    multiplayerMode() === 'local'
      ? (() => {
          const remote = getLocalBackend().readCloudSave(session.userId)
          return remote
            ? ({ ok: true as const, save: remote.payload, remote })
            : ({ ok: false as const, reason: 'none' })
        })()
      : await pullCloudSave().then((result) =>
          result.ok
            ? { ok: true as const, save: result.save, remote: undefined }
            : { ok: false as const, reason: result.reason },
        )

  if (!remoteResult.ok || options?.forceUpload) {
    return pushCloudSave(db, local)
  }

  const remote = remoteResult.save
  const remoteNewer =
    Date.parse(remote.updatedAt) > Date.parse(local.updatedAt) ||
    remote.saveVersion > local.saveVersion
  if (remoteNewer && !options?.forceUpload) {
    return {
      ok: false,
      reason: 'Cloud save is newer than the local save.',
      remote:
        'remote' in remoteResult && remoteResult.remote
          ? remoteResult.remote
          : {
              userId: session.userId,
              saveVersion: remote.saveVersion,
              updatedAt: remote.updatedAt,
              payload: remote,
            },
    }
  }
  return pushCloudSave(db, local)
}

/** Remote SaveStorage that writes localStorage and mirrors to cloud when signed in. */
export function createHybridSaveStorage(
  db: GameDatabase,
  onRemoteWarning?: (message: string) => void,
): SaveStorage {
  return {
    getItem(key: string) {
      return localStorage.getItem(key)
    },
    setItem(key: string, value: string) {
      localStorage.setItem(key, value)
      if (key !== SAVE_STORAGE_KEY || !getSession()) return
      try {
        const save = parseSave(JSON.parse(value))
        void pushCloudSave(db, save).then((result) => {
          if (!result.ok) onRemoteWarning?.(result.reason)
        })
      } catch {
        // Ignore parse failures during raw writes.
      }
    },
    removeItem(key: string) {
      localStorage.removeItem(key)
    },
  }
}

export function persistLocalAndMaybeCloud(
  _db: GameDatabase,
  save: PlayerSave,
  storage: SaveStorage = localStorage,
): PlayerSave {
  return writeSave(save, storage)
}
