import type { PlayerSave } from '../save/types'
import { parseSave, type SaveStorage, writeSave } from '../save/saveStore'
import { PET_COSMETIC_SLOT_ID, SAVE_STORAGE_KEY } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend, getSupabaseClient, multiplayerMode } from './client'
import {
  cloudSaveRecordFrom,
  isRemoteSaveNewer,
  REMOTE_NOT_CONFIGURED,
  REMOTE_SAVE_COLUMNS,
  REMOTE_SAVE_CONFLICT,
  REMOTE_TABLES,
  saveRowFor,
  stripMissingRemoteProfileColumns,
  type RemoteRow,
} from './remote'
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

/**
 * Uploads [save] as the account's cloud copy.
 *
 * `force` is the player choosing this save over the one already stored, having
 * been shown that the other is newer.
 */
export async function pushCloudSave(
  save: PlayerSave,
  options?: { force?: boolean },
): Promise<CloudSyncResult> {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to sync cloud saves.' }
  const stamped = { ...save, updatedAt: new Date().toISOString() }
  const validation = softValidateSave(stamped)
  if (!validation.ok) return validation

  if (multiplayerMode() === 'local') {
    const result = getLocalBackend().writeCloudSave(session.userId, stamped, {
      force: options?.force,
    })
    if (!result.ok) return { ok: false, reason: result.reason, remote: result.remote }
    getLocalBackend().upsertProfile(session.userId, {
      appearance: stamped.appearance,
      username: stamped.characterName || session.username,
      motto: stamped.motto ?? null,
      petCosmeticId: stamped.cosmetics.equipped[PET_COSMETIC_SLOT_ID] ?? null,
    })
    return { ok: true, save: stamped, source: 'uploaded' }
  }

  const client = getSupabaseClient()
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const { data: existing } = await client
    .from(REMOTE_TABLES.saves)
    .select(REMOTE_SAVE_COLUMNS)
    .eq('user_id', session.userId)
    .maybeSingle()
  const remote = cloudSaveRecordFrom(session.userId, existing)
  if (!options?.force && remote && isRemoteSaveNewer(remote, stamped)) {
    return { ok: false, reason: REMOTE_SAVE_CONFLICT, remote }
  }
  const { error } = await client
    .from(REMOTE_TABLES.saves)
    .upsert(saveRowFor(session.userId, stamped))
  if (error) return { ok: false, reason: error.message }
  // Publish motto / pet onto the profile row so other players can see them
  // (RLS blocks reading another account's cloud save).
  const profileRow: RemoteRow = {
    user_id: session.userId,
    appearance_json: stamped.appearance,
    motto: stamped.motto ?? null,
    pet_cosmetic_id: stamped.cosmetics.equipped[PET_COSMETIC_SLOT_ID] ?? null,
  }
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const { error: profileError } = await client.from(REMOTE_TABLES.profiles).upsert(profileRow)
    if (!profileError) break
    if (!stripMissingRemoteProfileColumns(profileRow, profileError.message)) {
      await client.from(REMOTE_TABLES.profiles).upsert({
        user_id: session.userId,
        appearance_json: stamped.appearance,
      })
      break
    }
  }
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
  if (!client) return { ok: false, reason: REMOTE_NOT_CONFIGURED }
  const { data, error } = await client
    .from(REMOTE_TABLES.saves)
    .select(REMOTE_SAVE_COLUMNS)
    .eq('user_id', session.userId)
    .maybeSingle()
  if (error) return { ok: false, reason: error.message }
  const remote = cloudSaveRecordFrom(session.userId, data)
  if (!remote) return { ok: false, reason: 'No cloud save for this account yet.' }
  const payload = parseSave(remote.payload)
  const validation = softValidateSave(payload)
  if (!validation.ok) return validation
  return { ok: true, save: payload, source: 'downloaded' }
}

/**
 * Merge strategy: last-write-wins by updatedAt / saveVersion.
 * Returns the save that should remain active locally after sync.
 */
export async function syncCloudSaveOnSafePoint(
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
    return pushCloudSave(local, { force: options?.forceUpload })
  }

  const remote = remoteResult.save
  const remoteNewer =
    Date.parse(remote.updatedAt) > Date.parse(local.updatedAt) ||
    remote.saveVersion > local.saveVersion
  if (remoteNewer) {
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
  return pushCloudSave(local)
}

/** Remote SaveStorage that writes localStorage and mirrors to cloud when signed in. */
export function createHybridSaveStorage(
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
        void pushCloudSave(save).then((result) => {
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
  save: PlayerSave,
  storage: SaveStorage = localStorage,
): PlayerSave {
  return writeSave(save, storage)
}
