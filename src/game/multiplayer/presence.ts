import type { PlayerSave } from '../save/types'
import { OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend } from './client'
import type { ActivityPresence, PublicPlayerProfile } from './types'

export type PresenceInput = Omit<
  ActivityPresence,
  'userId' | 'username' | 'updatedAt' | 'expiresAt' | 'guildName'
>

/**
 * What a save says about the player, before a backend stamps identity onto it.
 *
 * Presence advertises a skill level, and Combat is the one every character has,
 * so it is the default; a save without it falls back to whichever skill is first.
 */
export function presenceInputFromSave(save: PlayerSave): PresenceInput {
  const combat = save.skills.find((skill) => skill.skillId === 'SKL-0001')
  const skill = combat ?? save.skills[0]
  return {
    appearance: save.appearance,
    locationId: save.currentLocationId,
    currentActivityId: save.currentActivityId,
    skillId: skill?.skillId ?? null,
    skillLevel: skill?.level ?? null,
    outfitCosmeticId: save.cosmetics.equipped[OUTFIT_COSMETIC_SLOT_ID] ?? null,
    mountCosmeticId: save.cosmetics.equipped[PET_COSMETIC_SLOT_ID] ?? null,
  }
}

export function publishActivityPresence(save: PlayerSave): ActivityPresence | null {
  const session = getSession()
  if (!session) return null
  return getLocalBackend().upsertPresence(session, presenceInputFromSave(save))
}

export function clearActivityPresence(): void {
  const session = getSession()
  if (!session) return
  getLocalBackend().clearPresence(session.userId)
}

export function listPeersAtActivity(
  locationId: string,
  activityId: string | null,
  excludeSelf = true,
): ActivityPresence[] {
  const session = getSession()
  const peers = getLocalBackend().listPresence({ locationId, activityId })
  if (!excludeSelf || !session) return peers
  return peers.filter((row) => row.userId !== session.userId)
}

export function listPeersAtLocation(locationId: string, excludeSelf = true): ActivityPresence[] {
  const session = getSession()
  const peers = getLocalBackend().listPresence({ locationId })
  if (!excludeSelf || !session) return peers
  return peers.filter((row) => row.userId !== session.userId)
}

export function getPublicProfile(userId: string): PublicPlayerProfile | null {
  return getLocalBackend().publicProfile(userId)
}

export function sendFriendRequest(targetUserId: string): { ok: true } | { ok: false; reason: string } {
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in required.' }
  return getLocalBackend().sendFriendRequest(session.userId, targetUserId)
}
