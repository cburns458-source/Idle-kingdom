import type { GameDatabase, NpcRow } from '../data/types'
import type { PlayerSave } from '../save/types'

export const MASTER_DWARF_ID = 'NPC-0003'
export const ARCHMAGE_ID = 'NPC-0004'
export const SMITHING_SKILL_ID = 'SKL-0011'
export const ARCANA_SKILL_ID = 'SKL-0013'

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

export function shopIdForMerchant(db: GameDatabase, npc: NpcRow): string | null {
  if ((npc.Role ?? '').toLowerCase() !== 'merchant') return null
  const shop = db.Shops.find((row) => row['Location ID'] === npc['Location ID'])
  return shop?.['Shop ID'] ?? null
}
