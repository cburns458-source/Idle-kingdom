import type { PlayerSave } from '../save/types'
import { OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID } from '../save/types'
import { getSession } from './auth'
import { getLocalBackend } from './client'
import type { ActivityPresence, PublicPlayerProfile } from './types'

function activitySkill(
  save: PlayerSave,
): { skillId: string | null; skillLevel: number | null } {
  // Presence shows a relevant skill level when available; default Combat.
  const combat = save.skills.find((skill) => skill.skillId === 'SKL-0001')
  return {
    skillId: combat?.skillId ?? save.skills[0]?.skillId ?? null,
    skillLevel: combat?.level ?? save.skills[0]?.level ?? null,
  }
}

export function publishActivityPresence(save: PlayerSave): ActivityPresence | null {
  const session = getSession()
  if (!session) return null
  const skill = activitySkill(save)
  return getLocalBackend().upsertPresence(session, {
    appearance: save.appearance,
    locationId: save.currentLocationId,
    currentActivityId: save.currentActivityId,
    skillId: skill.skillId,
    skillLevel: skill.skillLevel,
    outfitCosmeticId: save.cosmetics.equipped[OUTFIT_COSMETIC_SLOT_ID] ?? null,
    mountCosmeticId: save.cosmetics.equipped[PET_COSMETIC_SLOT_ID] ?? null,
  })
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
