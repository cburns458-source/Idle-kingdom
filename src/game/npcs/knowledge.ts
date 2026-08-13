import { applyXp } from '../activity/xp'
import type { GameDatabase, NpcRow } from '../data/types'
import type { PlayerSave } from '../save/types'

export const MASTER_DWARF_ID = 'NPC-0003'
export const ARCHMAGE_ID = 'NPC-0004'
export const SMITHING_SKILL_ID = 'SKL-0011'
export const ARCANA_SKILL_ID = 'SKL-0013'

/** The general store merchant, who explains artisanry once. */
export const GENERAL_STORE_MERCHANT_ID = 'NPC-0007'
export const ARTISANRY_SKILL_ID = 'SKL-0012'
export const MERCHANT_TIP_XP = 11_000

export function npcsAtLocation(db: GameDatabase, locationId: string): NpcRow[] {
  return db.NPCs.filter((npc) => npc['Location ID'] === locationId)
}

export function hasNpcKnowledge(save: PlayerSave, npcId: string): boolean {
  return (save.unlockedNpcIds ?? []).includes(npcId)
}

export function unlockNpcKnowledge(
  save: PlayerSave,
  npcId: string,
): { ok: true; save: PlayerSave; alreadyHad: boolean } | { ok: false; reason: string } {
  if (npcId !== MASTER_DWARF_ID && npcId !== ARCHMAGE_ID) {
    return { ok: false, reason: 'This NPC does not teach projects.' }
  }
  if (hasNpcKnowledge(save, npcId)) {
    return { ok: true, save, alreadyHad: true }
  }
  return {
    ok: true,
    alreadyHad: false,
    save: {
      ...save,
      unlockedNpcIds: [...(save.unlockedNpcIds ?? []), npcId],
    },
  }
}

export function knowledgeNpcForSkill(skillId: string): string | null {
  if (skillId === SMITHING_SKILL_ID) return MASTER_DWARF_ID
  if (skillId === ARCANA_SKILL_ID) return ARCHMAGE_ID
  return null
}

export function hasProjectKnowledge(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
): { ok: true } | { ok: false; npcId: string; npcName: string } {
  const npcId = knowledgeNpcForSkill(skillId)
  if (!npcId) return { ok: true }
  if (hasNpcKnowledge(save, npcId)) return { ok: true }
  const npc = db.NPCs.find((row) => row['NPC ID'] === npcId)
  return {
    ok: false,
    npcId,
    npcName: npc?.['Display Name'] ?? 'mentor',
  }
}

export function hasClaimedMerchantTip(save: PlayerSave, npcId: string): boolean {
  return (save.claimedMerchantTipIds ?? []).includes(npcId)
}

/** Whether [npcId] has artisanry advice left to give. */
export function offersMerchantTip(save: PlayerSave, npcId: string): boolean {
  return npcId === GENERAL_STORE_MERCHANT_ID && !hasClaimedMerchantTip(save, npcId)
}

/**
 * Takes the merchant's one-off artisanry advice.
 *
 * Grants the XP and records the claim together, so listening twice cannot pay
 * twice. Returns null when there was nothing to claim, which is what a caller
 * that dismisses the dialogue unconditionally relies on.
 */
export function claimMerchantTip(
  db: GameDatabase,
  save: PlayerSave,
  npcId: string,
): { save: PlayerSave; xp: number } | null {
  if (!offersMerchantTip(save, npcId)) return null
  const applied = applyXp(save, db, ARTISANRY_SKILL_ID, MERCHANT_TIP_XP)
  return {
    save: {
      ...applied.save,
      claimedMerchantTipIds: [...(save.claimedMerchantTipIds ?? []), npcId],
    },
    xp: MERCHANT_TIP_XP,
  }
}

export function shopIdForMerchant(db: GameDatabase, npc: NpcRow): string | null {
  if ((npc.Role ?? '').toLowerCase() !== 'merchant') return null
  const shop = db.Shops.find((row) => row['Location ID'] === npc['Location ID'])
  return shop?.['Shop ID'] ?? null
}
