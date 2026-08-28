import { applyXp } from '../activity/xp'
import type { GameDatabase, NpcRow } from '../data/types'
import { getQuestProgress } from '../quests/quests'
import type { PlayerSave } from '../save/types'
import { npcLocationAt } from './roaming'

export const MASTER_DWARF_ID = 'NPC-0003'
export const ARCHMAGE_ID = 'NPC-0004'
export const QUILL_ID = 'NPC-0002'
export const SMITHING_SKILL_ID = 'SKL-0011'
export const ARCANA_SKILL_ID = 'SKL-0013'

/** The general store merchant, who points travelers toward Quill. */
export const GENERAL_STORE_MERCHANT_ID = 'NPC-0007'
export const ARTISANRY_SKILL_ID = 'SKL-0012'
export const MERCHANT_TIP_XP = 11_000

export const QUILL_LOCKED_REASON =
  'Locked — find Quill to learn how to make bows and quivers. The General Store merchant knows where he was last seen.'

export const QUILL_MISSING_REASON = 'Speak with Quill to learn how to make bows and quivers.'

export const FENNEL_ID = 'NPC-0014'
export const GETTING_STARTED_QUEST_ID = 'QST-0006'
export const FENNEL_WELCOME =
  'Welcome to the lands. I am Fennel. This farm is a good place to start — harvest, cook, and fight are all close by. Come talk to me when you want to learn the rest.'

export function npcHideAfterQuestId(npc: NpcRow): string | null {
  const notes = typeof npc.Notes === 'string' ? npc.Notes : ''
  const match = notes.match(/HideAfterQuest:\s*(QST-\d+)/i)
  return match?.[1]?.toUpperCase() ?? null
}

export function npcVisibleForSave(npc: NpcRow, save: PlayerSave): boolean {
  const questId = npcHideAfterQuestId(npc)
  if (!questId) return true
  return getQuestProgress(save, questId).status !== 'completed'
}

export function npcsAtLocation(
  db: GameDatabase,
  locationId: string,
  nowMs: number = Date.now(),
): NpcRow[] {
  return db.NPCs.filter((npc) => npcLocationAt(npc, nowMs) === locationId)
}

export function npcsAtLocationForSave(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
  nowMs: number = Date.now(),
): NpcRow[] {
  return npcsAtLocation(db, locationId, nowMs).filter((npc) => npcVisibleForSave(npc, save))
}

export function fennelIntroPending(save: PlayerSave): boolean {
  return !save.hasSeenFennelIntro && save.currentLocationId === 'LOC-0001' && save.raceId != null
}

export function hasNpcKnowledge(save: PlayerSave, npcId: string): boolean {
  return (save.unlockedNpcIds ?? []).includes(npcId)
}

export function unlockNpcKnowledge(
  save: PlayerSave,
  npcId: string,
): { ok: true; save: PlayerSave; alreadyHad: boolean } | { ok: false; reason: string } {
  if (npcId !== MASTER_DWARF_ID && npcId !== ARCHMAGE_ID && npcId !== QUILL_ID) {
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

/** Bow and quiver artisanry, taught by Quill rather than a skill-wide mentor. */
export function isQuillTaughtName(displayName: string): boolean {
  const name = displayName.trim().toLowerCase()
  return name === 'quiver' || name.endsWith(' quiver') || name === 'bow' || name.endsWith(' bow')
}

export function hasQuillProjectKnowledge(
  save: PlayerSave,
  displayName: string,
): boolean {
  return !isQuillTaughtName(displayName) || hasNpcKnowledge(save, QUILL_ID)
}

export function hasClaimedMerchantTip(save: PlayerSave, npcId: string): boolean {
  return (save.claimedMerchantTipIds ?? []).includes(npcId)
}

/** The general store no longer teaches artisanry; Quill does that now. */
export function offersMerchantTip(_save: PlayerSave, _npcId: string): boolean {
  return false
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
